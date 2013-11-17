--[[--------------------------------------------------------------------
    Ovale Spell Priority
    Copyright (C) 2012 Sidoine
    Copyright (C) 2012, 2013 Johnny C. Lam

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License in the LICENSE
    file accompanying this program.
--]]--------------------------------------------------------------------

--[[
	This addon is the core of the state machine for the simulator.
--]]

local _, Ovale = ...
local OvaleState = Ovale:NewModule("OvaleState")
Ovale.OvaleState = OvaleState

--<private-static-properties>
local OvaleData = Ovale.OvaleData
local OvaleFuture = nil		-- forward declaration
local OvaleQueue = Ovale.OvaleQueue

local pairs = pairs
local API_GetTime = GetTime

local self_statePrototype = {}
local self_stateModules = OvaleQueue:NewQueue("OvaleState_stateModules")

-- Whether the state of the simulator has been initialized.
local self_stateIsInitialized = false
--</private-static-properties>

--<public-static-properties>
-- The spell being cast.
OvaleState.currentSpellId = nil
OvaleState.now = nil
OvaleState.nextCast = nil
OvaleState.startCast = nil
OvaleState.endCast = nil
OvaleState.isChanneling = nil
OvaleState.lastSpellId = nil

-- The state for the simulator.
OvaleState.state = {
	currentTime = nil,
}
--</public-static-properties>

--<private-static-methods>
--</private-static-methods>

--<public-static-methods>
function OvaleState:OnInitialize()
	-- Resolve module dependencies.
	OvaleFuture = Ovale.OvaleFuture
end

function OvaleState:RegisterState(addon, statePrototype)
	self_stateModules:Insert(addon)
	self_statePrototype[addon] = statePrototype

	-- Mix-in addon's state prototype into OvaleState.state.
	for k, v in pairs(statePrototype) do
		self.state[k] = v
	end
end

function OvaleState:UnregisterState(addon)
	stateModules = OvaleQueue:NewQueue("OvaleState_stateModules")
	while self_stateModules:Size() > 0 do
		local stateAddon = self_stateModules:Remove()
		if stateAddon ~= addon then
			stateModules:Insert(addon)
		end
	end
	self_stateModules = stateModules

	-- Remove mix-in methods from addon's state prototype.
	local statePrototype = self_statePrototype[addon]
	for k in pairs(statePrototype) do
		self.state[k] = nil
	end
	self_stateModules[addon] = nil
end

function OvaleState:InvokeMethod(methodName, ...)
	for _, addon in self_stateModules:Iterator() do
		if addon[methodName] then
			addon[methodName](addon, ...)
		end
	end
end

function OvaleState:StartNewFrame()
	if not self_stateIsInitialized then
		self:InitializeState()
	end
	self.now = API_GetTime()
end

function OvaleState:InitializeState()
	self:InvokeMethod("InitializeState", self.state)
	self_stateIsInitialized = true
end

function OvaleState:Reset()
	local state = self.state
	state.currentTime = self.now
	Ovale:Logf("Reset state with current time = %f", state.currentTime)

	self.lastSpellId = OvaleFuture.lastSpellcast and OvaleFuture.lastSpellcast.spellId
	self.currentSpellId = nil
	self.isChanneling = false
	self.nextCast = self.now

	self:InvokeMethod("ResetState", self.state)
end

--[[
	Cast a spell in the simulator and advance the state of the simulator.

	Parameters:
		spellId		The ID of the spell to cast.
		startCast	The time at the start of the spellcast.
		endCast		The time at the end of the spellcast.
		nextCast	The earliest time at which the next spell can be cast (nextCast >= endCast).
		isChanneled	The spell is a channeled spell.
		nocd		The spell's cooldown is not triggered.
		targetGUID	The GUID of the target of the spellcast.
		spellcast	(optional) Table of spellcast information, including a snapshot of player's stats.
--]]
function OvaleState:ApplySpell(...)
	local spellId, startCast, endCast, nextCast, isChanneled, nocd, targetGUID, spellcast = ...
	if not spellId or not targetGUID then
		return
	end

	-- Update the latest spell cast in the simulator.
	local state = self.state
	self.nextCast = nextCast
	self.currentSpellId = spellId
	self.startCast = startCast
	self.endCast = endCast
	self.isChanneling = isChanneled
	self.lastSpellId = spellId

	-- Set the current time in the simulator to a little after the start of the current cast,
	-- or to now if in the past.
	if startCast >= self.now then
		state.currentTime = startCast + 0.1
	else
		state.currentTime = self.now
	end

	Ovale:Logf("Apply spell %d at %f currentTime=%f nextCast=%f endCast=%f targetGUID=%s", spellId, startCast, state.currentTime, self.nextCast, endCast, targetGUID)

	--[[
		Apply the effects of the spellcast in three phases.
			1. Effects at the beginning of the spellcast.
			2. Effects when the spell has been cast.
			3. Effects when the spellcast hits the target.
	--]]
	-- If the spellcast has already started, then the effects have already occurred.
	if startCast >= OvaleState.now then
		self:InvokeMethod("ApplySpellStartCast", self.state, ...)
	end
	-- If the spellcast has already ended, then the effects have already occurred.
	if endCast > OvaleState.now then
		self:InvokeMethod("ApplySpellAfterCast", self.state, ...)
	end
	self:InvokeMethod("ApplySpellOnHit", self.state, ...)
end
--</public-static-methods>
