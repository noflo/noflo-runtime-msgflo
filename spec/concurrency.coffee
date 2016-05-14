
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

sendPackets = (address, queue, packets, callback) ->
  client = msgflo.transport.getClient address
  client.connect (err) ->
    return callback err if err
    packets.forEach (packet) ->
      client.sendTo 'inqueue', queue, packet, (err) ->
        # ignored
    client.disconnect callback

concurrencyTests = (address) ->
  coordinator = null

  beforeEach (done) ->
    done()

  afterEach (done) ->
    done()

  describe 'test graph with prefetch=8', ->
    m = null
    options = null
    spy = null
    beforeEach (done) ->
      @timeout 4000
      id = randomstring.generate 4
      options =
        broker: address
        prefetch: 8
        graph: 'TestDelayOrError'
        iips: '{ "matcherror": "error" }'
        name: 'concurrent1'+id
        inports:
          in:
            queue: '_concurrent1_in_'+id
        outports:
          out:
            queue: '_concurrent1_out_'+id
          error:
            queue: '_concurrent1_error_'+id

      m = new mount.Mounter options
      m.start (err) ->
        return done err if err
        spyId = 'protocolspy-'+id+'-'+randomstring.generate(2)
        listen =
          out: options.outports.out.queue
          error: options.outports.error.queue
        spy = msgflo.utils.spy address, spyId, listen
        return  spy.startSpying done

    afterEach (done) ->
      m.stop done

    describe 'sending many messages', ->
      it 'should send as many messages out', (done) ->
        @timeout 4000

        inputs = [
          'dataA'
          'errorA'
          'dataB'
          'dataC'
          'dataD'
          'errorD'
          'dataE'
        ]

        spy.getMessages 'out', 5, (passed) ->
          passed = passed.sort()
          chai.expect(passed).to.eql ['dataA', 'dataB', 'dataC', 'dataD', 'dataE']

          spy.getMessages 'error', 2, (errors) ->
            errors = errors.sort()
            chai.expect(errors).to.eql ['errorA', 'errorD']

            done()
        sendPackets address, options.inports.in.queue, inputs, (err) ->
          return done err if err


describe 'Concurrency', ->
  Object.keys(transports).forEach (type) =>
    address = transports[type]

    describe ", transport=#{type}: ", () ->
      concurrencyTests address

