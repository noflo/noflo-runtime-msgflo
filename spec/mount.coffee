
chai = require 'chai' unless chai
path = require 'path'
msgflo = require 'msgflo'
randomstring = require 'randomstring'

mount = require('..').mount

# Note: most require running an external broker service
transports =
#  'direct': 'direct://broker1'
#  'MQTT': 'mqtt://localhost'
  'AMQP': 'amqp://localhost'

transportTest = (address) ->
  coordinator = null

  beforeEach (done) ->
    broker = msgflo.transport.getBroker address
    coordinator = new msgflo.coordinator.Coordinator broker
    coordinator.start (err) ->
      chai.expect(err).to.be.a 'null'
      done()

  afterEach (done) ->
    coordinator.stop () ->
      coordinator = null
      done()

  describe 'mounted graph', ->
    m = null
    options = null
    beforeEach (done) ->
      @timeout 4000
      options =
        broker: address
        graph: 'core/RepeatAsync'
        name: '1someone'+randomstring.generate 4
      m = new mount.Mounter options
      m.start done

    afterEach (done) ->
      m.stop done

    it 'should connect to broker', (done) ->
      coordinator.once 'participant-added', (participant) ->
        chai.expect(participant.id).to.contain options.name
        done()

    describe 'sending to input queue', ->
      it 'should come out on output queue', (done) ->
        coordinator.once 'participant-added', (participant) ->
          chai.expect(participant.id).to.contain options.name
          part = participant.id
          coordinator.subscribeTo part, 'out', (msg) ->
            chai.expect(msg.data).to.eql { foo: 'bar' }
            done()
          coordinator.sendTo part, 'in', { foo: 'bar' }


  describe 'graph with custom queues names', ->
    m = null
    options = null
    beforeEach (done) ->
      @timeout 4000
      id = randomstring.generate 4
      options =
        broker: address
        graph: 'core/Repeat'
        name: 'customqueue'+id
        inports:
          'in':
            queue: '_myinport33'+id
        outports:
          out:
            queue: '_myoutport33'+id
      m = new mount.Mounter options
      m.start done
    afterEach (done) ->
      m.stop done

    describe 'sending to specified input queue', ->
      it 'should output on specified queue', (done) ->
        input = { 'ff': 'uuuu' }
        onResult = (msg) ->
          chai.expect(msg.data).to.eql input
          done()
        client = msgflo.transport.getClient address
        client.connect (err) ->
          chai.expect(err).to.not.exist
          client.subscribeToQueue options.outports['out'].queue, onResult, (err) ->
            chai.expect(err).to.not.exist
            client.sendTo 'inqueue', options.inports['in'].queue, input, (err) ->
              chai.expect(err).to.not.exist

  describe 'graph with deadlettering', ->
    m = null
    options = null
    beforeEach (done) ->
      @timeout 4000
      id = randomstring.generate 4
      options =
        broker: address
        graph: 'core/ReadEnv'
        name: 'deadlettering'+id
        inports:
          key:
            queue: '_input44'+id
        outports:
          error:
            hidden: true
          out:
            hidden: true
      m = new mount.Mounter options
      m.start done
    afterEach (done) ->
      m.stop done

    describe 'input message causing error', ->
      it 'should be sent to deadletter queue', (done) ->
        inputCausingError = '__non_exitsting_envvar___'
        onDeadletter = (msg) ->
          chai.expect(msg.data).to.eql inputCausingError
          done()
        deadletter = 'dead-'+options.inports.key.queue
        client = msgflo.transport.getClient address
        client.connect (err) ->
          chai.expect(err).to.not.exist

          client.createQueue 'outqueue', deadletter, (err) ->
            chai.expect(err).to.not.exist
            client.subscribeToQueue deadletter, onDeadletter, (err) ->
              chai.expect(err).to.not.exist
              client.sendTo 'inqueue', options.inports.key.queue, inputCausingError, (err) ->
                chai.expect(err).to.not.exist


describe 'Mount', ->
  Object.keys(transports).forEach (type) =>
    address = transports[type]

    describe ", transport=#{type}: ", () ->
      transportTest address

    describe "options", ->
      describe 'default', ->
         process.env['CLOUDAMQP_URL'] = 'amqp://localhost'
         defaults = mount.normalizeOptions {}
         it 'exists for prefetch', ->
            chai.expect(defaults.prefetch).to.be.a 'number'
         it 'exists for basedir', ->
            chai.expect(defaults.basedir).to.be.a 'string'
         it 'exists for broker url', ->
            chai.expect(defaults.broker).to.be.a 'string'

      describe '--attr key=value', ->
        it 'should set key to be "value"', ->
          input =
            attr: [ 'key1=val1' ]
          options = mount.normalizeOptions input
          chai.expect(options.key1).to.equal 'val1'
      describe '--attr foo.bar.baz=value', ->
        it 'should set "value" on nested object', ->
          input =
            attr: [ 'foo.bar.baz=value' ]
          options = mount.normalizeOptions input
          chai.expect(options.foo.bar.baz).to.equal 'value'

      describe '--attr baz=value-with=in-it', ->
        it 'should set baz to be "value-with=in-it"', ->
          input =
            attr: [ 'baz=value-with=in-it' ]
          options = mount.normalizeOptions input
          chai.expect(options.baz).to.equal 'value-with=in-it'

      describe 'multiple --attr', ->
        it 'should set each of the key,value pairs', ->
          input =
            attr: [ 'sub.key11=val111', 'sub.key22=val222' ]
          options = mount.normalizeOptions input
          chai.expect(options.sub.key11).to.equal 'val111'
          chai.expect(options.sub.key22).to.equal 'val222'

      describe 'invalid --attr', () ->
        it 'should be handled somehow...'

