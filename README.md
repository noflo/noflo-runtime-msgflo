
noflo-runtime-msgflo
====================

[NoFlo](https://noflojs.org) runtime, designed for use with [msgflo](https://github.com/the-grid/msgflo).
Loads a NoFlo graph and registers it as a msgflo participant.
The exported ports of the NoFlo network then becomes accessible through message queues
([AMQP](http://en.wikipedia.org/wiki/Advanced_Message_Queuing_Protocol) or [MQTT](http://en.wikipedia.org/wiki/MQTT)),
and msgflo can coordinate how multiple such networks send data between eachother.

Will eventually allow a single entry-point for
[FBP runtime protocol](http://noflojs.org/documentation/protocol) clients (like [Flowhub](http://flowhub.io))
to access NoFlo FBP networks that span multiple nodes.


Usage
------

Using the commandline tool

    noflo-runtime-msgflo --name myworker --graph project/WorkerGraph --broker amqp://foo.cloudamqp.com/bar

Altenatively one can use the embedding API, see [src/mount.coffee](./src/mount.coffee)

    runtime = require 'noflo-runtime-msgflo'
    options =
      name: 'gssmeasure'
      graph: 'the-grid-api/PrecomputeGss',
      basedir: __dirname
      broker: config.amqp.url,
    rt = new runtime.mount.Mounter options
    rt.start (err, rt) ->
      # started


TODO
-----

* Implement FBP protocol over msgflo transport
