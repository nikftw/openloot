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

function Raid:ArmRunner()
	self:RememberPass()
	self:SetPass(false)
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

function Raid:IsOn()
	local raid = OL.db.activeRaid
	return raid and raid.on or false
end

function Raid:SyncRollListen()
	OL:Listen("START_LOOT_ROLL", self:IsRunner() and true or false)
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
	if on then
		OL.Comms:Send("state\0311\031" .. leader)
	else
		OL.Comms:Send("state\0310\031" .. leader)
	end
end

function Raid:Enable()
	OL.db.declinedMap = nil
	OL.db.activeRaid = { on = true, mapID = mapID(), isRunner = true }
	self:SyncRollListen()
	self:ArmRunner()
	self:Broadcast(true)
	OL.Versions:Query(true)
	OL:Print("OpenLoot is on. You will automatically need on loot.")
end

function Raid:Disable()
	local wasRunner = self:IsRunner()
	OL.db.activeRaid = nil
	self:SyncRollListen()
	self:RestorePass()
	if wasRunner then
		self:Broadcast(false)
	end
	OL:Print("OpenLoot is off for this raid.")
end

function Raid:EnableFromSlash()
	if not OL:IsLive() then
		OL:Print("You need to be in a raid.")
		return
	end
	if not self:CanLead() then
		OL:Print("Only a council raid leader can turn OpenLoot on.")
		return
	end
	self:Enable()
end

function Raid:DisableFromSlash()
	if not UnitIsGroupLeader("player") then
		OL:Print("Only the raid leader can turn OpenLoot off.")
		return
	end
	self:Disable()
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
		self:SyncRollListen()
		self:RestorePass()
		return
	end
	if raid.isRunner and UnitIsGroupLeader("player") then
		self:ArmRunner()
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
	self:SyncRollListen()
	self:RestorePass()
	if OL.Session then
		OL.Session:Clear()
	end
end

function Raid:OnLootRoll(rollID)
	if not self:IsRunner() or not rollID then
		return
	end
	pcall(function()
		local _, _, _, _, _, canNeed = GetLootRollItemInfo(rollID)
		local rollType = canNeed and 1 or 2
		RollOnLoot(rollID, rollType)
		if ConfirmLootRoll then
			C_Timer.After(0, function()
				pcall(ConfirmLootRoll, rollID, rollType)
			end)
		end
	end)
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
	if on then
		if self:IsRunner() then
			return
		end
		OL.db.activeRaid = { on = true, mapID = mapID(), isRunner = false }
		self:SyncRollListen()
		self:ApplyRaiderPass()
		if not wasOn then
			OL:Print("Pass on Loot is on for this OpenLoot raid.")
		end
	else
		OL.db.activeRaid = nil
		self:SyncRollListen()
		self:RestorePass()
		if wasOn then
			OL:Print("OpenLoot is off. Pass on Loot was restored.")
		end
	end
end
