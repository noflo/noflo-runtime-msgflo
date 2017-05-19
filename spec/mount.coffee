
chai = require 'chai' unless chai
path = require 'path'
msgflo = require 'msgflo'
randomstring = require 'randomstring'

mount = require('..').mount

# Note: most require running an external broker service
variants =
#  'direct': 'direct://broker1'
  'MQTT_single':
    broker: 'mqtt://localhost'
    dedicatedNetwork: false
  'MQTT_dedicated':
    broker: 'mqtt://localhost'
    dedicatedNetwork: true
  'AMQP_single':
    broker: 'amqp://localhost'
    dedicatedNetwork: false
  'AMQP_dedicated':
    broker: 'amqp://localhost'
    dedicatedNetwork: true

objectValues = (o) ->
  Object.keys(o).map (k) -> o[k]

# Need to ensure that if coordinator has already received participant
# we still fire the callback
onParticipantAdded = (coordinator, name, callback) ->
  participantMatches = (p) ->
    return p.id.indexOf(name) != -1
  returned = false
  onAdded = (p) ->
    return if returned
    return if not participantMatches p
    returned = true
    return callback p
  coordinator.once 'participant-added', onAdded
  matches = objectValues(coordinator.participants).filter participantMatches
  onAdded matches[0] if matches.length

extendOptions = (options, props = {}) ->
  newOptions = JSON.parse JSON.stringify options
  newOptions[key] = val for key, val of props
  newOptions

transportTest = (originalOptions) ->
  coordinator = null

  beforeEach (done) ->
    broker = msgflo.transport.getBroker originalOptions.broker
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
      options = extendOptions originalOptions,
        graph: 'core/RepeatAsync'
        name: '1someone'+randomstring.generate 4
      m = new mount.Mounter options
      m.start done

    afterEach (done) ->
      m.stop done

    it 'should connect to broker', (done) ->
      onParticipantAdded coordinator, options.name, (participant) ->
        chai.expect(participant.id).to.contain options.name
        done()

    describe 'sending to input queue', ->
      it.skip 'should come out on output queue', (done) ->
        onParticipantAdded coordinator, options.name, (participant) ->
          chai.expect(participant.id).to.contain options.name
          part = participant.id
          # XXX: Coordinator should do this??
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
      options = extendOptions originalOptions,
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
      it 'should output on specified exchange', (done) ->
        input = { 'ff': 'uuuu' }
        onResult = (msg) ->
          chai.expect(msg.data).to.eql input
          done()
        client = msgflo.transport.getClient options.broker
        client.connect (err) ->
          chai.expect(err).to.not.exist
          client.createQueue 'inqueue', options.outports['out'].queue, (err) ->
            chai.expect(err).to.not.exist
            client.subscribeToQueue options.outports['out'].queue, onResult, (err) ->
              chai.expect(err).to.not.exist
              client.sendTo 'inqueue', options.inports['in'].queue, input, (err) ->
                chai.expect(err).to.not.exist

  describe 'graph with multiple outputs for initial job', ->
    m = null
    options = null
    beforeEach (done) ->
      @timeout 4000
      id = randomstring.generate 4
      options = extendOptions originalOptions,
        graph: 'objects/SplitArray'
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
        @timeout 2000
        input = ['a', 'b', 'c']
        expected = input.slice 0
        onResult = (msg) ->
          chai.expect(msg.data).to.eql expected.shift()
          client.ackMessage msg
          done() unless expected.length
        client = msgflo.transport.getClient options.broker
        client.connect (err) ->
          chai.expect(err).to.not.exist
          client.createQueue 'inqueue', options.outports['out'].queue, (err) ->
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
      options = extendOptions originalOptions,
        graph: 'core/ReadEnv'
        name: 'deadlettering'+id
        inports:
          key:
            hidden: false
        outports:
          error:
            hidden: true
          out:
            hidden: true
        deadletter: 'key'
      m = new mount.Mounter options
      m.start done
    afterEach (done) ->
      m.stop done

    describe 'input message causing error', ->
      it 'should be sent to deadletter queue', (done) ->
        return @skip() if options.broker.substr(0, 4) is 'mqtt'
        @timeout 4000
        inputCausingError = '__non_exitsting_envvar___'
        onDeadletter = (msg) ->
          chai.expect(msg.data).to.eql inputCausingError
          done()
        inPort = m.getDefinition().inports.filter((p) -> p.id == 'key')[0]
        deadletter = 'dead-'+inPort.queue
        client = msgflo.transport.getClient options.broker
        client.connect (err) ->
          chai.expect(err).to.not.exist
          client.subscribeToQueue deadletter, onDeadletter, (err) ->
            chai.expect(err).to.not.exist
            client.sendTo 'inqueue', inPort.queue, inputCausingError, (err) ->
              chai.expect(err).to.not.exist

  describe 'IIPs specified on commandline with component', ->
    m = null
    options = null
    beforeEach (done) ->
      @timeout 4000
      id = randomstring.generate 4
      options = extendOptions originalOptions,
        graph: 'core/Kick'
        name: 'iips'+id
        inports:
          data:
            hidden: true
          in:
            queue: '_iipin_'+id
        outports:
          out:
            queue: '_iipout_'+id
        iips: '{ "data": "my iip wins" }'
      m = new mount.Mounter options
      m.start done
    afterEach (done) ->
      @timeout 4*1000
      m.stop done

    describe 'sending bang to Kick', ->
      it 'should send the IIP out', (done) ->
        @timeout 2000
        input = [ null ]
        expected = [ 'my iip wins' ]
        onResult = (msg) ->
          chai.expect(msg.data).to.eql expected.shift()
          client.ackMessage msg
          done() unless expected.length
        client = msgflo.transport.getClient options.broker
        client.connect (err) ->
          chai.expect(err).to.not.exist
          client.createQueue 'inqueue', options.outports['out'].queue, (err) ->
            chai.expect(err).to.not.exist
            client.subscribeToQueue options.outports['out'].queue, onResult, (err) ->
              chai.expect(err).to.not.exist
              client.sendTo 'inqueue', options.inports['in'].queue, input, (err) ->
                chai.expect(err).to.not.exist

  describe 'IIPs on commandline overriding IIP in graph', ->
    m = null
    options = null
    beforeEach (done) ->
      @timeout 4000
      id = randomstring.generate 4
      options = extendOptions originalOptions,
        graph: 'IIPKickTest'
        name: 'graphiips'+id
        inports:
          data:
            hidden: true
          in:
            queue: '_graphiipin_'+id
        outports:
          out:
            queue: '_graphiipout_'+id
        iips: '{ "data": "msgflo iip wins" }'
      m = new mount.Mounter options
      m.start done
    afterEach (done) ->
      m.stop done

    describe 'sending bang to Kick', ->
      it 'should send the IIP out', (done) ->
        @timeout 2000
        input = [ null ]
        expected = [ 'msgflo iip wins' ]
        onResult = (msg) ->
          chai.expect(msg.data).to.eql expected.shift()
          client.ackMessage msg
          done() unless expected.length
        client = msgflo.transport.getClient options.broker
        client.connect (err) ->
          chai.expect(err).to.not.exist
          client.createQueue 'inqueue', options.outports['out'].queue, (err) ->
            chai.expect(err).to.not.exist
            client.subscribeToQueue options.outports['out'].queue, onResult, (err) ->
              chai.expect(err).to.not.exist
              client.sendTo 'inqueue', options.inports['in'].queue, input, (err) ->
                chai.expect(err).to.not.exist

describe 'Mount', ->
  Object.keys(variants).forEach (type) =>
    options = variants[type]

    describe ", variant=#{type}: ", () ->
      transportTest options

    describe 'attempting stop without start', () ->
      it 'should return sucess without doing anything', (done) ->
        newOptions = extendOptions options,
          graph: 'core/RepeatAsync'
          name: '1someone'+randomstring.generate 4
        m = new mount.Mounter newOptions
        m.stop done

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

      describe '--attr inports.myport.hidden=true', ->
        it 'should set myport to be hidden', ->
          input =
            inports:
              myport:
                description: 'some port'
            attr: [ 'inports.myport.hidden=true' ]
          options = mount.normalizeOptions input
          isHidden = if options.inports.myport.hidden then true else false
          chai.expect(isHidden).to.eql true

      describe 'multiple --attr', ->
        it 'should set each of the key,value pairs', ->
          input =
            attr: [ 'sub.key11=val111', 'sub.key22=val222' ]
          options = mount.normalizeOptions input
          chai.expect(options.sub.key11).to.equal 'val111'
          chai.expect(options.sub.key22).to.equal 'val222'

      describe 'invalid --attr', () ->
        it 'should be handled somehow...'

      describe 'deadletter=in,item,foo', ->
        it 'should be split into an array', ->
          input =
            deadletter: 'in,item,foo'
          options = mount.normalizeOptions input
          chai.expect(options.deadletter).to.eql ['in', 'item', 'foo']
