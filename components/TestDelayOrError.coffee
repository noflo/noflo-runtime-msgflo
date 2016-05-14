noflo = require 'noflo'

exports.getComponent = ->
  c = new noflo.Component
  c.description = "Repeat with a random delay, or error"
  c.icon = 'step-forward'

  c.inPorts.add 'in',
    datatype: 'all'
    description: 'Packet to forward'
  c.inPorts.add 'matcherror',
    datatype: 'string'
    description: 'If string matches, error instead of forward'
    default: 'error'

  c.outPorts.add 'out',
    datatype: 'all'
  c.outPorts.add 'error',
    datatype: 'object'

  noflo.helpers.WirePattern c,
    in: ['in']
    out: 'out'
    params: 'matcherror'
    forwardGroups: true
    async: true
  , (data, groups, out, callback) ->

    timeout = Math.random()*200
    setTimeout ->
      console.log 'dd', data
      if data.indexOf(c.params.matcherror) == -1
        out.send data
        do callback
      else
        callback data
    , timeout

  c
