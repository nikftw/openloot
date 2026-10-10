local OL = OpenLoot

OL.Items = {}
local Items = OL.Items

local MIN_QUALITY = Enum.ItemQuality.Rare
local ARMOR = Enum.ItemClass.Armor
local WEAPON = Enum.ItemClass.Weapon
local SUBCLASS_READERS = { C_Item.GetItemSubClassInfo, GetItemSubClassInfo }

local TRADE_NEEDLE = "You may trade this item"
if BIND_TRADE_TIME_REMAINING then
	TRADE_NEEDLE = (BIND_TRADE_TIME_REMAINING:match("^(.-)%%s") or TRADE_NEEDLE):gsub("%s+$", "")
end

local SLOT_FALLBACK = {
	INVTYPE_HEAD = "Head",
	INVTYPE_NECK = "Neck",
	INVTYPE_SHOULDER = "Shoulder",
	INVTYPE_CHEST = "Chest",
	INVTYPE_ROBE = "Chest",
	INVTYPE_WAIST = "Waist",
	INVTYPE_LEGS = "Legs",
	INVTYPE_FEET = "Feet",
	INVTYPE_WRIST = "Wrist",
	INVTYPE_HAND = "Hands",
	INVTYPE_FINGER = "Finger",
	INVTYPE_TRINKET = "Trinket",
	INVTYPE_CLOAK = "Back",
	INVTYPE_WEAPON = "One-Hand",
	INVTYPE_2HWEAPON = "Two-Hand",
	INVTYPE_WEAPONMAINHAND = "Main Hand",
	INVTYPE_WEAPONOFFHAND = "Off Hand",
	INVTYPE_HOLDABLE = "Off Hand",
	INVTYPE_SHIELD = "Off Hand",
	INVTYPE_RANGED = "Ranged",
	INVTYPE_RANGEDRIGHT = "Ranged",
}

local ALWAYS_VISIBLE = {
	INVTYPE_CLOAK = true,
	INVTYPE_NECK = true,
	INVTYPE_FINGER = true,
	INVTYPE_TRINKET = true,
}

local SLOT_MAP = {
	INVTYPE_HEAD = { 1 },
	INVTYPE_NECK = { 2 },
	INVTYPE_SHOULDER = { 3 },
	INVTYPE_BODY = { 4 },
	INVTYPE_CHEST = { 5 },
	INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 },
	INVTYPE_LEGS = { 7 },
	INVTYPE_FEET = { 8 },
	INVTYPE_WRIST = { 9 },
	INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 },
	INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16, 17 },
	INVTYPE_2HWEAPON = { 16 },
	INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 },
	INVTYPE_HOLDABLE = { 17 },
	INVTYPE_SHIELD = { 17 },
	INVTYPE_RANGED = { 16 },
	INVTYPE_RANGEDRIGHT = { 16 },
	INVTYPE_THROWN = { 16 },
}

local ARMOR_SUBCLASS = {
	WARRIOR = 4,
	PALADIN = 4,
	DEATHKNIGHT = 4,
	HUNTER = 3,
	SHAMAN = 3,
	EVOKER = 3,
	ROGUE = 2,
	DRUID = 2,
	MONK = 2,
	DEMONHUNTER = 2,
	MAGE = 1,
	PRIEST = 1,
	WARLOCK = 1,
}

function Items:IsTradeable(bag, slot)
	if TRADE_NEEDLE == "" then
		return false
	end
	local data = C_TooltipInfo.GetBagItem(bag, slot)
	for _, line in ipairs(data and data.lines or {}) do
		local text = line.leftText
		if type(text) == "string" and text:find(TRADE_NEEDLE, 1, true) then
			return true
		end
	end
	return false
end

-- Item links travel as their item string, minus "item:" and trailing colons.
function Items:Pack(link)
	local itemString = type(link) == "string" and link:match("item:([%-%d:]+)")
	return itemString and (itemString:gsub(":+$", "")) or ""
end

function Items:Unpack(packed)
	if not packed or packed == "" then
		return nil
	end
	return "item:" .. packed
end

-- The full link when this client knows the item, else a stand-in link that
-- still shows a tooltip. The second value says whether the link is the real one.
function Items:Link(itemString)
	if not itemString then
		return nil, true
	end
	local _, link = C_Item.GetItemInfo(itemString)
	if link then
		return link, true
	end
	local itemID = C_Item.GetItemInfoInstant(itemString)
	if not itemID then
		return nil, true
	end
	return "|cffffffff|H" .. itemString .. "|h[" .. itemID .. "]|h|r", false
end

function Items:WhenLoaded(itemString, callback)
	local itemID = C_Item.GetItemInfoInstant(itemString)
	if itemID then
		Item:CreateFromItemID(itemID):ContinueOnItemLoad(callback)
	end
end

function Items:Describe(item)
	local _, _, _, equipLoc, texture, classID, subClassID = C_Item.GetItemInfoInstant(item.link)
	item.equipLoc = equipLoc or ""
	item.texture = texture
	item.classID = classID
	item.subClassID = subClassID
	return item
end

function Items:SlotLabel(equipLoc)
	if not equipLoc or equipLoc == "" then
		return ""
	end
	local globalName = _G[equipLoc]
	if type(globalName) == "string" and globalName ~= "" then
		return globalName
	end
	return SLOT_FALLBACK[equipLoc] or ""
end

function Items:TypeLabel(classID, subClassID)
	if classID == nil or subClassID == nil then
		return ""
	end
	for _, reader in pairs(SUBCLASS_READERS) do
		if reader then
			local ok, name = pcall(reader, classID, subClassID)
			if ok and type(name) == "string" and name ~= "" then
				return name
			end
		end
	end
	return ""
end

local function trim(text)
	if not text or text == "" then
		return ""
	end
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Items:RowMeta(item)
	local parts = {}
	if item.ilvl and item.ilvl > 0 then
		parts[#parts + 1] = trim(tostring(item.ilvl))
	end
	local typeName = trim(self:TypeLabel(item.classID, item.subClassID))
	local misc = item.classID == ARMOR and item.subClassID == 0
	if not misc and typeName ~= "" then
		local lower = typeName:lower()
		if lower ~= "miscellaneous" and lower ~= "misc" then
			parts[#parts + 1] = typeName
		end
	end
	local slotName = trim(self:SlotLabel(item.equipLoc))
	if slotName ~= "" then
		parts[#parts + 1] = slotName
	end
	return table.concat(parts, "· ")
end

function Items:PlayerCanUse(link, equipLoc, classID, subClassID)
	if ALWAYS_VISIBLE[equipLoc] then
		return true
	end
	if classID ~= ARMOR and classID ~= WEAPON then
		return true
	end
	if classID == ARMOR and subClassID and subClassID >= 1 and subClassID <= 4 then
		local _, classFile = UnitClass("player")
		local heaviest = ARMOR_SUBCLASS[classFile]
		if not heaviest then
			return true
		end
		return subClassID <= heaviest
	end
	if link then
		local itemID = C_Item.GetItemInfoInstant(link)
		if itemID then
			local ok, canUse = pcall(C_PlayerInfo.CanUseItem, itemID)
			if ok and type(canUse) == "boolean" then
				return canUse
			end
		end
	end
	return true
end

function Items:ItemLevel(link, location)
	if location and C_Item.DoesItemExist(location) then
		local current = C_Item.GetCurrentItemLevel(location)
		if current and current > 0 then
			return current
		end
	end
	if link then
		return C_Item.GetDetailedItemLevelInfo(link)
	end
	return nil
end

-- Every rare-or-better item in the bags that can still change hands, with
-- where it sits so the holder can find it again to trade.
function Items:ScanBags()
	local found = {}
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
			if C_Item.DoesItemExist(location) then
				local link = C_Container.GetContainerItemLink(bag, slot)
				local quality = C_Item.GetItemQuality(location)
				if link and quality and quality >= MIN_QUALITY
					and (not C_Item.IsBound(location) or self:IsTradeable(bag, slot)) then
					local ok, guid = pcall(C_Item.GetItemGUID, location)
					found[#found + 1] = {
						link = link,
						ilvl = self:ItemLevel(link, location) or 0,
						bag = bag,
						slot = slot,
						guid = ok and type(guid) == "string" and guid ~= "" and guid or nil,
					}
				end
			end
		end
	end
	return found
end

function Items:Equipped(equipLoc)
	local slots = SLOT_MAP[equipLoc]
	if not slots then
		return nil, nil
	end
	local first = GetInventoryItemLink("player", slots[1])
	local second = slots[2] and GetInventoryItemLink("player", slots[2]) or nil
	return first, second
end

local function levelOf(link)
	if not link then
		return nil
	end
	return C_Item.GetDetailedItemLevelInfo(link)
end

local function idOf(link)
	if not link then
		return nil
	end
	return C_Item.GetItemInfoInstant(link)
end

function Items:Compare(lootLink, lootIlvl, equipLoc)
	local first, second = self:Equipped(equipLoc)
	local lootID = idOf(lootLink)
	local firstLevel = levelOf(first)
	local secondLevel = levelOf(second)
	local base
	if lootID and idOf(first) == lootID and firstLevel then
		base = firstLevel
	elseif lootID and idOf(second) == lootID and secondLevel then
		base = secondLevel
	elseif firstLevel and secondLevel then
		base = math.min(firstLevel, secondLevel)
	else
		base = firstLevel or secondLevel
	end
	local diff
	if lootIlvl and base then
		diff = lootIlvl - base
	end
	if equipLoc ~= "INVTYPE_FINGER" and equipLoc ~= "INVTYPE_TRINKET" then
		second = nil
	end
	return base, diff, first, second
end

function Items:FindTradeSlot(entry, reserved)
	local function free(bag, slot)
		return bag and slot and not reserved[bag .. ":" .. slot]
	end
	local function guidAt(bag, slot)
		if not entry.guid then
			return nil
		end
		local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
		if not C_Item.DoesItemExist(location) then
			return nil
		end
		local ok, guid = pcall(C_Item.GetItemGUID, location)
		if ok then
			return guid
		end
		return nil
	end
	local function sameGuid(bag, slot)
		local current = guidAt(bag, slot)
		if not current or not entry.guid then
			return false
		end
		local ok, match = pcall(function()
			return current == entry.guid
		end)
		return ok and match or false
	end
	if entry.bag and entry.slot then
		local info = C_Container.GetContainerItemInfo(entry.bag, entry.slot)
		local keptGuid = sameGuid(entry.bag, entry.slot)
		local sameLink = info and info.hyperlink == entry.link
		if free(entry.bag, entry.slot) and (keptGuid or sameLink) then
			return entry.bag, entry.slot
		end
	end
	local linkBag, linkSlot
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			if free(bag, slot) then
				if sameGuid(bag, slot) then
					return bag, slot
				end
				local info = C_Container.GetContainerItemInfo(bag, slot)
				if not linkBag and info and info.hyperlink == entry.link then
					linkBag, linkSlot = bag, slot
				end
			end
		end
	end
	return linkBag, linkSlot
end

function Items:CleanNote(text)
	text = text or ""
	text = text:gsub("%c", " ")
	if #text > 80 then
		-- Cut on a character boundary, never inside a multi-byte one.
		text = text:sub(1, 80):gsub("[\192-\255][\128-\191]*$", "")
	end
	return text
end
