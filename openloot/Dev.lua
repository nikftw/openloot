-- Temporary test tools. Delete this file and its line in openloot.toc before release.
local OL = OpenLoot

OL.Dev = {}
local Dev = OL.Dev

local FAKE = {
	{ name = "Veyra", class = "PALADIN", rank = "Officer", note = "Main" },
	{ name = "Thorn", class = "HUNTER", rank = "Raider", note = "Clone1" },
	{ name = "Sable", class = "ROGUE", rank = "Raider", note = "Clone2" },
	{ name = "Nyx", class = "MAGE", rank = "Officer", note = "Main" },
	{ name = "Bramble", class = "DRUID", rank = "Raider", note = "Clone1" },
	{ name = "Quarrel", class = "WARRIOR", rank = "Raider", note = "Clone2" },
	{ name = "Moss", class = "SHAMAN", rank = "Raider", note = "Main" },
}

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

function Dev:Stop()
	OL.testSession = false
	if OL.Session then
		OL.Session:Clear()
	end
	OL:Print("Test session cleared.")
end

function Dev:Start()
	if OL.devMode then
		self:StopDemo(true)
	end
	local items = OL.Items:ScanBags(true)
	if #items == 0 then
		OL:Print("No items in your bags.")
		return
	end
	OL.testSession = true
	OL.Session:Start(items)
	OL:Print("Test session started from your bags. /openloot dev off clears it.")
end

function Dev:Slash(rest)
	local sub = (rest or ""):lower()
	if sub == "off" then
		self:Stop()
		return
	end
	self:Start()
end

function Dev:StopDemo(quiet)
	OL.devMode = false
	OL.devRoster = nil
	OL.devCouncil = nil
	if OL.Session then
		OL.Session:Clear()
	end
	if OL.Trade and OL.Trade.list then
		local kept = {}
		for _, entry in ipairs(OL.Trade.list) do
			local key = entry.key or ""
			local demo = key:sub(1, 4) == "dev:" or key:sub(1, 9) == "dev-demo:"
			if not demo then
				kept[#kept + 1] = entry
			end
		end
		OL.Trade.list = kept
		OL.Trade:Save()
		OL.Trade:Hide()
	end
	local store = OL.db and OL.db.history
	if store then
		for index = #store.order, 1, -1 do
			local id = store.order[index]
			if id and id:sub(1, 8) == "dev-demo" then
				store.sessions[id] = nil
				table.remove(store.order, index)
			end
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

function Dev:Demo()
	local me = OL:ShortName(OL:FullName("player"))
	local _, classFile = UnitClass("player")
	OL.testSession = false
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
		local item = piece(itemIDs[((index - 1) % #itemIDs) + 1], "Dev " .. slot[1] .. " " .. index, color, ilvl, slot[2], slot[3], slot[4])
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

	local kept = {}
	OL.Trade.list = OL.Trade.list or {}
	for _, entry in ipairs(OL.Trade.list) do
		local key = entry.key or ""
		if key:sub(1, 4) ~= "dev:" then
			kept[#kept + 1] = entry
		end
	end
	OL.Trade.list = kept
	for index = 1, 8 do
		local item = items[index * 3]
		local winner = roster[((index - 1) % #roster) + 1]
		OL.Trade.list[#OL.Trade.list + 1] = {
			key = "dev:" .. index,
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
	OL.History:Ensure("dev-demo", time())
	local session = OL.db.history.sessions["dev-demo"]
	session.awards = {}
	for index = 1, 20 do
		local item = items[index]
		local winner = item.awardedTo or roster[((index - 1) % #roster) + 1].name
		local cast = item.votes[winner]
		session.awards[index] = {
			index = index,
			winner = winner,
			link = item.link,
			response = cast and cast.response or "BIS",
			time = time() - (index * 60),
			rows = awardRows(item),
		}
	end
	OL.History:Ensure("dev-demo-2", time() - 86400)
	local older = OL.db.history.sessions["dev-demo-2"]
	older.awards = {}
	for index = 21, 24 do
		local item = items[index]
		local winner = roster[((index - 1) % #roster) + 1].name
		older.awards[#older.awards + 1] = {
			index = index,
			winner = winner,
			link = item.link,
			response = "UPGRADE",
			time = time() - 86400 - (index * 60),
			rows = awardRows(item),
		}
	end

	OL.Versions.known[me] = OL:Version()
	OL.Versions.known.Veyra = OL:Version()
	OL.Versions.known.Thorn = "0.1.0"
	OL.Versions.known.Nyx = "0.3.0"
	OL.Versions.known.Bramble = "0.1.0"
	OL.Versions.known.Moss = OL:Version()
	OL.Versions.known.Sable = nil
	OL.Versions.known.Quarrel = nil
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

function Dev:DemoSlash(rest)
	local sub = (rest or ""):lower()
	if sub == "off" or (sub == "" and OL.devMode) then
		self:StopDemo(false)
		return
	end
	self:Demo()
end
