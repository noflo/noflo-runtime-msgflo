path = require 'path'

noflo = require 'noflo'
async = require 'async'
msgflo = require 'msgflo'

debug = require('debug')('noflo-runtime-msgflo:mount')

wrapInport = (client, instance, port, queueName) ->
  debug 'wrapInport', port, queueName
  socket = noflo.internalSocket.createSocket()
  instance.inPorts[port].attach socket

  onMessage = (msg) ->
    groupId = msg.amqp.fields.deliveryTag
    debug 'onInMessage', typeof msg.data, msg.data, groupId
    return unless msg.data

    socket.connect()
    socket.beginGroup groupId
    socket.send msg.data
    socket.endGroup()
    socket.disconnect()

  return if not queueName
  client.subscribeToQueue queueName, onMessage, (err) ->
    throw err if err

wrapOutport = (client, instance, port, queueName) ->
  debug 'wrapOutport', port, queueName
  socket = noflo.internalSocket.createSocket()
  instance.outPorts[port].attach socket
  groups = []

  # TODO: NACK or kill when output is inproperly grouped
  socket.on 'begingroup', (group) ->
    debug 'beginGroup', port, group
    groups.push group
  socket.on 'endgroup', (group) ->
    debug 'endGroup', port, group
    groups.pop()
  socket.on 'disconnect', ->
    debug 'onDisconnect', port, groups
    groups = []

  socket.on 'data', (data) ->
    debug 'onOutMessage', port, typeof data, groups
    # ack/nack
    msg =
      amqp:
        fields:
          deliveryTag: groups[0]
      data: null
    if port == 'error'
      client.nackMessage msg, false, false
    else
      client.ackMessage msg

    # Send to outport
    return if not queueName # hidden
    client.sendTo 'outqueue', queueName, data, (err) ->
      debug 'sent output data', queueName, err, data

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

loadAndStartGraph = (loader, graphName, callback) ->
  loader.load graphName, (err, instance) ->
    return callback err if err
    onReady = () ->
      instance.start() if instance.network
      return callback null, instance
    if instance.isReady()
      onReady()
    else
      instance.once 'ready', onReady

getDefinition = (instance, options) ->

    definition =
      component: options.graph
      icon: 'file-word-o' # FIXME: implement
      label: 'No description' # FIXME: implement
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

class Mounter
  constructor: (@options) ->
    # default options
    @options.inports = {} if not @options.inports
    @options.outports = {} if not @options.outports
    @options.basedir = process.cwd() if not @options.basedir
    @options.prefetch = 1 if not @options.prefetch

    @loader = new noflo.ComponentLoader @options.basedir
    @client = msgflo.transport.getClient @options.broker, { prefetch: @options.prefetch }
    @instance = null # noflo.Component instance

  start: (callback) ->
    @client.connect (err) =>
      return callback err if err
      loadAndStartGraph @loader, @options.graph, (err, instance) =>
        return callback err if err
        debug 'started graph', @options.graph
        @instance = instance

        definition = @getDefinition instance
        # TODO: support queues being set up over FBP protocol
        setupQueues @client, definition, (err) =>
          debug 'queues set up', err
          return callback err if err

          for port in definition.inports
            wrapInport @client, instance, port.id, port.queue
          for port in definition.outports
            wrapOutport @client, instance, port.id, port.queue

          # Send discovery package to broker on 'fbp' queue
          @sendParticipant definition, (err) ->
            return callback err

  stop: (callback) ->
    return callback null if not @graph
    @graph.shutdown (err) =>
      @graph = null
      return callback err if err
      return callback null if not @client
      @client.disconnect (err) =>
        @client = null
        return callback err

  getDefinition: () ->
    return null if not @instance
    return getDefinition @instance, @options

  sendParticipant: (definition, callback) ->
    debug 'sendParticipant', definition.id
    @client.registerParticipant definition, callback

exports.Mounter = Mounter

