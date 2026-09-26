local OL = OpenLoot

OL.Items = {}
local Items = OL.Items

local MIN_QUALITY = (Enum and Enum.ItemQuality and Enum.ItemQuality.Rare) or 3

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

local tip

local function scanTip()
	if not tip then
		tip = CreateFrame("GameTooltip", "OpenLootScanTip", nil, "GameTooltipTemplate")
		tip:SetOwner(UIParent, "ANCHOR_NONE")
	end
	return tip
end

function Items:IsTradeable(bag, slot)
	tip = scanTip()
	tip:ClearLines()
	local shown = pcall(tip.SetBagItem, tip, bag, slot)
	if not shown then
		return false
	end
	local needle = "You may trade this item"
	if BIND_TRADE_TIME_REMAINING then
		needle = BIND_TRADE_TIME_REMAINING:match("^(.-)%%s") or needle
		needle = needle:gsub("%s+$", "")
	end
	if needle == "" then
		return false
	end
	for line = 1, tip:NumLines() do
		local fontString = _G["OpenLootScanTipTextLeft" .. line]
		local text = fontString and fontString:GetText()
		if text and text:find(needle, 1, true) then
			return true
		end
	end
	return false
end

function Items:SlotLabel(equipLoc)
	if not equipLoc or equipLoc == "" then
		return ""
	end
	local globalName = _G[equipLoc]
	if type(globalName) == "string" and globalName ~= "" then
		return globalName
	end
	local fallback = {
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
	return fallback[equipLoc] or ""
end

function Items:TypeLabel(classID, subClassID)
	if classID == nil or subClassID == nil then
		return ""
	end
	local readers = { C_Item and C_Item.GetItemSubClassInfo, GetItemSubClassInfo }
	for _, reader in ipairs(readers) do
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
	local armorClass = Enum and Enum.ItemClass and Enum.ItemClass.Armor or 4
	local misc = item.classID == armorClass and item.subClassID == 0
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
	local armorClass = Enum and Enum.ItemClass and Enum.ItemClass.Armor or 4
	local weaponClass = Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2
	if classID ~= armorClass and classID ~= weaponClass then
		return true
	end
	if classID == armorClass and subClassID and subClassID >= 1 and subClassID <= 4 then
		local _, classFile = UnitClass("player")
		local heaviest = ARMOR_SUBCLASS[classFile]
		if not heaviest then
			return true
		end
		return subClassID <= heaviest
	end
	if link and C_PlayerInfo and C_PlayerInfo.CanUseItem then
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

function Items:ScanBags(allItems)
	local found = {}
	local maxBag = NUM_BAG_SLOTS or 4
	for bag = 0, maxBag do
		local slots = C_Container.GetContainerNumSlots(bag) or 0
		for slot = 1, slots do
			local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
			if C_Item.DoesItemExist(location) then
				local link = C_Container.GetContainerItemLink(bag, slot)
				local quality = C_Item.GetItemQuality(location)
				local take = false
				if link and allItems then
					take = true
				elseif link and quality and quality >= MIN_QUALITY then
					local bound = C_Item.IsBound(location)
					take = not bound or self:IsTradeable(bag, slot)
				end
				if take then
					local _, _, _, equipLoc, icon, classID, subClassID = C_Item.GetItemInfoInstant(link)
					local guid
					if C_Item.GetItemGUID then
						local ok, value = pcall(C_Item.GetItemGUID, location)
						if ok and type(value) == "string" and value ~= "" then
							guid = value
						end
					end
					found[#found + 1] = {
						link = link,
						ilvl = self:ItemLevel(link, location) or 0,
						texture = icon,
						equipLoc = equipLoc or "",
						quality = quality,
						classID = classID,
						subClassID = subClassID,
						bag = bag,
						slot = slot,
						guid = guid,
						votes = {},
						ballots = {},
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
		if not entry.guid or not C_Item.GetItemGUID then
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
	local maxBag = NUM_BAG_SLOTS or 4
	local linkBag, linkSlot
	for bag = 0, maxBag do
		local slots = C_Container.GetContainerNumSlots(bag) or 0
		for slot = 1, slots do
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
	text = text:gsub("[\31\r\n]", " ")
	if #text > 80 then
		text = text:sub(1, 80)
	end
	return text
end
