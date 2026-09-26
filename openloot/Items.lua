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

local tip = CreateFrame("GameTooltip", "OpenLootScanTip", nil, "GameTooltipTemplate")
tip:SetOwner(UIParent, "ANCHOR_NONE")

function Items:IsTradeable(bag, slot)
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

function Items:PlayerCanUse(link, equipLoc, classID, subClassID)
	if ALWAYS_VISIBLE[equipLoc] then
		return true
	end
	local armorClass = Enum and Enum.ItemClass and Enum.ItemClass.Armor or 4
	local weaponClass = Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2
	if classID ~= armorClass and classID ~= weaponClass then
		return true
	end
	local itemID = C_Item.GetItemInfoInstant(link)
	if itemID and C_Item.GetItemSpecInfo then
		local specs = C_Item.GetItemSpecInfo(itemID)
		if specs and #specs > 0 then
			local specIndex = GetSpecialization()
			local specID = specIndex and GetSpecializationInfo(specIndex)
			if not specID then
				return true
			end
			for _, id in ipairs(specs) do
				if id == specID then
					return true
				end
			end
			return false
		end
	end
	if classID == armorClass and subClassID and subClassID >= 1 and subClassID <= 4 then
		local _, classFile = UnitClass("player")
		return ARMOR_SUBCLASS[classFile] == subClassID
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

function Items:ScanBags()
	local found = {}
	local maxBag = NUM_BAG_SLOTS or 4
	for bag = 0, maxBag do
			local slots = C_Container.GetContainerNumSlots(bag) or 0
		for slot = 1, slots do
			local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
			if C_Item.DoesItemExist(location) then
				local link = C_Container.GetContainerItemLink(bag, slot)
				local quality = C_Item.GetItemQuality(location)
				if link and quality and quality >= MIN_QUALITY then
					local bound = C_Item.IsBound(location)
					if not bound or self:IsTradeable(bag, slot) then
						local _, _, _, equipLoc, icon, classID, subClassID = C_Item.GetItemInfoInstant(link)
						found[#found + 1] = {
							link = link,
							ilvl = self:ItemLevel(link, location) or 0,
							texture = icon,
							equipLoc = equipLoc or "",
							quality = quality,
							classID = classID,
							subClassID = subClassID,
							votes = {},
							rolls = {},
						}
					end
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
	return base, diff, first, second
end

function Items:CleanNote(text)
	text = text or ""
	text = text:gsub("[\31\r\n]", " ")
	if #text > 80 then
		text = text:sub(1, 80)
	end
	return text
end
