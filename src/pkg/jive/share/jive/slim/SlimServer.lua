
--[[
=head1 NAME

jive.slim.SlimServer - SlimServer object

=head1 DESCRIPTION

Represents and interfaces with a real SlimServer on the network.

=head1 SYNOPSIS

 -- Create a SlimServer
 local myServer = SlimServer(jnt, '192.168.1.1', 'Raoul')

 -- Allow some time here for newtork IO to occur

 -- Get the SlimServer version
 local myServerVersion = myServer:getVersion()

=head1 FUNCTIONS

=cut
--]]

-- our stuff
local assert, tostring, type = assert, tostring, type
local pairs, ipairs, setmetatable = pairs, ipairs, setmetatable

local os          = require("os")
local table       = require("table")

local oo          = require("loop.base")

local SocketHttp  = require("jive.net.SocketHttp")
local HttpPool    = require("jive.net.HttpPool")
local Player      = require("jive.slim.Player")
local RequestHttp = require("jive.net.RequestHttp")

local log         = require("jive.utils.log").logger("slimserver")
local logcache    = require("jive.utils.log").logger("slimserver.cache")

require("jive.slim.RequestsCli")
local RequestServerstatus = jive.slim.RequestServerstatus


-- FIXME: squeezenetwork behaviour

-- jive.slim.SlimServer is a base class
module(..., oo.class)

-- our class constants
local HTTPPORT = 9000                -- Slimserver HTTP port
local RETRY_UNREACHABLE = 120        -- Min delay (in s) before retrying a server unreachable


-- _setPlumbingState
-- set the validity status of the server, i.e. can we talk to it
local function _setPlumbingState(self, state)

	if state ~= self.plumbing.state then
		
		log:debug(tostring(self), ":_setPlumbingState(", state, ")")

		if self.plumbing.state == 'init' and state == 'connected' then
			self.jnt:notify('serverConnected', self)
		end

		self.plumbing.state = state
	end
end


-- forward declaration
local _establishConnection

-- _errSink
-- manages connection errors
local function _errSink(self, name, err)

	if err then
		log:error(tostring(self), ": ", err, " during ", name)
	
		-- give peace a chance and retry immediately, unless that's what we were already doing
		if self.plumbing.state == 'retry' then
			_setPlumbingState(self, 'unreachable')
		else
			_setPlumbingState(self, 'retry')
			_establishConnection(self)
		end
	end
	
	-- always return false so data (probably bogus) is not sent for processing
	return false
end


-- _getSink
-- returns a sink
local function _getSink(self, name)

	local func = self[name]
	if func and type(func) == "function" then

		return function(chunk, err)
			
			-- be smart and don't call errSink if not necessary
			if not err or _errSink(self, name, err) then
			
				func(self, chunk)
			end
		end

	else
		log:error(tostring(self), ": no function called [", name .."]")
	end
end


-- _establishConnection
-- sends our long term request
_establishConnection = function(self)
	log:debug(tostring(self), ":_establishConnection()")

	-- try to get a long term connection with the server, timeout at 60 seconds.
	-- get 50 players
	-- FIXME: what if the server has more than 50 players?
	
	self.jsp:fetch(
		RequestServerstatus(
			_getSink(self, "_serverstatusSink"), 
			0, 
			50, 
			60, 
			{
				["playerprefs"] = 'menuItem'
			}
		)
	)
end


-- _serverstatusSink
-- processes the result of the serverstatus call
function _serverstatusSink(self, data, err)
	log:debug(tostring(self), ":_serverstatusSink()")
--	log:info(data)

	-- check we have a result 
	if not data.result then
		log:error(tostring(self), ": chunk with no result ??!")
		log:error(data)
		return
	end

	-- if we get here we're connected
	_setPlumbingState(self, 'connected')
	
	-- remember players from server
	local serverPlayers = data.result["@players"]
	data.result["@players"] = nil
	
	-- remember our state
	local selfState = self.state
	
	-- update in one shot
	self.state = data.result
	
	-- manage rescan
	-- use tostring to handle nil case (in either server of self data)
	if tostring(self.state["rescan"]) != tostring(selfState["rescan"]) then
		-- rescan has changed
		if not self.state["rescan"] then
			-- rescanning
			self.jnt:notify('serverRescanning', self)
		else
			self.jnt:notify('serverRescanDone', self)
		end
	end
	
	-- update players
	
	-- copy all players we know about
	local selfPlayers = {}
	for k,v in pairs(self.players) do
		selfPlayers[k] = k
	end
	
	if data.result["player count"] > 0 then

		for i, player_info in ipairs(serverPlayers) do
	
			-- remove the player from our list since it is reported by the server
			selfPlayers[player_info.playerid] = nil
	
			if not self.players[player_info.playerid] then
			
				self.players[player_info.playerid] = Player(self, self.jnt, self.jpool, player_info)
			end
		end
	else
		log:warn(tostring(self), ": has no players!")
	end
	
	-- any players still in the list are gone...
	for k,v in pairs(selfPlayers) do
		self.players[k]:free()
		self.players[k] = nil
	end
	
end


--[[

=head2 jive.slim.SlimServer(jnt, ip, name)

Create a SlimServer object at IP address I<ip> with name I<name>. Once created, the
object will immediately connect to slimserver to discover players and other attributes
of the server.

=cut
--]]
function __init(self, jnt, ip, name)
	log:debug("SlimServer:__init(", tostring(ip), ", ", tostring(name), ")")

	assert(ip, "Cannot create SlimServer without ip address")

	local obj = oo.rawnew(self, {

		name = name,
		jnt = jnt,

		-- connection stuff
		plumbing = {
			state = 'init',
			lastSeen = os.time(),
			ip = ip,
		},

		-- data from SS
		state = {},

		-- players
		players = {},

		-- our pool
		jpool = HttpPool(jnt, ip, HTTPPORT, 4, 2, name),

		-- our socket for long term connections
		jsp = SocketHttp(jnt, ip, HTTPPORT, name .. "LT"),
		
	})

	obj.id = obj:idFor(ip, port, name)
	
	-- our long term request
	_establishConnection(obj)
	
	-- We're here!
	obj.jnt:notify('serverNew', obj)
	
	return obj
end


--[[

=head2 jive.slim.SlimServer:free()

Deletes a SlimServer object, frees memory and closes connections with the server.

=cut
--]]
function free(self)
	log:debug(tostring(self), ":free()")
	
	-- notify we're going away
	self.jnt:notify("serverDelete", self)

	-- delete players
	for id, player in pairs(self.players) do
		player:free()
	end
	self.players = nil

	-- delete connections
	if self.jpool then
		self.jpool:free()
		self.jpool = nil
	end
	if self.jsp then
		self.jsp:free()
		self.jsp = nil
	end
end


--[[

=head2 jive.slim.SlimServer:idFor(ip, port, name)

Returns an identifier for a server named I<name> at IP address I<ip>:I<port>.

=cut
--]]
function idFor(self, ip, port, name)
	return tostring(ip) .. ":" .. tostring(port)
end


--[[

=head2 jive.slim.SlimServer:updateFromUdp(name)

The L<jive.slim.SlimServers> cache calls this method every time the server
answers the discovery request. This method updates the server name if it has changed
and manages retries of the server long term connection.

=cut
--]]
function updateFromUdp(self, name)
	log:debug(tostring(self), ":updateFromUdp()")

	-- update the name in all cases
	if self.name ~= name then
	
		log:info(tostring(self), ": Renamed to ", tostring(name))
		self.name = name
	end

	-- manage retries
	local now = os.time()
	
	if self.plumbing.state == 'unreachable' and now - self.plumbing.lastSeen > RETRY_UNREACHABLE then
		_setPlumbingState(self, 'retry')
		_establishConnection(self)
	end

	self.plumbing.lastSeen = now
end


--[[

=head2 jive.slim.SlimServer:fetchArtworkThumb(artworkId, sink, uriGenerator)

Get the thumb for I<artworkId> and send it to I<sink>. I<uriGenerator> must be a function that
computes the URI to request the artwork from the server from I<artworkId> (i.e. if needed, this
method will call uriGenerator(artworkId) and use the result as URI).
The SlimServer object maintains an artwork cache.

=cut
--]]

-- FIXME: the CLI does not return a consistent ID per album.
-- If we want to cache, we would need ONE id by album available everywhere.

local _artworkThumbCache = setmetatable({}, { __mode="kv" })
local _artworkThumbSinks = {}


-- _dunpArtworkCache
-- returns statistical data about our cache
local function _dumpArtworkThumbCache()
	local size = 0
	local items = 0
	for k, v in pairs(_artworkThumbCache) do
		items = items + 1
		size = size + #v
	end
	logcache:debug("_artworkThumbCache: ", tostring(items), " items, ", tostring(size), " bytes")
end


-- _getArworkThumbSink
-- returns a sink for artwork so we can cache it before sending it forward
local function _getArtworkThumbSink(artworkId)

	return function(chunk, err)
		-- on error, print something...
		if err then
			logcache:error("_getArtworkThumbSink(", tostring(artworkId), "):", err)
		end
		-- if we have data
		if chunk then
			logcache:debug("_getArtworkThumbSink(", tostring(artworkId), ")")
			-- call all stored sinks
			for i,sink in ipairs(_artworkThumbSinks[artworkId]) do
				sink(chunk)
				sink(nil)
			end
			-- store the artwork in the cache
			_artworkThumbCache[artworkId] = chunk
			
			if logcache:isDebug() then
				_dumpArtworkThumbCache()
			end
		end
		-- in all cases, remove the sinks
		_artworkThumbSinks[artworkId] = nil
	end
end


function fetchArtworkThumb(self, artworkId, sink, uriGenerator)
	logcache:debug(tostring(self), ":fetchArtworkThumb(", tostring(artworkId), ")")

	if logcache:isDebug() then
		_dumpArtworkThumbCache()
	end

	-- do we have the artwork in the cache
	local artwork = _artworkThumbCache[artworkId]
	if artwork then
		logcache:debug("..artwork in cache")
		sink(artwork)
		sink(nil)
		return
	end
	
	-- are we requesting it already?
	local sinks = _artworkThumbSinks[artworkId]
	if sinks then
		logcache:debug("..artwork already requested")
		table.insert(sinks, sink)
		return
	end
	
	-- no luck, generate a request for the artwork
	local req = RequestHttp(
		_getArtworkThumbSink(artworkId), 
		'GET', 
		uriGenerator(artworkId)
	)
	-- remember the sink
	_artworkThumbSinks[artworkId] = {sink}
	logcache:debug("..fetching artwork")
	self.jpool:queue(req)

end


--[[

=head2 tostring(aSlimServer)

if I<aSlimServer> is a L<jive.SlimServer>, prints
 SlimServer {name}

=cut
--]]
function __tostring(self)
	return "SlimServer {" .. tostring(self.name) .. "}"
end


-- Accessors

--[[

=head2 jive.slim.SlimServer:getVersion()

Returns the server version

=cut
--]]
function getVersion(self)
	return self.version
end


--[[

=head2 jive.slim.SlimServer:getIpPort()

Returns the server IP address and HTTP port

=cut
--]]
function getIpPort(self)
	return self.plumbing.ip, HTTPPORT
end


--[[

=head2 jive.slim.SlimServer:getName()

Returns the server name

=cut
--]]
function getName(self)
	return self.name
end


--[[

=head2 jive.slim.SlimServer:getLastSeen()

Returns the time at which the last indication the server is alive happened,
either data from the server or response to discovery. This is used by
L<jive.slim.SlimServers> to delete old servers.

=cut
--]]
function getLastSeen(self)
	return self.plumbing.lastSeen
end


--[[

=head2 jive.slim.SlimServer:isConnected()

Returns the state of the long term connection with the server. This is used by
L<jive.slim.SlimServers> to delete old servers.

=cut
--]]
function isConnected(self)
	return self.plumbing.state == "connected"
end


-- Proxies

function queue(self, request)
	self.jpool:queue(request)
end
function queuePriority(self, request)
	self.jpool:queuePriority(request)
end

--[[

=head1 LICENSE

Copyright 2007 Logitech. All Rights Reserved.

This file is subject to the Logitech Public Source License Version 1.0. Please see the LICENCE file for details.

=cut
--]]

