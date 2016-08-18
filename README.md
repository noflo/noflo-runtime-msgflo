
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

## Debugging

noflo-runtime-msgflo supports [flowtrace](https://github.com/flowbased/flowtrace) allows to trace & store the execution of the NoFlo network,
so you can debug any issues that would occur.
You can enable tracing using `--trace` commandline argument,
or via the `trace:start` [FBP runtime protocol](http://noflojs.org/documentation/protocol/#trace) message.

    noflo-runtime-msgflo --graph project/MyMainGraph --trace

To trigger dumping a flowtrace locally, send the `SIGUSR2` Unix signal

    kill -SIGUSR2 $PID_OF_PROCESS
    ... Wrote flowtrace to: /tmp/1151020-12063-ami5vq.json

Or, to trigger a flowtrace remotely, send a `trace:dump` FBP protocol message to the queue of participant.

    msgflo-send-message --queue .fbp.$participantId.receive --json '{ "protocol":"trace", "command":"dump", "payload":{ "graph":"default", "type":"flowtrace.json"} }'

Then, assuming `.fbp.$participantId.send` has been bound to queue `my-flowtraces`, one could download it

    msgflo-dump-message --queue my-flowtraces --amount 1

You can now use various flowtrace tools to introspect the data.
For instance, you can get a human readable log using `flowtrace-show`

    flowtrace-show /tmp/1151020-12063-ami5vq.json

    -> IN repeat CONN
    -> IN repeat DATA hello world
    -> IN stdout CONN
    -> IN stdout DATA hello world
    -> IN repeat DISC
    -> IN stdout DISC

Optimizing startup time
----

Since NoFlo 0.7 [FBP manifest](https://github.com/flowbased/fbp-manifest) 
is used, making it possible to cache components which turns process startup
faster due to less disk IO.
To cache graph's components, first install `noflo` and run
`noflo-cache-preheat` to create the FBP manifest file `fbp.json`. Then run the
graph passing the cache parameter:

    noflo-runtime-msgflo --cache true --name myworker --graph project/WorkerGraph --broker amqp://foo.cloudamqp.com/bar

TODO
-----

### 0.3

* Implement [FBP protocol over msgflo](https://github.com/noflo/noflo-runtime-msgflo/issues/30) transport
