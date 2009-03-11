
--[[
=head1 NAME

jive.ui.Textarea - A text area widget.

=head1 DESCRIPTION

A text area widget, extends L<jive.ui.Widget>.

=head1 SYNOPSIS

 -- Create a new text area
 local textarea = jive.ui.Textarea("text", "This is some\ntext that spans\nseveral lines")

 -- Scroll the text down by 2 lines
 textarea:scroll(2)

 -- Set the text
 textarea:setValue("Different text")

=head1 STYLE

The Label includes the following style parameters in addition to the widgets basic parameters.

=over

B<bg> : the background color, defaults to no background color.

B<fg> : the foreground color, defaults to black.

B<bg_img> : the background image.

B<font> : the text font, a L<jive.ui.Font> object.

B<line_height> : the line height to use, defaults to the font ascend height.
=back

B<text_align> : the text alignment.

=head1 METHODS

=cut
--]]


-- stuff we use
local _assert, string, tostring, type = _assert, string, tostring, type

local oo	= require("loop.simple")
local string	= require("string")
local Widget	= require("jive.ui.Widget")
local Scrollbar	= require("jive.ui.Scrollbar")
local Flick	= require("jive.ui.Flick")
local math      = require("math")

local log       = require("jive.utils.log").logger("ui")


local EVENT_SCROLL	= jive.ui.EVENT_SCROLL
local EVENT_KEY_PRESS	= jive.ui.EVENT_KEY_PRESS
local EVENT_MOUSE_PRESS    = jive.ui.EVENT_MOUSE_PRESS
local EVENT_MOUSE_DOWN     = jive.ui.EVENT_MOUSE_DOWN
local EVENT_MOUSE_UP       = jive.ui.EVENT_MOUSE_UP
local EVENT_MOUSE_MOVE     = jive.ui.EVENT_MOUSE_MOVE
local EVENT_MOUSE_DRAG     = jive.ui.EVENT_MOUSE_DRAG
local EVENT_MOUSE_HOLD     = jive.ui.EVENT_MOUSE_HOLD
local EVENT_MOUSE_ALL      = jive.ui.EVENT_MOUSE_ALL

local EVENT_CONSUME	= jive.ui.EVENT_CONSUME
local EVENT_UNUSED	= jive.ui.EVENT_UNUSED
local ACTION    	= jive.ui.ACTION

local KEY_FWD		= jive.ui.KEY_FWD
local KEY_REW		= jive.ui.KEY_REW
local KEY_GO		= jive.ui.KEY_GO
local KEY_BACK		= jive.ui.KEY_BACK
local KEY_UP          = jive.ui.KEY_UP
local KEY_DOWN        = jive.ui.KEY_DOWN
local KEY_LEFT        = jive.ui.KEY_LEFT
local KEY_RIGHT       = jive.ui.KEY_RIGHT
local KEY_PAGE_UP     = jive.ui.KEY_PAGE_UP
local KEY_PAGE_DOWN   = jive.ui.KEY_PAGE_DOWN


-- our class
module(...)
oo.class(_M, Widget)


--[[

=head2 jive.ui.Textarea(style, text)

Construct a new Textarea widget. I<style> is the widgets style. I<text> is the initial text displayed.

=cut
--]]
function __init(self, style, text)
	_assert(type(style) == "string")
	_assert(type(text) ~= nil)

	local obj = oo.rawnew(self, Widget(style))
	obj.scrollbar = Scrollbar("scrollbar",
		function(_, value)
			obj:_scrollTo(value)
		end)
	obj.scrollbar.parent = obj
	obj.dragOrigin = {}
	obj.dragYSinceShift = 0
	obj.pixelOffsetY = 0
	obj.currentShiftDirection = 0

	obj.flick = Flick(obj)

	obj.topLine = 0
	obj.visibleLines = 0
	obj.text = text

	obj:addActionListener("page_up", obj, _pageUpAction)
	obj:addActionListener("page_down", obj, _pageDownAction)
	--up/down coming in as scroll events

	obj:addListener(EVENT_SCROLL | EVENT_MOUSE_ALL,
			 function (event)
				return obj:_eventHandler(event)
			 end)
	
	return obj
end


--[[

=head2 jive.ui.Textarea:getText()

Returns the text contained in this Textarea.

=cut
--]]
function getText(self)
	return self.text
end


--[[

=head2 jive.ui.Textarea:setValue(text)

Sets the text in the Textarea to I<text>.

=cut
--]]
function setValue(self, text)
	self.text = text
	self:reLayout()
end


--[[

=head2 jive.ui.Textarea:isScrollable()

Returns true if the textarea is scrollable, otherwise it returns false.

=cut
--]]
function isScrollable(self)
	return true -- #self.items > self.visibleItems
end


function isTouchMouseEvent(self, mouseEvent)
	local x, y, fingerCount = mouseEvent:getMouse()

	return fingerCount ~= nil
end


function _pageUpAction(self)
	self:scrollBy( -(self.visibleLines - 1) )
end


function _pageDownAction(self)
	self:scrollBy( self.visibleLines - 1 )
end


--[[

=head2 jive.ui.Textarea:scrollBy(scroll)

Scroll the Textarea by I<scroll> items. If I<scroll> is negative the text scrolls up, otherwise the text scrolls down.

=cut
--]]
function scrollBy(self, scroll)
	_assert(type(scroll) == "number")

	self:_scrollTo(self.topLine + scroll)
end

function _scrollTo(self, topLine)
	if topLine < 0 then
		topLine = 0
	end
	if topLine + self.visibleLines > self.numLines then
		topLine = self.numLines - self.visibleLines
	end

	self.topLine = topLine
	self.scrollbar:setScrollbar(0, self.numLines, self.topLine + 1, self.visibleLines)
	self:reDraw()
end


function _eventHandler(self, event)
	local type = event:getType()

	if type == EVENT_SCROLL then

		self:scrollBy(event:getScroll())
		return EVENT_CONSUME
	end

	if type == EVENT_MOUSE_PRESS or type == EVENT_MOUSE_HOLD or type == EVENT_MOUSE_MOVE then
		--no special handling, consume

		return EVENT_CONSUME
	end

	if type == EVENT_MOUSE_DOWN then
		--sometimes up doesn't occur so we must again try to reset state
		-- note: sometimes down isn't called either (if drag starts outside of bounds), so bug still exists where scrollbar drag falsely continues
		self.sliderDragInProgress = false
		self.bodyDragInProgress = false

		--stop any running flick on contact
		if self.flick.flickTimer:isRunning() then
			self.flick:stopFlick(true)
			return EVENT_CONSUME
		end
	end

	if type == EVENT_MOUSE_DRAG or type == EVENT_MOUSE_DOWN then
		if self.scrollbar:mouseInside(event) or (self.sliderDragInProgress and evtype ~= EVENT_MOUSE_DOWN ) then
			self.sliderDragInProgress = true

			--zero out offset (scrollbar currently only moves discretely)
			self.pixelOffsetY = 0
			return self.scrollbar:_event(event)
		else --mouse is inside textarea body
			if not self:isTouchMouseEvent(event) then
				--regulr mouse drag works like scrollbar scroll for now.
				return self.scrollbar:_event(event)

			else  --touchpad
				if type == EVENT_MOUSE_DOWN then
					self.dragOrigin.x, self.dragOrigin.y = event:getMouse();
					self.currentShiftDirection = 0
					self.flick:resetFlickData()
					self.flick:updateFlickData(event)
					
				else -- type == EVENT_MOUSE_DRAG
					if ( self.dragOrigin.y == nil) then
						--might have started drag outside of this textarea's bounds, so reset origin
						self.dragOrigin.x, self.dragOrigin.y = event:getMouse();
					end

					local mouseX, mouseY = event:getMouse()

					local dragAmountY = self.dragOrigin.y - mouseY

					--reset origin
					self.dragOrigin.x, self.dragOrigin.y = mouseX, mouseY

					self.flick:updateFlickData(event)

					self:handleDrag(dragAmountY)

				end
			end
		end

		return EVENT_CONSUME
	end
	if type == EVENT_MOUSE_UP then
		--todo: UP not called if we are outside widget bounds, need this widget to handle events when drag in progress
		self.dragOrigin.x, self.dragOrigin.y = nil, nil

		local flickSpeed, flickDirection = self.flick:getFlickSpeed(self.itemHeight)

		if flickSpeed then
			self.flick:flick(flickSpeed, flickDirection)
		end

		self.flick:resetFlickData()


		self.sliderDragInProgress = false
		self.bodyDragInProgress = false

		return EVENT_CONSUME 
	end

	return EVENT_UNUSED
end

function resetDragData(self)
	self.pixelOffsetY = 0
	self.dragYSinceShift = 0
end


function handleDrag(self, dragAmountY, byItemOnly)

	if dragAmountY ~= 0 then
--		log:error("handleDrag dragAmountY: ", dragAmountY )

		self.dragYSinceShift = self.dragYSinceShift + dragAmountY
--		log:error("handleDrag dragYSinceShift: ", self.dragYSinceShift )

		if (self.dragYSinceShift > 0 and math.floor(self.dragYSinceShift / self.lineHeight) > 0) or
				(self.dragYSinceShift < 0 and math.floor(self.dragYSinceShift / self.lineHeight) < 0) then
			local itemShift = math.floor(self.dragYSinceShift / self.lineHeight)
			self.dragYSinceShift = self.dragYSinceShift % self.lineHeight
			if not byItemOnly then
				self.pixelOffsetY = -1 * self.dragYSinceShift
			else
				--by item only so fix the position so that the top item is visible in the same spot each time
				self.pixelOffsetY = 0
			end
			if itemShift > 0 and self.currentShiftDirection <= 0 then
				self.currentShiftDirection = 1
			elseif itemShift < 0 and self.currentShiftDirection >= 0 then
				self.currentShiftDirection = -1
			end

			log:debug("self:scrollBy( itemShift ) ", itemShift, " self.pixelOffsetY: ", self.pixelOffsetY )
			self:scrollBy( itemShift)

			if self:isAtTop() or self:isAtBottom() then
				self:resetDragData()
			end

		else
			--smooth scroll
			if not byItemOnly then
				self.pixelOffsetY = -1 * self.dragYSinceShift
			end

			if self:isAtBottom() then
				self:resetDragData()
			end

			log:debug("Scroll offset by: ", self.pixelOffsetY, " item height: ", self.lineHeight)
			--todo: update scrollbar
--			self:_updateScrollbar()
			self:reDraw()
		end
	end
end


--required functions for Drag module
function isAtBottom(self)
	return (self.topLine + self.visibleLines  >= self.numLines)
end


function isAtTop(self)
	return self.topLine == 0
end


function __tostring(self)
	return "Textarea(" .. string.sub(tostring(self.text), 1, 20) .."...)"
end


--[[

=head1 LICENSE

Copyright 2007 Logitech. All Rights Reserved.

This file is subject to the Logitech Public Source License Version 1.0. Please see the LICENCE file for details.

=cut
--]]

