local OL = OpenLoot

OL.RaiderFrame = {}
local Frame = OL.RaiderFrame

local ROW_BUTTONS = {
	{ id = "BIS", text = "BIS", width = 52 },
	{ id = "UPGRADE", text = "Upgrade", width = 72 },
	{ id = "OFFSPEC", text = "Offspec", width = 70 },
	{ id = "PASS", text = "Pass", width = 52 },
}

function Frame:Ensure()
	if self.frame then
		return
	end
	local frame = OL.UI:CreateWindow("OpenLoot", 560, 420)
	self.frame = frame
	self.rows = {}
	self.showAll = false
	self.openNote = nil

	local scroll = OL.UI:CreateScroll(frame.content)
	scroll:SetPoint("TOPLEFT", 0, 0)
	scroll:SetPoint("BOTTOMRIGHT", 0, 28)
	self.scroll = scroll

	self.empty = frame.content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	self.empty:SetPoint("TOP", 0, -12)
	self.empty:SetText("No usable items.")
	self.empty:Hide()

	self.toggle = OL.UI:FlatButton(frame.content, "Show all", 90, 18)
	self.toggle:SetPoint("BOTTOMLEFT", frame.content, "BOTTOMLEFT", 0, 0)
	self.toggle:SetScript("OnClick", function()
		self.showAll = not self.showAll
		self.toggle:SetText(self.showAll and "Show usable" or "Show all")
		self:Refresh()
	end)
end

function Frame:Show()
	self:Ensure()
	self.frame:Show()
end

function Frame:Hide()
	if self.frame then
		self.frame:Hide()
	end
end

local function usable(item)
	return OL.Items:PlayerCanUse(item.link, item.equipLoc, item.classID, item.subClassID)
end

function Frame:Refresh()
	if not self.frame or not self.frame:IsShown() or self.refreshing then
		return
	end
	self.refreshing = true
	local session = OL.Session.active
	if session and self.sessionId ~= session.id then
		self.sessionId = session.id
		self.openNote = nil
	end
	local items = session and session.items or {}
	local visible = {}
	for index, item in ipairs(items) do
		if self.showAll or usable(item) then
			visible[#visible + 1] = { index = index, item = item }
		end
	end
	self.empty:SetShown(#visible == 0)

	local y = 0
	for rowIndex, entry in ipairs(visible) do
		local row = self.rows[rowIndex]
		if not row then
			row = self:CreateRow(self.scroll.content)
			self.rows[rowIndex] = row
		end
		row:Show()
		local height = self:FillRow(row, entry.index, entry.item)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", self.scroll.content, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", self.scroll.content, "RIGHT", 0, 0)
		y = y + height + 6
	end
	for rowIndex = #visible + 1, #self.rows do
		self.rows[rowIndex]:Hide()
	end
	self.scroll.content:SetHeight(math.max(1, y))
	self.refreshing = false
end

function Frame:CreateRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(62)
	row.icon = OL.UI:Icon(row, 36)
	row.icon:SetPoint("TOPLEFT", 0, 0)
	row.ilvl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.ilvl:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -10)
	row.link = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.link:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.link:SetPoint("RIGHT", row.ilvl, "LEFT", -8, 0)
	row.link:SetJustifyH("LEFT")
	row.buttons = {}
	local x = 0
	for _, spec in ipairs(ROW_BUTTONS) do
		local button = OL.UI:FlatButton(row, spec.text, spec.width, 18)
		button.responseId = spec.id
		button:SetPoint("TOPLEFT", row, "TOPLEFT", x, -40)
		row.buttons[#row.buttons + 1] = button
		x = x + spec.width + 4
	end
	row.noteButton = OL.UI:FlatButton(row, "Note", 52, 18)
	row.noteButton:SetPoint("TOPLEFT", row, "TOPLEFT", x, -40)
	row.noteBox = CreateFrame("EditBox", nil, row, "BackdropTemplate")
	row.noteBox:SetHeight(20)
	row.noteBox:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -62)
	row.noteBox:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.noteBox:SetAutoFocus(false)
	row.noteBox:SetFontObject(GameFontHighlightSmall)
	row.noteBox:SetMaxLetters(80)
	row.noteBox:SetTextInsets(6, 6, 2, 2)
	row.noteBox:SetBackdrop({ bgFile = OL.UI.WHITE, edgeFile = OL.UI.WHITE, edgeSize = 1 })
	row.noteBox:SetBackdropColor(0.1, 0.1, 0.12, 1)
	row.noteBox:SetBackdropBorderColor(0.3, 0.3, 0.32, 1)
	row.noteBox:Hide()
	row.icon:EnableMouse(true)
	row.icon:SetScript("OnEnter", function(self)
		OL.UI:ItemTip(self, row.linkText)
	end)
	row.icon:SetScript("OnLeave", function()
		OL.UI:HideTip()
	end)
	return row
end

function Frame:FillRow(row, index, item)
	row.linkText = item.link
	row.icon:SetIcon(item.texture)
	row.link:SetText(item.link)
	row.ilvl:SetText(item.ilvl and item.ilvl > 0 and tostring(item.ilvl) or "")
	local awarded = item.awardedTo ~= nil
	for _, button in ipairs(row.buttons) do
		local selected = item.myResponse == button.responseId
		if selected then
			button:SetBaseColor(0.2, 0.38, 0.28, 1)
		else
			button:SetBaseColor(0.16, 0.16, 0.18, 1)
		end
		button:SetEnabled(not awarded)
		button:SetScript("OnClick", function()
			OL.Session:SetResponse(index, button.responseId, item.myNote)
		end)
	end
	if item.myNote and item.myNote ~= "" then
		row.noteButton:SetBaseColor(0.2, 0.28, 0.38, 1)
	else
		row.noteButton:SetBaseColor(0.16, 0.16, 0.18, 1)
	end
	row.noteButton:SetEnabled(not awarded)
	row.noteButton:SetScript("OnClick", function()
		if self.openNote == index then
			OL.Session:SetResponse(index, item.myResponse, row.noteBox:GetText())
			self.openNote = nil
		else
			self.openNote = index
		end
		self:Refresh()
		if self.openNote == index then
			row.noteBox:SetFocus()
		end
	end)
	local showNote = self.openNote == index and not awarded
	row.noteBox:SetShown(showNote)
	if showNote and not row.noteBox:HasFocus() then
		row.noteBox:SetText(item.myNote or "")
	end
	row.noteBox:SetScript("OnEnterPressed", function(edit)
		edit:ClearFocus()
		OL.Session:SetResponse(index, item.myResponse, edit:GetText())
		self.openNote = nil
		self:Refresh()
	end)
	row.noteBox:SetScript("OnEditFocusLost", function(edit)
		if self.refreshing or self.openNote ~= index then
			return
		end
		OL.Session:SetResponse(index, item.myResponse, edit:GetText())
	end)
	if showNote then
		row:SetHeight(86)
		return 86
	end
	row:SetHeight(62)
	return 62
end
