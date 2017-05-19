# 0.11.3 - May 5, 2017

* Discovery messages sent to MsgFlo now contain NoFlo component icon and description

# 0.11.0 - March 15, 2017

Breaking changes

* Updated `noflo` to 0.8.x. This release breaks compatibility with 0.7.x.
See the [release announcement](http://bergie.iki.fi/blog/noflo-0-8/).

# 0.10.0 - March 15, 2017

* MsgFlo discovery messages are now sent periodically, not just on startup
* Updated `msgflo` to 0.10.x and `msgflo-nodejs` to 0.9.x

# 0.9.0 - November 29, 2016

* Updated `msgflo` to 0.9.x and `msgflo-nodejs` to 0.7.x
* Updated `fbp` to 1.5.x, some new convenience syntax in .FBP files

# 0.8.0 - June 13, 2016

* Support `--dedicated-network` option, creates a new NoFlo.Network instance for each message.
This makes it easier to have concurrency safety, but means networks cannot share state at all.

# 0.7.0 - June 2, 2016

* Update to NoFlo 0.7.x. This has some breaking changes in non-core parts of the API, see the [NoFlo changelog](https://github.com/noflo/noflo/blob/master/CHANGES.md#070-march-31st-2016).

# 0.2.14 - February 17, 2016

* Add support for specifying IIPs via `--iip '{ "portA": "iipA", ... }'`

# 0.2.1 - November 21, 2015

* Initial support for recording [Flowtrace](https://github.com/flowbased/flowtrace)s

# 0.1.12 - October 5, 2015

* Fixed support for MQTT transport and added end2end tests

# 0.1.8

* Support setting up deadletter queues using `--deadletter` option

# 0.1.3

* Add support for New Relic Insights metrics for executed jobs. Event: `MsgfloJobCompleted`

# 0.1.0 - June 23, 2015

* Can expose a NoFlo graph as a MsgFlo participant
* Support for AMQP / RabbitMQ transport
* Used in production at [The Grid](https://thegrid.io)
