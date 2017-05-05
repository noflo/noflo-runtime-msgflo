common = require './common'
newrelic = require './newrelic'
runtime = require './runtime'

path = require 'path'
noflo = require 'noflo'
async = require 'async'
msgflo = require 'msgflo-nodejs'
uuid = require 'uuid'
trace = require('noflo-runtime-base').trace

debug = require('debug')('noflo-runtime-msgflo:mount')
debugError = require('debug')('noflo-runtime-msgflo:error')

wrapInport = (transactions, instance, port) ->
  debug 'wrapInport', port, Object.keys instance.inPorts?.ports

  socket = noflo.internalSocket.createSocket()
  instance.inPorts[port].attach socket

  onMessage = (msg) ->
    groupId = msg?.amqp?.fields?.deliveryTag
    groupId = uuid.v4() if not groupId
    debug 'onInMessage', typeof msg.data, msg.data, groupId
    return unless msg.data

    transactions.open groupId, port
    socket.connect()
    socket.beginGroup groupId
    socket.send msg.data
    socket.endGroup groupId
    socket.disconnect()

  return onMessage

wrapOutport = (transactions, client, instance, port, queueName, callback) ->
  debug 'wrapOutport', port, queueName
  socket = noflo.internalSocket.createSocket()
  instance.outPorts[port].attach socket
  groups = []
  dataReceived = false

  # TODO: NACK or kill when output is inproperly grouped
  socket.on 'begingroup', (group) ->
    debug 'beginGroup', port, group
    groups.push group
  socket.on 'endgroup', (group) ->
    debug 'endGroup', port, group
    groups.pop()
    return if groups.length
    return unless dataReceived
    dataReceived = false
    # ack/nack
    msg =
      amqp:
        fields:
          deliveryTag: group
      data: null

    result =
      id: group
      type: null

    if port is 'error'
      client.nackMessage msg, false, false
      result.type = 'error'
    else
      client.ackMessage msg
      result.type = 'ok'
    transactions.close group, port
    callback result

  socket.on 'disconnect', ->
    debug 'onDisconnect', port, groups
    groups = []

  socket.on 'data', (data) ->
    debug 'onOutMessage', port, typeof data, groups
    dataReceived = true if groups.length
    debugError 'ERROR', data if port == 'error'
    debugError 'STACK', '\n'+data.stack if port == 'error' and data?.stack

    # Send to outport
    return if not queueName # hidden
    client.sendTo 'outqueue', queueName, data, (err) ->
      debug 'sent output data', queueName, err, data

# Execute all packets using the existing NoFlo network
wrapPortsOnExisting = (transactions, client, instance, definition) ->
  for port in definition.inports
    continue unless port.queue
    continue unless port.id

    # Normal mode is to reuse same network for each message
    onMessage = wrapInport transactions, instance, port.id
    client.subscribeToQueue port.queue, onMessage, (err) ->
      throw err if err

  for port in definition.outports
    wrapOutport transactions, client, instance, port.id, port.queue, ->

# Execute each packet using a dedicated NoFlo network
wrapPortsDedicated = (transactions, client, loader, instances, definition, options) ->
  definition.inports.forEach (port) ->
    return unless port.queue
    return unless port.id

    onMessage = (msg) ->
      loadAndStartGraph loader, options.graph, options.iips, (err, instance) ->
        throw err if err
        debug 'wrapPortsDedicated network started'
        instances.push instance

        for outPort in definition.outports
          wrapOutport transactions, client, instance, outPort.id, outPort.queue, (result) ->
            setTimeout ->
              debug 'wrapPortsDedicated network shutdown'
              instance.shutdown (err) ->
                throw err if err
                instances.splice instances.indexOf(instance), 1
            , 1

        wrappedIn = wrapInport transactions, instance, port.id
        wrappedIn msg

    client.subscribeToQueue port.queue, onMessage, (err) ->
      throw err if err

setupQueues = (client, def, callback) ->
  setupIn = (port, cb) ->
    client.createQueue 'inqueue', port.queue, cb
  setupOut = (port, cb) ->
    client.createQueue 'outqueue', port.queue, cb

  inports = def.inports.filter (p) -> not p.hidden
  outports = def.outports.filter (p) -> not p.hidden

  async.map inports, setupIn, (err) ->
    return callback err if err
    async.map outports, setupOut, callback

setupDeadLettering = (client, inports, deadletters, callback) ->
  # NOTE: relies on msgflo setting up the deadletter exchange with matching naming convention
  setupDeadletter = (name, cb) ->
    port = inports.filter((p) -> p.id == name)[0]
    deadletter = 'dead-'+port.queue
    client.createQueue 'inqueue', deadletter, cb

  async.map deadletters, setupDeadletter, callback

sendIIPs = (instance, iips) ->
  for port, data of iips
    socket = noflo.internalSocket.createSocket()
    instance.inPorts[port].attach socket
    socket.connect()
    socket.send data
    socket.disconnect()

loadAndStartGraph = (loader, graphName, iips, callback) ->
  loader.load graphName, (err, instance) ->
    return callback err if err
    onReady = () ->
      onStarted = (err) ->
        return callback err if err
        # needs to happen after NoFlo network has sent its IIPs
        debug 'sending IIPs', Object.keys(iips)
        sendIIPs instance, iips
        return callback null, instance

      if instance.isSubgraph() and instance.network
        # Subgraphs need process-error handling
        instance.network.on 'process-error', (err) ->
          console.log err.id, err.error?.message, err.error?.stack
          setTimeout ->
            # Need to not throw syncronously to avoid cascading affects
            throw err.error
          , 0
      # Tell Network to start sending IIPs
      instance.start onStarted
    if instance.isReady()
      onReady()
    else
      instance.once 'ready', onReady

getDefinition = (instance, options) ->
  definition =
    component: options.graph
    icon: instance.getIcon()
    label: instance.getDescription()
    inports: []
    outports: []

  # TODO: read out type annotations
  for name in Object.keys instance.inPorts.ports
    port =
      id: name
      type: 'all'
    definition.inports.push port

  for name in Object.keys instance.outPorts.ports
    port =
      id: name
      type: 'all'
    definition.outports.push port

  # merge in port overrides from options
  for id, port of options.inports
    def = definition.inports.filter((p) -> p.id == id)[0]
    for k, v of port
      def[k] = v if v
  for id, port of options.outports
    def = definition.outports.filter((p) -> p.id == id)[0]
    for k, v of port
      def[k] = v if v

  def = msgflo.participant.instantiateDefinition definition, options.name
  return def

applyOption = (obj, option) ->
  tokens = option.split '='
  if tokens.length > 1
    value = tokens.slice(1).join('=')
    key = tokens[0]
    keys = key.split '.'

    target = obj
    for k,i in keys
      last = (i == keys.length-1)
      if last
        target[k] = value
      else
        target[k] = {} if not target[k]
        target = target[k]

exports.normalizeOptions = normalizeOptions = (opt) ->
  options = common.clone opt

  options.deadletter = options.deadletter.split(',') if options.deadletter

  # defaults
  options.deadletter = [] if not options.deadletter
  options.inports = {} if not options.inports
  options.outports = {} if not options.outports
  options.basedir = process.cwd() if not options.basedir
  options.prefetch = 1 if not options.prefetch
  options.iips = '{}' if not options.iips
  options.dedicatedNetwork = false unless options.dedicatedNetwork

  options.discoveryInterval = process.env['MSGFLO_DISCOVERY_PERIOD'] unless options.discoveryInterval
  options.broker = process.env['MSGFLO_BROKER'] if not options.broker
  options.broker = process.env['CLOUDAMQP_URL'] if not options.broker

  options.discoveryInterval = 60 unless options.discoveryInterval

  options.iips = JSON.parse options.iips

  if options.attr and options.attr.length
    for option in options.attr
      applyOption options, option

    delete options.option

  return options


class Mounter
  constructor: (options) ->
    @options = normalizeOptions options
    @client = msgflo.transport.getClient @options.broker, { prefetch: @options.prefetch }
    loader = options.loader or new noflo.ComponentLoader @options.basedir, { cache: @options.cache }
    @loader = loader
    @tracer = new trace.Tracer {}
    @instances = [] # noflo.Component instances
    @transactions = null # loaded with instance
    @coordinator = null
    @discoveryInterval = null

  start: (callback) ->
    debug 'starting'
    @client.connect (err) =>
      return callback err if err
      loadAndStartGraph @loader, @options.graph, @options.iips, (err, instance) =>
        return callback err if err
        debug 'started graph', @options.graph
        @instances.push instance
        @tracer.attach instance.network if @options.trace

        definition = @getDefinition instance
        @transactions = new newrelic.Transactions definition
        @coordinator = new runtime.SendReceivePair @client, ".fbp.#{definition.id}"
        @coordinator.onReceive = (data) =>
          @handleFbpMessage data
        @coordinator.create (err) =>
          return callback err if err

          @setupQueuesForComponent instance, definition, (err) =>
            return callback err if err

            # Connect queues to instance
            if @options.dedicatedNetwork
              debug 'setup in dedicated network mode'
              wrapPortsDedicated @transactions, @client, @loader, @instances, definition, @options
            else
              debug 'setup in single network mode'
              wrapPortsOnExisting @transactions, @client, instance, definition

            # Send discovery package, first once
            @sendParticipant definition, (err) =>
              # then periodically
              @discoveryInterval = setInterval () =>
                @sendParticipant definition, (err) ->
                  console.log 'WARNING: Failed to send Msgflo discovery', err if err
              , @options.discoveryInterval*1000/2.2
              return callback err, @options

  stop: (callback) ->
    return callback null if not @instances.length
    clearInterval @discoveryInterval
    debug "stopping #{@instances.length} instances"
    async.each @instances, (instance, done) ->
      instance.shutdown done
    , (err) =>
      @instances = []
      debug 'stopped component instances', err
      return callback err if not @coordinator
      @coordinator.destroy (err) =>
        debug 'coordinator connection destroyed', err
        @coordinator = null
        return callback null if not @client
        @client.disconnect (err) =>
          debug 'disconnected client', err
          @client = null
          return callback err

  setupQueuesForComponent: (instance, definition, callback) ->
    setupQueues @client, definition, (err) =>
      debug 'queues set up', err
      return callback err if err

      setupDeadLettering @client, definition.inports, @options.deadletter, (err) =>
        return callback err if err
        return callback null

  getDefinition: () ->
    return null if not @instances.length
    return getDefinition @instances[0], @options

  sendParticipant: (definition, callback) ->
    debug 'sendParticipant', definition.id
    @client.registerParticipant definition, callback

  handleFbpMessage: (data) ->
    { protocol, command, payload } = data
    return if protocol != 'trace'

    # Handle trace subprotocol
    switch command
      when 'start'
        for instance in @instances
          @tracer.attach instance.network
        @coordinator?.send data
      when 'stop'
        for instance in @instances
          @tracer.detach instance.network
        @coordinator?.send data
      when 'clear'
        null # FIXME: implement
        @coordinator?.send data
      when 'dump'
        @tracer.dumpString (err, trace) =>
          reply = common.clone data
          reply.payload.flowtrace = trace
          @coordinator?.send reply

exports.Mounter = Mounter
