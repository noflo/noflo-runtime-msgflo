chai = require 'chai'
exec = require('child_process').exec
path = require 'path'

noflo_msgflo_procfile = (fixture, options, callback) ->
  script = path.join __dirname, '../bin', 'noflo-msgflo-procfile'
  graph = path.join __dirname, 'fixtures', fixture
  cmd = "#{script} #{graph} #{options}"
  exec cmd, callback

describe 'noflo-msgflo-procfile', ->

  describe "imgflo-server.fbp", ->
    it 'outputs a Procfile to stdout', (done) ->
      @timeout 4000
      expected = """
      imgflo_worker: noflo-runtime-msgflo --graph imgflo-server/ProcessImage
      web: node index.js
      
      """
      options = "--ignore=imgflo_jobs --ignore=imgflo_api --include 'web: node index.js'"
      noflo_msgflo_procfile 'imgflo-server.fbp', options, (err, stdout) ->
        chai.expect(err).to.not.exist
        chai.expect(stdout).to.equal expected
        done()

