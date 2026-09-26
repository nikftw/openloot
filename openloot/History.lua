local OL = OpenLoot

OL.History = {}
local History = OL.History

function History:Init()
	self.selected = nil
end

function History:Ensure(id, when)
	local store = OL.db.history
	if store.sessions[id] then
		return store.sessions[id]
	end
	local entry = { id = id, time = when or time(), awards = {} }
	store.sessions[id] = entry
	table.insert(store.order, 1, id)
	self.selected = id
	if self.frame and self.frame:IsShown() then
		self:Refresh()
	end
	return entry
end

function History:AddAward(sessionId, award)
	local session = self:Ensure(sessionId, award.time)
	for _, existing in ipairs(session.awards) do
		if existing.index == award.index then
			return
		end
	end
	session.awards[#session.awards + 1] = award
	if self.frame and self.frame:IsShown() then
		self:Refresh()
	end
end

function History:Toggle()
	self:EnsureFrame()
	if self.frame:IsShown() then
		self.frame:Hide()
	else
		self.frame:Show()
		self:Refresh()
	end
end

function History:EnsureFrame()
	if self.frame then
		return
	end
	local frame = OL.UI:CreateWindow("OpenLoot History", 640, 406)
	self.frame = frame
	OL:WatchWindow(frame, "history")
	frame:HookScript("OnShow", function()
		local order = OL.db.history and OL.db.history.order
		self.selected = order and order[1] or nil
	end)
	self.sessionButtons = {}
	self.awardRows = {}

	self.sessionPane = CreateFrame("Frame", nil, frame.content)
	self.sessionPane:SetPoint("TOPLEFT", 0, 0)
	self.sessionPane:SetPoint("BOTTOMLEFT", 0, 0)
	self.sessionPane:SetWidth(128)

	self.exportButton = OL.UI:FlatButton(self.sessionPane, "Export current", 128, 24)
	self.exportButton:SetPoint("TOPLEFT", 0, 0)
	self.exportButton:SetScript("OnClick", function()
		self:ShowExport()
	end)

	local sessionScroll = OL.UI:CreateScroll(self.sessionPane)
	sessionScroll:SetPoint("TOPLEFT", 0, -28)
	sessionScroll:SetPoint("BOTTOMRIGHT", 0, 0)
	self.sessionScroll = sessionScroll

	self.main = CreateFrame("Frame", nil, frame.content)
	self.main:SetPoint("TOPLEFT", self.sessionPane, "TOPRIGHT", 4, 0)
	self.main:SetPoint("BOTTOMRIGHT", 0, 0)

	local px = OL.UI:Pixel()
	self.headerName = OL.UI:Text(self.main, "OVERLAY", "GameFontDisableSmall")
	self.headerName:SetPoint("TOPLEFT", 4, -px)
	self.headerName:SetWidth(100)
	self.headerName:SetJustifyH("LEFT")
	self.headerName:SetWordWrap(false)
	self.headerName:SetText("Name")
	self.headerItem = OL.UI:Text(self.main, "OVERLAY", "GameFontDisableSmall")
	self.headerItem:SetPoint("TOPLEFT", 108 - px, -px)
	self.headerItem:SetJustifyH("LEFT")
	self.headerItem:SetWordWrap(false)
	self.headerItem:SetText("Item")
	self.headerTime = OL.UI:Text(self.main, "OVERLAY", "GameFontDisableSmall")
	self.headerTime:SetPoint("TOPRIGHT", -4, -px)
	self.headerTime:SetWidth(92)
	self.headerTime:SetJustifyH("RIGHT")
	self.headerTime:SetWordWrap(false)
	self.headerTime:SetText("Time")
	self.headerResponse = OL.UI:Text(self.main, "OVERLAY", "GameFontDisableSmall")
	self.headerResponse:SetPoint("TOPRIGHT", self.headerTime, "TOPLEFT", -4 - (2 * px), 0)
	self.headerResponse:SetWidth(76)
	self.headerResponse:SetJustifyH("LEFT")
	self.headerResponse:SetWordWrap(false)
	self.headerResponse:SetText("Response")

	local scroll = OL.UI:CreateScroll(self.main)
	scroll:SetPoint("TOPLEFT", 0, -16)
	scroll:SetPoint("BOTTOMRIGHT", 0, 0)
	self.scroll = scroll
end

function History:ItemLabel(link)
	if not link or link == "" then
		return ""
	end
	local name = link:match("%[(.-)%]")
	if name and name ~= "" then
		return name
	end
	return link
end

function History:CsvCell(text)
	text = tostring(text or ""):gsub('"', '""')
	return '"' .. text .. '"'
end

function History:Csv()
	local lines = { "Name,Item,Response,Time" }
	for _, entry in ipairs(self:VisibleAwards()) do
		local award = entry.award
		lines[#lines + 1] = table.concat({
			self:CsvCell(OL:ShortName(award.winner or "")),
			self:CsvCell(self:ItemLabel(award.link)),
			self:CsvCell(award.response and OL:ResponseText(award.response) or ""),
			self:CsvCell(date("%d %b %H:%M", award.time or entry.session.time)),
		}, ",")
	end
	return table.concat(lines, "\n")
end

function History:EnsureExport()
	if self.exportFrame then
		return
	end
	local frame = OL.UI:CreateWindow("OpenLoot Export", 520, 360)
	frame:SetFrameStrata("DIALOG")
	local scroll = OL.UI:CreateScroll(frame.content)
	scroll:SetAllPoints()
	local box = CreateFrame("EditBox", nil, scroll.content)
	box:SetMultiLine(true)
	box:SetFontObject(GameFontHighlightSmall)
	OL.UI:Face(box)
	box:SetAutoFocus(false)
	box:SetPoint("TOPLEFT", 0, 0)
	box:SetWidth(490)
	box:SetScript("OnEscapePressed", function()
		frame:Hide()
	end)
	self.exportBox = box
	self.exportScroll = scroll
	self.exportFrame = frame
end

function History:ShowExport()
	self:EnsureFrame()
	self:EnsureExport()
	local text = self:Csv()
	local lines = 1
	for _ in text:gmatch("\n") do
		lines = lines + 1
	end
	self.exportBox:SetText(text)
	self.exportBox:SetHeight(math.max(300, lines * 14))
	self.exportScroll.content:SetHeight(self.exportBox:GetHeight())
	self.exportBox:SetFocus()
	self.exportBox:HighlightText()
	self.exportFrame:Show()
end

function History:VisibleAwards()
	local awards = {}
	local order = OL.db.history.order
	for _, id in ipairs(order) do
		if not self.selected or self.selected == id then
			local session = OL.db.history.sessions[id]
			if session then
				for _, award in ipairs(session.awards) do
					awards[#awards + 1] = { session = session, award = award }
				end
			end
		end
	end
	return awards
end

function History:Refresh()
	self:EnsureFrame()
	if not self.frame:IsShown() then
		return
	end
	local order = OL.db.history.order
	if not self.selected or not OL.db.history.sessions[self.selected] then
		self.selected = order[1]
	end
	local y = 0
	for index, id in ipairs(order) do
		local button = self.sessionButtons[index]
		if not button then
			button = OL.UI:FlatButton(self.sessionScroll.content, "", 128, 24)
			self.sessionButtons[index] = button
		end
		local session = OL.db.history.sessions[id]
		if not session then
			button:Hide()
		else
			button:SetText(date("%d %b %H:%M", session.time))
			if self.selected == id then
				button:SetBaseColor(0.2, 0.32, 0.42, 1)
			else
				button:SetBaseColor(0.16, 0.16, 0.18, 1)
			end
			button:SetScript("OnClick", function()
				self.selected = id
				self:Refresh()
			end)
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", self.sessionScroll.content, "TOPLEFT", 0, -y)
			button:Show()
			y = y + OL.UI:P(28)
		end
	end
	for index = #order + 1, #self.sessionButtons do
		self.sessionButtons[index]:Hide()
	end
	self.sessionScroll.content:SetHeight(math.max(1, y))

	local awards = self:VisibleAwards()
	y = 0
	for index, entry in ipairs(awards) do
		local row = self.awardRows[index]
		if not row then
			row = self:CreateAwardRow(self.scroll.content)
			self.awardRows[index] = row
		end
		local award = entry.award
		local icon
		if award.link and C_Item.GetItemInfoInstant(award.link) then
			icon = select(5, C_Item.GetItemInfoInstant(award.link))
		end
		row.icon:SetIcon(icon)
		row.name:SetText(OL:ShortName(award.winner or ""))
		row.time:SetText(date("%d %b %H:%M", award.time or entry.session.time))
		row.link:SetText(award.link or "")
		row.response:SetText(award.response and OL:ResponseText(award.response) or "")
		row.linkHit:SetScript("OnEnter", function(selfHit)
			OL.UI:ItemTip(selfHit, award.link)
		end)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", self.scroll.content, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", self.scroll.content, "RIGHT", 0, 0)
		row:Show()
		y = y + OL.UI:P(24)
	end
	for index = #awards + 1, #self.awardRows do
		self.awardRows[index]:Hide()
	end
	self.scroll.content:SetHeight(math.max(1, y))
end

function History:CreateAwardRow(parent)
	local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	row:SetHeight(OL.UI:P(24))
	row:SetClipsChildren(true)
	row:SetBackdrop({ bgFile = OL.UI.WHITE })
	row:SetBackdropColor(0.1, 0.1, 0.12, 1)
	row.name = OL.UI:Text(row, "OVERLAY", "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", 4, 0)
	row.name:SetWidth(100)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.time = OL.UI:Text(row, "OVERLAY", "GameFontHighlightSmall")
	row.time:SetWidth(92)
	row.time:SetPoint("RIGHT", -4, 0)
	row.time:SetJustifyH("RIGHT")
	row.time:SetWordWrap(false)
	row.response = OL.UI:Text(row, "OVERLAY", "GameFontHighlightSmall")
	row.response:SetWidth(76)
	row.response:SetPoint("RIGHT", row.time, "LEFT", -4, 0)
	row.response:SetJustifyH("LEFT")
	row.response:SetWordWrap(false)
	row.icon = OL.UI:Icon(row, 16)
	row.icon:SetPoint("LEFT", 108, 0)
	row.icon:EnableMouse(false)
	row.linkHit = CreateFrame("Button", nil, row)
	row.linkHit:SetHeight(16)
	row.linkHit:SetClipsChildren(true)
	row.linkHit:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
	row.linkHit:SetPoint("RIGHT", row.response, "LEFT", -4, 0)
	row.link = OL.UI:Text(row.linkHit, "OVERLAY", "GameFontHighlightSmall")
	row.link:SetPoint("LEFT", 0, 0)
	row.link:SetPoint("RIGHT", 0, 0)
	row.link:SetJustifyH("LEFT")
	row.link:SetWordWrap(false)
	row.linkHit:SetScript("OnLeave", function()
		OL.UI:HideTip()
	end)
	return row
end
