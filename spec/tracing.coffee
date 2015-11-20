
chai = require 'chai' unless chai
path = require 'path'
msgflo = require 'msgflo'
randomstring = require 'randomstring'

mount = require('..').mount

transportTests = (address) ->
  broker = null

  beforeEach (done) ->
    broker = msgflo.transport.getBroker address
    broker.connect done

  afterEach (done) ->
    broker.disconnect done

  describe 'graph with proccessed data', ->
    m = null
    options = null
    spy = null
    started = false
    participant = null

    beforeEach (done) ->
      @timeout 6*1000
      options =
        broker: address
        graph: 'RepeatTest'
        name: '3anyone-'+randomstring.generate 4        
        trace: true # enable tracing

      spy = new msgflo.utils.spy address, 'tracingspy', { 'repeated': "#{options.name}.OUT" }
      m = new mount.Mounter options

      broker.subscribeParticipantChange (msg) ->
        #console.log 'participant discovered', msg.data.payload
        return broker.nackMessage(msg) if started
        broker.ackMessage msg

        participant = msg.data.payload 
        if participant.role != options.name
          console.log "WARN: tracing test got unexpected participant #{participant.role}" if participant.role != 'tracingspy'
          return

        started = true
        spy.startSpying (err) ->
          return done err if err
          # process some data
          onOutputReceived = 
          spy.getMessages 'repeated', 1, (data) ->
            err = if data.repeat == 'this!' then null else new Error "wrong output data: #{data}"
            spy.stop done
          broker.sendTo 'inqueue', "#{participant.role}.IN", { repeat: 'this!' }, (err) ->
            return done err if err

      m.start (err) ->
        return done err if err

    afterEach (done) ->
      m.stop done

    describe 'triggering with FBP protocol message', ->
      it 'should return it over FBP protocol', (done) ->
        @timeout 4*1000

        # TODO: have these queues declared in the discovery message. Don't rely on convention
        fbpQueue =
          IN: ".fbp.#{participant.id}.receive"
          OUT: ".fbp.#{participant.id}.send"
        msg =
          protocol: 'trace'
          command: 'dump'
          payload:
            graph: 'default'
            type: 'flowtrace.json'
        onTraceReceived = (data) ->
          #console.log 'got trace', data
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
          chai.expect(events).to.eql ['connect', 'data', 'disconnect']
          return done()

        spy = new msgflo.utils.spy address, 'protocolspy', { 'reply': fbpQueue.OUT }
        spy.getMessages 'reply', 1, (messages) ->
          onTraceReceived messages[0]
        spy.startSpying (err) ->
          chai.expect(err).to.not.exist
          broker.sendTo 'inqueue', fbpQueue.IN, msg, (err) ->
            chai.expect(err).to.not.exist

describe 'Tracing', () ->

    transportTests 'amqp://localhost'
