
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
        it 'should connect to broker', (done) ->
          @timeout 4000
          options =
            broker: address
            graph: 'core/RepeatAsync'
            name: '1someone'
          m = new mount.Mounter options
          m.start (err) ->
            chai.expect(err).to.be.a 'null'
            coordinator.once 'participant-added', (participant) ->
              chai.expect(participant.id).to.contain options.name
              done()

      describe 'sending to input queue', ->
        it 'should come out on output queue', (done) ->
          options =
            broker: address
            graph: 'core/RepeatAsync'
            name: '1some2'
          m = new mount.Mounter options
          m.start (err) ->
            chai.expect(err).to.be.a 'null'
            coordinator.once 'participant-added', (participant) ->
              console.log 'added', participant
              chai.expect(participant.id).to.contain options.name
              part = participant.id
              coordinator.subscribeTo part, 'out', (msg) ->
                chai.expect(msg.data).to.eql { foo: 'bar' }
                done()
              coordinator.sendTo part, 'in', { foo: 'bar' }
    

