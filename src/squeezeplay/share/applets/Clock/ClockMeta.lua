local oo            = require("loop.simple")

local AppletMeta    = require("jive.AppletMeta")

local appletManager = appletManager
local jiveMain      = jiveMain


module(...)
oo.class(_M, AppletMeta)


function jiveVersion(self)
	return 1, 1
end

function defaultSettings(self)
	return {
		-- nothing to see here, move along, move along
	}
end

function registerApplet(self)

end

function configureApplet(self)

	--[[
	-- TODO: Radial Clock
	appletManager:callService("addScreenSaver",
		self:string("SCREENSAVER_CLOCK_STYLE_RADIAL"), 
		"NewClock", 
		"openAnalogClock", _, _, 20
	)
	--]]

	appletManager:callService("addScreenSaver",
		self:string("SCREENSAVER_CLOCK_STYLE_DIGITAL"), 
		"Clock", 
		"openDetailedClock", _, _, 24
	)

	appletManager:callService("addScreenSaver",
		self:string("SCREENSAVER_CLOCK_STYLE_DOTMATRIX"), 
		"Clock", 
		"openStyledClock", _, _, 26
	)
end


--[[

=head1 LICENSE

Copyright 2007 Logitech. All Rights Reserved.

This file is subject to the Logitech Public Source License Version 1.0. Please see the LICENCE file for details.

=cut
--]]
