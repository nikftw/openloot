local ADDON = "openloot"

OpenLoot = OpenLoot or {}
local OL = OpenLoot

OL.PREFIX = "OpenLoot"
OL.RESPONSES = {
	{ id = "BIS", text = "BIS" },
	{ id = "UPGRADE", text = "Upgrade" },
	{ id = "OFFSPEC", text = "Offspec" },
	{ id = "PASS", text = "Pass" },
}

local defaults = {
	councilMode = "officerChat",
	maxRankIndex = 1,
	history = { sessions = {}, order = {} },
	activeRaid = nil,
	declinedMap = nil,
	passTouch = nil,
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

function OL:ShortName(name)
	if not name or name == "" then
		return ""
	end
	return Ambiguate(name, "short")
end

function OL:FullName(unit)
	unit = unit or "player"
	return GetUnitName(unit, true) or UnitName(unit) or ""
end

function OL:ResponseText(id)
	for _, response in ipairs(self.RESPONSES) do
		if response.id == id then
			return response.text
		end
	end
	return id or ""
end

function OL:InitDB()
	OpenLootDB = copyDefaults(OpenLootDB, defaults)
	self.db = OpenLootDB
end

local function statusText()
	local raid = OL.db.activeRaid
	local mode = "off"
	if raid and raid.on then
		mode = raid.isRunner and "on (you are the runner)" or "on"
	end
	local count = OL.Council and OL.Council:Count() or 0
	local items = OL.Session and OL.Session:ItemCount() or 0
	OL:Print(string.format("Raid mode %s. Council members: %d. Session items: %d.", mode, count, items))
end

function OL:Slash(message)
	local cmd, rest = message:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	if cmd == "" then
		statusText()
	elseif cmd == "on" then
		self.RaidMode:EnableFromSlash()
	elseif cmd == "off" then
		self.RaidMode:DisableFromSlash()
	elseif cmd == "run" then
		self.Session:Run()
	elseif cmd == "h" or cmd == "history" then
		self.History:Toggle()
	elseif cmd == "council" then
		self.Council:Slash(rest)
	else
		self:Print("Commands: on, off, run, h, council")
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
	OL.ready = true
end

function handlers.PLAYER_LOGIN()
	if C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	elseif GuildRoster then
		GuildRoster()
	end
	OL.Council:Rebuild()
end

function handlers.PLAYER_ENTERING_WORLD()
	if not OL.ready then
		return
	end
	OL.RaidMode:OnZone()
	OL.RaidMode:RequestState()
end

function handlers.ZONE_CHANGED_NEW_AREA()
	if OL.ready then
		OL.RaidMode:OnZone()
	end
end

function handlers.PLAYER_REGEN_ENABLED()
	if OL.ready then
		OL.RaidMode:OnLeaveCombat()
	end
end

function handlers.GUILD_ROSTER_UPDATE()
	if OL.ready then
		OL.Council:Rebuild()
	end
end

function handlers.GROUP_ROSTER_UPDATE()
	if not OL.ready then
		return
	end
	OL.RaidMode:OnRoster()
	if OL.Session:IsActive() then
		OL.CouncilFrame:Refresh()
	end
end

function handlers.GROUP_LEFT()
	if OL.ready then
		OL.RaidMode:OnGroupLeft()
	end
end

function handlers.START_LOOT_ROLL(rollID)
	if OL.ready then
		OL.RaidMode:OnLootRoll(rollID)
	end
end

function handlers.CHAT_MSG_SYSTEM(text)
	if OL.ready then
		OL.Session:OnSystemRoll(text)
	end
end

function handlers.CHAT_MSG_ADDON(prefix, message, _, sender)
	if OL.ready and prefix == OL.PREFIX then
		OL.Comms:OnMessage(sender, message)
	end
end

local events = CreateFrame("Frame")
for eventName in pairs(handlers) do
	events:RegisterEvent(eventName)
end
events:SetScript("OnEvent", function(_, eventName, ...)
	local handler = handlers[eventName]
	if handler then
		handler(...)
	end
end)

SLASH_OPENLOOT1 = "/openloot"
SlashCmdList.OPENLOOT = function(message)
	OL:Slash(message or "")
end
