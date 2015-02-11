
noflo-runtime-msgflo
====================

[NoFlo](https://noflojs.org) runtime, designed for use with [msgflo](https://github.com/the-grid/msgflo).
Loads a NoFlo graph and registers it as a msgflo participant.
The exported ports of the NoFlo network then becomes accessible through message queues (AMQP or MQTT),
and msgflo can coordinate how multiple such networks send data between eachother.

Will eventually allow a single entry-point for
[FBP runtime protocol](http://noflojs.org/documentation/protocol) clients (like [Flowhub](http://flowhub.io))
to access NoFlo FBP networks that span multiple nodes.


TODO
-----

* Implement FBP protocol over msgflo transport
