program = require 'commander'
mount = require '../src/mount'

main = ->
  program
    .option '--broker <url>', 'Address of messaging broker', String, 'amqp://localhost'
    .option '--graph <file.json/fbp>', 'Default graph file to load', String, ''
    .option '--basedir <path>', 'Base directory for NoFlo components', String, ''
    .option '--prefetch <number>', 'How many concurrent jobs / prefetching', Number, 1
    .option '--name <name[*]>', 'Name of client. Wildcards replaced with random string', String, 'noflo-runtime-msgflo-*'
    .parse process.argv

  m = mount.Mounter program
  m.start (err) ->
    throw err if err
    console.log 'Started', program.broker

