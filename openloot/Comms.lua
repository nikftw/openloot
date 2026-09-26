local OL = OpenLoot

OL.Comms = {}
local Comms = OL.Comms

local SEP = "\31"
local CHUNK = "\2"
local MAX_PART = 200
local queue = {}
local incoming = {}

local function splitHead(text, count)
	local fields = {}
	local startAt = 1
	for _ = 1, count - 1 do
		local found = text:find(SEP, startAt, true)
		if not found then
			fields[#fields + 1] = text:sub(startAt)
			return fields
		end
		fields[#fields + 1] = text:sub(startAt, found - 1)
		startAt = found + 1
	end
	fields[#fields + 1] = text:sub(startAt)
	return fields
end

local function split(text)
	local fields = {}
	local startAt = 1
	while true do
		local found = text:find(SEP, startAt, true)
		if not found then
			fields[#fields + 1] = text:sub(startAt)
			break
		end
		fields[#fields + 1] = text:sub(startAt, found - 1)
		startAt = found + 1
	end
	return fields
end

function Comms:Channel()
	if IsInRaid() then
		return "RAID"
	end
	if IsInGroup() then
		return "PARTY"
	end
	return nil
end

function Comms:Destinations()
	local list = {}
	local function add(channel, target)
		list[#list + 1] = { channel = channel, target = target }
	end
	local channel = self:Channel()
	if channel then
		add(channel)
	end
	if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and channel ~= "INSTANCE_CHAT" then
		add("INSTANCE_CHAT")
	end
	if not IsInGroup() then
		return list
	end
	local mine = OL:ShortName(OL:FullName("player"))
	for index = 1, GetNumGroupMembers() do
		local unit
		if IsInRaid() then
			unit = "raid" .. index
		elseif index == 1 then
			unit = "player"
		else
			unit = "party" .. (index - 1)
		end
		if UnitExists(unit) and not UnitIsUnit(unit, "player") then
			local name = GetUnitName(unit, true) or OL:FullName(unit)
			if name and name ~= "" and OL:ShortName(name) ~= mine then
				add("WHISPER", name)
			end
		end
	end
	return list
end

local function sendResult(result)
	if result == nil or result == true or result == 0 then
		return "ok"
	end
	local results = Enum and Enum.SendAddonMessageResult
	if results and result == results.Success then
		return "ok"
	end
	if results and (result == results.AddonMessageThrottle or result == results.ChannelThrottle) then
		return "wait"
	end
	if result == 3 or result == 8 then
		return "wait"
	end
	return "fail"
end

local function transmit(payload, channel, target)
	local result
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		result = C_ChatInfo.SendAddonMessage(OL.PREFIX, payload, channel, target)
	elseif SendAddonMessage then
		SendAddonMessage(OL.PREFIX, payload, channel, target)
		return "ok"
	else
		return "fail"
	end
	return sendResult(result)
end

function Comms:Init()
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		C_ChatInfo.RegisterAddonMessagePrefix(OL.PREFIX)
	end
end

function Comms:Enqueue(payload)
	local destinations = self:Destinations()
	if #destinations == 0 then
		return false
	end
	for _, dest in ipairs(destinations) do
		queue[#queue + 1] = { text = payload, channel = dest.channel, target = dest.target }
	end
	return true
end

function Comms:Send(payload)
	if OL.devMode then
		return
	end
	local queued
	if #payload <= MAX_PART then
		queued = self:Enqueue(payload)
	else
		local id = tostring(time()) .. tostring(math.random(100, 999))
		local total = math.ceil(#payload / MAX_PART)
		queued = false
		for index = 1, total do
			local part = payload:sub((index - 1) * MAX_PART + 1, index * MAX_PART)
			if self:Enqueue(CHUNK .. id .. SEP .. index .. SEP .. total .. SEP .. part) then
				queued = true
			end
		end
	end
	if not queued and not IsInGroup() and not self.toldGroup then
		self.toldGroup = true
		OL:Print("You are not in a group, so nobody else receives this.")
	end
	if queued then
		self:Kick()
	end
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
			return
		end
		if outcome == "ok" and queue[1] then
			C_Timer.After(0.15, step)
			return
		end
		self.pumping = false
	end
	step()
end

function Comms:Clear()
	wipe(queue)
end

function Comms:Pump()
	local index = nil
	for entryIndex, entry in ipairs(queue) do
		if entry.channel ~= "WHISPER" then
			index = entryIndex
			break
		end
	end
	if not index then
		index = queue[1] and 1 or nil
	end
	local entry = index and queue[index]
	if not entry then
		return "empty"
	end
	local ok, outcome = pcall(transmit, entry.text, entry.channel, entry.target)
	if not ok then
		outcome = "fail"
	end
	if outcome == "wait" then
		return "wait"
	end
	table.remove(queue, index)
	if outcome == "fail" and not self.toldFail then
		self.toldFail = true
		OL:Print("The group did not accept an OpenLoot message. Both characters need this version of the addon, then /reload.")
	end
	return "ok"
end

function Comms:IsSelf(sender)
	local mine = OL:FullName("player")
	if mine == "" then
		return false
	end
	return OL:ShortName(sender) == OL:ShortName(mine)
end

function Comms:Dispatch(sender, payload)
	local fields = split(payload)
	local op = fields[1]
	if not op or op == "" then
		return
	end
	table.remove(fields, 1)
	OL:OnComm(sender, op, fields)
end

function Comms:OnMessage(sender, message)
	if self:IsSelf(sender) then
		return
	end
	if message:sub(1, 1) ~= CHUNK then
		self:Dispatch(sender, message)
		return
	end
	local fields = splitHead(message:sub(2), 4)
	local id, index, total, data = fields[1], tonumber(fields[2]), tonumber(fields[3]), fields[4]
	if not id or not index or not total or not data then
		return
	end
	local bucket = incoming[id]
	if not bucket then
		bucket = { total = total, parts = {} }
		incoming[id] = bucket
	end
	bucket.parts[index] = data
	local combined = {}
	for partIndex = 1, bucket.total do
		if not bucket.parts[partIndex] then
			return
		end
		combined[#combined + 1] = bucket.parts[partIndex]
	end
	incoming[id] = nil
	self:Dispatch(sender, table.concat(combined))
end

function OL:OnComm(sender, op, fields)
	if op == "state" or op == "stateq" then
		self.RaidMode:OnComm(sender, op, fields)
	elseif op == "ver" or op == "verq" then
		self.Versions:OnComm(sender, op, fields)
	elseif op == "begin" or op == "item" or op == "vend" or op == "vote" or op == "ballot" or op == "award" or op == "close" then
		self.Session:OnComm(sender, op, fields)
	end
end
