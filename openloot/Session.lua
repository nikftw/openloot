local OL = OpenLoot

OL.Session = {}
local Session = OL.Session

local SEP = OL.Comms.SEP
local SCAN_WAIT = 5

-- Wire ops. Every op that names a session carries its id first: the full id
-- in S, E and Q, the three-character tag in the rest.
--   q  leader asks every raider for their bags
--   R  raider -> leader (whisper): per item  packed link, ilvl
--   S  leader: the session. id, map id, instance name, then per item
--      packed link, ilvl, holder, ref
--   V  raider vote: id, index, response, slot ilvl, note, gear 1, gear 2
--   K  leader catch-up, every vote on one item: id, index, then per vote
--      voter, response, slot ilvl, note, gear 1, gear 2
--   B  council ballot: id, index, choice
--   L  leader catch-up, every ballot on one item: id, index, then voter, choice
--   A  award: id, index, winner, response, time, award tail
--   C  skip or disenchant: id, index, reason, time, award tail
--   M  leader catch-up copy of an award or close: id, index, winner, reason, response, time, award tail
--      The award tail is the council votes for the winner, the winner's two
--      equipped items (packed) and their note.
--   E  session over: id
--   Y  (whisper) the session this client asked about is over
--   Q  ask the leader to catch this client up: the session id this client
--      has (or empty), then per item  vote hash, ballot hash, settled (1/0)
-- An empty holder means the session owner. ref is the holder's own index into
-- the bag scan they sent, so bag, slot and guid never leave their client.

local CLOSE_CODE = { skip = "s", disenchant = "d" }
local CLOSE_FROM = { s = "skip", d = "disenchant" }
local CLOSE_LABEL = { skip = "Skip", disenchant = "Disenchant" }

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

-- Responses, votes and awards name their session by the last three
-- characters of its id: enough to tell it from the session it replaced.
local function tag(id)
	return id:sub(-3)
end

local function send(...)
	OL.Comms:Send(table.concat({ ... }, SEP))
end

local function sendTo(target, ...)
	OL.Comms:Send(table.concat({ ... }, SEP), target)
end

-- Responses and ballots wait half a second, so quick clicks share a frame.
local function sendSoon(...)
	OL.Comms:Send(table.concat({ ... }, SEP), nil, 0.5)
end

-- Order-independent fingerprint of a table of strings, for the catch-up digest.
local function hash(entries, describe)
	local total = 0
	for key, value in pairs(entries) do
		local text = describe(key, value)
		local h = 0
		for index = 1, #text do
			h = (h * 31 + text:byte(index)) % 16777216
		end
		total = (total + h) % 16777216
	end
	return string.format("%x", total)
end

local function describeVote(voter, vote)
	return voter .. "|" .. tostring(vote.response) .. "|" .. tostring(vote.slotIlvl) .. "|" .. (vote.note or "")
end

local function describeBallot(voter, choice)
	return voter .. "|" .. tostring(choice)
end

local function me()
	return OL:Me()
end

-- Window redraws. What this player does redraws at once. What arrives from
-- other players (responses, votes, awards, item loads) is gathered and drawn
-- at most every 0.2s, and only in the window it shows up in: other players'
-- responses and council votes only ever appear in the council window.
local dirtyRaider, dirtyCouncil, redrawQueued = false, false, false

local function flush()
	redrawQueued = false
	if dirtyRaider then
		dirtyRaider = false
		OL.RaiderFrame:Refresh()
	end
	if dirtyCouncil then
		dirtyCouncil = false
		OL.CouncilFrame:Refresh()
	end
end

local function redrawSoon(raider, council)
	dirtyRaider = dirtyRaider or raider
	dirtyCouncil = dirtyCouncil or council
	if not redrawQueued then
		redrawQueued = true
		C_Timer.After(0.2, flush)
	end
end

local function repaint()
	dirtyRaider, dirtyCouncil = true, true
	flush()
end

local function pack(link)
	return OL.Items:Pack(link)
end

local function tail(award)
	return field(award.votes), pack(award.gear1), pack(award.gear2), field(award.note)
end

local function readTail(fields, first)
	return numberOrNil(fields[first]), textOrNil(fields[first + 1]), textOrNil(fields[first + 2]), textOrNil(fields[first + 3])
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

-- Shared with every window: read it, never change it.
function Session:Roster()
	return OL:Roster().list
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
	elseif OL.RaiderFrame.frame then
		OL.RaiderFrame:Hide()
	end
	if OL.Council:IsLocalCouncil() and self:WindowOpen("council") then
		OL.CouncilFrame:Show()
	elseif OL.CouncilFrame.frame then
		OL.CouncilFrame:Hide()
	end
	repaint()
end

function Session:End()
	if not self:IsActive() then
		return
	end
	send("E", self.active.id)
	self:Clear()
	OL:Print("Loot session closed.")
end

function Session:Clear()
	if self.active and self.active.id then
		self:RememberEnd(self.active.id)
	end
	self.active = nil
	OL.db.session = nil
	OL.db.scan = nil
	OL.RaiderFrame:Hide()
	OL.CouncilFrame:Hide()
end

-- Fill in what every client can work out from the link itself, and swap the
-- stand-in link for the real one once the item has loaded.
function Session:Prepare(item)
	item.votes = item.votes or {}
	item.ballots = item.ballots or {}
	if item.packed and not item.link then
		local itemString = OL.Items:Unpack(item.packed)
		local link, loaded = OL.Items:Link(itemString)
		item.link = link
		if not loaded then
			OL.Items:WhenLoaded(itemString, function()
				item.link = OL.Items:Link(itemString) or item.link
				redrawSoon(true, true)
			end)
		end
	end
	return OL.Items:Describe(item)
end

function Session:Start(items)
	local id = string.format("%x", time())
	if self.active then
		local old = self.active.id
		OL.Comms:Clear()
		send("E", old)
		self:RememberEnd(old)
		local base, extra = id, 1
		while id == old or self:HasEnded(id) do
			extra = extra + 1
			id = base .. "." .. extra
		end
	end
	for _, item in ipairs(items) do
		self:Prepare(item)
	end
	self.active = { id = id, items = items, owner = OL:FullName("player") }
	self:Bind()
	self:OpenSessionWindows()
	local instance, _, _, _, _, _, _, map = GetInstanceInfo()
	OL.History:Ensure(id, time(), instance, map)
	self:SendBody()
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
	for _, member in ipairs(self:Roster()) do
		if member.short ~= "" and member.short ~= mine and member.online then
			expect[member.short] = true
		end
	end
	return expect
end

-- Keep this character's own scan, so an awarded item's ref finds its bag slot.
local function scanOwnBags()
	local scan = OL.Items:ScanBags()
	OL.db.scan = scan
	return scan
end

function Session:Gather()
	if self.pending then
		return
	end
	OL.Council:Rebuild()
	local pending = {
		items = {},
		done = {},
		expect = self:ScanExpect(),
	}
	self.pending = pending
	for ref, found in ipairs(scanOwnBags()) do
		pending.items[#pending.items + 1] = { link = found.link, ilvl = found.ilvl, holder = me(), ref = ref }
	end
	if next(pending.expect) == nil then
		self:FinishGather()
		return
	end
	send("q")
	C_Timer.After(SCAN_WAIT, function()
		if self.pending == pending then
			self:FinishGather()
		end
	end)
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

function Session:OnScanRequest(sender)
	if OL.RaidMode:IsRunner() or not OL.RaidMode:IsLeader(sender) then
		return
	end
	local parts = { "R" }
	for _, found in ipairs(scanOwnBags()) do
		parts[#parts + 1] = pack(found.link)
		parts[#parts + 1] = field(found.ilvl)
	end
	OL.Comms:Send(table.concat(parts, SEP), sender)
end

function Session:OnScan(sender, fields)
	local pending = self.pending
	if not pending or pending.finished then
		return
	end
	local who = OL:ShortName(sender)
	if who == "" or who == me() or not pending.expect[who] or pending.done[who] then
		return
	end
	pending.done[who] = true
	for first = 1, #fields - 1, 2 do
		if fields[first] ~= "" then
			pending.items[#pending.items + 1] = {
				packed = fields[first],
				ilvl = numberOrNil(fields[first + 1]) or 0,
				holder = who,
				ref = (first + 1) / 2,
			}
		end
	end
	for name in pairs(pending.expect) do
		if not pending.done[name] then
			return
		end
	end
	self:FinishGather()
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
	local slotIlvl, first, second
	if responseId ~= "PASS" then
		slotIlvl, _, first, second = OL.Items:Compare(item.link, item.ilvl, item.equipLoc)
		first, second = textOrNil(pack(first)), textOrNil(pack(second))
	end
	self:ApplyVote(self.active.id, index, me(), responseId, slotIlvl, note, first, second)
	sendSoon("V", tag(self.active.id), index, OL:ResponseCode(responseId), field(slotIlvl), note, first, second)
end

function Session:ClearResponse(index)
	local item = self.active and self.active.items[index]
	if not item or item.awardedTo or not item.myResponse then
		return
	end
	self:ApplyVote(self.active.id, index, me())
	sendSoon("V", tag(self.active.id), index)
end

-- id is the session id, or the short tag the busy messages carry instead.
function Session:Item(id, index)
	local active = self.active
	if not index or not active or (active.id ~= id and tag(active.id) ~= id) then
		return nil
	end
	return active.items[index]
end

local function makeVote(response, slotIlvl, note, first, second)
	return {
		response = response,
		note = textOrNil(note),
		slotIlvl = slotIlvl,
		s1 = textOrNil(first),
		s2 = textOrNil(second),
	}
end

function Session:ApplyVote(id, index, voter, response, slotIlvl, note, first, second)
	local item = self:Item(id, index)
	if not item then
		return
	end
	local name = OL:ShortName(voter)
	item.votes[name] = response and makeVote(response, slotIlvl, note, first, second) or nil
	if name == me() then
		item.myResponse = response
		if response then
			item.myNote = note
		end
		repaint()
	else
		redrawSoon(false, true)
	end
end

function Session:CastBallot(index, candidate)
	local item = self.active and self.active.items[index]
	if not item or item.awardedTo or not OL.Council:IsLocalCouncil() then
		return
	end
	local choice = OL:ShortName(candidate)
	if item.ballots[me()] == choice then
		choice = ""
	end
	self:ApplyBallot(self.active.id, index, me(), choice)
	sendSoon("B", tag(self.active.id), index, choice)
end

function Session:ApplyBallot(id, index, voter, choice)
	local item = self:Item(id, index)
	if not item then
		return
	end
	item.ballots[OL:ShortName(voter)] = textOrNil(choice) and OL:ShortName(choice) or nil
	if OL:ShortName(voter) == me() then
		OL.CouncilFrame:Refresh()
	else
		redrawSoon(false, true)
	end
end

-- Record an award, skip or disenchant on this client. winner is a player for
-- an award, nil for a close. Returns false if the item was already settled.
function Session:Settle(id, index, winner, closed, response, when, ...)
	local item = self:Item(id, index)
	if not item or item.awardedTo or item.closed then
		return false
	end
	id = self.active.id
	if winner then
		item.awardedTo = winner
		OL.Trade:Add(item, winner, id, index)
	else
		item.closed = closed
	end
	OL.History:AddAward(id, OL.History:Record(id, index, winner or CLOSE_LABEL[closed], item.link, response, when, ...))
	OL.CouncilFrame:AdvanceFrom(index)
	redrawSoon(true, true)
	return true
end

function Session:Award(index, winner)
	local item = self.active and self.active.items[index]
	if not item or item.awardedTo or item.closed or not OL.Council:IsLocalCouncil() then
		return
	end
	local id = self.active.id
	winner = OL:ShortName(winner)
	local vote = item.votes[winner]
	local award = OL.History:Capture(id, index, item, winner, vote and vote.response or "", time())
	self:Settle(id, index, winner, nil, award.response, award.time, award.votes, award.gear1, award.gear2, award.note)
	repaint()
	send("A", tag(id), index, winner, OL:ResponseCode(award.response), award.time, tail(award))
	pcall(SendChatMessage, winner .. " was awarded " .. item.link, IsInRaid() and "RAID" or "PARTY")
end

function Session:Close(index, reason)
	local item = self.active and self.active.items[index]
	if not item or item.awardedTo or item.closed or not CLOSE_CODE[reason] or not OL.Council:IsLocalCouncil() then
		return
	end
	local id = self.active.id
	local award = OL.History:Capture(id, index, item, CLOSE_LABEL[reason], reason, time())
	self:Settle(id, index, nil, reason, reason, award.time, award.votes, award.gear1, award.gear2, award.note)
	repaint()
	send("C", tag(id), index, CLOSE_CODE[reason], award.time, tail(award))
end

function Session:SendMark(target, index, item)
	local id = self.active.id
	local saved = OL.History:Find(id, index) or {}
	local response = saved.response or ""
	if response == "" and item.awardedTo then
		local vote = item.votes[item.awardedTo]
		response = vote and vote.response or ""
	end
	sendTo(target, "M", tag(id), index, field(item.awardedTo), CLOSE_CODE[item.closed] or "",
		item.closed and "" or OL:ResponseCode(response), field(saved.time), tail(saved))
end

-- The session body, and every settled item. target nil means the whole group.
function Session:SendBody(target)
	local session = self.active
	if not session then
		return
	end
	local owner = OL:ShortName(session.owner)
	local saved = OL.db.history.sessions[session.id] or {}
	local parts = { "S", session.id, field(saved.mapID), field(saved.instance) }
	for _, item in ipairs(session.items) do
		local holder = item.holder ~= owner and item.holder or ""
		parts[#parts + 1] = item.packed or pack(item.link)
		parts[#parts + 1] = field(item.ilvl)
		parts[#parts + 1] = field(holder)
		parts[#parts + 1] = field(item.ref)
	end
	OL.Comms:Hold()
	OL.Comms:Send(table.concat(parts, SEP), target)
	for index, item in ipairs(session.items) do
		if item.awardedTo or item.closed then
			self:SendMark(target, index, item)
		end
	end
	OL.Comms:Release()
end

function Session:SendVotes(target, index, item, only)
	local parts = { "K", tag(self.active.id), index }
	for voter, vote in pairs(item.votes) do
		if not only or voter == only then
			parts[#parts + 1] = voter
			parts[#parts + 1] = OL:ResponseCode(vote.response)
			parts[#parts + 1] = field(vote.slotIlvl)
			parts[#parts + 1] = field(vote.note)
			parts[#parts + 1] = field(vote.s1)
			parts[#parts + 1] = field(vote.s2)
		end
	end
	OL.Comms:Send(table.concat(parts, SEP), target)
end

function Session:SendBallots(target, index, item)
	local parts = { "L", tag(self.active.id), index }
	for voter, choice in pairs(item.ballots) do
		parts[#parts + 1] = voter
		parts[#parts + 1] = choice
	end
	OL.Comms:Send(table.concat(parts, SEP), target)
end

function Session:Digest()
	local parts = {}
	for _, item in ipairs(self.active and self.active.items or {}) do
		parts[#parts + 1] = hash(item.votes, describeVote)
		parts[#parts + 1] = hash(item.ballots, describeBallot)
		parts[#parts + 1] = (item.awardedTo or item.closed) and "1" or "0"
	end
	return parts
end

-- A client asked to be caught up. Whisper back only what its digest says it
-- is missing. Officers get every vote and ballot; a raider only needs their own.
function Session:Answer(sender, f)
	if OL.RaidMode:IsRunner() then
		OL.RaidMode:Broadcast(sender)
	end
	if not self:IsActive() then
		self:Restore()
	end
	if not self.active then
		-- Only a client that still holds a session needs telling it is over.
		if textOrNil(f[1]) then
			sendTo(sender, "Y")
		end
		return
	end
	local same = f[1] == self.active.id
	local who = OL:ShortName(sender)
	local info = OL.Council:Info(sender)
	local council = info and info.council
	OL.Comms:Hold()
	if not same then
		self:SendBody(sender)
	end
	for index, item in ipairs(self.active.items) do
		local base = 2 + (index - 1) * 3
		if council then
			if (same and f[base] ~= hash(item.votes, describeVote)) or (not same and next(item.votes)) then
				self:SendVotes(sender, index, item)
			end
			if (same and f[base + 1] ~= hash(item.ballots, describeBallot)) or (not same and next(item.ballots)) then
				self:SendBallots(sender, index, item)
			end
		elseif not same and item.votes[who] then
			self:SendVotes(sender, index, item, who)
		end
		if same and f[base + 2] ~= "1" and (item.awardedTo or item.closed) then
			self:SendMark(sender, index, item)
		end
	end
	OL.Comms:Release()
end

function Session:AskLeader()
	local parts = { "Q", self.active and self.active.id or "" }
	for _, value in ipairs(self:Digest()) do
		parts[#parts + 1] = value
	end
	OL.Comms:Send(table.concat(parts, SEP), OL.RaidMode:LeaderName())
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
		if item.packed then
			item.link = nil
		end
		self:Prepare(item)
	end
	return true
end

function Session:RestoreWindows()
	local windows = OL.db.windows
	if not windows then
		return
	end
	if windows.history then
		OL.History:EnsureFrame()
		OL.History.frame:Show()
		OL.History:Refresh()
	end
	if windows.versions then
		OL.Versions:Ensure()
		OL.Versions.frame:Show()
		OL.Versions:Query(false)
	end
	if windows.trade and #OL.Trade.list > 0 then
		OL.Trade:Show()
	end
end

function Session:CatchUp()
	if not self:IsActive() then
		self:Restore()
	end
	if self:IsActive() then
		self:ShowUI()
	end
	self:RestoreWindows()
end

-- A session body from the leader. Votes, ballots and settled items already
-- known for the same id and item are kept.
function Session:TakeBody(sender, fields)
	local id = fields[1]
	if not id or self:HasEnded(id) then
		return
	end
	if not self:IsActive() then
		self:Restore()
	end
	local previous = self.active and self.active.id == id and self.active.items or {}
	local fresh = not (self.active and self.active.id == id)
	local owner = OL:ShortName(sender)
	local items = {}
	for first = 4, #fields - 3, 4 do
		local index = #items + 1
		local item = {
			packed = fields[first],
			ilvl = numberOrNil(fields[first + 1]) or 0,
			holder = textOrNil(fields[first + 2]) or owner,
			ref = numberOrNil(fields[first + 3]),
		}
		local prev = previous[index]
		if prev and (prev.packed == item.packed or pack(prev.link) == item.packed) then
			for _, key in ipairs({ "link", "votes", "ballots", "myResponse", "myNote", "awardedTo", "closed" }) do
				item[key] = prev[key]
			end
		end
		items[index] = self:Prepare(item)
	end
	self.active = { id = id, items = items, owner = sender }
	OL.History:Ensure(id, time(), textOrNil(fields[3]), numberOrNil(fields[2]))
	if fresh then
		self:OpenSessionWindows()
		OL.Council:Rebuild()
	end
	self:Bind()
	self:ShowUI()
end

local handlers = {}

function handlers.q(self, sender)
	self:OnScanRequest(sender)
end

function handlers.R(self, sender, fields)
	self:OnScan(sender, fields)
end

function handlers.Q(self, sender, fields)
	if UnitIsGroupLeader("player") then
		self:Answer(sender, fields)
	end
end

function handlers.Y(self, sender)
	if not OL.RaidMode:IsLeader(sender) then
		return
	end
	if self:IsActive() then
		self:Clear()
		OL:Print("Loot session closed.")
	else
		OL.db.session = nil
	end
end

function handlers.S(self, sender, fields)
	if OL.RaidMode:IsLeader(sender) then
		self:TakeBody(sender, fields)
	end
end

-- Other players' responses only matter to the council window; a raider's
-- own window shows their own response alone.
function handlers.V(self, sender, f)
	if not OL.Council:IsLocalCouncil() then
		return
	end
	self:ApplyVote(f[1], tonumber(f[2]), sender, OL:ResponseFromCode(f[3]), numberOrNil(f[4]), textOrNil(f[5]), textOrNil(f[6]), textOrNil(f[7]))
end

-- The leader's full set of votes for one item replaces ours, except our own
-- vote, which this client always knows best.
function handlers.K(self, sender, f)
	local item = OL.RaidMode:IsLeader(sender) and self:Item(f[1], tonumber(f[2]))
	if not item then
		return
	end
	local mine = me()
	local own = item.votes[mine]
	wipe(item.votes)
	for first = 3, #f - 5, 6 do
		local voter = f[first]
		local response = OL:ResponseFromCode(f[first + 1])
		if voter ~= "" and response then
			item.votes[voter] = makeVote(response, numberOrNil(f[first + 2]), textOrNil(f[first + 3]), textOrNil(f[first + 4]), textOrNil(f[first + 5]))
		end
	end
	if own then
		item.votes[mine] = own
	elseif item.votes[mine] then
		item.myResponse = item.votes[mine].response
		item.myNote = item.votes[mine].note
	end
	redrawSoon(true, true)
end

-- Council votes only matter to the council window.
function handlers.B(self, sender, f)
	if OL.Council:IsLocalCouncil() then
		self:ApplyBallot(f[1], tonumber(f[2]), sender, f[3])
	end
end

function handlers.L(self, sender, f)
	local item = OL.RaidMode:IsLeader(sender) and self:Item(f[1], tonumber(f[2]))
	if not item then
		return
	end
	wipe(item.ballots)
	for first = 3, #f - 1, 2 do
		if f[first] ~= "" and f[first + 1] ~= "" then
			item.ballots[f[first]] = f[first + 1]
		end
	end
	redrawSoon(false, true)
end

function handlers.A(self, _, f)
	self:Settle(f[1], tonumber(f[2]), textOrNil(f[3]), nil, OL:ResponseFromCode(f[4]) or "", numberOrNil(f[5]) or time(), readTail(f, 6))
end

function handlers.C(self, _, f)
	local reason = CLOSE_FROM[f[3]]
	if reason then
		self:Settle(f[1], tonumber(f[2]), nil, reason, reason, numberOrNil(f[4]) or time(), readTail(f, 5))
	end
end

function handlers.M(self, sender, f)
	if not OL.RaidMode:IsLeader(sender) then
		return
	end
	local winner, reason = textOrNil(f[3]), CLOSE_FROM[f[4]]
	if winner or reason then
		self:Settle(f[1], tonumber(f[2]), winner, reason, reason or OL:ResponseFromCode(f[5]) or "", numberOrNil(f[6]) or time(), readTail(f, 7))
	end
end

function handlers.E(self, sender, f)
	local id = f[1]
	local owner = self.active and self.active.owner
	if not OL.RaidMode:IsLeader(sender) and not (owner and OL:ShortName(sender) == OL:ShortName(owner)) then
		return
	end
	self:RememberEnd(id)
	if self.active and self.active.id == id then
		self:Clear()
		OL:Print("Loot session closed.")
	end
end

function Session:OnComm(sender, op, fields)
	handlers[op](self, sender, fields)
end

OL.Comms:Route(Session, "q", "R", "Q", "Y", "S", "V", "K", "B", "L", "A", "C", "M", "E")
