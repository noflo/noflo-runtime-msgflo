program = require 'commander'
mount = require '../src/mount'

addOption = (val, list) ->
  list.push val

parse = (args) ->
  program
    .option('--broker <url>', 'Address of messaging broker', String, 'amqp://localhost')
    .option('--graph <GraphName>', 'Default graph file to load', String, 'core/Repeat')
    .option('--basedir <path>', 'Base directory for NoFlo components', String, '')
    .option('--prefetch <number>', 'How many concurrent jobs / prefetching', Number, 1)
    .option('--name <name[*]>', 'Name of client. Wildcards replaced with random string', String, 'noflo-runtime-msgflo-*')
    .option('--attr key.subkey=value', 'Additional attributes', addOption, [])
    .parse args

  delete program.options # not clone()able
  return program
    
main = ->
  options = parse process.argv
  m = new mount.Mounter program
  m.start (err) ->
    throw err if err
    console.log 'Started', program.broker

exports.parse = parse
exports.main = main
