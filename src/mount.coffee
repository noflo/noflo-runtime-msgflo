
path = require 'path'

noflo = require 'noflo'
async = require 'async'
msgflo = require 'msgflo'
randomstring = require 'randomstring'

loader = null
getLoader = ->
  baseDir = path.join __dirname, '..'
  loader = new noflo.ComponentLoader baseDir unless loader
  loader

wrapInport = (client, instance, port, queueName) ->
  console.log 'wrapInport', port, queueName
  socket = noflo.internalSocket.createSocket()
  instance.inPorts[port].attach socket

  onMessage = (msg) ->
    return unless msg
    message = JSON.parse msg.content.toString()

    socket.beginGroup msg.fields.deliveryTag
    socket.send message
    socket.endGroup()
    socket.disconnect()

  client.subscribeToQueue queueName, onMessage, (err) ->
    throw err if err

wrapOutport = (client, instance, port, queueName) ->
  console.log 'wrapOutport', port, queueName
  socket = noflo.internalSocket.createSocket()
  instance.outPorts[port].attach socket
  groups = []

  # TODO: send ACK/NACK
  # NACK or kill when output is inproperly grouped
  # 
  socket.on 'begingroup', (group) ->
    groups.push group
  socket.on 'endgroup', (group) ->
    groups.pop()
  socket.on 'disconnect', ->
    groups = []

  socket.on 'data', (data) ->
    # Send to outport
    msg = new Buffer JSON.stringify data
    client.sendToQueue queueName, msg, (err) ->
      console.log err

values = (dict) ->
  return Object.keys(dict).map (key) -> return dict[key]

setupQueues = (client, def, callback) ->

  # FIXME: Allow only one message per worker before ack/nack
  # channel.prefetch 1
  setupQueue = (port, callback) ->
    client.createQueue port.queue, callback

  ports = def.inports.concat(def.outports)
  async.map ports, setupQueue, (err) ->
    return callback err if err
    return callback null


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
    @client = msgflo.transport.getClient @options.broker
    @graph = null
    @network = null
    @options.id = @options.id.replace '*', randomstring.generate 6

  start: (callback) ->
    queueName = (type, port) ->
      return "#{options.id}-#{type}-#{port}"

    @client.connect (err) =>
      return callback err if err

      # Send discovery package to broker on 'fbp' queue
      @client.createQueue 'fbp', (err) =>
        return callback err if err

        loadAndStartGraph @options.graph, (err, instance) =>
          return callback err if err
          console.log 'loaded', instance

          definition = @getDefinition instance
          # TODO: support queues being set up over FBP protocol
          setupQueues @client, definition, (err) =>
            console.log 'queues set up', err
            return callback err if err

#            console.log 'setting up', definition
            for port in definition.inports
              console.log port
              wrapInport @client, instance, port.id, port.queue
            for port in definition.outports
              console.log port
              wrapOutport @client, instance, port.id, port.queue

            console.log 'sending participant'
            @sendParticipant definition, (err) ->
              return callback err

  getDefinition: (graph) ->

    definition =
      id: @options.id
      'class': @options.graph
      icon: 'file-word-o' # FIXME: implement
      label: 'No description' # FIXME: implement
      inports: []
      outports: []

    console.log graph

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
    msg =
      protocol: 'discovery'
      command: 'participant'
      payload: definition
    @client.sendToQueue 'fbp', msg, (err) ->
      console.log 'SENT participant'
      return callback err

exports.Mounter = Mounter

