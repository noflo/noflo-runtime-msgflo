
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

describe 'Mount', ->
  Object.keys(transports).forEach (type) =>
    address = transports[type]

    describe ", transport=#{type}: ", () ->
      transportTest address

  # FIXME: implement test for these cases
  describe 'specifying queue name in options', ->
    it 'should be used instead of default'
  describe 'specifying port as hidden', ->
    it 'should not create queue'

