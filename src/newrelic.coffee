debug = require('debug')('noflo-runtime-msgflo:newrelic')

try
  debug 'attempt load New Relic'
  nr = require 'newrelic'
catch e
  debug 'New Relic integration disabled', e.toString()

class Transactions
  constructor: (@definition) ->
    @transactions = {}

  open: (id, port) ->
    return if not nr?
    debug 'Transaction.open', id
    @transactions[id] =
      id: id
      start: Date.now()
      inport: port

  close: (id, port) ->
    return if not nr?
    transaction = @transactions[id]
    if transaction
      debug 'Transaction.close', id
      duration = Date.now()-transaction.start
      event =
        role: @definition.role
        component: @definition.component
        inport: transaction.inport
        outport: port
        duration: duration
      name = 'MsgfloJobCompleted'
      nr.recordCustomEvent name, event
      debug 'recorded event', name, event
      delete @transactions[id]

exports.Transactions = Transactions
