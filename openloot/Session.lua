local OL = OpenLoot

OL.Session = {}
local Session = OL.Session

local SEP = "\31"

local function field(value)
	if value == nil then
		return ""
	end
	return tostring(value)
end

local function textOrNil(value)
	if value == nil or value == "" then
		return nil
	end
	return value
end

local function numberOrNil(value)
	if value == nil or value == "" then
		return nil
	end
	return tonumber(value)
end

local function textureOf(value)
	if value and value:match("^%d+$") then
		return tonumber(value)
	end
	return textOrNil(value)
end

local function join(parts)
	return table.concat(parts, SEP)
end

local function tail(award)
	return {
		award.class or "",
		award.votes ~= nil and tostring(award.votes) or "",
		award.instance or "",
		award.mapID ~= nil and award.mapID ~= "" and tostring(award.mapID) or "",
		award.gear1 or "",
		award.gear2 or "",
		award.note or "",
	}
end

local function append(parts, extra)
	for _, value in ipairs(extra) do
		parts[#parts + 1] = value
	end
	return parts
end

local function me()
	return OL:ShortName(OL:FullName("player"))
end

local function repaint()
	OL.RaiderFrame:Refresh()
	OL.CouncilFrame:Refresh()
end

local function itemLine(id, index, item)
	return join({
		"item", id, index, field(item.ilvl), item.equipLoc or "", field(item.texture),
		field(item.classID), field(item.subClassID), item.link or "",
		item.holder or "", field(item.bag), field(item.slot), item.guid or "",
	})
end

function Session:Init()
	self.active = nil
	self:Restore()
end

function Session:IsActive()
	return self.active ~= nil
end

function Session:IsHolder()
	return self.active and OL:ShortName(self.active.owner or "") == me()
end

function Session:Roster()
	local roster = {}
	if not IsInGroup() then
		local _, classFile = UnitClass("player")
		roster[1] = { name = OL:FullName("player"), classFile = classFile }
		return roster
	end
	for index = 1, GetNumGroupMembers() do
		local name, classFile
		if IsInRaid() then
			name, _, _, _, _, classFile = GetRaidRosterInfo(index)
		else
			local unit = index == 1 and "player" or ("party" .. (index - 1))
			if UnitExists(unit) then
				_, classFile = UnitClass(unit)
				name = OL:FullName(unit)
			end
		end
		if name then
			roster[#roster + 1] = { name = name, classFile = classFile }
		end
	end
	return roster
end

function Session:RememberEnd(id)
	if not id or id == "" then
		return
	end
	self.ended = self.ended or {}
	self.ended[id] = true
end

function Session:HasEnded(id)
	return self.ended and self.ended[id] and true or false
end

function Session:Bind()
	if self.active then
		OL.db.session = self.active
	end
end

function Session:OpenSessionWindows()
	OL.db.windows = OL.db.windows or {}
	OL.db.windows.raider = true
	OL.db.windows.council = true
end

function Session:WindowOpen(name)
	local windows = OL.db.windows
	if not windows or windows[name] == nil then
		return true
	end
	return windows[name] and true or false
end

function Session:ShowUI()
	if self.active and self:HasEnded(self.active.id) then
		self:Clear()
		return
	end
	if self:WindowOpen("raider") then
		OL.RaiderFrame:Show()
	elseif OL.RaiderFrame and OL.RaiderFrame.frame then
		OL.RaiderFrame:Hide()
	end
	if OL.Council:IsLocalCouncil() and self:WindowOpen("council") then
		OL.CouncilFrame:Show()
	elseif OL.CouncilFrame and OL.CouncilFrame.frame then
		OL.CouncilFrame:Hide()
	end
	OL.RaiderFrame:Refresh()
	OL.CouncilFrame:Refresh()
end

function Session:End()
	if not self:IsActive() then
		return
	end
	local id = self.active.id
	OL.Comms:Send(join({ "end", id }))
	self:Clear()
	OL:Print("Loot session closed.")
end

function Session:Clear()
	if self.active and self.active.id then
		self:RememberEnd(self.active.id)
	end
	self.active = nil
	self.announced = nil
	self.announceAt = nil
	if OL.db then
		OL.db.session = nil
	end
	if OL.RaiderFrame then
		OL.RaiderFrame:Hide()
	end
	if OL.CouncilFrame then
		OL.CouncilFrame:Hide()
	end
end

function Session:Start(items)
	local id = OL:ShortName(OL:FullName("player")) .. "-" .. tostring(time())
	for _, item in ipairs(items) do
		item.votes = item.votes or {}
		item.ballots = item.ballots or {}
	end
	self.active = { id = id, items = items, owner = OL:FullName("player") }
	self:Bind()
	self:OpenSessionWindows()
	OL.History:Ensure(id, time())
	self:SendBody(false)
	self:ShowUI()
	local others = IsInGroup() and math.max(0, GetNumGroupMembers() - 1) or 0
	if others == 0 then
		OL:Print(string.format("Session started with %d items on this character. Join a raid before starting if someone else should see it.", #items))
	else
		OL:Print(string.format("Session started with %d items. Sent to %d other %s.", #items, others, others == 1 and "player" or "players"))
	end
end

function Session:ScanExpect()
	local expect = {}
	local mine = me()
	if IsInRaid() then
		for index = 1, GetNumGroupMembers() do
			local name, _, _, _, _, _, _, online = GetRaidRosterInfo(index)
			local short = name and OL:ShortName(name) or ""
			if short ~= "" and short ~= mine and online ~= false then
				expect[short] = true
			end
		end
		return expect
	end
	for _, member in ipairs(self:Roster()) do
		local short = OL:ShortName(member.name)
		if short ~= "" and short ~= mine then
			expect[short] = true
		end
	end
	return expect
end

function Session:Gather()
	if self.pending then
		return
	end
	OL.Council:Rebuild()
	local pending = {
		items = {},
		seen = {},
		got = {},
		want = {},
		done = {},
		expect = self:ScanExpect(),
	}
	self.pending = pending
	for _, item in ipairs(OL.Items:ScanBags()) do
		item.holder = me()
		pending.items[#pending.items + 1] = item
	end
	local waiting = false
	for _ in pairs(pending.expect) do
		waiting = true
		break
	end
	if not waiting then
		self:FinishGather()
		return
	end
	OL.Comms:Send("scanq")
	if not self.pending or self.pending.finished then
		return
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(1, function()
			self:FinishGather()
		end)
	else
		self:FinishGather()
	end
end

function Session:FinishGather()
	local pending = self.pending
	if not pending or pending.finished then
		return
	end
	pending.finished = true
	self.pending = nil
	if #pending.items == 0 then
		OL:Print("No unbound or tradeable blue-or-better items in the raid.")
		return
	end
	self:Start(pending.items)
end

function Session:NoteScan(sender, item)
	local pending = self.pending
	if not pending or pending.finished or not item or not item.link or item.link == "" then
		return
	end
	local who = OL:ShortName(sender)
	if who == "" or who == me() or not pending.expect[who] then
		return
	end
	local key = who .. ":" .. tostring(item.bag) .. ":" .. tostring(item.slot) .. ":" .. (item.guid or item.link)
	if pending.seen[key] then
		return
	end
	pending.seen[key] = true
	item.holder = who
	item.votes = {}
	item.ballots = {}
	pending.items[#pending.items + 1] = item
	pending.got[who] = (pending.got[who] or 0) + 1
	self:CheckScan(who)
end

function Session:CheckScan(who)
	local pending = self.pending
	if not pending or pending.finished or not who then
		return
	end
	local want = pending.want[who]
	if not want or (pending.got[who] or 0) < want then
		return
	end
	pending.done[who] = true
	for name in pairs(pending.expect) do
		if not pending.done[name] then
			return
		end
	end
	self:FinishGather()
end

function Session:OnScanRequest(sender)
	if OL.RaidMode:IsRunner() then
		return
	end
	local leader = OL.RaidMode:LeaderName()
	if not leader or OL:ShortName(sender) ~= OL:ShortName(leader) then
		return
	end
	local items = OL.Items:ScanBags()
	for _, item in ipairs(items) do
		OL.Comms:Send(join({
			"scan",
			field(item.ilvl),
			item.equipLoc or "",
			field(item.texture),
			field(item.classID),
			field(item.subClassID),
			item.link or "",
			field(item.bag),
			field(item.slot),
			item.guid or "",
		}))
	end
	OL.Comms:Send(join({ "scandone", #items }))
end

function Session:OnScan(sender, fields)
	self:NoteScan(sender, {
		ilvl = numberOrNil(fields[1]) or 0,
		equipLoc = fields[2] or "",
		texture = textureOf(fields[3]),
		classID = numberOrNil(fields[4]),
		subClassID = numberOrNil(fields[5]),
		link = fields[6] or "",
		bag = numberOrNil(fields[7]),
		slot = numberOrNil(fields[8]),
		guid = textOrNil(fields[9]),
	})
end

function Session:OnScanDone(sender, fields)
	local pending = self.pending
	if not pending or pending.finished then
		return
	end
	local who = OL:ShortName(sender)
	if who == "" or not pending.expect[who] then
		return
	end
	pending.want[who] = tonumber(fields[1]) or 0
	self:CheckScan(who)
end

function Session:Run()
	if not OL:IsLive() then
		OL:Print("OpenLoot only runs inside a raid.")
		return
	end
	if not OL.RaidMode:IsRunner() then
		OL:Print("Only the raid leader running OpenLoot can start a session.")
		return
	end
	if self.pending then
		return
	end
	if self:IsActive() then
		OL.UI:Prompt("OpenLoot", "Replace the current loot session?", {
			{ text = "Replace", onClick = function()
				self:Gather()
			end },
			{ text = "Cancel" },
		})
		return
	end
	self:Gather()
end

function Session:SetResponse(index, responseId, note)
	local item = self.active and self.active.items[index]
	if not item or item.awardedTo then
		return
	end
	note = OL.Items:CleanNote(note ~= nil and note or item.myNote or "")
	responseId = responseId or item.myResponse
	if not responseId then
		item.myNote = note
		repaint()
		return
	end
	local slotIlvl, diff, first, second = OL.Items:Compare(item.link, item.ilvl, item.equipLoc)
	item.myResponse = responseId
	item.myNote = note
	local name = me()
	item.votes[name] = {
		response = responseId,
		note = note,
		slotIlvl = slotIlvl,
		diff = diff,
		s1 = first,
		s2 = second,
	}
	OL.Comms:Send(join({
		"vote", self.active.id, index, responseId, field(slotIlvl), field(diff), note, field(first), field(second),
	}))
	repaint()
end

function Session:ClearResponse(index)
	local item = self.active and self.active.items[index]
	if not item or item.awardedTo or not item.myResponse then
		return
	end
	item.myResponse = nil
	local name = me()
	item.votes[name] = nil
	OL.Comms:Send(join({
		"vote", self.active.id, index, "", "", "", item.myNote or "", "", "",
	}))
	repaint()
end

function Session:ApplyVote(id, index, sender, response, slotIlvl, diff, note, first, second)
	if not index or not self.active or self.active.id ~= id then
		return
	end
	local item = self.active.items[index]
	if not item then
		return
	end
	local name = OL:ShortName(sender)
	if not response or response == "" then
		item.votes[name] = nil
		if name == me() then
			item.myResponse = nil
		end
		repaint()
		return
	end
	item.votes[name] = {
		response = response,
		note = note,
		slotIlvl = slotIlvl,
		diff = diff,
		s1 = first,
		s2 = second,
	}
	if name == me() then
		item.myResponse = response
		item.myNote = note
	end
	repaint()
end

function Session:CastBallot(index, candidate)
	local item = self.active and self.active.items[index]
	if not item or item.awardedTo or not (OL.Council:IsLocalCouncil()) then
		return
	end
	item.ballots = item.ballots or {}
	local mine = me()
	local choice = OL:ShortName(candidate)
	if item.ballots[mine] == choice then
		item.ballots[mine] = nil
		choice = ""
	else
		item.ballots[mine] = choice
	end
	OL.Comms:Send(join({ "ballot", self.active.id, index, mine, choice }))
	OL.CouncilFrame:Refresh()
end

function Session:ApplyBallot(id, index, voter, choice)
	if not index or not self.active or self.active.id ~= id then
		return
	end
	local item = self.active.items[index]
	if not item then
		return
	end
	item.ballots = item.ballots or {}
	local name = OL:ShortName(voter)
	if not choice or choice == "" then
		item.ballots[name] = nil
	else
		item.ballots[name] = OL:ShortName(choice)
	end
	OL.CouncilFrame:Refresh()
end

function Session:Award(index, winner)
	local item = self.active and self.active.items[index]
	if not item or item.awardedTo or not (OL.Council:IsLocalCouncil()) then
		return
	end
	local shortWinner = OL:ShortName(winner)
	item.awardedTo = shortWinner
	local winnerVote = item.votes[shortWinner]
	local award = OL.History:Capture(self.active.id, index, item, shortWinner, winnerVote and winnerVote.response or "", time())
	OL.History:AddAward(self.active.id, award)
	OL.Trade:Add(item, shortWinner, self.active.id, index)
	OL.Comms:Send(join(append({
		"award", self.active.id, index, shortWinner, item.link, award.response, award.time,
	}, tail(award))))
	local channel = IsInRaid() and "RAID" or "PARTY"
	pcall(SendChatMessage, OL:ShortName(shortWinner) .. " was awarded " .. item.link, channel)
	repaint()
	OL.CouncilFrame:AdvanceFrom(index)
end

function Session:Close(index, reason)
	local item = self.active and self.active.items[index]
	if not item or item.awardedTo or item.closed or not (OL.Council:IsLocalCouncil()) then
		return
	end
	if reason ~= "skip" and reason ~= "disenchant" then
		return
	end
	item.closed = reason
	local label = reason == "disenchant" and "Disenchant" or "Skip"
	local award = OL.History:Capture(self.active.id, index, item, label, reason, time())
	OL.History:AddAward(self.active.id, award)
	OL.Comms:Send(join(append({ "close", self.active.id, index, reason, award.time }, tail(award))))
	repaint()
	OL.CouncilFrame:AdvanceFrom(index)
end

function Session:StoreItem(index, incoming)
	local prev = self.active.items[index]
	if prev and prev.link == incoming.link then
		incoming.votes = prev.votes or {}
		incoming.ballots = prev.ballots or {}
		incoming.myResponse = prev.myResponse
		incoming.myNote = prev.myNote
		incoming.awardedTo = prev.awardedTo
		incoming.closed = prev.closed
		if incoming.bag == nil then
			incoming.bag = prev.bag
		end
		if incoming.slot == nil then
			incoming.slot = prev.slot
		end
		if not incoming.guid then
			incoming.guid = prev.guid
		end
		if not incoming.holder then
			incoming.holder = prev.holder
		end
	else
		incoming.votes = incoming.votes or {}
		incoming.ballots = incoming.ballots or {}
	end
	self.active.items[index] = incoming
end

function Session:SendBody(withVotes)
	local session = self.active
	if not session then
		return
	end
	OL.Comms:Send(join({ "begin", session.id }))
	for index, item in ipairs(session.items) do
		OL.Comms:Send(itemLine(session.id, index, item))
		if withVotes then
			for voter, vote in pairs(item.votes or {}) do
				OL.Comms:Send(join({
					"keep", session.id, index, voter,
					vote.response or "", field(vote.slotIlvl), field(vote.diff), vote.note or "",
					field(vote.s1), field(vote.s2),
				}))
			end
			for voter, choice in pairs(item.ballots or {}) do
				OL.Comms:Send(join({ "kept", session.id, index, voter, choice or "" }))
			end
			if item.awardedTo or item.closed then
				local saved = OL.History:Find(session.id, index)
				local response = saved and saved.response or ""
				if response == "" and item.awardedTo and item.votes then
					local vote = item.votes[OL:ShortName(item.awardedTo)]
					response = vote and vote.response or ""
				end
				local when = saved and saved.time or ""
				OL.Comms:Send(join(append({
					"mark", session.id, index, item.awardedTo or "", item.closed or "", response, when,
				}, saved and tail(saved) or { "", "", "", "", "", "", "" })))
			end
		end
	end
	OL.Comms:Send(join({ "vend", session.id }))
end

function Session:Broadcast()
	self:SendBody(true)
end

function Session:Announce()
	if not UnitIsGroupLeader("player") or not IsInGroup() then
		return
	end
	if not self:IsActive() then
		self:Restore()
	end
	local token = self:IsActive() and self.active.id or ""
	local now = GetTime()
	if self.announceAt and self.announced == token and (now - self.announceAt) < 1 then
		return
	end
	self.announced = token
	self.announceAt = now
	if token == "" then
		OL.Comms:Send("sync")
		return
	end
	self:Broadcast()
end

function Session:Restore()
	if self:IsActive() then
		return false
	end
	local saved = OL.db and OL.db.session
	if type(saved) ~= "table" or not saved.id or type(saved.items) ~= "table" then
		return false
	end
	if self:HasEnded(saved.id) then
		OL.db.session = nil
		return false
	end
	self.active = saved
	for _, item in ipairs(saved.items) do
		item.votes = item.votes or {}
		item.ballots = item.ballots or {}
	end
	return true
end

function Session:RestoreWindows()
	local windows = OL.db.windows
	if not windows then
		return
	end
	if windows.history and OL.History then
		OL.History:EnsureFrame()
		OL.History.frame:Show()
		OL.History:Refresh()
	end
	if windows.versions and OL.Versions then
		OL.Versions:Ensure()
		OL.Versions.frame:Show()
		OL.Versions:Query(false)
	end
	if windows.trade and OL.Trade and OL.Trade.list and #OL.Trade.list > 0 then
		OL.Trade:Show()
	end
end

function Session:CatchUp(ask)
	local restored = false
	if not self:IsActive() then
		restored = self:Restore()
	end
	if self:IsActive() then
		self:ShowUI()
	end
	self:RestoreWindows()
	if not IsInGroup() then
		return
	end
	if not ask and not restored then
		return
	end
	if UnitIsGroupLeader("player") then
		self:Announce()
	else
		OL.Comms:Send("syncq")
	end
end

function Session:OnSyncRequest()
	if not UnitIsGroupLeader("player") then
		return
	end
	if not self:IsActive() then
		self:Restore()
	end
	self:Announce()
end

function Session:TakeSession(id, sender)
	if not self:IsActive() then
		self:Restore()
	end
	if self.active and self.active.id == id then
		return false
	end
	self.active = { id = id, items = {}, owner = sender }
	self:OpenSessionWindows()
	return true
end

function Session:ApplyMark(id, index, awardedTo, closed, response, when, class, votes, instance, mapID, gear1, gear2, note)
	if not index or not self.active or self.active.id ~= id then
		return
	end
	local item = self.active.items[index]
	if not item then
		return
	end
	local changed = false
	if awardedTo and awardedTo ~= "" and not item.awardedTo then
		item.awardedTo = awardedTo
		changed = true
		OL.History:AddAward(id, OL.History:FromWire(id, index, awardedTo, item.link, response, when, class, votes, instance, mapID, gear1, gear2, note))
	end
	if not item.awardedTo and closed and (closed == "skip" or closed == "disenchant") and not item.closed then
		item.closed = closed
		changed = true
		local label = closed == "disenchant" and "Disenchant" or "Skip"
		OL.History:AddAward(id, OL.History:FromWire(id, index, label, item.link, closed, when, class, votes, instance, mapID, gear1, gear2, note))
	end
	if changed then
		repaint()
	end
end

local function fromLeader(sender)
	local leader = OL.RaidMode:LeaderName()
	return leader and OL:ShortName(sender) == OL:ShortName(leader)
end

local function canEnd(sender)
	if fromLeader(sender) then
		return true
	end
	local owner = Session.active and Session.active.owner
	return owner and OL:ShortName(sender) == OL:ShortName(owner) or false
end

function Session:OnComm(sender, op, fields)
	if op == "sync" then
		if fromLeader(sender) and (not fields[1] or fields[1] == "") then
			if self:IsActive() then
				self:Clear()
				OL:Print("Loot session closed.")
			elseif OL.db then
				OL.db.session = nil
			end
		end
		return
	end
	if op == "keep" or op == "kept" or op == "mark" then
		if not fromLeader(sender) then
			return
		end
	end
	if op == "keep" then
		self:ApplyVote(fields[1], tonumber(fields[2]), fields[3], textOrNil(fields[4]), numberOrNil(fields[5]), numberOrNil(fields[6]), textOrNil(fields[7]), textOrNil(fields[8]), textOrNil(fields[9]))
		return
	end
	if op == "kept" then
		self:ApplyBallot(fields[1], tonumber(fields[2]), fields[3], textOrNil(fields[4]))
		return
	end
	if op == "mark" then
		self:ApplyMark(fields[1], tonumber(fields[2]), textOrNil(fields[3]), textOrNil(fields[4]), textOrNil(fields[5]), numberOrNil(fields[6]), textOrNil(fields[7]), numberOrNil(fields[8]), textOrNil(fields[9]), numberOrNil(fields[10]), textOrNil(fields[11]), textOrNil(fields[12]), textOrNil(fields[13]))
		return
	end
	if op == "scanq" then
		self:OnScanRequest(sender)
		return
	end
	if op == "scan" then
		self:OnScan(sender, fields)
		return
	end
	if op == "scandone" then
		self:OnScanDone(sender, fields)
		return
	end
	if not fields[1] then
		return
	end
	if (op == "begin" or op == "item" or op == "vend") and self:HasEnded(fields[1]) then
		return
	end
	local leader = fromLeader(sender)
	if (op == "begin" or op == "item" or op == "vend") and not leader then
		return
	end
	if op == "begin" then
		if self:TakeSession(fields[1], sender) then
			OL.History:Ensure(fields[1], time())
			OL.Council:Rebuild()
		end
		self:Bind()
		self:ShowUI()
		return
	end
	if op == "item" then
		self:TakeSession(fields[1], sender)
		local index = tonumber(fields[2])
		if not index then
			return
		end
		self:StoreItem(index, {
			link = fields[8],
			ilvl = numberOrNil(fields[3]) or 0,
			equipLoc = fields[4] or "",
			texture = textureOf(fields[5]),
			classID = numberOrNil(fields[6]),
			subClassID = numberOrNil(fields[7]),
			holder = textOrNil(fields[9]),
			bag = numberOrNil(fields[10]),
			slot = numberOrNil(fields[11]),
			guid = textOrNil(fields[12]),
		})
		self:Bind()
		self:ShowUI()
		return
	end
	if op == "vend" then
		self:ShowUI()
		return
	end
	if op == "ballot" then
		self:ApplyBallot(fields[1], tonumber(fields[2]), fields[3], textOrNil(fields[4]))
		return
	end
	if op == "vote" then
		self:ApplyVote(fields[1], tonumber(fields[2]), sender, textOrNil(fields[3]), numberOrNil(fields[4]), numberOrNil(fields[5]), textOrNil(fields[6]), textOrNil(fields[7]), textOrNil(fields[8]))
		return
	end
	if op == "end" then
		if canEnd(sender) then
			local id = fields[1]
			local open = self.active and self.active.id == id
			self:RememberEnd(id)
			if open then
				self:Clear()
				OL:Print("Loot session closed.")
			end
		end
		return
	end
	if op == "close" then
		local index = tonumber(fields[2])
		local reason = fields[3]
		if self.active and self.active.id == fields[1] and index and (reason == "skip" or reason == "disenchant") then
			local item = self.active.items[index]
			if item and not item.awardedTo and not item.closed then
				item.closed = reason
				local label = reason == "disenchant" and "Disenchant" or "Skip"
				OL.History:AddAward(fields[1], OL.History:FromWire(
					fields[1], index, label, item.link, reason,
					numberOrNil(fields[4]), textOrNil(fields[5]), numberOrNil(fields[6]),
					textOrNil(fields[7]), numberOrNil(fields[8]), textOrNil(fields[9]),
					textOrNil(fields[10]), textOrNil(fields[11])
				))
				repaint()
				OL.CouncilFrame:AdvanceFrom(index)
			end
		end
		return
	end
	if op == "award" then
		local index = tonumber(fields[2])
		if self.active and self.active.id == fields[1] and index then
			local item = self.active.items[index]
			if item and not item.awardedTo then
				item.awardedTo = fields[3]
				OL.Trade:Add(item, fields[3], fields[1], index)
				repaint()
				OL.CouncilFrame:AdvanceFrom(index)
			end
		end
		OL.History:AddAward(fields[1], OL.History:FromWire(
			fields[1], index, fields[3], fields[4], fields[5] or "",
			tonumber(fields[6]) or time(), textOrNil(fields[7]), numberOrNil(fields[8]),
			textOrNil(fields[9]), numberOrNil(fields[10]), textOrNil(fields[11]),
			textOrNil(fields[12]), textOrNil(fields[13])
		))
	end
end
