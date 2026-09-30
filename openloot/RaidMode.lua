local OL = OpenLoot

OL.RaidMode = {}
local Raid = OL.RaidMode

local function mapID()
	return select(8, GetInstanceInfo())
end

function Raid:Init()
	self.wasInRaidInstance = false
end

function Raid:GetPass()
	if C_Loot and C_Loot.IsPassOnLoot then
		return C_Loot.IsPassOnLoot()
	end
	if GetOptOutOfLoot then
		return GetOptOutOfLoot() and true or false
	end
	return false
end

function Raid:SetPass(enabled)
	local flag = enabled and true or false
	if C_Loot and C_Loot.SetPassOnLoot then
		if pcall(C_Loot.SetPassOnLoot, flag) then
			return
		end
	end
	if SetOptOutOfLoot then
		pcall(SetOptOutOfLoot, flag)
	end
end

function Raid:RememberPass()
	if not OL.db.passTouch then
		OL.db.passTouch = { previous = self:GetPass() }
	end
end

function Raid:ApplyRaiderPass()
	self:RememberPass()
	self:SetPass(true)
end

function Raid:RestorePass()
	if OL.db.passTouch then
		self:SetPass(OL.db.passTouch.previous and true or false)
		OL.db.passTouch = nil
	end
end

function Raid:IsRunner()
	local raid = OL.db.activeRaid
	return raid and raid.on and raid.isRunner or false
end

function Raid:MuleName()
	local raid = OL.db.activeRaid
	local name = raid and raid.mule
	if not name or name == "" then
		return nil
	end
	return name
end

function Raid:IsMule()
	local mule = self:MuleName()
	return mule ~= nil and OL:ShortName(mule) == OL:ShortName(OL:FullName("player"))
end

function Raid:IsCollector()
	if not self:IsOn() then
		return false
	end
	if self:MuleName() then
		return self:IsMule()
	end
	return self:IsRunner()
end

function Raid:IsOn()
	local raid = OL.db.activeRaid
	return raid and raid.on or false
end

function Raid:SyncRollListen()
	local on = self:IsCollector() and true or false
	OL:Listen("START_LOOT_ROLL", on)
	OL:Listen("CONFIRM_LOOT_ROLL", on)
end

function Raid:SyncMasterListen()
	local on = self:IsOn() and true or false
	OL:Listen("LOOT_OPENED", on)
	OL:Listen("LOOT_READY", on)
	OL:Listen("CONFIRM_LOOT_DISTRIBUTION", self:IsCollector() and true or false)
end

function Raid:ApplyLootRole()
	local collect = self:IsCollector()
	self.collecting = collect
	self:SyncRollListen()
	self:SyncMasterListen()
	if not self:IsOn() then
		return
	end
	if collect then
		self:RememberPass()
		self:SetPass(false)
	else
		self:ApplyRaiderPass()
	end
end

function Raid:LeaderName()
	if UnitIsGroupLeader("player") then
		return OL:FullName("player")
	end
	if IsInRaid() then
		for index = 1, GetNumGroupMembers() do
			local name, rank = GetRaidRosterInfo(index)
			if name and rank == 2 then
				return name
			end
		end
	end
	local count = GetNumGroupMembers()
	for index = 1, count do
		local unit = IsInRaid() and ("raid" .. index) or ("party" .. index)
		if UnitExists(unit) and UnitIsGroupLeader(unit) then
			return OL:FullName(unit)
		end
	end
	return nil
end

function Raid:CanLead()
	return UnitIsGroupLeader("player") and OL.Council:IsLocalCouncil()
end

function Raid:Broadcast(on)
	local leader = self:LeaderName() or OL:FullName("player")
	local mule = self:MuleName() or ""
	if on then
		OL.Comms:Send("state\0311\031" .. leader .. "\031" .. mule)
	else
		OL.Comms:Send("state\0310\031" .. leader)
	end
end

function Raid:Enable()
	OL.db.declinedMap = nil
	OL.db.activeRaid = { on = true, mapID = mapID(), isRunner = true }
	self:ApplyLootRole()
	self:Broadcast(true)
	OL.Versions:Query(true)
	OL:Print("OpenLoot is on. You will automatically need on loot.")
end

function Raid:Disable()
	local wasRunner = self:IsRunner()
	OL.db.activeRaid = nil
	self.collecting = false
	self:SyncRollListen()
	self:SyncMasterListen()
	self:RestorePass()
	if wasRunner then
		self:Broadcast(false)
	end
	OL:Print("OpenLoot is off for this raid.")
end

function Raid:SetMule(text)
	if not self:IsRunner() then
		OL:Print("Only the raid leader running OpenLoot can set the pack mule.")
		return
	end
	local token = text and text:match("^(%S+)") or nil
	local mule = nil
	if token then
		mule = OL:ShortName(token)
		if mule == "" then
			mule = token
		end
	end
	local raid = OL.db.activeRaid
	raid.mule = mule
	raid.muleSeen = mule and OL:GroupUnit(mule) and true or nil
	self:ApplyLootRole()
	self:Broadcast(true)
	if mule then
		OL:Print(mule .. " is the pack mule and will take the loot.")
	else
		OL:Print("Pack mule cleared. You will take the loot.")
	end
end

function Raid:OnRoster()
	if not self:IsRunner() then
		return
	end
	local raid = OL.db.activeRaid
	local mule = raid and raid.mule
	if not mule then
		return
	end
	if OL:GroupUnit(mule) then
		raid.muleSeen = true
		return
	end
	if not raid.muleSeen then
		return
	end
	raid.mule = nil
	raid.muleSeen = nil
	self:ApplyLootRole()
	self:Broadcast(true)
	OL:Print(OL:ShortName(mule) .. " left the raid. You will take the loot.")
end

function Raid:ConsiderPrompt()
	if not OL:IsLive() or not self:CanLead() then
		return
	end
	if self:IsOn() then
		return
	end
	if OL.db.declinedMap and OL.db.declinedMap == mapID() then
		return
	end
	if self.promptOpen then
		return
	end
	self.promptOpen = true
	OL.UI:Prompt("OpenLoot", "Do you want to run OpenLoot for this raid?", {
		{ text = "Yes", onClick = function()
			self.promptOpen = false
			self:Enable()
		end },
		{ text = "No", onClick = function()
			self.promptOpen = false
			OL.db.declinedMap = mapID()
		end },
	})
end

function Raid:OnZone()
	local inside = OL:IsLive()
	if self.wasInRaidInstance and not inside then
		self.promptOpen = false
		self.askedMap = nil
		self.restoredMap = nil
		self.reloadAsked = nil
		self.reloadPushed = nil
		if self:IsOn() then
			self:Disable()
		else
			self:RestorePass()
		end
		OL.db.declinedMap = nil
	end
	self.wasInRaidInstance = inside
end

function Raid:OnEnter(isReload)
	local map = mapID()
	self.wasInRaidInstance = true
	self:RestoreIfSaved(isReload, map)
	local shouldAsk = self.askedMap ~= map
	if isReload and not self.reloadAsked then
		shouldAsk = true
		self.reloadAsked = true
	end
	if shouldAsk then
		self.askedMap = map
		self:RequestState()
	end
	if OL.Session then
		OL.Session:CatchUp(shouldAsk)
	end
	self:ConsiderPrompt()
end

function Raid:RestoreIfSaved(isReload, map)
	local raid = OL.db.activeRaid
	if not raid or not raid.on then
		return
	end
	map = map or mapID()
	if raid.mapID and raid.mapID ~= map then
		OL.db.activeRaid = nil
		self.collecting = false
		self:SyncRollListen()
		self:SyncMasterListen()
		self:RestorePass()
		return
	end
	self:ApplyLootRole()
	if raid.isRunner and UnitIsGroupLeader("player") then
		local shouldPush = self.restoredMap ~= map
		if isReload and not self.reloadPushed then
			shouldPush = true
			self.reloadPushed = true
		end
		if shouldPush then
			self.restoredMap = map
			self:Broadcast(true)
		end
	end
end

function Raid:RequestState()
	if not IsInGroup() or self:IsRunner() or UnitIsGroupLeader("player") then
		return
	end
	OL.Comms:Send("stateq")
end

function Raid:OnGroupLeft()
	self.askedMap = nil
	self.restoredMap = nil
	self.reloadAsked = nil
	self.reloadPushed = nil
	self.promptOpen = false
	OL.Comms:Clear()
	OL.db.activeRaid = nil
	self.collecting = false
	self:SyncRollListen()
	self:SyncMasterListen()
	self:RestorePass()
	if OL.Session then
		OL.Session:Clear()
	end
end

function Raid:OnLootRoll(rollID)
	if not self:IsCollector() or not rollID then
		return
	end
	pcall(RollOnLoot, rollID, LOOT_ROLL_TYPE_NEED or 1)
end

function Raid:Dismiss(which, confirm, a, b)
	local function go()
		if confirm then
			pcall(confirm, a, b)
		end
		if StaticPopup_Hide then
			StaticPopup_Hide(which)
		end
	end
	go()
	if C_Timer and C_Timer.After then
		C_Timer.After(0, go)
	end
end

function Raid:SkipRollConfirm(rollID, rollType)
	if not self:IsCollector() or not rollID then
		return
	end
	self:Dismiss("CONFIRM_LOOT_ROLL", ConfirmLootRoll, rollID, rollType)
end

function Raid:SkipLootConfirm(slot)
	if not self:IsCollector() and not self:IsMasterLooter() then
		return
	end
	self:Dismiss("CONFIRM_LOOT_DISTRIBUTION", slot and ConfirmLootSlot or nil, slot)
end

function Raid:LootMethod()
	if C_PartyInfo and C_PartyInfo.GetLootMethod then
		local ok, method, partyID, raidID = pcall(C_PartyInfo.GetLootMethod)
		if ok then
			return method, partyID, raidID
		end
	end
	if GetLootMethod then
		local ok, method, partyID, raidID = pcall(GetLootMethod)
		if ok then
			return method, partyID, raidID
		end
	end
	return nil
end

function Raid:IsMasterMethod(method)
	if method == "master" or method == 2 then
		return true
	end
	return Enum and Enum.LootMethod and method == Enum.LootMethod.Masterlooter or false
end

function Raid:IsMasterLooter()
	local method, partyID, raidID = self:LootMethod()
	if not self:IsMasterMethod(method) then
		return false
	end
	local mine = OL:ShortName(OL:FullName("player"))
	if IsInRaid() and raidID and raidID > 0 then
		local name = GetRaidRosterInfo(raidID)
		return name and OL:ShortName(name) == mine or false
	end
	if partyID == 0 then
		return true
	end
	if partyID and partyID > 0 then
		local unit = "party" .. partyID
		return UnitExists(unit) and OL:ShortName(OL:FullName(unit)) == mine or false
	end
	return false
end

function Raid:LootTarget()
	local mule = self:MuleName()
	if mule then
		return OL:ShortName(mule)
	end
	local leader = self:LeaderName()
	return leader and OL:ShortName(leader) or nil
end

function Raid:CandidateName(slot, index)
	if not GetMasterLootCandidate then
		return nil
	end
	local ok, name = pcall(GetMasterLootCandidate, slot, index)
	if ok and type(name) == "string" and name ~= "" then
		return name
	end
	ok, name = pcall(GetMasterLootCandidate, index)
	if ok and type(name) == "string" and name ~= "" then
		return name
	end
	return nil
end

function Raid:CandidateIndex(slot, target)
	local short = OL:ShortName(target)
	if short == "" then
		return nil
	end
	for index = 1, 40 do
		local name = self:CandidateName(slot, index)
		if not name then
			return nil
		end
		if OL:ShortName(name) == short then
			return index
		end
	end
	return nil
end

function Raid:IsLootItem(slot)
	if GetLootSlotType then
		local ok, kind = pcall(GetLootSlotType, slot)
		if ok and kind ~= nil then
			if kind == 2 or kind == 3 or kind == LOOT_SLOT_MONEY or kind == LOOT_SLOT_CURRENCY then
				return false
			end
			if kind == 1 or kind == LOOT_SLOT_ITEM then
				return true
			end
		end
	end
	if LootSlotHasItem then
		local ok, has = pcall(LootSlotHasItem, slot)
		return ok and has or false
	end
	return false
end

function Raid:OnMasterLoot()
	if not self:IsOn() or not self:IsMasterLooter() or not GiveMasterLoot then
		return
	end
	local now = GetTime and GetTime() or 0
	if self.lastMaster and now - self.lastMaster < 0.5 then
		return
	end
	self.lastMaster = now
	local target = self:LootTarget()
	if not target then
		return
	end
	local count = 0
	if GetNumLootItems then
		local ok, num = pcall(GetNumLootItems)
		count = ok and tonumber(num) or 0
	end
	local given = 0
	local missed = false
	for slot = count, 1, -1 do
		if self:IsLootItem(slot) then
			local index = self:CandidateIndex(slot, target)
			if index and pcall(GiveMasterLoot, slot, index) then
				given = given + 1
				self:SkipLootConfirm(slot)
			else
				missed = true
			end
		end
	end
	local who = OL:ShortName(target)
	if given > 0 then
		OL:Print("Master looted " .. given .. " to " .. who .. ".")
	end
	if missed then
		OL:Print("Couldn't master loot every item to " .. who .. ".")
	end
end

function Raid:OnComm(sender, op, fields)
	if op == "stateq" then
		if self:IsRunner() and OL.Council:IsLocalCouncil() then
			self:Broadcast(true)
		elseif UnitIsGroupLeader("player") then
			OL.Comms:Send("state\0310\031" .. OL:FullName("player"))
		end
		return
	end
	local leader = self:LeaderName()
	if not leader or OL:ShortName(sender) ~= OL:ShortName(leader) then
		return
	end
	local on = fields[1] == "1"
	local wasOn = self:IsOn()
	local wasCollecting = self.collecting and true or false
	if on then
		if self:IsRunner() then
			return
		end
		local mule = fields[3]
		if mule == "" then
			mule = nil
		end
		OL.db.activeRaid = { on = true, mapID = mapID(), isRunner = false, mule = mule }
		self:ApplyLootRole()
		if self:IsCollector() then
			if not wasCollecting then
				OL:Print("You will automatically need on loot.")
			end
		elseif not wasOn or wasCollecting then
			OL:Print("Pass on Loot is on for this OpenLoot raid.")
		end
	else
		OL.db.activeRaid = nil
		self.collecting = false
		self:SyncRollListen()
		self:SyncMasterListen()
		self:RestorePass()
		if wasOn then
			OL:Print("OpenLoot is off. Pass on Loot was restored.")
		end
	end
end
