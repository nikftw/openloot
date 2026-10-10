local ADDON = "openloot"

OpenLoot = OpenLoot or {}
local OL = OpenLoot
local events
local listening = {}

OL.PREFIX = "OpenLoot"
OL.RESPONSES = {
	{ id = "BIS", text = "BIS", code = "B" },
	{ id = "UPGRADE", text = "Upgrade", code = "U" },
	{ id = "OFFSPEC", text = "Offspec", code = "O" },
	{ id = "PASS", text = "Pass", code = "P" },
}
local responseById, responseByCode = {}, {}
for _, response in ipairs(OL.RESPONSES) do
	responseById[response.id] = response
	responseByCode[response.code] = response
end

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

-- A name's short form never changes, so each is worked out once.
local shortNames = {}

function OL:ShortName(name)
	if not name or name == "" then
		return ""
	end
	if issecretvalue and issecretvalue(name) then
		return ""
	end
	local known = shortNames[name]
	if known then
		return known
	end
	local ok, short = pcall(Ambiguate, name, "short")
	if not ok or not short or short == "" then
		return ""
	end
	shortNames[name] = short
	return short
end

-- The group, read once after each roster change: everyone's name, short
-- name, class, unit and online state in roster order, by short name, and the
-- leader. Solo, it holds just this character.
local roster

function OL:Roster()
	if roster then
		return roster
	end
	local list, byShort, leader = {}, {}, nil
	local function add(name, classFile, unit, online, isLeader)
		local member = { name = name, short = self:ShortName(name), classFile = classFile, unit = unit, online = online }
		list[#list + 1] = member
		byShort[member.short] = member
		if isLeader then
			leader = name
		end
	end
	if IsInRaid() then
		for index = 1, GetNumGroupMembers() do
			local name, rank, _, _, _, classFile, _, online = GetRaidRosterInfo(index)
			if name then
				add(name, classFile, "raid" .. index, online ~= false, rank == 2)
			end
		end
	else
		add(self:FullName("player"), select(2, UnitClass("player")), "player", true, UnitIsGroupLeader("player"))
		for index = 1, GetNumSubgroupMembers() do
			local unit = "party" .. index
			if UnitExists(unit) then
				add(self:FullName(unit), select(2, UnitClass(unit)), unit, true, UnitIsGroupLeader(unit))
			end
		end
	end
	roster = { list = list, byShort = byShort, leader = leader }
	return roster
end

function OL:RosterChanged()
	roster = nil
end

function OL:FullName(unit)
	unit = unit or "player"
	return GetUnitName(unit, true) or UnitName(unit) or ""
end

function OL:Me()
	if not self.me then
		local short = self:ShortName(self:FullName("player"))
		if short == "" then
			return short
		end
		self.me = short
	end
	return self.me
end

function OL:Version()
	return C_AddOns.GetAddOnMetadata(ADDON, "Version") or "0"
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
	if short == self:Me() then
		return "player"
	end
	local member = self:Roster().byShort[short]
	return member and member.unit or nil
end

function OL:ResponseText(id)
	local response = responseById[id]
	return response and response.text or id or ""
end

function OL:ResponseCode(id)
	local response = responseById[id]
	return response and response.code or ""
end

function OL:ResponseFromCode(code)
	local response = responseByCode[code]
	return response and response.id or nil
end

function OL:IsLive()
	local _, instanceType = GetInstanceInfo()
	return instanceType == "raid"
end

function OL:Listen(eventName, enabled)
	if enabled then
		if listening[eventName] then
			return
		end
		if pcall(events.RegisterEvent, events, eventName) then
			listening[eventName] = true
		end
	elseif listening[eventName] then
		listening[eventName] = nil
		pcall(events.UnregisterEvent, events, eventName)
	end
end

function OL:Wake()
	self.awake = true
	self.RaidMode:SyncListen()
	self.Council:EnsureSelf()
	self.RaidMode:OnEnter()
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
	self:Listen("LOOT_READY", false)
	self:Listen("CONFIRM_LOOT_DISTRIBUTION", false)
end

function OL:SyncPresence()
	if self:IsLive() then
		self:Wake()
	else
		self:Sleep()
		self.Session:CatchUp()
		self.RaidMode:MaybeAsk()
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
	if not (isLogin or isReload) then
		return
	end
	OL:SyncPresence()
	OL:Listen("PLAYER_ENTERING_WORLD", false)
end

function handlers.ZONE_CHANGED_NEW_AREA()
	OL:SyncPresence()
end

function handlers.GROUP_LEFT()
	OL:RosterChanged()
	OL.RaidMode:OnGroupLeft()
	if not OL:IsLive() then
		OL:Sleep()
	end
end

function handlers.START_LOOT_ROLL(rollID)
	OL.RaidMode:OnLootRoll(rollID)
end

function handlers.CONFIRM_LOOT_ROLL(rollID, rollType)
	OL.RaidMode:SkipRollConfirm(rollID, rollType)
end

function handlers.GROUP_ROSTER_UPDATE()
	OL:RosterChanged()
	OL.RaidMode:OnRoster()
end

function handlers.LOOT_READY()
	OL.RaidMode:OnMasterLoot()
end

function handlers.CONFIRM_LOOT_DISTRIBUTION(slot)
	OL.RaidMode:SkipLootConfirm(slot)
end

function handlers.CHAT_MSG_ADDON(prefix, message, _, sender)
	if prefix == OL.PREFIX then
		OL.Comms:OnMessage(sender, message)
	end
end

function handlers.TRADE_SHOW()
	OL.Trade:OnTradeShow()
end

function handlers.TRADE_CLOSED()
	OL.Trade:OnTradeClosed()
end

function handlers.TRADE_ACCEPT_UPDATE()
	OL.Trade:OnAccept()
end

function handlers.UI_INFO_MESSAGE(...)
	OL.Trade:OnInfo(...)
end

events = CreateFrame("Frame")
for _, eventName in ipairs({
	"ADDON_LOADED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
	"GROUP_LEFT", "GROUP_ROSTER_UPDATE", "CHAT_MSG_ADDON",
}) do
	OL:Listen(eventName, true)
end
events:SetScript("OnEvent", function(_, eventName, ...)
	if OL.ready or eventName == "ADDON_LOADED" then
		handlers[eventName](...)
	end
end)

SLASH_OPENLOOT1 = "/openloot"
SLASH_OPENLOOT2 = "/ol"
SlashCmdList.OPENLOOT = function(message)
	OL:Slash(message or "")
end
