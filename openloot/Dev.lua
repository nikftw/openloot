-- Temporary in-game demo. Delete this file and its line in openloot.toc before release.
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
		store.sessions["dev-demo"] = nil
		for index = #store.order, 1, -1 do
			if store.order[index] == "dev-demo" then
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
	OL:Print("Dev mode off.")
end

function Dev:Place(frame, point, x, y)
	if not frame then
		return
	end
	frame:ClearAllPoints()
	frame:SetPoint(point, UIParent, point, x, y)
end

function Dev:Start()
	local me = OL:ShortName(OL:FullName("player"))
	local _, classFile = UnitClass("player")
	OL.devMode = true

	local roster = { { name = me, classFile = classFile } }
	local council = {}
	council[me] = { name = me, rankName = "Dev", rankIndex = 0, officerNote = "Main", council = true }
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
	local cloak = piece(19019, "Dev Cloak of the Council", epic, 639, "INVTYPE_CLOAK", 4, 1)
	local ring = piece(17182, "Dev Band of the First", epic, 639, "INVTYPE_FINGER", 4, 0)
	local trinket = piece(32837, "Dev Spore of Looking", epic, 639, "INVTYPE_TRINKET", 4, 0)
	local neck = piece(22589, "Dev Chain of Officers", epic, 636, "INVTYPE_NECK", 4, 0)
	local plate = piece(236329, "Dev Chest of the Wall", epic, 639, "INVTYPE_CHEST", 4, 4)
	local staff = piece(19019, "Dev Staff of Counting", epic, 639, "INVTYPE_2HWEAPON", 2, 10)
	local awardedRing = piece(17182, "Dev Loop of the Second", epic, 642, "INVTYPE_FINGER", 4, 0)
	local cloth = piece(22589, "Dev Robe of the Bench", rare, 626, "INVTYPE_ROBE", 4, 1)

	local gearA = link(19019, "Equipped Cloak", epic)
	local gearB = link(17182, "Equipped Ring", epic)
	local responses = {
		[me] = vote("BIS", 626, "Main set", gearA, nil),
		Veyra = vote("UPGRADE", 623, "Would replace the cloak", gearA, nil),
		Thorn = vote("OFFSPEC", 610, nil, gearA, nil),
		Sable = vote("PASS", 639, nil, gearA, nil),
		Nyx = vote("BIS", 600, "Clone still needs it", gearA, nil),
		Bramble = vote("UPGRADE", 630, nil, gearA, nil),
		Quarrel = vote("PASS", 639, nil, gearA, nil),
		Moss = vote(nil, nil, nil, nil, nil),
	}
	cloak.votes = responses
	cloak.myResponse = "BIS"
	cloak.myNote = "Main set"
	cloak.ballots = { Veyra = me, Nyx = "Veyra" }

	ring.votes = {
		[me] = vote("UPGRADE", 623, nil, gearB, gearB),
		Veyra = vote("BIS", 610, "Lower ring", gearB, gearB),
		Thorn = vote("PASS", 639, nil, gearB, gearB),
		Nyx = vote("OFFSPEC", 616, nil, gearB, gearB),
	}
	ring.myResponse = "UPGRADE"

	trinket.votes = { [me] = vote("OFFSPEC", 619, "Already have the other one", gearA, gearB) }
	neck.votes = {}
	plate.votes = { Quarrel = vote("BIS", 629, "Plate chest", gearA, nil) }
	staff.votes = { Nyx = vote("BIS", 615, nil, gearA, nil) }
	awardedRing.votes = { Veyra = vote("BIS", 610, "This is the one", gearB, gearB) }
	awardedRing.awardedTo = "Veyra"
	cloth.votes = { Bramble = vote("UPGRADE", 600, nil, gearA, nil) }

	for _, item in ipairs({ cloak, ring, trinket, neck, plate, staff, awardedRing, cloth }) do
		for _, person in ipairs(roster) do
			local cast = item.votes[person.name]
			if cast and cast.slotIlvl then
				cast.diff = item.ilvl - cast.slotIlvl
			end
		end
	end

	OL.Session.active = {
		id = "dev-demo",
		owner = OL:FullName("player"),
		items = { cloak, ring, trinket, neck, plate, staff, awardedRing, cloth },
	}

	OL.Trade.list = OL.Trade.list or {}
	local already = false
	for _, entry in ipairs(OL.Trade.list) do
		if entry.key == "dev:7" then
			already = true
		end
	end
	if not already then
		OL.Trade.list[#OL.Trade.list + 1] = {
			key = "dev:7",
			link = awardedRing.link,
			texture = awardedRing.texture,
			winner = "Veyra",
		}
		OL.Trade.list[#OL.Trade.list + 1] = {
			key = "dev:2",
			link = ring.link,
			texture = ring.texture,
			winner = "Thorn",
		}
		OL.Trade:Save()
	end

	local rows = {}
	for _, person in ipairs(roster) do
		local cast = awardedRing.votes[person.name] or {}
		local info = council[person.name]
		rows[#rows + 1] = {
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
	OL.History:Ensure("dev-demo", time())
	local session = OL.db.history.sessions["dev-demo"]
	session.awards = {
		{
			index = 7,
			winner = "Veyra",
			link = awardedRing.link,
			response = "BIS",
			time = time(),
			rows = rows,
		},
	}

	OL.Versions:Remember(me, OL:Version())
	OL.Versions.known.Veyra = OL:Version()
	OL.Versions.known.Thorn = "0.1.0"
	OL.Versions:Remember("Nyx", "0.3.0")
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

	self:Place(OL.RaiderFrame.frame, "TOPLEFT", 24, -60)
	self:Place(OL.CouncilFrame.frame, "TOPRIGHT", -24, -60)
	self:Place(OL.Trade.frame, "BOTTOMLEFT", 24, 40)
	self:Place(OL.History.frame, "BOTTOMRIGHT", -24, 40)

	OL:Print("Dev mode on. Fake loot, trades, history, and versions are local only. /openloot dev off to clear.")
end

function Dev:Slash(rest)
	local sub = (rest or ""):lower()
	if sub == "off" or (sub == "" and OL.devMode) then
		self:Stop()
		return
	end
	self:Start()
end
