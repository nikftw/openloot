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

local function me()
	return OL:ShortName(OL:FullName("player"))
end

local function repaint()
	OL.RaiderFrame:Refresh()
	OL.CouncilFrame:Refresh()
end

local function itemLine(id, index, item, test)
	return join({
		"item", id, index, field(item.ilvl), item.equipLoc or "", field(item.texture),
		field(item.classID), field(item.subClassID), item.link or "", test or "",
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
	if OL.devRoster then
		return OL.devRoster
	end
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
	local test = ""
	OL.Comms:Send(join({ "begin", id, #items, test }))
	for index, item in ipairs(items) do
		OL.Comms:Send(itemLine(id, index, item, test))
	end
	OL.Comms:Send(join({ "vend", id, test }))
	self:ShowUI()
	local others = IsInGroup() and math.max(0, GetNumGroupMembers() - 1) or 0
	if others == 0 then
		OL:Print(string.format("Session started with %d items on this character. Join a raid before starting if someone else should see it.", #items))
	else
		OL:Print(string.format("Session started with %d items. Sent to %d other %s.", #items, others, others == 1 and "player" or "players"))
	end
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
	OL.Council:Rebuild()
	local items = OL.Items:ScanBags()
	if #items == 0 then
		OL:Print("No unbound or tradeable blue-or-better items in your bags.")
		return
	end
	if self:IsActive() then
		OL.UI:Prompt("OpenLoot", "Replace the current loot session?", {
			{ text = "Replace", onClick = function()
				self:Start(items)
			end },
			{ text = "Cancel" },
		})
		return
	end
	self:Start(items)
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
	if not item or item.awardedTo or not (OL.Council:IsLocalCouncil() or OL.devMode) then
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
	if not item or item.awardedTo or not (OL.Council:IsLocalCouncil() or OL.devMode) then
		return
	end
	local shortWinner = OL:ShortName(winner)
	item.awardedTo = shortWinner
	local winnerVote = item.votes[shortWinner]
	local award = {
		index = index,
		winner = shortWinner,
		link = item.link,
		response = winnerVote and winnerVote.response or "",
		time = time(),
	}
	OL.History:AddAward(self.active.id, award)
	OL.Trade:Add(item, shortWinner, self.active.id, index)
	OL.Comms:Send(join({ "award", self.active.id, index, shortWinner, item.link, award.response, award.time }))
	local channel = IsInRaid() and "RAID" or "PARTY"
	pcall(SendChatMessage, OL:ShortName(shortWinner) .. " was awarded " .. item.link, channel)
	repaint()
	OL.CouncilFrame:AdvanceFrom(index)
end

function Session:Close(index, reason)
	local item = self.active and self.active.items[index]
	if not item or item.awardedTo or item.closed or not (OL.Council:IsLocalCouncil() or OL.devMode) then
		return
	end
	if reason ~= "skip" and reason ~= "disenchant" then
		return
	end
	item.closed = reason
	local label = reason == "disenchant" and "Disenchant" or "Skip"
	OL.History:AddAward(self.active.id, {
		index = index,
		winner = label,
		link = item.link,
		response = reason,
		time = time(),
	})
	OL.Comms:Send(join({ "close", self.active.id, index, reason }))
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
		incoming.bag = prev.bag
		incoming.slot = prev.slot
		incoming.guid = prev.guid
	else
		incoming.votes = incoming.votes or {}
		incoming.ballots = incoming.ballots or {}
	end
	self.active.items[index] = incoming
end

function Session:Broadcast()
	local session = self.active
	if not session then
		return
	end
	local test = ""
	OL.Comms:Send(join({ "begin", session.id, #session.items, test }))
	for index, item in ipairs(session.items) do
		OL.Comms:Send(itemLine(session.id, index, item, test))
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
			local response = ""
			if item.awardedTo and item.votes then
				local vote = item.votes[OL:ShortName(item.awardedTo)]
				response = vote and vote.response or ""
			end
			OL.Comms:Send(join({ "mark", session.id, index, item.awardedTo or "", item.closed or "", response }))
		end
	end
	OL.Comms:Send(join({ "vend", session.id, test }))
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

function Session:ApplyMark(id, index, awardedTo, closed, response)
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
		OL.History:AddAward(id, {
			index = index,
			winner = awardedTo,
			link = item.link,
			response = response or "",
			time = time(),
		})
	end
	if not item.awardedTo and closed and (closed == "skip" or closed == "disenchant") and not item.closed then
		item.closed = closed
		changed = true
		OL.History:AddAward(id, {
			index = index,
			winner = closed == "disenchant" and "Disenchant" or "Skip",
			link = item.link,
			response = closed,
			time = time(),
		})
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
		self:ApplyMark(fields[1], tonumber(fields[2]), textOrNil(fields[3]), textOrNil(fields[4]), textOrNil(fields[5]))
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
				OL.History:AddAward(fields[1], {
					index = index,
					winner = reason == "disenchant" and "Disenchant" or "Skip",
					link = item.link,
					response = reason,
					time = time(),
				})
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
		OL.History:AddAward(fields[1], {
			index = index,
			winner = fields[3],
			link = fields[4],
			response = fields[5] or "",
			time = tonumber(fields[6]) or time(),
		})
	end
end
