path = require 'path'

noflo = require 'noflo'
async = require 'async'
msgflo = require 'msgflo'
randomstring = require 'randomstring'

debug = require('debug')('noflo-runtime-msgflo:mount')

loader = null
getLoader = ->
  baseDir = path.join __dirname, '..'
  loader = new noflo.ComponentLoader baseDir unless loader
  loader

wrapInport = (client, instance, port, queueName) ->
  debug 'wrapInport', port, queueName
  socket = noflo.internalSocket.createSocket()
  instance.inPorts[port].attach socket

  onMessage = (msg) ->
    debug 'onMessage', typeof msg.data, msg.data
    return unless msg.data

    socket.beginGroup msg.amqp.fields.deliveryTag
    socket.send msg.data
    socket.endGroup()
    socket.disconnect()

  client.subscribeToQueue queueName, onMessage, (err) ->
    throw err if err

wrapOutport = (client, instance, port, queueName) ->
  debug 'wrapOutport', port, queueName
  socket = noflo.internalSocket.createSocket()
  instance.outPorts[port].attach socket
  groups = []

  # TODO: NACK or kill when output is inproperly grouped
  socket.on 'begingroup', (group) ->
    groups.push group
  socket.on 'endgroup', (group) ->
    groups.pop()
  socket.on 'disconnect', ->
    groups = []

  socket.on 'data', (data) ->
    # ack/nack
    msg =
      amqp:
        fields:
          deliveryTag: groups[0]
      data: null
    if port == 'error'
      client.nackMessage msg
    else
      client.ackMessage msg

    # Send to outport
    client.sendTo 'outqueue', queueName, data, (err) ->
      debug 'sent output data', queueName, err, data

setupQueues = (client, def, callback) ->
  setupIn = (port, cb) ->
    client.createQueue 'inqueue', port.queue, cb
  setupOut = (port, cb) ->
    client.createQueue 'outqueue', port.queue, cb

  async.map def.inports, setupIn, (err) ->
    return callback err if err
    async.map def.outports, setupOut, callback

loadAndStartGraph = (graphName, callback) ->
  loader = getLoader()
  loader.load graphName, (err, instance) ->
    return callback err if err
    onReady = () ->
      instance.start() if instance.network
      return callback null, instance
    if instance.isReady()
      onReady()
    else
      instance.once 'ready', onReady

class Mounter
  constructor: (@options) ->
    clientOptions =
      prefetch: 1
    @client = msgflo.transport.getClient @options.broker, clientOptions
    @graph = null
    @network = null
    @options.id = @options.id.replace '*', randomstring.generate 6

  start: (callback) ->
    @client.connect (err) =>
      return callback err if err
      loadAndStartGraph @options.graph, (err, instance) =>
        return callback err if err
        debug 'started graph', @options.graph

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

  getDefinition: (graph) ->

    definition =
      id: @options.id
      component: @options.graph
      icon: 'file-word-o' # FIXME: implement
      label: 'No description' # FIXME: implement
      inports: []
      outports: []

    for name in Object.keys graph.inPorts.ports
      port =
        id: name
        queue: @options.id+'-inputs-'+name
        type: 'all'
      definition.inports.push port

    for name in Object.keys graph.outPorts.ports
      port =
        id: name
        queue: @options.id+'-outputs-'+name
        type: 'all'
      definition.outports.push port

    return definition

  sendParticipant: (definition, callback) ->
    debug 'sendParticipant', definition.id
    @client.registerParticipant definition, callback

exports.Mounter = Mounter

