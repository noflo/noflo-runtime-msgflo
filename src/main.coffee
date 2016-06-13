program = require 'commander'
mount = require '../src/mount'
debug = require('debug')('noflo-runtime-msgflo:main')

addOption = (val, list) ->
  list.push val

parse = (args) ->
  program
    .option('--broker <url>', 'Address of messaging broker', String, '')
    .option('--graph <GraphName>', 'Default graph file to load', String, 'core/Repeat')
    .option('--basedir <path>', 'Base directory for NoFlo components', String, '')
    .option('--prefetch <number>', 'How many concurrent jobs / prefetching', Number, 1)
    .option('--name <name[*]>', 'Name of client. Wildcards replaced with random string', String, 'noflo-runtime-msgflo-*')
    .option('--deadletter <in1,in2>', 'Set up deadlettering queues for the named inport', String, '')
    .option('--iips <JSON>', 'Initial information packets (IIP) to send to ports', String, '{}')
    .option('--attr key.subkey=value', 'Additional attributes', addOption, [])
    .option('--trace [true]', 'Enable tracing with Flowtrace', Boolean, false)
    .option('--cache [true]', 'Enable NoFlo component cache', Boolean, false)
    .option('--dedicated-network [true]', 'Create a dedicated NoFlo network for each packet', Boolean, false)
    .parse args

  delete program.options # not clone()able
  delete program._events
  delete program.Command
  delete program.Option
  return program

main = ->
  options = parse process.argv
  m = new mount.Mounter options

  process.on 'uncaughtException', (error) =>
    debug 'uncaught exception', options.trace
    console.log "ERROR: Caught exception #{error.message}" if error.message
    console.log "Stack trace: #{error.stack}" if error.stack

    if not options.trace
      process.exit 2
    m.tracer.dumpFile null, (err, fname) ->
      console.log 'Wrote flowtrace to:', fname
      process.exit 2

  process.on 'SIGUSR2', () =>
    debug 'SIGUSR2', options.trace
    return console.log 'SIGUSR2 caught, but tracing not enabled' if not options.trace
    m.tracer.dumpFile null, (err, fname) ->
      console.log 'Wrote flowtrace to:', fname

  process.on 'SIGTERM', () =>
    debug 'Got SIGTERM, attempting graceful shutdown'
    m.stop (err) ->
      throw err if err # just to get error + stack
      process.exit 0

  m.start (err, def) ->
    throw err if err
    console.log 'noflo-runtime-msgflo started:', "#{def.name}(#{def.graph})", process.pid

exports.parse = parse
exports.main = main
