local OL = OpenLoot

OL.Demo = {}
local Demo = OL.Demo

local FAKE = {}
local ROSTER = [[
Veyra PALADIN Officer Main
Thorn HUNTER Raider Clone1
Sable ROGUE Raider Clone2
Nyx MAGE Officer Main
Bramble DRUID Raider Clone1
Quarrel WARRIOR Raider Clone2
Moss SHAMAN Raider Main
Cinder MAGE Raider Clone3
Holt WARRIOR Officer Main
Piper HUNTER Raider Clone1
Wren DRUID Raider Clone2
Ash WARLOCK Raider Clone3
Lark PRIEST Officer Main
Flint DEATHKNIGHT Raider Clone1
Ivy MONK Raider Clone2
Reed EVOKER Raider Clone3
Gale SHAMAN Raider Main
Nim ROGUE Raider Clone1
Ora PALADIN Raider Clone2
Pell HUNTER Raider Clone3
Quill MAGE Officer Main
Rune DEATHKNIGHT Raider Clone1
Sedge DRUID Raider Clone2
]]
for line in ROSTER:gmatch("[^\n]+") do
	local name, class, rank, note = line:match("^%s*(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s*$")
	if name then
		FAKE[#FAKE + 1] = { name = name, class = class, rank = rank, note = note }
	end
end

local function link(itemID, name, color)
	return "|c" .. color .. "|Hitem:" .. itemID .. "::::::::80:::::|h[" .. name .. "]|h|r"
end

local function textureOf(itemLink)
	if not C_Item.GetItemInfoInstant then
		return nil
	end
	return select(5, C_Item.GetItemInfoInstant(itemLink))
end

local function piece(itemID, name, color, ilvl, equipLoc, classID, subClassID)
	local itemLink = link(itemID, name, color)
	return {
		link = itemLink,
		ilvl = ilvl,
		texture = textureOf(itemLink),
		equipLoc = equipLoc,
		classID = classID,
		subClassID = subClassID,
		votes = {},
		ballots = {},
	}
end

local function vote(response, slotIlvl, note, s1, s2)
	return {
		response = response,
		note = note,
		slotIlvl = slotIlvl,
		diff = slotIlvl and 0 or nil,
		s1 = s1,
		s2 = s2,
	}
end

local function demoKey(key)
	return type(key) == "string" and (key:sub(1, 5) == "demo:" or key:sub(1, 4) == "dev:")
end

local function demoSession(id)
	return type(id) == "string" and id:sub(1, 8) == "dev-demo"
end

function Demo:ScrubSaved()
	local db = OL.db
	if not db then
		return
	end
	local store = db.history
	if store and store.order and store.sessions then
		for index = #store.order, 1, -1 do
			local id = store.order[index]
			if demoSession(id) then
				store.sessions[id] = nil
				table.remove(store.order, index)
			end
		end
	end
	if type(db.trades) == "table" then
		local kept = {}
		local removed = false
		for _, entry in ipairs(db.trades) do
			local key = type(entry) == "table" and entry.key or ""
			if demoKey(key) then
				removed = true
			else
				kept[#kept + 1] = entry
			end
		end
		if removed then
			db.trades = kept
			if OL.Trade then
				OL.Trade.list = kept
			end
		end
	end
	if demoSession(type(db.session) == "table" and db.session.id or nil) then
		db.session = nil
	end
end

function Demo:HoldSaves()
	if self.held or not OL.db then
		return
	end
	self:ScrubSaved()
	self.held = {
		history = OL.db.history,
		trades = OL.db.trades,
		session = OL.db.session,
	}
	OL.db.history = { sessions = {}, order = {} }
	OL.db.trades = {}
	OL.db.session = nil
	if OL.Trade then
		OL.Trade.list = OL.db.trades
	end
end

function Demo:ReleaseSaves()
	if not self.held or not OL.db then
		self.held = nil
		return
	end
	OL.db.history = self.held.history
	OL.db.trades = self.held.trades
	OL.db.session = self.held.session
	self.held = nil
	if OL.Trade then
		OL.Trade.list = OL.db.trades
		OL.Trade:SyncListen()
	end
end

function Demo:StopDemo(quiet)
	OL.devMode = false
	OL.devRoster = nil
	OL.devCouncil = nil
	if self.held and OL.Session then
		OL.Session:Clear()
	end
	self:ReleaseSaves()
	if OL.Session and OL.Session:Restore() then
		OL.Session:ShowUI()
	end
	if OL.Trade then
		if not OL.Trade.list or #OL.Trade.list == 0 then
			OL.Trade:Hide()
		elseif OL.Trade.frame and OL.Trade.frame:IsShown() then
			OL.Trade:Refresh()
		end
	end
	if OL.Versions then
		for _, person in ipairs(FAKE) do
			OL.Versions.known[person.name] = nil
		end
	end
	if OL.History and OL.History.frame and OL.History.frame:IsShown() then
		OL.History:Refresh()
	end
	if OL.Versions and OL.Versions.frame then
		OL.Versions.frame:Hide()
	end
	if not quiet then
		OL:Print("Demo off.")
	end
end

function Demo:Demo()
	if self.held then
		self:StopDemo(true)
	end
	self:HoldSaves()
	local me = OL:ShortName(OL:FullName("player"))
	local _, classFile = UnitClass("player")
	OL.devMode = true

	local roster = { { name = me, classFile = classFile } }
	local council = {}
	local myRank = "Guild Master"
	local saved = OL.Council.byShort and OL.Council.byShort[me]
	if saved and saved.rankName and saved.rankName ~= "" then
		myRank = saved.rankName
	end
	council[me] = { name = me, rankName = myRank, rankIndex = 0, officerNote = "Main", council = true }
	for _, person in ipairs(FAKE) do
		roster[#roster + 1] = { name = person.name, classFile = person.class }
		council[person.name] = {
			name = person.name,
			rankName = person.rank,
			rankIndex = 2,
			officerNote = person.note,
			council = person.rank == "Officer",
		}
	end
	OL.devRoster = roster
	OL.devCouncil = council

	local epic = "ffa335ee"
	local rare = "ff0070dd"
	local responses = { "BIS", "UPGRADE", "OFFSPEC", "PASS" }
	local slots = {
		{ "Cloak", "INVTYPE_CLOAK", 4, 1 },
		{ "Ring", "INVTYPE_FINGER", 4, 0 },
		{ "Trinket", "INVTYPE_TRINKET", 4, 0 },
		{ "Neck", "INVTYPE_NECK", 4, 0 },
		{ "Chest", "INVTYPE_CHEST", 4, 4 },
		{ "Staff", "INVTYPE_2HWEAPON", 2, 10 },
		{ "Robe", "INVTYPE_ROBE", 4, 1 },
		{ "Helm", "INVTYPE_HEAD", 4, 4 },
		{ "Legs", "INVTYPE_LEGS", 4, 3 },
		{ "Gloves", "INVTYPE_HAND", 4, 2 },
	}
	local itemIDs = { 19019, 17182, 32837, 22589, 236329 }
	local items = {}
	for index = 1, 30 do
		local slot = slots[((index - 1) % #slots) + 1]
		local color = index % 5 == 0 and rare or epic
		local ilvl = 610 + (index % 30)
		local item = piece(itemIDs[((index - 1) % #itemIDs) + 1], "Demo " .. slot[1] .. " " .. index, color, ilvl, slot[2], slot[3], slot[4])
		local dual = slot[2] == "INVTYPE_FINGER" or slot[2] == "INVTYPE_TRINKET"
		for personIndex, person in ipairs(roster) do
			local response = responses[((index + personIndex - 2) % #responses) + 1]
			local slotIlvl = ilvl - ((personIndex * 3 + index) % 24)
			local note = (index + personIndex) % 3 == 0 and "Demo note " .. index or nil
			local gearA = link(itemIDs[1], person.name .. " " .. slot[1] .. " 1", epic)
			local gearB = dual and link(itemIDs[2], person.name .. " " .. slot[1] .. " 2", rare) or nil
			local cast = vote(response, slotIlvl, note, gearA, gearB)
			cast.diff = ilvl - slotIlvl
			item.votes[person.name] = cast
		end
		if index == 1 then
			item.votes[roster[#roster].name] = vote(nil, nil, nil, nil, nil)
			item.myResponse = "BIS"
			item.myNote = "Main set"
		elseif index % 4 == 2 then
			item.myResponse = responses[((index - 1) % #responses) + 1]
			item.myNote = "Saved note"
		end
		local winner = roster[((index - 1) % #roster) + 1]
		item.ballots = { Veyra = me, Nyx = winner.name }
		if index % 6 == 0 then
			item.awardedTo = winner.name
		end
		items[index] = item
	end

	OL.Session.active = {
		id = "dev-demo",
		owner = OL:FullName("player"),
		items = items,
	}

	OL.Trade.list = OL.db.trades
	for index = 1, 8 do
		local item = items[index * 3]
		local winner = roster[((index - 1) % #roster) + 1]
		OL.Trade.list[#OL.Trade.list + 1] = {
			key = "demo:" .. index,
			link = item.link,
			texture = item.texture,
			winner = winner.name,
		}
	end
	OL.Trade:Save()

	local function awardRows(item)
		local built = {}
		for _, person in ipairs(roster) do
			local cast = item.votes[person.name] or {}
			local info = council[person.name]
			built[#built + 1] = {
				name = person.name,
				class = person.classFile,
				rank = info and info.rankName or "",
				officerNote = info and info.officerNote or "",
				response = cast.response,
				slotIlvl = cast.slotIlvl,
				diff = cast.diff,
				note = cast.note,
				s1 = cast.s1,
				s2 = cast.s2,
			}
		end
		return built
	end
	for sessionIndex = 16, 1, -1 do
		local id = sessionIndex == 1 and "dev-demo" or ("dev-demo-" .. sessionIndex)
		local when = time() - ((sessionIndex - 1) * 86400)
		OL.History:Ensure(id, when)
		local session = OL.db.history.sessions[id]
		session.awards = {}
		for awardIndex = 1, 24 do
			local item = items[((sessionIndex * 3 + awardIndex - 1) % #items) + 1]
			local winner = roster[((awardIndex + sessionIndex) % #roster) + 1].name
			local cast = item.votes[winner]
			session.awards[awardIndex] = {
				index = awardIndex,
				winner = winner,
				link = item.link,
				response = cast and cast.response or responses[((awardIndex + sessionIndex) % #responses) + 1],
				time = when - (awardIndex * 90),
				rows = awardRows(item),
			}
		end
	end

	local versions = { OL:Version(), "0.1.0", "0.2.0", "0.3.0", nil }
	OL.Versions.known[me] = OL:Version()
	for index, person in ipairs(FAKE) do
		OL.Versions.known[person.name] = versions[((index - 1) % #versions) + 1]
	end
	OL.Versions.waiting = false

	OL.RaiderFrame:Show()
	OL.RaiderFrame:Refresh()
	OL.CouncilFrame:Show()
	OL.CouncilFrame.selected = 1
	OL.CouncilFrame:Refresh()
	OL.Trade:Show()
	OL.History:EnsureFrame()
	OL.History.selected = "dev-demo"
	OL.History.frame:Show()
	OL.History:Refresh()
	OL.Versions:Ensure()
	OL.Versions.frame:Show()
	OL.Versions:Refresh()

	OL:Print("Demo on. Sample screens are local only. /openloot demo off to clear.")
end

local logout = CreateFrame("Frame")
logout:RegisterEvent("PLAYER_LOGOUT")
logout:SetScript("OnEvent", function()
	Demo:ReleaseSaves()
end)

function Demo:DemoSlash(rest)
	local sub = (rest or ""):lower()
	if sub == "off" or (sub == "" and OL.devMode) then
		self:StopDemo(false)
		return
	end
	self:Demo()
end
