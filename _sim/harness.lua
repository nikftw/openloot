local files = {
	"Core.lua", "Comms.lua", "Council.lua", "Items.lua", "UI.lua", "RaidMode.lua",
	"Session.lua", "RaiderFrame.lua", "CouncilFrame.lua", "History.lua", "Trade.lua", "Version.lua",
}

local logLines = {}
local function log(text)
	logLines[#logLines + 1] = text
	print(text)
end

local function shortOf(name)
	return (name or ""):match("^([^%-]+)") or ""
end

local catalog = {}
local function addItem(def)
	catalog[def.id] = def
	return def
end

addItem({ id = 19019, name = "Thunderfury", equip = "INVTYPE_WEAPON", classID = 2, subClassID = 7, icon = 135349, ilvl = 80, quality = 4 })
addItem({ id = 17182, name = "Sulfuras", equip = "INVTYPE_2HWEAPON", classID = 2, subClassID = 5, icon = 135537, ilvl = 60, quality = 4 })
addItem({ id = 19888, name = "Overlord's Embrace", equip = "INVTYPE_CLOAK", classID = 4, subClassID = 1, icon = 133754, ilvl = 68, quality = 4 })
addItem({ id = 18821, name = "Quick Strike Ring", equip = "INVTYPE_FINGER", classID = 4, subClassID = 0, icon = 133355, ilvl = 66, quality = 3 })
addItem({ id = 17063, name = "Band of Accuria", equip = "INVTYPE_FINGER", classID = 4, subClassID = 0, icon = 133357, ilvl = 40, quality = 4 })
addItem({ id = 18813, name = "Don Rodrigo's Band", equip = "INVTYPE_FINGER", classID = 4, subClassID = 0, icon = 133356, ilvl = 45, quality = 4 })
addItem({ id = 19378, name = "Cloak of the Brood Lord", equip = "INVTYPE_CLOAK", classID = 4, subClassID = 1, icon = 133753, ilvl = 50, quality = 4 })

local function linkOf(id)
	local item = catalog[id]
	return "|cffa335ee|Hitem:" .. id .. "::::::::80:::::|h[" .. item.name .. "]|h|r"
end

local roster = {
	{ name = "Shane-Area52", class = "PALADIN", raidRank = 2, guildRank = 0, guildRankName = "Guild Master", note = "Main" },
	{ name = "Veyra-Area52", class = "MAGE", raidRank = 0, guildRank = 1, guildRankName = "Officer", note = "Main" },
	{ name = "Thorn-Area52", class = "HUNTER", raidRank = 0, guildRank = 4, guildRankName = "Raider", note = "Clone1" },
	{ name = "Nyx-Area52", class = "PRIEST", raidRank = 0, guildRank = 1, guildRankName = "Officer", note = "Main" },
}

local bags = {
	[0] = {
		{ id = 19019, bound = false },
		{ id = 19888, bound = false },
		{ id = 18821, bound = true, tradeable = true },
	},
}

local bagsByPlayer = {
	["Shane-Area52"] = bags,
}

local equipped = {
	[16] = 17182,
	[15] = 19378,
	[11] = 17063,
	[12] = 18813,
}

local lootSim = {
	method = "group",
	raidID = nil,
	items = 0,
	candidates = {},
	given = {},
}
local wire = {}
local flushing = false

-- Off by default: timers fire at once, as the original demo expects. A
-- scenario can switch to virtual time, where timers wait for advance() and
-- each client's addon messages are throttled (THROTTLE_BURST messages, then
-- THROTTLE_RATE more per second).
local clock = { virtual = false, now = 0, timers = {}, seq = 0 }
local THROTTLE_BURST = 10
local THROTTLE_RATE = 1

local function schedule(delay, fn, handle)
	clock.seq = clock.seq + 1
	clock.timers[#clock.timers + 1] = { at = clock.now + (delay or 0), seq = clock.seq, fn = fn, handle = handle }
end

local function advance(seconds)
	local stop = clock.now + seconds
	while true do
		local best, bestIndex
		for index, timer in ipairs(clock.timers) do
			if timer.at <= stop and (not best or timer.at < best.at or (timer.at == best.at and timer.seq < best.seq)) then
				best, bestIndex = timer, index
			end
		end
		if not best then
			break
		end
		table.remove(clock.timers, bestIndex)
		clock.now = math.max(clock.now, best.at)
		if not (best.handle and best.handle._dead) then
			local ok, err = xpcall(best.fn, debug.traceback)
			if not ok then
				print("TIMER ERROR " .. tostring(err))
			end
		end
	end
	clock.now = stop
end
local hops = 0
local clients = {}

local wireStats = { frames = 0, bytes = 0 }

local function opcode(payload)
	local ops = {}
	for part in (payload .. "\30"):gmatch("(.-)\30") do
		if part:sub(1, 1) == "\2" then
			ops[#ops + 1] = "chunk"
		else
			ops[#ops + 1] = part:match("^([^\31]*)") or part
		end
	end
	return table.concat(ops, "+")
end

local function personByName(name)
	local short = shortOf(name)
	for _, person in ipairs(roster) do
		if person.name == name or shortOf(person.name) == short then
			return person
		end
	end
	return nil
end

local function widget(kind, parent, env)
	local self = {
		_kind = kind,
		_parent = parent,
		_scripts = {},
		_shown = false,
		_text = "",
		_width = 100,
		_height = 24,
		_enabled = true,
		_lines = {},
		_strata = "MEDIUM",
		_level = 1,
	}
	local function child(kindName)
		local created = widget(kindName, self, env)
		return created
	end
	local methods = {}
	function methods:SetScript(name, fn)
		self._scripts[name] = fn
	end
	function methods:HookScript(name, fn)
		local prev = self._scripts[name]
		if prev then
			self._scripts[name] = function(...)
				prev(...)
				return fn(...)
			end
		else
			self._scripts[name] = fn
		end
	end
	function methods:GetScript(name)
		return self._scripts[name]
	end
	function methods:HasScript(name)
		return self._scripts[name] ~= nil
	end
	function methods:Show()
		self._shown = true
		if self._scripts.OnShow then
			self._scripts.OnShow(self)
		end
	end
	function methods:Hide()
		local was = self._shown
		self._shown = false
		if was and self._scripts.OnHide then
			self._scripts.OnHide(self)
		end
	end
	function methods:IsShown()
		return self._shown
	end
	function methods:IsVisible()
		return self._shown
	end
	function methods:SetText(text)
		self._text = text or ""
	end
	function methods:GetText()
		return self._text
	end
	function methods:SetShown(shown)
		if shown then
			self:Show()
		else
			self:Hide()
		end
	end
	function methods:SetTexture(texture)
		self._texture = texture
	end
	function methods:GetTexture()
		return self._texture
	end
	function methods:SetPoint(...)
		self._points = self._points or {}
		self._points[#self._points + 1] = { ... }
	end
	function methods:ClearAllPoints()
		self._points = {}
	end
	function methods:SetSize(width, height)
		self._width = width
		self._height = height
	end
	function methods:SetWidth(width)
		self._width = width
	end
	function methods:SetHeight(height)
		self._height = height
	end
	function methods:GetWidth()
		return self._width or 0
	end
	function methods:GetHeight()
		return self._height or 0
	end
	function methods:GetStringWidth()
		return #(self._text or "") * 6
	end
	function methods:GetLeft()
		return 100
	end
	function methods:GetTop()
		return 500
	end
	function methods:GetRight()
		return 200
	end
	function methods:GetBottom()
		return 400
	end
	function methods:GetEffectiveScale()
		return 1
	end
	function methods:GetScale()
		return 1
	end
	function methods:GetFrameLevel()
		return self._level or 1
	end
	function methods:SetFrameLevel(level)
		self._level = level
	end
	function methods:GetFrameStrata()
		return self._strata
	end
	function methods:SetFrameStrata(strata)
		self._strata = strata
	end
	function methods:GetAlpha()
		return 1
	end
	function methods:GetParent()
		return self._parent
	end
	function methods:IsEnabled()
		return self._enabled
	end
	function methods:Enable()
		self._enabled = true
	end
	function methods:Disable()
		self._enabled = false
	end
	function methods:CreateFontString()
		return child("FontString")
	end
	function methods:CreateTexture()
		return child("Texture")
	end
	function methods:CreateAnimationGroup()
		return child("AnimationGroup")
	end
	function methods:NumLines()
		return #self._lines
	end
	function methods:ClearLines()
		self._lines = {}
	end
	function methods:SetBagItem(bag, slot)
		self._lines = {}
		local item = specBags(env, bag, slot)
		if item and item.tradeable then
			self._lines[1] = "You may trade this item with eligible players for the next 2 hours."
			env["OpenLootScanTipTextLeft1"] = {
				GetText = function()
					return self._lines[1]
				end,
			}
		end
		return true
	end
	function methods:RegisterEvent(name)
		self._events = self._events or {}
		self._events[name] = true
		env._eventFrames = env._eventFrames or {}
		env._eventFrames[self] = true
	end
	function methods:UnregisterEvent(name)
		self._events = self._events or {}
		if not self._events[name] then
			error('Attempt to unregister unknown event "' .. tostring(name) .. '"')
		end
		self._events[name] = nil
	end
	local mt = {
		__index = function(_, key)
			if methods[key] then
				return methods[key]
			end
			if type(key) == "string" and key:match("^[A-Z]") then
				return function() end
			end
			return nil
		end,
	}
	return setmetatable(self, mt)
end

function specBags(env, bag, slot)
	local mine = bagsByPlayer[env._spec.name]
	local contents = mine and mine[bag]
	return contents and contents[slot] or nil
end

local function install(env, spec)
	env._spec = spec
	env._G = env
	env.SlashCmdList = {}
	env.unpack = table.unpack
	env.time = os.time
	env.date = os.date
	env.wipe = function(t)
		for key in pairs(t) do
			t[key] = nil
		end
		return t
	end
	env.Ambiguate = function(name)
		return shortOf(name)
	end
	env.issecretvalue = function()
		return false
	end
	env.print = function(text)
		log("[" .. shortOf(spec.name) .. "] PRINT " .. tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
	end
	env.Enum = {
		ItemQuality = { Rare = 3, Epic = 4 },
		ItemClass = { Armor = 4, Weapon = 2 },
		SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 1, ChannelThrottle = 2 },
		LootMethod = { Freeforall = 0, Roundrobin = 1, Masterlooter = 2, Group = 3, Needbeforegreed = 4, Personal = 5 },
	}
	env.RAID_CLASS_COLORS = setmetatable({}, {
		__index = function()
			return { r = 1, g = 1, b = 1 }
		end,
	})
	env.NUM_BAG_SLOTS = 4
	env.LE_PARTY_CATEGORY_HOME = 2
	function env.strsplit(sep, text)
		local out = {}
		local start = 1
		while true do
			local found = text:find(sep, start, true)
			if not found then
				out[#out + 1] = text:sub(start)
				break
			end
			out[#out + 1] = text:sub(start, found - 1)
			start = found + 1
		end
		return table.unpack(out)
	end
	env.C_TooltipInfo = {}
	function env.C_TooltipInfo.GetBagItem(bag, slot)
		local item = specBags(env, bag, slot)
		if item and item.tradeable then
			return { lines = { { leftText = "You may trade this item with eligible players for the next 2 hours." } } }
		end
		return { lines = {} }
	end
	-- Everyone but the leader starts with no item data, as a raider would for
	-- loot they have never seen, so links load through Item:ContinueOnItemLoad.
	env._known = {}
	env._uncached = spec.name ~= "Shane-Area52"
	env.Item = {}
	function env.Item:CreateFromItemID(itemID)
		return {
			ContinueOnItemLoad = function(_, callback)
				env._known[itemID] = true
				callback()
			end,
		}
	end
	env.LE_PARTY_CATEGORY_INSTANCE = 1
	env.INVTYPE_CLOAK = "Cloak"
	env.INVTYPE_FINGER = "Finger"
	env.INVTYPE_WEAPON = "Weapon"
	env.INVTYPE_2HWEAPON = "Two-Hand"

	function env.CreateFrame(kind, name, parent)
		local frame = widget(kind or "Frame", parent, env)
		if name and name ~= "" then
			env[name] = frame
		end
		return frame
	end
	env.UIParent = env.CreateFrame("Frame", "UIParent")
	env.GameTooltip = env.CreateFrame("GameTooltip", "GameTooltip")
	env.GameFontHighlight = {}
	env.GameFontHighlightSmall = {}
	env.GameFontDisableSmall = {}
	env.GameFontNormal = {}

	function env.GetTime()
		if clock.virtual then
			return clock.now
		end
		return os.clock()
	end
	function env.GetPhysicalScreenSize()
		return 2560, 1440
	end
	function env.UnitIsDeadOrGhost()
		return env._ghost and true or false
	end
	function env.GetInstanceInfo()
		if env._outside then
			return "Searing Gorge", "none", 0, "", 5, 0, false, 0
		end
		return "Molten Core", "raid", 14, "20 Player", 40, 0, false, 409
	end
	function env.IsInRaid()
		return not env._solo and not env._party
	end
	function env.IsInGroup(category)
		if category ~= nil or env._solo then
			return false
		end
		return true
	end
	function env.GetNumGroupMembers()
		return #roster
	end
	function env.GetNumSubgroupMembers()
		return #roster - 1
	end
	function env.UnitExists(unit)
		return env.UnitName(unit) ~= nil
	end
	function env.UnitName(unit)
		local person = env._unitPerson(unit)
		if not person then
			return nil
		end
		return shortOf(person.name)
	end
	function env.GetUnitName(unit, full)
		local person = env._unitPerson(unit)
		if not person then
			return nil
		end
		if full then
			return person.name
		end
		return shortOf(person.name)
	end
	function env.UnitClass(unit)
		local person = env._unitPerson(unit)
		if not person then
			return nil
		end
		return person.class, person.class
	end
	function env.UnitIsGroupLeader(unit)
		local person = env._unitPerson(unit)
		return person and person.raidRank == 2 or false
	end
	function env.GetRaidRosterInfo(index)
		local person = roster[index]
		if not person then
			return nil
		end
		return person.name, person.raidRank, 1, 80, person.class, person.class, "Molten Core", true
	end
	function env.IsInGuild()
		return true
	end
	function env.GetGuildInfo(unit)
		local person = env._unitPerson(unit)
		if not person then
			return nil
		end
		return "OpenLoot", person.guildRankName, person.guildRank
	end
	function env.GetNumGuildMembers()
		return #roster
	end
	function env.GetGuildRosterInfo(index)
		local person = roster[index]
		if not person then
			return nil
		end
		return person.name, person.guildRankName, person.guildRank, 80, person.class, "Molten Core", "", person.note, true
	end
	env.C_GuildInfo = {}
	function env.C_GuildInfo.GuildControlGetRankFlags(rankIndex)
		local speak = rankIndex == 0 or rankIndex == 1
		return { false, false, false, speak }
	end
	function env._unitPerson(unit)
		if unit == "player" then
			return personByName(spec.name)
		end
		local index = unit and unit:match("^raid(%d+)$")
		if index then
			return roster[tonumber(index)]
		end
		return nil
	end

	local pass = false
	function env.GetOptOutOfLoot()
		return pass
	end
	function env.SetOptOutOfLoot(flag)
		pass = flag and true or false
		log("[" .. shortOf(spec.name) .. "] PASS " .. (pass and "on" or "off"))
	end
	env.C_PartyInfo = {}
	function env.C_PartyInfo.GetLootMethod()
		local method = lootSim.method == "master" and env.Enum.LootMethod.Masterlooter or env.Enum.LootMethod.Group
		return method, nil, lootSim.raidID
	end
	function env.GetNumLootItems()
		return lootSim.items
	end
	function env.GetLootSlotType()
		return 1
	end
	function env.LootSlotHasItem()
		return true
	end
	function env.GetMasterLootCandidate(_, index)
		return lootSim.candidates[index]
	end
	function env.GiveMasterLoot(slot, index)
		local name = lootSim.candidates[index]
		lootSim.given[#lootSim.given + 1] = { from = shortOf(spec.name), slot = slot, to = name }
		log("[" .. shortOf(spec.name) .. "] MASTER " .. slot .. " to " .. tostring(name))
		return true
	end

	env.C_AddOns = {}
	function env.C_AddOns.GetAddOnMetadata()
		return "0.5.0"
	end
	function env.C_AddOns.RegisterAddonMessagePrefix()
		return true
	end

	env.C_ChatInfo = {}
	function env.C_ChatInfo.RegisterAddonMessagePrefix()
		return true
	end
	local bucket = { tokens = THROTTLE_BURST, at = 0 }
	function env.C_ChatInfo.SendAddonMessage(prefix, payload, channel, target)
		if #payload > 255 then
			error("addon message over 255 bytes: " .. #payload)
		end
		if clock.virtual then
			bucket.tokens = math.min(THROTTLE_BURST, bucket.tokens + (clock.now - bucket.at) * THROTTLE_RATE)
			bucket.at = clock.now
			if bucket.tokens < 1 then
				wireStats.throttled = (wireStats.throttled or 0) + 1
				return env.Enum.SendAddonMessageResult.AddonMessageThrottle
			end
			bucket.tokens = bucket.tokens - 1
		end
		wireStats.frames = wireStats.frames + 1
		wireStats.bytes = wireStats.bytes + #payload
		-- Per op: how many messages of it, their bytes, and a sample payload.
		wireStats.ops = wireStats.ops or {}
		for part in (payload .. "\30"):gmatch("(.-)\30") do
			local op = part:sub(1, 1) == "\2" and "chunk" or (part:match("^([^\31]*)") or "?")
			local entry = wireStats.ops[op] or { count = 0, bytes = 0, receivers = 0 }
			entry.count = entry.count + 1
			entry.bytes = entry.bytes + #part
			entry.receivers = entry.receivers + (channel == "WHISPER" and 1 or (#roster - 1))
			entry.sample = entry.sample or part
			wireStats.ops[op] = entry
		end
		wire[#wire + 1] = {
			from = spec.name,
			payload = payload,
			channel = channel or "RAID",
			target = target,
		}
		flushWire()
		return 0
	end

	env.C_Timer = {}
	function env.C_Timer.After(delay, fn)
		if clock.virtual then
			schedule(delay, fn)
			return
		end
		if fn then
			fn()
		end
	end
	function env.C_Timer.NewTimer(delay, fn)
		local handle = {}
		function handle:Cancel()
			handle._dead = true
		end
		if clock.virtual then
			schedule(delay, fn, handle)
			return handle
		end
		if fn then
			fn()
		end
		return handle
	end
	function env.C_Timer.NewTicker(delay, fn)
		local handle = {}
		function handle:Cancel()
			handle._dead = true
		end
		if clock.virtual then
			local function tick()
				fn(handle)
				schedule(delay, tick, handle)
			end
			schedule(delay, tick, handle)
		end
		return handle
	end

	function env.SendChatMessage(text, channel)
		log("[" .. shortOf(spec.name) .. "] CHAT " .. tostring(channel) .. " " .. tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|Hitem:[^|]+|h", ""):gsub("|h", ""))
	end
	env._popup = nil
	env._rolled = nil
	function env.GetLootRollItemLink(rollID)
		local drop = env._bossDrop
		if drop and drop.rollID == rollID then
			return drop.link
		end
		return nil
	end
	function env.RollOnLoot(rollID, rollType)
		local names = { [0] = "Pass", [1] = "Need", [2] = "Greed", [3] = "Disenchant" }
		env._rolled = rollType
		log("[" .. shortOf(spec.name) .. "] ROLL " .. (names[rollType] or tostring(rollType)))
		local drop = env._bossDrop
		if drop and drop.rollID == rollID and drop.bop and not drop.confirmFired then
			drop.confirmFired = true
			env._popup = "CONFIRM_LOOT_ROLL"
			log("[game] POPUP CONFIRM_LOOT_ROLL for " .. drop.name)
			env.fire("CONFIRM_LOOT_ROLL", rollID, rollType)
		end
	end
	function env.ConfirmLootRoll(rollID, rollType)
		log("[" .. shortOf(spec.name) .. "] CONFIRM ROLL " .. tostring(rollType))
	end
	function env.StaticPopup_Hide(which)
		if env._popup == which then
			env._popup = nil
		end
		log("[" .. shortOf(spec.name) .. "] HIDE " .. tostring(which))
	end

	env.ItemLocation = {}
	function env.ItemLocation:CreateFromBagAndSlot(bag, slot)
		return { bag = bag, slot = slot }
	end
	env.C_Item = {}
	function env.C_Item.DoesItemExist(location)
		return specBags(env, location.bag, location.slot) and true or false
	end
	function env.C_Item.GetItemQuality(location)
		local item = specBags(env, location.bag, location.slot)
		local def = item and catalog[item.id]
		return def and def.quality or nil
	end
	function env.C_Item.IsBound(location)
		local item = specBags(env, location.bag, location.slot)
		return item and item.bound or false
	end
	function env.C_Item.GetItemInfo(itemString)
		local id = tonumber((itemString or ""):match("item:(%d+)"))
		local def = id and catalog[id]
		if not def or (env._uncached and not env._known[id]) then
			return nil
		end
		return def.name, linkOf(id)
	end
	function env.C_Item.GetItemGUID(location)
		local item = specBags(env, location.bag, location.slot)
		if not item then
			return nil
		end
		return "guid:" .. item.id .. ":" .. location.bag .. ":" .. location.slot
	end
	function env.C_Item.GetCurrentItemLevel(location)
		local item = specBags(env, location.bag, location.slot)
		local def = item and catalog[item.id]
		return def and def.ilvl or nil
	end
	function env.C_Item.GetDetailedItemLevelInfo(itemLink)
		local id = tonumber((itemLink or ""):match("item:(%d+)"))
		local def = id and catalog[id]
		return def and def.ilvl or nil
	end
	function env.C_Item.GetItemInfoInstant(itemLink)
		local id = tonumber((itemLink or ""):match("item:(%d+)"))
		local def = id and catalog[id]
		if not def then
			return nil
		end
		return id, "Armor", "Misc", def.equip, def.icon, def.classID, def.subClassID
	end
	env.C_Container = {}
	function env.C_Container.GetContainerNumSlots(bag)
		local mine = bagsByPlayer[spec.name]
		local contents = mine and mine[bag]
		return contents and #contents or 0
	end
	function env.C_Container.GetContainerItemLink(bag, slot)
		local item = specBags(env, bag, slot)
		if not item then
			return nil
		end
		return linkOf(item.id)
	end
	function env.C_Container.GetContainerItemInfo(bag, slot)
		local item = specBags(env, bag, slot)
		if not item then
			return nil
		end
		return { hyperlink = linkOf(item.id), itemID = item.id }
	end
	function env.GetInventoryItemLink(unit, slot)
		if unit ~= "player" then
			return nil
		end
		local id = equipped[slot]
		if not id then
			return nil
		end
		return linkOf(id)
	end
	env.C_PlayerInfo = {}
	function env.C_PlayerInfo.CanUseItem()
		return true
	end

	function env.fire(event, ...)
		log("[" .. shortOf(spec.name) .. "] EVENT " .. event)
		for frame in pairs(env._eventFrames or {}) do
			if frame._events and frame._events[event] and frame._scripts.OnEvent then
				frame._scripts.OnEvent(frame, event, ...)
			end
		end
	end
end

function flushWire()
	if flushing then
		return
	end
	flushing = true
	hops = 0
	while #wire > 0 do
		hops = hops + 1
		if hops > 400 then
			error("addon message loop did not stop")
		end
		local message = table.remove(wire, 1)
		local who = message.target and (shortOf(message.target)) or message.channel
		log("[" .. shortOf(message.from) .. "] SEND " .. opcode(message.payload) .. " via " .. message.channel .. (message.target and (" to " .. shortOf(message.target)) or ""))
		for _, client in ipairs(clients) do
			if client.spec.name ~= message.from then
				local hit = message.channel ~= "WHISPER" or client.spec.name == message.target
				if hit then
					log("[" .. shortOf(client.spec.name) .. "] RECV " .. opcode(message.payload) .. " from " .. shortOf(message.from))
					client.env.OpenLoot.Comms:OnMessage(message.from, message.payload)
				end
			end
		end
	end
	flushing = false
end

local function loadAddon(env)
	for _, file in ipairs(files) do
		local source = SOURCES[file]
		if not source then
			error("missing " .. file)
		end
		local chunk, err = load(source, "@" .. file, "t", env)
		if not chunk then
			error(err)
		end
		chunk()
	end
end

local function boot(name)
	local env = {}
	setmetatable(env, { __index = _G })
	local spec = personByName(name)
	install(env, spec)
	loadAddon(env)
	local prompt = env.OpenLoot.UI.Prompt
	function env.OpenLoot.UI:Prompt(title, body, buttons)
		log("[" .. shortOf(spec.name) .. "] PROMPT " .. tostring(body))
		return prompt(self, title, body, buttons)
	end
	clients[#clients + 1] = { spec = spec, env = env }
	local ok, err = xpcall(function()
		env.fire("ADDON_LOADED", "openloot")
		env.fire("PLAYER_ENTERING_WORLD", true, false)
	end, function(e)
		return tostring(e) .. "\n" .. debug.traceback()
	end)
	if not ok then
		log("[" .. shortOf(name) .. "] ERROR during boot\n" .. err)
	end
	return env
end

local function click(env, label)
	local windows = env.OpenLoot.UI.windows or {}
	for _, frame in ipairs(windows) do
		if frame:IsShown() and frame.buttons then
			for _, button in ipairs(frame.buttons) do
				if button:GetText() == label and button._scripts.OnClick then
					log("[" .. shortOf(env._spec.name) .. "] CLICK " .. label)
					button._scripts.OnClick(button)
					return true
				end
			end
		end
	end
	return false
end

local function shown(frame)
	return frame and frame.frame and frame.frame:IsShown() and true or false
end

if SCENARIO_SOURCE then
	local scenario = assert(load(SCENARIO_SOURCE, "@" .. SCENARIO_NAME, "t", _ENV))
	scenario({
		log = log, shortOf = shortOf, roster = roster, bagsByPlayer = bagsByPlayer, catalog = catalog,
		addItem = addItem, linkOf = linkOf, equipped = equipped, lootSim = lootSim, boot = boot,
		clients = clients, click = click, wireStats = wireStats, clock = clock, advance = advance,
	})
	do return end
end

print("Virtual raid: Molten Core. You are Shane, raid leader and guild master.")
print("With you: Veyra (officer), Thorn (raider), Nyx (officer).")
print("")

for _, person in ipairs(roster) do
	boot(person.name)
end

local shane = clients[1].env
print("")
if not click(shane, "Yes") then
	log("[Shane] ERROR the raid prompt did not appear")
end

local scripted = {
	["Shane"] = {
		{ "PASS", "Upgrade" },
		{ "PASS", "Upgrade" },
		{ "PASS", "Upgrade" },
	},
	["Veyra"] = {
		{ "UPGRADE", "Main set" },
		{ "PASS", "" },
		{ "OFFSPEC", "Main set" },
	},
	["Thorn"] = {
		{ "UPGRADE", "Main set" },
		{ "PASS", "" },
		{ "BIS", "Upgrade" },
	},
	["Nyx"] = {
		{ "BIS", "Offspec" },
		{ "OFFSPEC", "Upgrade" },
		{ "OFFSPEC", "" },
	},
}

local function step(label, fn)
	local ok, err = xpcall(fn, function(e)
		return tostring(e) .. "\n" .. debug.traceback()
	end)
	if not ok then
		log(label .. " ERROR\n" .. err)
	end
end

print("")
step("[Shane] /ol run", function()
	shane.OpenLoot:Slash("run")
end)

local session = shane.OpenLoot.Session.active
if not session then
	log("[Shane] ERROR no loot session started")
else
	for _, client in ipairs(clients) do
		local who = shortOf(client.spec.name)
		for index = 1, #session.items do
			local response, note = scripted[who][index][1], scripted[who][index][2]
			step("[" .. who .. "] response " .. index, function()
				client.env.OpenLoot.Session:SetResponse(index, response, note)
			end)
		end
	end

	local people = {}
	for _, person in ipairs(roster) do
		people[#people + 1] = shortOf(person.name)
	end
	local winners = { "Veyra", "Nyx", "Shane" }
	for index = 1, #session.items do
		local winner = winners[index]
		step("[Shane] award " .. index, function()
			shane.OpenLoot.Session:Award(index, winner)
		end)
	end

	print("")
	print("Loot session:")
	for index, item in ipairs(shane.OpenLoot.Session.active.items) do
		local name = item.link:match("%[(.-)%]") or item.link
		log(index .. ". " .. name .. " -> " .. tostring(item.awardedTo))
		for _, person in ipairs(people) do
			local vote = item.votes[person]
			local text = vote and shane.OpenLoot:ResponseText(vote.response) or "no response"
			local note = vote and vote.note and vote.note ~= "" and (" (" .. vote.note .. ")") or ""
			log("    " .. person .. ": " .. text .. note)
		end
	end

	print("")
	print("Trade list:")
	local trades = shane.OpenLoot.Trade.list or {}
	if #trades == 0 then
		log("    empty")
	end
	for _, entry in ipairs(trades) do
		local name = (entry.link or ""):match("%[(.-)%]") or entry.link
		log("    " .. tostring(entry.winner) .. " is owed " .. tostring(name))
	end

	print("")
	print("Export:")
	log(shane.OpenLoot.History:Csv())

	local function plain(text)
		return (tostring(text or "")):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|Hitem:[^|]+|h%[", ""):gsub("%]|h", "")
	end
	local function dumpHistory(env, who)
		step("[" .. who .. "] /ol h", function()
			env.OpenLoot:Slash("h")
		end)
		local history = env.OpenLoot.History
		local frame = history.frame
		print("")
		print(who .. " history:")
		log("window " .. tostring(frame and frame:IsShown()) .. " " .. tostring(frame and frame:GetWidth()) .. " x " .. tostring(frame and frame:GetHeight()))
		log("title " .. plain(frame.titleText:GetText()) .. " bar " .. tostring(frame.titleBar:IsShown()))
		log("headers " .. history.headerName:GetText() .. " | " .. history.headerItem:GetText() .. " | " .. history.headerResponse:GetText() .. " | " .. history.headerTime:GetText())
		for _, button in ipairs(history.sessionButtons) do
			if button:IsShown() then
				log("session " .. button:GetText())
			end
		end
		local rows = 0
		for _, row in ipairs(history.awardRows) do
			if row:IsShown() then
				rows = rows + 1
				local icon = row.icon and row.icon.texture and row.icon.texture:GetTexture()
				log(row.name:GetText() .. " | " .. plain(row.link:GetText()) .. " | " .. row.response:GetText() .. " | " .. row.time:GetText() .. " | icon " .. tostring(icon))
			end
		end
		log(rows .. " rows, content height " .. tostring(history.scroll.content:GetHeight()))
	end
	dumpHistory(shane, "Shane")
	dumpHistory(clients[4].env, "Nyx")

	local trade = shane.OpenLoot.Trade
	local function dumpTrade(label)
		print("")
		print(label)
		local frame = trade.frame
		log("window " .. tostring(frame and frame:IsShown()) .. " " .. tostring(frame and frame:GetWidth()) .. " x " .. tostring(frame and frame:GetHeight()))
		local shown = 0
		for _, row in ipairs(trade.rows or {}) do
			if row:IsShown() then
				shown = shown + 1
				log(plain(row.link:GetText()) .. " | " .. row.winner:GetText() .. " | " .. row.trade:GetText())
			end
		end
		if shown == 0 then
			log("no rows")
		end
	end
	dumpTrade("Shane trade window, before the trade:")

	local baseName = shane.UnitName
	function shane.UnitName(unit)
		if unit == "NPC" then
			return shane._npc and shortOf(shane._npc) or nil
		end
		return baseName(unit)
	end
	function shane.UnitIsUnit(left, right)
		local function who(unit)
			if unit == "NPC" then
				return shane._npc and shortOf(shane._npc) or ""
			end
			local person = shane._unitPerson(unit)
			return person and shortOf(person.name) or ""
		end
		local a, b = who(left), who(right)
		return a ~= "" and a == b
	end
	shane._npc = "Nyx-Area52"
	shane._tradeSlots = {}
	local recipient = shane.CreateFrame("FontString", "TradeFrameRecipientNameText")
	recipient:SetText("Nyx")
	function shane.ClearCursor() end
	function shane.C_Container.PickupContainerItem(bag, slot)
		local link = shane.C_Container.GetContainerItemLink(bag, slot)
		shane._cursor = link
		log("[Shane] PICKUP bag " .. bag .. " slot " .. slot .. " " .. plain(link))
		return true
	end
	function shane.ClickTradeButton(slot)
		shane._tradeSlots[slot] = shane._cursor
		log("[Shane] TRADE SLOT " .. slot .. " " .. plain(shane._cursor))
		shane._cursor = nil
		return true
	end
	function shane.GetTradePlayerItemLink(slot)
		return shane._tradeSlots[slot]
	end
	shane.ERR_TRADE_COMPLETE = "Trade complete."
	shane.LE_GAME_ERR_TRADE_COMPLETE = 1

	print("")
	print("Nyx opens a trade with Shane.")
	step("[Shane] TRADE_SHOW", function()
		shane.fire("TRADE_SHOW")
	end)
	log("partner " .. tostring(trade.partner))
	if not shane._tradeSlots[1] then
		log("nothing was placed in the trade")
	end
	for slot, link in pairs(shane._tradeSlots) do
		log("offered slot " .. slot .. ": " .. plain(link))
	end

	print("")
	print("Shane accepts. The trade completes.")
	step("[Shane] TRADE_ACCEPT_UPDATE", function()
		shane.fire("TRADE_ACCEPT_UPDATE", 1, 1)
	end)
	step("[Shane] UI_INFO_MESSAGE", function()
		shane.fire("UI_INFO_MESSAGE", shane.LE_GAME_ERR_TRADE_COMPLETE, shane.ERR_TRADE_COMPLETE)
	end)
	step("[Shane] TRADE_CLOSED", function()
		shane.fire("TRADE_CLOSED")
	end)
	dumpTrade("Shane trade window, after trading the cloak to Nyx:")

	local function client(name)
		for _, entry in ipairs(clients) do
			if shortOf(entry.spec.name) == name then
				return entry.env
			end
		end
	end
	local nyx = client("Nyx")
	local thorn = client("Thorn")

	print("")
	print("Pack mule:")
	step("[Shane] /ol mule Nyx", function()
		shane.OpenLoot:Slash("mule Nyx")
	end)
	bagsByPlayer["Nyx-Area52"] = {
		[0] = {
			{ id = 17182, bound = false },
		},
	}
	step("[Nyx] /ol run", function()
		nyx.OpenLoot:Slash("run")
	end)
	step("[Shane] /ol run", function()
		shane.OpenLoot:Slash("run")
	end)
	step("[Shane] Replace", function()
		if not click(shane, "Replace") then
			log("[Shane] ERROR the replace prompt did not appear")
		end
	end)
	print("")
	print("Mixed bags:")
	local mixed = shane.OpenLoot.Session.active
	local nyxIndex = nil
	for index, item in ipairs(mixed and mixed.items or {}) do
		local name = (item.link or ""):match("%[(.-)%]") or item.link
		log(index .. ". " .. name .. " held by " .. tostring(item.holder))
		if item.holder == "Nyx" then
			nyxIndex = index
		end
	end
	if nyxIndex then
		step("[Shane] award Nyx's item to Veyra", function()
			shane.OpenLoot.Session:Award(nyxIndex, "Veyra")
		end)
	else
		log("[Shane] ERROR Nyx's item was not in the session")
	end
	local function owes(env, itemName)
		for _, entry in ipairs(env.OpenLoot.Trade.list or {}) do
			if (entry.link or ""):find(itemName, 1, true) then
				return true
			end
		end
		return false
	end
	log("Shane owes Sulfuras: " .. tostring(owes(shane, "Sulfuras")))
	log("Nyx owes Sulfuras: " .. tostring(owes(nyx, "Sulfuras")))
	step("[Nyx] roll", function()
		nyx.fire("START_LOOT_ROLL", 7, 60)
	end)
	step("[Shane] roll", function()
		shane.fire("START_LOOT_ROLL", 7, 60)
	end)

	lootSim.method = "master"
	lootSim.raidID = 1
	lootSim.items = 2
	lootSim.candidates = { "Shane", "Veyra", "Thorn", "Nyx" }
	lootSim.given = {}
	print("")
	print("Shane is master looter (only the raid leader can be). Two items drop.")
	step("[Shane] LOOT_READY", function()
		shane.fire("LOOT_READY")
	end)
	for _, gift in ipairs(lootSim.given) do
		log("given slot " .. gift.slot .. " to " .. tostring(gift.to))
	end

	print("")
	print("Nyx leaves the raid.")
	local saved = roster[4]
	roster[4] = nil
	step("[Shane] GROUP_ROSTER_UPDATE", function()
		shane.fire("GROUP_ROSTER_UPDATE")
	end)
	roster[4] = saved
	shane.OpenLoot.RaidMode.lastMaster = nil
	lootSim.given = {}
	step("[Shane] LOOT_READY after Nyx left", function()
		shane.fire("LOOT_READY")
	end)
	for _, gift in ipairs(lootSim.given) do
		log("given slot " .. gift.slot .. " to " .. tostring(gift.to))
	end

	print("")
	step("[Shane] /ol mule Nobody", function()
		shane.OpenLoot:Slash("mule Nobody")
	end)
	step("[Shane] roster update with an unseen mule", function()
		shane.fire("GROUP_ROSTER_UPDATE")
	end)
	step("[Shane] /ol mule", function()
		shane.OpenLoot:Slash("mule")
	end)
end

local function registered(env, eventName)
	for frame in pairs(env._eventFrames or {}) do
		if frame._events and frame._events[eventName] then
			return true
		end
	end
	return false
end

local function partyClient(instanceType, mapName)
	local env = {}
	setmetatable(env, { __index = _G })
	install(env, personByName("Shane-Area52"))
	env._inGroup = true
	env.GetInstanceInfo = function()
		return mapName, instanceType, 0, "", 5, 0, false, 1429
	end
	env.IsInRaid = function()
		return false
	end
	env.IsInGroup = function(category)
		if category ~= nil then
			return false
		end
		return env._inGroup and true or false
	end
	loadAddon(env)
	return env
end

local function partyLeave(instanceType, mapName)
	print("")
	print("Party check: " .. mapName .. " (" .. instanceType .. "). Not a raid.")
	local env = partyClient(instanceType, mapName)
	step("[" .. instanceType .. "] boot", function()
		env.fire("ADDON_LOADED", "openloot")
		env.fire("PLAYER_ENTERING_WORLD", true, false)
		env.fire("GROUP_ROSTER_UPDATE")
	end)
	step("[" .. instanceType .. "] commands", function()
		env.OpenLoot:Slash("run")
		env.OpenLoot:Slash("mule Nyx")
		env.OpenLoot:Slash("trade")
	end)
	step("[" .. instanceType .. "] leave", function()
		env._inGroup = false
		env.fire("GROUP_LEFT")
		env.fire("GROUP_LEFT")
		env.fire("ZONE_CHANGED_NEW_AREA")
	end)
	local ol = env.OpenLoot
	local quiet = {
		"START_LOOT_ROLL",
		"CONFIRM_LOOT_ROLL",
		"LOOT_OPENED",
		"LOOT_READY",
		"CONFIRM_LOOT_DISTRIBUTION",
	}
	for _, eventName in ipairs(quiet) do
		if registered(env, eventName) then
			log("[" .. instanceType .. "] ERROR still listening for " .. eventName)
		end
	end
	if ol.RaidMode:IsOn() or (ol.db.activeRaid ~= nil) then
		log("[" .. instanceType .. "] ERROR raid mode stayed on after leaving a party")
	end
	if ol.Session:IsActive() or ol.db.session ~= nil then
		log("[" .. instanceType .. "] ERROR a loot session existed outside a raid")
	end
	if ol.db.passTouch ~= nil then
		log("[" .. instanceType .. "] ERROR pass on loot was changed in a party")
	end
end

partyLeave("none", "Elwynn Forest")
partyLeave("party", "Deadmines")

print("")
log("Wire: " .. wireStats.frames .. " addon messages, " .. wireStats.bytes .. " bytes")
