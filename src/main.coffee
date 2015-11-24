program = require 'commander'
mount = require '../src/mount'

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
    .option('--attr key.subkey=value', 'Additional attributes', addOption, [])
    .option('--trace [true]', 'Enable tracing with Flowtrace', Boolean, false)
    .option('--ignore-exceptions [false]', 'Do not exit process when caught exceptions', Boolean, false)
    .parse args

  delete program.options # not clone()able
  return program

main = ->
  options = parse process.argv
  m = new mount.Mounter options

  process.on 'uncaughtException', (error) =>
    return console.log 'ERROR: Tracing not enabled' if not options.trace
    console.log "ERROR: Caught exception #{error.message}" if error.message
    console.log "Stack trace: #{error.stack}" if error.stack
    m.tracer.dumpFile null, (err, fname) ->
      console.log 'Wrote flowtrace to:', fname
      process.exit(2) if not options.ignoreExceptions

  process.on 'SIGUSR2', () =>
    return console.log 'ERROR: Tracing not enabled' if not options.trace
    m.tracer.dumpFile null, (err, fname) ->
      console.log 'Wrote flowtrace to:', fname

  m.start (err, def) ->
    throw err if err
    console.log 'noflo-runtime-msgflo started:', "#{def.name}(#{def.graph})"

exports.parse = parse
exports.main = main
