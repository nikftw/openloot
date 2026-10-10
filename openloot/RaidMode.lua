local OL = OpenLoot

OL.RaidMode = {}
local Raid = OL.RaidMode

-- Loot while OpenLoot is on. The collector is the pack mule, or the raid
-- leader when no mule is set. Only the raid leader can be master looter.
--
--   Group loot   the collector has Pass on Loot off and needs every roll;
--                everyone else (the leader too, when a mule is set) passes.
--   Master loot  the leader loots the boss and every item goes straight to
--                the collector, with no prompt and no chat message.
--
-- Nothing here sends addon messages during the raid. The leader broadcasts
-- the state once when OpenLoot is turned on or the mule changes. Everyone
-- else with the addon asks the leader once after logging in, reloading or
-- joining the group, inside the instance or not, and the answer sets their
-- Pass on Loot. The state lasts until they leave the group.

local function mapID()
	return select(8, GetInstanceInfo())
end

function Raid:Init()
	self.wasInRaidInstance = false
	self.needAsk = true
end

-- Ask once a raid group and its leader are known; a party never asks. needAsk
-- is set at login or reload, and again after leaving a group, so the next
-- raid gets asked too (a party converted to a raid asks on that roster update).
function Raid:MaybeAsk()
	if not self.needAsk or not IsInRaid() or UnitIsGroupLeader("player") or not self:LeaderName() then
		return
	end
	self.needAsk = false
	OL.Session:AskLeader()
end

function Raid:GetPass()
	return GetOptOutOfLoot() and true or false
end

function Raid:SetPass(enabled)
	enabled = enabled and true or false
	if self:GetPass() ~= enabled then
		SetOptOutOfLoot(enabled)
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
	return mule ~= nil and OL:ShortName(mule) == OL:Me()
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

-- Rolls only matter to the collector, master loot only to the leader, and
-- both only inside the raid.
function Raid:SyncListen()
	local live = OL:IsLive()
	local collect = live and self:IsCollector() and true or false
	local runner = live and self:IsRunner() and true or false
	OL:Listen("START_LOOT_ROLL", collect)
	OL:Listen("CONFIRM_LOOT_ROLL", collect)
	OL:Listen("LOOT_READY", runner)
	OL:Listen("CONFIRM_LOOT_DISTRIBUTION", runner)
end

function Raid:ApplyLootRole()
	local collect = self:IsCollector()
	self.collecting = collect
	self:SyncListen()
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
	return OL:Roster().leader
end

-- Messages that only the leader may send check the sender here.
function Raid:IsLeader(sender)
	local leader = self:LeaderName()
	return leader ~= nil and OL:ShortName(sender) == OL:ShortName(leader)
end

function Raid:CanLead()
	return UnitIsGroupLeader("player") and OL.Council:IsLocalCouncil()
end

-- T  the leader's loot state: "1" and the mule (empty for none). target
-- whispers it to one raider who asked; nil tells the whole raid.
function Raid:Broadcast(target)
	local SEP = OL.Comms.SEP
	OL.Comms:Send("T" .. SEP .. "1" .. SEP .. (self:MuleName() or "") .. SEP .. tostring(OL.db.activeRaid.mapID or ""), target)
end

function Raid:Enable()
	OL.db.declinedMap = nil
	OL.db.activeRaid = { on = true, mapID = mapID(), isRunner = true }
	self:ApplyLootRole()
	self:Broadcast()
	OL:Print("OpenLoot is on. You will automatically need on loot.")
end

function Raid:Off()
	OL.db.activeRaid = nil
	self.collecting = false
	self:SyncListen()
	self:RestorePass()
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
	self:Broadcast()
	if mule then
		OL:Print(mule .. " is the pack mule and will take the loot.")
	else
		OL:Print("Pack mule cleared. You will take the loot.")
	end
end

function Raid:OnRoster()
	self:MaybeAsk()
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
	self:Broadcast()
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

-- Zoning never turns OpenLoot off; leaving the group does. Leaving the
-- instance alive only lets the leader be asked again next time they enter.
function Raid:OnZone()
	local inside = OL:IsLive()
	if self.wasInRaidInstance and not inside and not UnitIsDeadOrGhost("player") then
		self.promptOpen = false
		OL.db.declinedMap = nil
	end
	self.wasInRaidInstance = inside
end

function Raid:OnEnter()
	self.wasInRaidInstance = true
	self:RestoreIfSaved(mapID())
	OL.Session:CatchUp()
	self:MaybeAsk()
	self:ConsiderPrompt()
end

-- Saved state from a different raid is stale: drop it and ask again.
function Raid:RestoreIfSaved(map)
	local raid = OL.db.activeRaid
	if not raid or not raid.on then
		return
	end
	if raid.mapID and raid.mapID ~= map then
		self:Off()
		self.needAsk = true
		return
	end
	self:ApplyLootRole()
end

function Raid:OnGroupLeft()
	self.needAsk = true
	self.promptOpen = false
	OL.Comms:Reset()
	self:Off()
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
		StaticPopup_Hide(which)
	end
	go()
	C_Timer.After(0, go)
end

function Raid:SkipRollConfirm(rollID, rollType)
	if not self:IsCollector() or not rollID then
		return
	end
	self:Dismiss("CONFIRM_LOOT_ROLL", ConfirmLootRoll, rollID, rollType)
end

function Raid:SkipLootConfirm(slot)
	if not self:IsRunner() then
		return
	end
	self:Dismiss("CONFIRM_LOOT_DISTRIBUTION", slot and ConfirmLootSlot or nil, slot)
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

-- The leader opened a boss's loot under master loot: hand every item to the
-- collector at once, without a prompt or a chat line.
function Raid:OnMasterLoot()
	if not self:IsRunner() or C_PartyInfo.GetLootMethod() ~= Enum.LootMethod.Masterlooter then
		return
	end
	local now = GetTime()
	if self.lastMaster and now - self.lastMaster < 0.5 then
		return
	end
	self.lastMaster = now
	local target = self:LootTarget()
	if not target then
		return
	end
	for slot = GetNumLootItems(), 1, -1 do
		if self:IsLootItem(slot) then
			local index = self:CandidateIndex(slot, target)
			if index and pcall(GiveMasterLoot, slot, index) then
				self:SkipLootConfirm(slot)
			end
		end
	end
end

function Raid:OnComm(sender, op, fields)
	if not self:IsLeader(sender) or self:IsRunner() then
		return
	end
	local wasOn = self:IsOn()
	local wasCollecting = self.collecting and true or false
	local mule = fields[2]
	if mule == "" then
		mule = nil
	end
	OL.db.activeRaid = { on = true, mapID = tonumber(fields[3]) or mapID(), isRunner = false, mule = mule }
	self:ApplyLootRole()
	if self:IsCollector() then
		if not wasCollecting then
			OL:Print("You will automatically need on loot.")
		end
	elseif not wasOn or wasCollecting then
		OL:Print("Pass on Loot is on for this OpenLoot raid.")
	end
end

OL.Comms:Route(Raid, "T")
