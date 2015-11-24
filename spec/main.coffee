chai = require 'chai' unless chai

main = require('..').main

describe 'Parse', ->

  describe 'when ignore-exceptions option is given', ->

    it 'should not ignore exceptions', (done) ->
      args = '--ignore-exceptions'
      options = main.parse args
      chai.expect(options.ignoreExceptions).to.exist
      chai.expect(options.ignoreExceptions).to.be.a 'boolean'
      chai.expect(options.ignoreExceptions).to.be.equal false
      done()
