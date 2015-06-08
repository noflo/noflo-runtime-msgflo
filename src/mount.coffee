common = require './common'

path = require 'path'
noflo = require 'noflo'
async = require 'async'
msgflo = require 'msgflo'

debug = require('debug')('noflo-runtime-msgflo:mount')
debugError = require('debug')('noflo-runtime-msgflo:error')

try
  debug 'attempt load New Relic'
  nr = require 'newrelic'
catch e
  debug 'New Relic integration disabled', e.toString()

createTransaction = (name, group) ->
  wrapper = () ->
    # do nothing, just using wrapper to capture 'this'
    # XXX: do we need to bind it? using =>
    return () ->
      nr.endTransaction()

  nr.createBackgroundTransaction name, group, wrapper  
  return wrapper # callback which will end the transaction

class Transactions
  constructor: (@name) ->
    @transactions = {}

  open: (id, port) ->
    return if not nr?
    debug 'Transaction.open', id
    @transactions[id] =
      id: id
      start: Date.now()
      inport: port

  close: (id, port) ->
    return if not nr?
    transaction = @transactions[id]
    if transaction
      debug 'Transaction.close', id
      duration = Date.now()-transaction.start
      event =
        role: @name
        inport: transaction.inport
        outport: port
        duration: duration
      name = 'MsgfloJobCompleted'
      nr.recordCustomEvent name, event
      debug 'recorded event', name, event
      delete @transactions[id]

wrapInport = (transactions, client, instance, port, queueName) ->
  debug 'wrapInport', port, queueName
  socket = noflo.internalSocket.createSocket()
  instance.inPorts[port].attach socket

  onMessage = (msg) ->
    groupId = msg.amqp.fields.deliveryTag
    debug 'onInMessage', typeof msg.data, msg.data, groupId
    return unless msg.data

    transactions.open groupId, port
    socket.connect()
    socket.beginGroup groupId
    socket.send msg.data
    socket.endGroup()
    socket.disconnect()

  return if not queueName
  client.subscribeToQueue queueName, onMessage, (err) ->
    throw err if err

wrapOutport = (transactions, client, instance, port, queueName) ->
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
    if port is 'error'
      client.nackMessage msg, false, false
    else
      client.ackMessage msg
    transactions.close group, port

  socket.on 'disconnect', ->
    debug 'onDisconnect', port, groups
    groups = []

  socket.on 'data', (data) ->
    debug 'onOutMessage', port, typeof data, groups
    dataReceived = true if groups.length
    debugError 'ERROR', data if port == 'error'
    debugError 'STACK', '\n'+data.stack if port == 'error' if data.stack

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

  # defaults
  options.inports = {} if not options.inports
  options.outports = {} if not options.outports
  options.basedir = process.cwd() if not options.basedir
  options.prefetch = 1 if not options.prefetch

  options.broker = process.env['MSGFLO_BROKER'] if not options.broker
  options.broker = process.env['CLOUDAMQP_URL'] if not options.broker

  if options.attr and options.attr.length
    for option in options.attr
      applyOption options, option

    delete options.option

  return options

class Mounter
  constructor: (options) ->
    @options = normalizeOptions options
    @loader = new noflo.ComponentLoader @options.basedir
    @client = msgflo.transport.getClient @options.broker, { prefetch: @options.prefetch }
    @instance = null # noflo.Component instance
    @transactions = new Transactions @options.name

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
            wrapInport @transactions, @client, instance, port.id, port.queue
          for port in definition.outports
            wrapOutport @transactions, @client, instance, port.id, port.queue

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

