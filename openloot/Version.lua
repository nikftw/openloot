local OL = OpenLoot

OL.Versions = {}
local Versions = OL.Versions

function Versions:Init()
	self.known = {}
	self.rows = {}
	self.report = false
	self.waiting = false
	self.warnedFor = nil
	self:Remember("player", OL:Version())
end

function Versions:Remember(name, version)
	local short = OL:ShortName(name)
	if short == "" or not version or version == "" then
		return
	end
	self.known[short] = version
	local mine = OL:Version()
	if OL:CompareVersion(mine, version) < 0 and self.warnedFor ~= version then
		self.warnedFor = version
		OL:Print(OL:ShortName(short) .. " has OpenLoot " .. version .. ". You have " .. mine .. ".")
	end
	if self.frame and self.frame:IsShown() then
		self:Refresh()
	end
end

function Versions:Announce()
	self:Remember(OL:FullName("player"), OL:Version())
	if not IsInGroup() then
		return
	end
	OL.Comms:Send("ver\31" .. OL:Version())
end

function Versions:Query(report)
	self.report = report and true or false
	self.waiting = true
	self:Announce()
	if IsInGroup() then
		OL.Comms:Send("verq")
	end
	if self.timer then
		self.timer:Cancel()
		self.timer = nil
	end
	if self.frame and self.frame:IsShown() then
		self:Refresh()
	end
	local function finish()
		self.timer = nil
		self.waiting = false
		self:Refresh()
		self:Summarize()
	end
	if C_Timer.NewTimer then
		self.timer = C_Timer.NewTimer(4, finish)
	else
		C_Timer.After(4, finish)
	end
end

function Versions:Summarize()
	if not self.report then
		return
	end
	self.report = false
	if not IsInGroup() then
		OL:Print("You are on OpenLoot " .. OL:Version() .. ".")
		return
	end
	local mine = OL:ShortName(OL:FullName("player"))
	local old, missing = {}, {}
	for _, member in ipairs(OL.Session:Roster()) do
		local short = OL:ShortName(member.name)
		if short ~= mine then
			local version = self.known[short]
			if not version then
				missing[#missing + 1] = short
			elseif OL:CompareVersion(version, OL:Version()) < 0 then
				old[#old + 1] = short .. " " .. version
			end
		end
	end
	if #old == 0 and #missing == 0 then
		OL:Print("Everyone is on OpenLoot " .. OL:Version() .. ".")
		return
	end
	if #old > 0 then
		OL:Print("Out of date: " .. table.concat(old, ", ") .. ".")
	end
	if #missing > 0 then
		OL:Print("No OpenLoot response: " .. table.concat(missing, ", ") .. ".")
	end
end

function Versions:Toggle()
	self:Ensure()
	if self.frame:IsShown() then
		self.frame:Hide()
		return
	end
	self.frame:Show()
	self:Query(true)
end

function Versions:Ensure()
	if self.frame then
		return
	end
	local frame = OL.UI:CreateWindow("OpenLoot Versions", 272, 30)
	self.frame = frame
	OL:WatchWindow(frame, "versions")
	local clip = CreateFrame("Frame", nil, frame.content)
	clip:SetClipsChildren(true)
	clip:SetPoint("TOPLEFT", 0, 0)
	clip:SetPoint("BOTTOMRIGHT", 0, 0)
	local content = CreateFrame("Frame", nil, clip)
	content:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, 0)
	content:SetPoint("TOPRIGHT", clip, "TOPRIGHT", 0, 0)
	content:SetHeight(1)
	clip.content = content
	clip.offset = 0
	clip:EnableMouseWheel(true)
	clip:SetScript("OnMouseWheel", function(selfClip, delta)
		local rowH = OL.UI:P(24)
		local maxOffset = (content:GetHeight() or 0) - (selfClip:GetHeight() or 0)
		if maxOffset < 0 then
			maxOffset = 0
		end
		local nextOffset = OL.UI:Snap((selfClip.offset or 0) - delta * rowH)
		if nextOffset < 0 then
			nextOffset = 0
		elseif nextOffset > maxOffset then
			nextOffset = OL.UI:Snap(maxOffset)
		end
		selfClip.offset = nextOffset
		content:ClearAllPoints()
		content:SetPoint("TOPLEFT", selfClip, "TOPLEFT", 0, nextOffset)
		content:SetPoint("TOPRIGHT", selfClip, "TOPRIGHT", 0, nextOffset)
	end)
	self.scroll = clip
end

function Versions:WhisperOne(member)
	local short = OL:ShortName(member.name)
	local current = OL:Version()
	local version = self.known[short]
	local text
	if not version then
		text = "Please install OpenLoot. This raid is on " .. current .. "."
	elseif OL:CompareVersion(version, current) < 0 then
		text = "Please update OpenLoot to " .. current .. ". You are on " .. version .. "."
	end
	if not text then
		return
	end
	if OL.devMode then
		OL:Print("Demo: would whisper " .. OL:ShortName(short) .. ": " .. text)
		return
	end
	if pcall(SendChatMessage, text, "WHISPER", nil, member.name) then
		OL:Print("Whispered " .. OL:ShortName(short) .. ".")
	end
end

function Versions:Status(version)
	if not version then
		if self.waiting then
			return "...", 0.7, 0.7, 0.7
		end
		return "Not installed", 0.55, 0.55, 0.55
	end
	local cmp = OL:CompareVersion(version, OL:Version())
	if cmp < 0 then
		return version, 0.95, 0.35, 0.28
	end
	if cmp > 0 then
		return version, 0.95, 0.8, 0.25
	end
	return version, 0.45, 0.9, 0.5
end

function Versions:Refresh()
	if not self.frame or not self.frame:IsShown() then
		return
	end
	local roster = {}
	for _, member in ipairs(OL.Session:Roster()) do
		roster[#roster + 1] = member
	end
	local function rank(version)
		if not version then
			return self.waiting and 3 or 1
		end
		if OL:CompareVersion(version, OL:Version()) < 0 then
			return 2
		end
		return 3
	end
	table.sort(roster, function(left, right)
		local leftName = OL:ShortName(left.name)
		local rightName = OL:ShortName(right.name)
		local leftRank = rank(self.known[leftName])
		local rightRank = rank(self.known[rightName])
		if leftRank ~= rightRank then
			return leftRank < rightRank
		end
		return leftName:lower() < rightName:lower()
	end)
	local rowH = OL.UI:P(24)
	for index, member in ipairs(roster) do
		local row = self.rows[index]
		if not row then
			row = self:CreateRow(self.scroll.content)
			self.rows[index] = row
		end
		local short = OL:ShortName(member.name)
		local known = self.known[short]
		local text, red, green, blue = self:Status(known)
		local mine = OL:ShortName(OL:FullName("player"))
		local behind = short ~= mine and ((not known and not self.waiting) or (known and OL:CompareVersion(known, OL:Version()) < 0))
		row.name:SetText(short)
		row.name:SetTextColor(OL.UI:ClassColor(member.classFile))
		row.version:SetText(text)
		row.version:SetTextColor(red, green, blue)
		row.whisper:SetShown(behind)
		row.whisper:SetScript("OnClick", function()
			self:WhisperOne(member)
		end)
		local y = OL.UI:Snap((index - 1) * rowH)
		local buttonH = OL.UI:P(16)
		local inset = OL.UI:Snap((rowH - buttonH) / 2)
		row:SetHeight(rowH)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", self.scroll.content, "TOPLEFT", 0, -y)
		row:SetPoint("TOPRIGHT", self.scroll.content, "TOPRIGHT", 0, -y)
		row.version:ClearAllPoints()
		row.version:SetPoint("RIGHT", row, "RIGHT", -OL.UI:P(4), 0)
		row.whisper:SetSize(OL.UI:P(64), buttonH)
		row.whisper:ClearAllPoints()
		local textW = OL.UI:Snap(row.version:GetStringWidth() or 0)
		row.whisper:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(OL.UI:P(4) + textW + OL.UI:P(4)), -inset)
		row:Show()
	end
	for index = #roster + 1, #self.rows do
		self.rows[index]:Hide()
	end
	self.scroll.content:SetHeight(math.max(1, OL.UI:Snap(#roster * rowH)))
	if not self.frame.collapsed and not self.frame.gripSized then
		local count = math.max(#roster, 1)
		local shown = count > 8 and 8.5 or count
		local height = OL.UI:FitHeight(OL.UI:Snap(rowH * shown))
		self.frame:SetHeight(height)
		self.frame.expandedHeight = height
		self.frame:SetWidth(272)
	end
end

function Versions:CreateRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(OL.UI:P(24))
	row.version = OL.UI:Text(row, "OVERLAY", "GameFontHighlightSmall")
	row.version:SetJustifyH("RIGHT")
	row.version:SetWordWrap(false)
	row.whisper = OL.UI:FlatButton(row, "Whisper", 64, 16)
	row.whisper:Hide()
	row.name = OL.UI:Text(row, "OVERLAY", "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", 4, 0)
	row.name:SetPoint("RIGHT", row.whisper, "LEFT", -4, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	return row
end

function Versions:OnComm(sender, op, fields)
	if op == "verq" then
		self:Announce()
		return
	end
	if op == "ver" then
		self:Remember(sender, fields[1])
	end
end
