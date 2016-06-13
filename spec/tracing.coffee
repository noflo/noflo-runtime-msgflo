
chai = require 'chai' unless chai
path = require 'path'
msgflo = require 'msgflo'
randomstring = require 'randomstring'

mount = require('..').mount

waitStarted = (broker, role, callback) ->
  started = false

  broker.subscribeParticipantChange (msg) ->
    return broker.nackMessage(msg) if started
    broker.ackMessage msg

    participant = msg.data.payload 
    if participant.role != role
      console.log "WARN: tracing test got unexpected participant #{participant.role}"
      return

    started = true
    return callback null, participant

processData = (broker, address, role, testid, callback) ->
  spy = msgflo.utils.spy address, "tracingspy-#{testid}", { 'repeated': "#{role}.OUT" }
  spy.startSpying (err) ->
    return done err if err
    # process some data
    spy.getMessages 'repeated', 1, (messages) ->
      data = messages[0]
      err = if data.repeat == role then null else new Error "wrong output data: #{JSON.stringify(data)}"
      return callback err
#            spy.stop done
    broker.sendTo 'inqueue', "#{role}.IN", { repeat: role }, (err) ->
      return done err if err

sendReceiveFbp = (broker, address, participantId, testid, msg, callback) ->
  # TODO: have these queues declared in the discovery message. Don't rely on convention
  fbpQueues =
    IN: ".fbp.#{participantId}.receive"
    OUT: ".fbp.#{participantId}.send"
  # FIXME: don't use Spy/Participant here. Instead runtime.SendReceivePair ?

  spy = msgflo.utils.spy address, 'protocolspy-'+testid+'-'+randomstring.generate(2), { 'reply': fbpQueues.OUT }
  cleanCallback = (err, data) ->
    return callback err, data

  spy.startSpying (err) ->
    return cleanCallback err if err

    spy.getMessages 'reply', 1, (messages) ->
      data = messages[0]
      return cleanCallback null, data
    broker.sendTo 'inqueue', fbpQueues.IN, msg, (err) ->
      return cleanCallback err if err

requestTraceDump = (broker, address, participantId, testid, callback) ->
  msg =
    protocol: 'trace'
    command: 'dump'
    payload:
      graph: 'default'
      type: 'flowtrace.json'
  sendReceiveFbp broker, address, participantId, testid, msg, callback

validateTrace = (data) ->

  chai.expect(data).to.have.keys [ 'protocol', 'command', 'payload' ]
  chai.expect(data.protocol).to.eql 'trace'
  chai.expect(data.command).to.eql 'dump'
  p = data.payload
  chai.expect(p).to.have.keys ['graph', 'type', 'flowtrace']
  chai.expect(p.type).to.eql 'flowtrace.json'
  trace = JSON.parse p.flowtrace
  chai.expect(trace).to.have.keys ['header', 'events']
  chai.expect(trace.events).to.be.an 'array'
  events = trace.events.map (e) -> "#{e.command}"
  eventTypes = []
  for e in events
    eventTypes.push e if eventTypes.indexOf(e) == -1
  eventTypes = eventTypes.sort()
  chai.expect(eventTypes, 'should have received all NoFlo packet event types').to.eql ([
    'connect'
    'data'
    'disconnect'
    'begingroup'
    'endgroup'
  ]).sort()

transportTests = (address) ->
  broker = null

  beforeEach (done) ->
    broker = msgflo.transport.getBroker address
    broker.connect done

  afterEach (done) ->
    broker.disconnect done

  describe '--trace=true', ->
    m = null
    options = null
    participant = null
    testid = ''

    beforeEach (done) ->
      @timeout 6*1000
      testid = randomstring.generate 4
      options =
        broker: address
        graph: 'RepeatTest'
        name: 'tracetrue-'+testid
        trace: true # enable tracing
      m = new mount.Mounter options
      waitStarted broker, options.name, (err, p) ->
        return done err if err
        participant = p
        return done err
      m.start (err) ->
        return done err if err

    afterEach (done) ->
      m.stop done

    describe 'process data, trigger via FBP protocol', ->
      it 'should return flowtrace over FBP protocol', (done) ->
        @timeout 6*1000
        processData broker, address, options.name, testid, (err) ->
          chai.expect(err).to.not.exist
          requestTraceDump broker, address, participant.id, testid, (err, trace) ->
            chai.expect(err).to.not.exist
            validateTrace trace
            return done()

  describe '--trace=false', ->
    m = null
    options = null
    participant = null
    testid = ''

    beforeEach (done) ->
      @timeout 6*1000
      testid = randomstring.generate 4
      options =
        broker: address
        graph: 'RepeatTest'
        name: 'tracefalse-'+testid
        trace: false # disable tracing
      m = new mount.Mounter options
      waitStarted broker, options.name, (err, p) ->
        return done err if err
        participant = p
        return done err
      m.start (err) ->
        return done err if err

    afterEach (done) ->
      m.stop done

    describe 'enabling tracing over FBP protocol', () ->
      enableMsg =
        protocol: 'trace'
        command: 'start'
        payload:
          graph: 'default'
          type: 'flowtrace.json'

      it.skip 'should respond with ack', (done) ->
        sendReceiveFbp broker, address, participant.id, testid, enableMsg, (err, reply) ->
          chai.expect(err).to.not.exist
          chai.expect(reply).to.eql enableMsg
          done()

      describe 'process data, trigger via FBP protocol', ->
        it 'should return flowtrace over FBP protocol', (done) ->
          @timeout 4*1000

          sendReceiveFbp broker, address, participant.id, testid, enableMsg, (err, reply) ->
            chai.expect(err).to.not.exist
            processData broker, address, options.name, testid, (err) ->
              chai.expect(err).to.not.exist
              requestTraceDump broker, address, participant.id, testid, (err, trace) ->
                chai.expect(err).to.not.exist
                validateTrace trace
                return done()

describe 'Tracing', () ->

    transportTests 'amqp://localhost'
