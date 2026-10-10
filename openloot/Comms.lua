local OL = OpenLoot

OL.Comms = {}
local Comms = OL.Comms

-- One addon message (a frame) carries up to FRAME bytes. Logical messages are
-- packed into frames back to back, split by PACK. A message too long for one
-- frame is cut into CHUNK parts and rebuilt by the receiver.
local SEP = "\31"
local PACK = "\30"
local CHUNK = "\2"
local FRAME = 255
local PART = FRAME - 16
local STEP = 0.15
-- Messages for the whole group go out before whispers. Whispers are one
-- client's catch-up and can wait; the group should never queue behind them.
local group = {}
local direct = {}
local incoming = {}
local held = 0
local nextId = 0

Comms.SEP = SEP

function Comms:Channel()
	if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and not IsInGroup(LE_PARTY_CATEGORY_HOME) then
		return "INSTANCE_CHAT"
	end
	if IsInRaid() then
		return "RAID"
	end
	if IsInGroup() then
		return "PARTY"
	end
	return nil
end

local function transmit(payload, channel, target)
	local result = C_ChatInfo.SendAddonMessage(OL.PREFIX, payload, channel, target)
	local codes = Enum.SendAddonMessageResult
	if result == nil or result == true or result == codes.Success then
		return "ok"
	end
	if result == codes.AddonMessageThrottle or result == codes.ChannelThrottle then
		return "wait"
	end
	return "fail"
end

local function pending()
	return group[1] ~= nil or direct[1] ~= nil
end

function Comms:Init()
	C_ChatInfo.RegisterAddonMessagePrefix(OL.PREFIX)
end

-- Queue messages without sending until the matching Release, so a burst
-- (a whole session, a catch-up) leaves in as few frames as possible.
function Comms:Hold()
	held = held + 1
end

function Comms:Release()
	held = math.max(0, held - 1)
	if held == 0 and pending() and not self.lingering then
		self:Kick()
	end
end

-- linger: seconds to wait before sending if nothing is queued yet, so quick
-- clicks (responses, ballots) leave together in one frame.
function Comms:Send(payload, target, linger)
	if not target and not self:Channel() then
		if not self.toldGroup then
			self.toldGroup = true
			OL:Print("You are not in a group, so nobody else receives this.")
		end
		return
	end
	local list = target and direct or group
	if #payload <= FRAME then
		list[#list + 1] = { text = payload, target = target }
	else
		nextId = nextId % 4095 + 1
		local id = string.format("%x", nextId)
		local total = math.ceil(#payload / PART)
		for index = 1, total do
			list[#list + 1] = {
				text = CHUNK .. id .. SEP .. index .. SEP .. total .. SEP .. payload:sub((index - 1) * PART + 1, index * PART),
				target = target,
			}
		end
	end
	if held > 0 or self.pumping or self.lingering then
		return
	end
	if linger then
		self.lingering = true
		C_Timer.After(linger, function()
			self.lingering = false
			self:Kick()
		end)
		return
	end
	self:Kick()
end

function Comms:Kick()
	if self.pumping then
		return
	end
	self.pumping = true
	local function step()
		local outcome = self:Pump()
		if outcome == "wait" then
			C_Timer.After(1, step)
		elseif outcome == "ok" and pending() then
			C_Timer.After(STEP, step)
		else
			self.pumping = false
		end
	end
	step()
end

function Comms:Clear()
	wipe(group)
	wipe(direct)
end

-- Leaving the group: nothing queued or half received matters any more.
function Comms:Reset()
	self:Clear()
	wipe(incoming)
end

function Comms:Pump()
	local list = group[1] and group or direct
	local first = list[1]
	if not first then
		return "empty"
	end
	local target = first.target
	local channel = target and "WHISPER" or self:Channel()
	if not channel then
		wipe(list)
		return "empty"
	end
	-- Pack this target's messages, in order, into one frame. Take them off the
	-- queue before sending: a reply can arrive inside the send and queue (or
	-- clear) messages of its own.
	local picks, size = {}, -1
	for index, entry in ipairs(list) do
		if entry.target == target then
			if size + 1 + #entry.text > FRAME then
				break
			end
			picks[#picks + 1] = index
			size = size + 1 + #entry.text
		end
	end
	local taken = {}
	for position = #picks, 1, -1 do
		taken[position] = table.remove(list, picks[position])
	end
	local parts = {}
	for position, entry in ipairs(taken) do
		parts[position] = entry.text
	end
	local ok, outcome = pcall(transmit, table.concat(parts, PACK), channel, target)
	if not ok then
		outcome = "fail"
	end
	if outcome == "wait" then
		for position = 1, #taken do
			table.insert(list, picks[position], taken[position])
		end
		return "wait"
	end
	if outcome == "fail" and not self.toldFail then
		self.toldFail = true
		OL:Print("The group did not accept an OpenLoot message. Both characters need this version of the addon, then /reload.")
	end
	return "ok"
end

function Comms:IsSelf(sender)
	local mine = OL:Me()
	return mine ~= "" and OL:ShortName(sender) == mine
end

local function dispatch(sender, payload)
	local fields = { strsplit(SEP, payload) }
	local op = table.remove(fields, 1)
	if op and op ~= "" then
		OL:OnComm(sender, op, fields)
	end
end

local function rebuild(sender, part)
	local id, index, total, data = part:match("^\2(%x+)\31(%d+)\31(%d+)\31(.*)$")
	index, total = tonumber(index), tonumber(total)
	if not id or not index or not total then
		return
	end
	local key = sender .. ":" .. id
	local bucket = incoming[key]
	if not bucket or bucket.total ~= total then
		bucket = { total = total, parts = {}, have = 0 }
		incoming[key] = bucket
	end
	if not bucket.parts[index] then
		bucket.parts[index] = data
		bucket.have = bucket.have + 1
	end
	if bucket.have < total then
		return
	end
	incoming[key] = nil
	dispatch(sender, table.concat(bucket.parts))
end

function Comms:OnMessage(sender, message)
	if self:IsSelf(sender) then
		return
	end
	for part in (message .. PACK):gmatch("(.-)\30") do
		if part:sub(1, 1) == CHUNK then
			rebuild(sender, part)
		elseif part ~= "" then
			dispatch(sender, part)
		end
	end
end

local routes = {}

function Comms:Route(owner, ...)
	for index = 1, select("#", ...) do
		routes[select(index, ...)] = owner
	end
end

function OL:OnComm(sender, op, fields)
	local owner = routes[op]
	if owner then
		owner:OnComm(sender, op, fields)
	end
end
