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
	local frame = OL.UI:CreateWindow("OpenLoot Versions", 272, 220)
	self.frame = frame
	self.header = OL.UI:Text(frame.content, "OVERLAY", "GameFontDisableSmall")
	self.header:SetPoint("TOPLEFT", 4, 0)
	self.header:SetText("Name")
	self.headerVersion = OL.UI:Text(frame.content, "OVERLAY", "GameFontDisableSmall")
	self.headerVersion:SetPoint("TOPRIGHT", -4, 0)
	self.headerVersion:SetText("Version")
	self.scroll = OL.UI:CreateScroll(frame.content)
	self.scroll:SetPoint("TOPLEFT", 0, -20)
	self.scroll:SetPoint("BOTTOMRIGHT", 0, 0)
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
	local roster = OL.Session:Roster()
	local y = 0
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
		row.name:SetText(OL:ShortName(short))
		row.name:SetTextColor(OL.UI:ClassColor(member.classFile))
		row.version:SetText(text)
		row.version:SetTextColor(red, green, blue)
		row.whisper:SetShown(behind)
		row.whisper:SetScript("OnClick", function()
			self:WhisperOne(member)
		end)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", self.scroll.content, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", self.scroll.content, "RIGHT", 0, 0)
		row:Show()
		y = y + 24
	end
	for index = #roster + 1, #self.rows do
		self.rows[index]:Hide()
	end
	self.scroll.content:SetHeight(math.max(1, y))
	if not self.frame.collapsed then
		local visible = math.min(math.max(#roster, 1), 12)
		local height = 52 + visible * 24
		self.frame:SetHeight(height)
		self.frame.expandedHeight = height
	end
end

function Versions:CreateRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(24)
	row.name = OL.UI:Text(row, "OVERLAY", "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", 4, 0)
	row.name:SetJustifyH("LEFT")
	row.version = OL.UI:Text(row, "OVERLAY", "GameFontHighlightSmall")
	row.version:SetPoint("RIGHT", -4, 0)
	row.version:SetJustifyH("RIGHT")
	row.whisper = OL.UI:FlatButton(row, "Whisper", 64, 16)
	row.whisper:SetPoint("RIGHT", row.version, "LEFT", -4, 0)
	row.whisper:Hide()
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
