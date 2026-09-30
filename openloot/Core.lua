local ADDON = "openloot"

OpenLoot = OpenLoot or {}
local OL = OpenLoot
local events

OL.PREFIX = "OpenLoot"
OL.RESPONSES = {
	{ id = "BIS", text = "BIS" },
	{ id = "UPGRADE", text = "Upgrade" },
	{ id = "OFFSPEC", text = "Offspec" },
	{ id = "PASS", text = "Pass" },
}

local defaults = {
	history = { sessions = {}, order = {} },
	trades = {},
	activeRaid = nil,
	declinedMap = nil,
	passTouch = nil,
	frames = {},
}

local function copyDefaults(dst, src)
	if type(dst) ~= "table" then
		dst = {}
	end
	for key, value in pairs(src) do
		if type(value) == "table" then
			dst[key] = copyDefaults(dst[key], value)
		elseif dst[key] == nil then
			dst[key] = value
		end
	end
	return dst
end

function OL:Print(message)
	print("|cff6cb6ffOpenLoot|r: " .. tostring(message))
end

function OL:RememberWindow(name, shown)
	if not self.db then
		return
	end
	self.db.windows = self.db.windows or {}
	self.db.windows[name] = shown and true or false
end

function OL:WatchWindow(frame, name)
	frame:HookScript("OnShow", function()
		OL:RememberWindow(name, true)
	end)
	frame:HookScript("OnHide", function()
		OL:RememberWindow(name, false)
	end)
end

function OL:ShortName(name)
	if not name or name == "" then
		return ""
	end
	if issecretvalue and issecretvalue(name) then
		return ""
	end
	local ok, short = pcall(Ambiguate, name, "short")
	if not ok or not short or short == "" then
		return ""
	end
	return short
end

function OL:FullName(unit)
	unit = unit or "player"
	return GetUnitName(unit, true) or UnitName(unit) or ""
end

function OL:Version()
	local version
	if C_AddOns and C_AddOns.GetAddOnMetadata then
		version = C_AddOns.GetAddOnMetadata(ADDON, "Version")
	elseif GetAddOnMetadata then
		version = GetAddOnMetadata(ADDON, "Version")
	end
	return version or "0.4.0"
end

function OL:CompareVersion(left, right)
	local function parts(text)
		local values = {}
		for piece in tostring(text or "0"):gmatch("%d+") do
			values[#values + 1] = tonumber(piece) or 0
		end
		return values
	end
	local a = parts(left)
	local b = parts(right)
	local count = math.max(#a, #b)
	for index = 1, count do
		local av = a[index] or 0
		local bv = b[index] or 0
		if av < bv then
			return -1
		end
		if av > bv then
			return 1
		end
	end
	return 0
end

function OL:GroupUnit(name)
	local short = self:ShortName(name)
	if short == "" then
		return nil
	end
	if short == self:ShortName(self:FullName("player")) then
		return "player"
	end
	if IsInRaid() then
		for index = 1, GetNumGroupMembers() do
			local raidName = GetRaidRosterInfo(index)
			if raidName and self:ShortName(raidName) == short then
				return "raid" .. index
			end
		end
		return nil
	end
	if IsInGroup() then
		for index = 1, 4 do
			local unit = "party" .. index
			if UnitExists(unit) and self:ShortName(self:FullName(unit)) == short then
				return unit
			end
		end
	end
	return nil
end

function OL:ResponseText(id)
	for _, response in ipairs(self.RESPONSES) do
		if response.id == id then
			return response.text
		end
	end
	return id or ""
end

function OL:IsLive()
	local _, instanceType = GetInstanceInfo()
	return instanceType == "raid"
end

function OL:Listen(eventName, enabled)
	if enabled then
		events:RegisterEvent(eventName)
	else
		events:UnregisterEvent(eventName)
	end
end

function OL:Wake(isReload)
	self.awake = true
	self.RaidMode:SyncRollListen()
	self.Council:EnsureSelf()
	self.RaidMode:OnEnter(isReload)
	if self.Trade then
		self.Trade:ShowIfPending()
	end
end

function OL:Sleep()
	self.RaidMode:OnZone()
	if not self.awake then
		return
	end
	self.awake = false
	self:Listen("START_LOOT_ROLL", false)
	self:Listen("CONFIRM_LOOT_ROLL", false)
	self:Listen("LOOT_OPENED", false)
	self:Listen("LOOT_READY", false)
	self:Listen("CONFIRM_LOOT_DISTRIBUTION", false)
end

function OL:SyncPresence(isReload, askSession)
	if self:IsLive() then
		self:Wake(isReload)
	else
		self:Sleep()
		if self.Session and IsInGroup() then
			self.Session:CatchUp(askSession and true or false)
		end
	end
end

function OL:InitDB()
	OpenLootDB = copyDefaults(OpenLootDB, defaults)
	self.db = OpenLootDB
end

function OL:Slash(message)
	local cmd = message:match("^(%S*)")
	cmd = (cmd or ""):lower()
	if cmd == "run" then
		self.Session:Run()
	elseif cmd == "h" or cmd == "history" then
		self.History:Toggle()
	elseif cmd == "trade" then
		self.Trade:Show()
	elseif cmd == "v" or cmd == "version" then
		self.Versions:Toggle()
	elseif cmd == "resize" then
		self.UI:ToggleResize()
	elseif cmd == "mule" then
		local name = message:match("^%S+%s+(.+)$")
		self.RaidMode:SetMule(name)
	else
		self:Print("Commands: run, trade, v, h, resize, mule")
	end
end

local handlers = {}

function handlers.ADDON_LOADED(name)
	if name ~= ADDON then
		return
	end
	OL:InitDB()
	OL.Comms:Init()
	OL.Council:Init()
	OL.RaidMode:Init()
	OL.Session:Init()
	OL.History:Init()
	OL.Trade:Init()
	OL.Versions:Init()
	OL.ready = true
	OL:Listen("ADDON_LOADED", false)
end

function handlers.PLAYER_ENTERING_WORLD(isLogin, isReload)
	if not OL.ready or not (isLogin or isReload) then
		return
	end
	OL:SyncPresence(isReload and true or false, true)
	OL:Listen("PLAYER_ENTERING_WORLD", false)
end

function handlers.ZONE_CHANGED_NEW_AREA()
	if OL.ready then
		OL:SyncPresence(false, false)
	end
end

function handlers.GROUP_LEFT()
	if not OL.ready then
		return
	end
	OL.RaidMode:OnGroupLeft()
	if not OL:IsLive() then
		OL:Sleep()
	end
end

function handlers.START_LOOT_ROLL(rollID)
	if OL.ready then
		OL.RaidMode:OnLootRoll(rollID)
	end
end

function handlers.CONFIRM_LOOT_ROLL(rollID, rollType)
	if OL.ready then
		OL.RaidMode:SkipRollConfirm(rollID, rollType)
	end
end

function handlers.GROUP_ROSTER_UPDATE()
	if OL.ready then
		OL.RaidMode:OnRoster()
	end
end

function handlers.LOOT_OPENED()
	if OL.ready then
		OL.RaidMode:OnMasterLoot()
	end
end

function handlers.LOOT_READY()
	if OL.ready then
		OL.RaidMode:OnMasterLoot()
	end
end

function handlers.CONFIRM_LOOT_DISTRIBUTION(slot)
	if OL.ready then
		OL.RaidMode:SkipLootConfirm(slot)
	end
end

function handlers.CHAT_MSG_ADDON(prefix, message, _, sender)
	if OL.ready and prefix == OL.PREFIX then
		OL.Comms:OnMessage(sender, message)
	end
end

events = CreateFrame("Frame")
local quietEvents = {
	START_LOOT_ROLL = true,
	CONFIRM_LOOT_ROLL = true,
	LOOT_OPENED = true,
	LOOT_READY = true,
	CONFIRM_LOOT_DISTRIBUTION = true,
}
for eventName in pairs(handlers) do
	if not quietEvents[eventName] then
		events:RegisterEvent(eventName)
	end
end
events:SetScript("OnEvent", function(_, eventName, ...)
	local handler = handlers[eventName]
	if handler then
		handler(...)
	end
end)

SLASH_OPENLOOT1 = "/openloot"
SLASH_OPENLOOT2 = "/ol"
SlashCmdList.OPENLOOT = function(message)
	OL:Slash(message or "")
end
