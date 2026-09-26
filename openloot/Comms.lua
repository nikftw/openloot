local OL = OpenLoot

OL.Comms = {}
local Comms = OL.Comms

local SEP = "\31"
local CHUNK = "\2"
local MAX_PART = 200
local queue = {}
local incoming = {}
local ticker

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

function Comms:Init()
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		C_ChatInfo.RegisterAddonMessagePrefix(OL.PREFIX)
	end
	if not ticker then
		ticker = C_Timer.NewTicker(0.15, function()
			self:Pump()
		end)
	end
end

function Comms:Enqueue(payload)
	queue[#queue + 1] = payload
end

function Comms:Send(payload)
	if #payload <= MAX_PART then
		self:Enqueue(payload)
		return
	end
	local id = tostring(time()) .. tostring(math.random(100, 999))
	local total = math.ceil(#payload / MAX_PART)
	for index = 1, total do
		local part = payload:sub((index - 1) * MAX_PART + 1, index * MAX_PART)
		self:Enqueue(CHUNK .. id .. SEP .. index .. SEP .. total .. SEP .. part)
	end
end

function Comms:Clear()
	wipe(queue)
end

function Comms:Pump()
	local payload = queue[1]
	if not payload then
		return
	end
	local channel = self:Channel()
	if not channel then
		return
	end
	table.remove(queue, 1)
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		C_ChatInfo.SendAddonMessage(OL.PREFIX, payload, channel)
	elseif SendAddonMessage then
		SendAddonMessage(OL.PREFIX, payload, channel)
	end
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
	elseif op == "begin" or op == "item" or op == "vend" or op == "vote" or op == "award" or op == "arow" or op == "aend" or op == "rollq" or op == "roll" then
		self.Session:OnComm(sender, op, fields)
	end
end
