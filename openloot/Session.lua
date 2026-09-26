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

function Session:Init()
	self.active = nil
end

function Session:IsActive()
	return self.active ~= nil
end

function Session:IsHolder()
	return self.active and OL:ShortName(self.active.owner or "") == OL:ShortName(OL:FullName("player"))
end

function Session:ItemCount()
	if not self.active then
		return 0
	end
	return #self.active.items
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

function Session:ShowUI()
	OL.RaiderFrame:Show()
	if OL.Council:IsLocalCouncil() then
		OL.CouncilFrame:Show()
	elseif OL.CouncilFrame then
		OL.CouncilFrame:Hide()
	end
	OL.RaiderFrame:Refresh()
	OL.CouncilFrame:Refresh()
end

function Session:Clear()
	self.active = nil
	if OL.RaiderFrame then
		OL.RaiderFrame:Hide()
	end
	if OL.CouncilFrame then
		OL.CouncilFrame:Hide()
	end
end

function Session:Start(items)
	local id = OL:ShortName(OL:FullName("player")) .. "-" .. tostring(time())
	self.active = { id = id, items = items, owner = OL:FullName("player") }
	OL.History:Ensure(id, time())
	local test = OL.testSession and "1" or ""
	OL.Comms:Send(join({ "begin", id, #items, test }))
	for index, item in ipairs(items) do
		OL.Comms:Send(join({
			"item", id, index, field(item.ilvl), item.equipLoc or "", field(item.texture),
			field(item.classID), field(item.subClassID), item.link, test,
		}))
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
		OL.RaiderFrame:Refresh()
		return
	end
	local slotIlvl, diff, first, second = OL.Items:Compare(item.link, item.ilvl, item.equipLoc)
	item.myResponse = responseId
	item.myNote = note
	local name = OL:ShortName(OL:FullName("player"))
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
	OL.RaiderFrame:Refresh()
	OL.CouncilFrame:Refresh()
end

function Session:ClearResponse(index)
	local item = self.active and self.active.items[index]
	if not item or item.awardedTo or not item.myResponse then
		return
	end
	item.myResponse = nil
	local name = OL:ShortName(OL:FullName("player"))
	item.votes[name] = nil
	OL.Comms:Send(join({
		"vote", self.active.id, index, "", "", "", item.myNote or "", "", "",
	}))
	OL.RaiderFrame:Refresh()
	OL.CouncilFrame:Refresh()
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
		if name == OL:ShortName(OL:FullName("player")) then
			item.myResponse = nil
			OL.RaiderFrame:Refresh()
		end
		OL.CouncilFrame:Refresh()
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
	OL.CouncilFrame:Refresh()
end

function Session:CastBallot(index, candidate)
	local item = self.active and self.active.items[index]
	if not item or item.awardedTo or not (OL.Council:IsLocalCouncil() or OL.devMode) then
		return
	end
	item.ballots = item.ballots or {}
	local mine = OL:ShortName(OL:FullName("player"))
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
	OL.RaiderFrame:Refresh()
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
	OL.RaiderFrame:Refresh()
	OL.CouncilFrame:AdvanceFrom(index)
end

local function fromLeader(sender)
	local leader = OL.RaidMode:LeaderName()
	return leader and OL:ShortName(sender) == OL:ShortName(leader)
end

function Session:OnComm(sender, op, fields)
	if not fields[1] then
		return
	end
	local leader = fromLeader(sender)
	local testBegin = op == "begin" and fields[3] == "1"
	local testItem = op == "item" and fields[9] == "1"
	local testVend = op == "vend" and fields[2] == "1"
	if (op == "begin" or op == "item" or op == "vend") and not leader and not testBegin and not testItem and not testVend then
		return
	end
	if op == "begin" then
		if not (self.active and self.active.id == fields[1]) then
			self.active = { id = fields[1], items = {}, owner = sender, test = testBegin }
			OL.History:Ensure(fields[1], time())
			OL.Council:Rebuild()
		end
		return
	end
	if op == "item" then
		if not self.active or self.active.id ~= fields[1] then
			self.active = { id = fields[1], items = {}, owner = sender, test = testItem }
		end
		local index = tonumber(fields[2])
		if not index then
			return
		end
		self.active.items[index] = {
			link = fields[8],
			ilvl = numberOrNil(fields[3]) or 0,
			equipLoc = fields[4] or "",
			texture = textureOf(fields[5]),
			classID = numberOrNil(fields[6]),
			subClassID = numberOrNil(fields[7]),
			votes = {},
			ballots = {},
		}
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
				OL.RaiderFrame:Refresh()
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
				OL.RaiderFrame:Refresh()
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
