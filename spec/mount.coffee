
chai = require 'chai' unless chai
path = require 'path'
msgflo = require 'msgflo'

mount = require '../src/mount'

# Note: most require running an external broker service
transports =
#  'direct': 'direct://broker1'
#  'MQTT': 'mqtt://localhost'
  'AMQP': 'amqp://localhost'

describe 'Mount', ->

  Object.keys(transports).forEach (type) =>
    address = transports[type]
    console.log address
    coordinator = null
    first = null

    describe ", transport=#{type}: ", () ->

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

      describe 'starting mounted graph', ->
        it 'should not fail', (done) ->
          options =
            broker: address
            graph: 'core/RepeatAsync'
            id: '0-test-*'
          m = new mount.Mounter options
          m.start (err) ->
            chai.expect(err).to.be.a 'null'
            done()

      describe.skip 'starting mounted graph', ->
        it 'should connect to broker', (done) ->
          options =
            broker: address
            graph: 'core/RepeatAsync'
            id: '1-test-*'
          m = new mount.Mounter options
          m.start (err) ->
            chai.expect(err)


      describe.skip 'sending to input queue', ->
        it 'should come out on output queue', (done) ->
          done()
    

