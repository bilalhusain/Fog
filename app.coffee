fs = require 'fs'

express = require 'express'
winston = require 'winston'

# configuration stuff
PORT = 3003
BASE_URL = "http://localhost:#{PORT}"

# representation for available modules (in-memory storage)
class ModuleSnapshot # a particular version of module
	@obj = {}

	constructor: (name, version) ->
		@obj =
			name: name
			_id: name
			version: version
			dist:
				tarball: "#{BASE_URL}/registry/#{name}/-/#{name}-#{version}.tgz"

	toJson: -> JSON.stringify @obj

class Module
	@obj = {}

	constructor: (name, latestVersion, modules) ->
		@obj =
			name: name
			'dist-tags':
				latest: latestVersion
			_id: name
			versions: {}

		for module in modules
			@obj.versions[module.obj.version] = module.obj

	toJson: -> JSON.stringify @obj

registry = {}
loadRegistry =  () ->
	winston.log 'info', 'loading registry'

	# scan tarballs directory for tarballs/:module-:version.tgz
	tarballs = fs.readdirSync './tarballs'
	for tarball in tarballs
		m = /^(.*)-(\d+)\.(\d+)\.(\d+)\.tgz$/.exec tarball
		return if not m # not a module tarball

		if not registry[m[1]]
			registry[m[1]] = new Module(m[1], '0.0.0', [])

		version = "#{m[2]}.#{m[3]}.#{m[4]}"
		registry[m[1]].obj.versions[version] = new ModuleSnapshot(m[1], version)
		winston.log 'info', "loaded #{m[0]} into registry"

	# finally figure out all the latest version
	for k, v of registry
		latestVersion = [0, 0, 0] # major, minor, patch
		for version, snapshot of registry[k].obj.versions
			values = version.split '.'
			if values.length isnt 3
				throw 'invalid semver'
			major = +values[0]
			minor = +values[1]
			patch = +values[2]
			if (major > latestVersion[0])
				latestVersion = [major, minor, patch]
			else if (major is latestVersion[0] and minor > latestVersion[1])
				latestVersion = [major, minor, patch]
			else if (major is latestVersion[0] and minor is latestVersion[1] and patch > latestVersion[2])
				latestVersion = [major, minor, patch]
			else
				# nothing

		registry[k].obj.version = latestVersion.join '.'
		registry[k].obj['dist-tags']['latest'] = latestVersion.join '.'
		winston.log 'info', "updated latest for module #{k} in registry"


# the webapp
app = express.createServer()

app.configure () ->
	app.use express.bodyParser()

	loadRegistry()
	for k, item of registry
		winston.log 'info', "#{item.obj.name}\n---\n#{item.toJson()}\n"

app.get "/registry/:module/-/*", (req, res) ->
	winston.log 'info', "requested tarball #{req.params[0]}"
	fs.readFile "tarballs/#{req.params[0]}", (err, data) ->
		if err
			res.send 404
			return
		res.send data

app.get '/registry/:module', (req, res) ->
	winston.log 'info', "requested module #{req.params.module}"

	module = req.params.module
	if not registry[module]
		res.send 404
		return
	res.send registry[module].toJson()

app.get '/registry/:module/:version', (req, res) ->	
	winston.log 'info', "GET /registry/:module/:version"

	module = req.params.module
	version = req.params.version
	winston.log 'info', "requested module #{module} version #{version}"
	if not registry[module] or not registry[module].obj.versions[version]
		res.send 404
		return
	res.send registry[module].obj.versions[version].toJson()

app.put '/registry/:module', (req, res) ->
	winston.log 'info', "PUT /registry/:module"

	module = req.params.module
	if registry[module]
		res.send registry[module].toJson()
	else
		registry[module] = new Module(module, '0.0.0', [])
		res.send '{}'

app.put '/registry/:module/:version/-tag/latest', (req, res) ->
	winston.log 'info', "PUT /registry/:module/:version/-tag/latest"

	module = req.params.module
	version = req.params.version
	# don't know if should respond with latest tag or blindly take as latest
	registry[module].obj.version = version
	registry[module].obj.versions[version] = new ModuleSnapshot(module, version)
	res.send registry[module].toJson()

app.put '/registry/:module/-/:filename/*', (req, res) ->
	winston.log 'info', "PUT /registry/:module/-/:filename"

	module = req.params.module
	stream = fs.createWriteStream "tarballs/#{req.params.filename}"
	req.on 'data', (chunk) ->
		stream.write chunk
	req.on 'end', () ->
		stream.end()
		res.send registry[module].toJson()

app.all '*', (req, res) ->
	winston.log 'warn', "unmatched path #{req.params[0]}"
	res.send 404

app.listen PORT

