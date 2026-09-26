local OL = OpenLoot

OL.RaiderFrame = {}
local Frame = OL.RaiderFrame

local ROW_HEIGHT = 44

local ROW_BUTTONS = {
	{ id = "BIS", text = "BIS", width = 40 },
	{ id = "UPGRADE", text = "Upgrade", width = 62 },
	{ id = "OFFSPEC", text = "Offspec", width = 58 },
	{ id = "PASS", text = "Pass", width = 40 },
}

local CONTROL_WIDTH = 0
for index, spec in ipairs(ROW_BUTTONS) do
	CONTROL_WIDTH = CONTROL_WIDTH + spec.width
	if index > 1 then
		CONTROL_WIDTH = CONTROL_WIDTH + 4
	end
end

local RESPONSE_TEXT = {
	BIS = "BIS",
	UPGRADE = "Upgrade",
	OFFSPEC = "Offspec",
	PASS = "Pass",
}

function Frame:Ensure()
	if self.frame then
		return
	end
	local frame = OL.UI:CreateWindow("OpenLoot", CONTROL_WIDTH * 2 + 12, 626)
	self.frame = frame
	self.rows = {}
	self.showAll = false

	local scroll = OL.UI:CreateScroll(frame.content)
	scroll:SetPoint("TOPLEFT", 0, 0)
	scroll:SetPoint("BOTTOMRIGHT", 0, 22)
	self.scroll = scroll

	self.empty = OL.UI:Text(frame.content, "OVERLAY", "GameFontDisable")
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
		y = y + height + 4
	end
	for rowIndex = #visible + 1, #self.rows do
		self.rows[rowIndex]:Hide()
	end
	local view = self.scroll:GetHeight() or 0
	local step = ROW_HEIGHT + 4
	local overscroll = 0
	if view > step then
		overscroll = view - step
	end
	self.scroll.content:SetHeight(math.max(1, y + overscroll))
	self.refreshing = false
end

function Frame:Advance(row)
	local step = (row:GetHeight() or ROW_HEIGHT) + 4
	local hops = 1
	local index
	for candidateIndex, candidate in ipairs(self.rows) do
		if candidate == row then
			index = candidateIndex
			break
		end
	end
	if index then
		local cursor = index + 1
		while self.rows[cursor] and self.rows[cursor]:IsShown() and self.rows[cursor].finished do
			hops = hops + 1
			cursor = cursor + 1
		end
	end
	local scroll = self.scroll
	local nextScroll = scroll:GetVerticalScroll() + step * hops
	local maxScroll = scroll:GetVerticalScrollRange()
	if nextScroll > maxScroll then
		nextScroll = maxScroll
	end
	if nextScroll < 0 then
		nextScroll = 0
	end
	scroll:SetVerticalScroll(nextScroll)
end

function Frame:CreateRow(parent)
	local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	row:SetHeight(ROW_HEIGHT)
	row:SetBackdrop({ bgFile = OL.UI.WHITE })
	row:SetBackdropColor(0.1, 0.1, 0.12, 1)
	row:SetClipsChildren(false)

	row.item = CreateFrame("Frame", nil, row)
	row.item:SetPoint("TOPLEFT", 0, 0)
	row.item:SetPoint("BOTTOMLEFT", 0, 0)
	row.item:SetClipsChildren(true)
	row:SetScript("OnSizeChanged", function(self, width)
		if width and width > 0 then
			self.item:SetWidth(math.floor((width - 4) * 0.5))
		end
	end)

	row.icon = OL.UI:Icon(row.item, 36)
	row.icon:SetPoint("LEFT", 4, 0)
	row.link = OL.UI:Text(row.item, "OVERLAY", "GameFontHighlight")
	row.link:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 4, -4)
	row.link:SetPoint("RIGHT", -4, 0)
	row.link:SetJustifyH("LEFT")
	row.link:SetWordWrap(false)
	row.meta = OL.UI:Text(row.item, "OVERLAY", "GameFontHighlight")
	row.meta:SetPoint("TOPLEFT", row.link, "BOTTOMLEFT", 0, -4)
	row.meta:SetPoint("RIGHT", -4, 0)
	row.meta:SetJustifyH("LEFT")
	row.meta:SetWordWrap(false)

	row.controls = CreateFrame("Frame", nil, row)
	row.controls:SetWidth(CONTROL_WIDTH)
	row.controls:SetPoint("TOPRIGHT", 0, 0)
	row.controls:SetPoint("BOTTOMRIGHT", 0, 0)

	row.buttons = {}
	local x = 0
	for _, spec in ipairs(ROW_BUTTONS) do
		local button = OL.UI:FlatButton(row.controls, spec.text, spec.width, 18)
		button.responseId = spec.id
		button:SetPoint("TOPLEFT", row.controls, "TOPLEFT", x, -4)
		row.buttons[#row.buttons + 1] = button
		x = x + spec.width + 4
	end
	row.choice = OL.UI:Text(row, "OVERLAY", "GameFontHighlightSmall")
	row.choice:SetPoint("LEFT", row.controls, "TOPLEFT", 0, -13)
	row.choice:Hide()
	row.back = OL.UI:FlatButton(row.controls, "Back", 44, 18)
	row.back:SetPoint("LEFT", row.choice, "RIGHT", 4, 0)
	row.back:Hide()

	row.noteLabel = OL.UI:Text(row.controls, "OVERLAY", "GameFontDisableSmall")
	row.noteLabel:SetPoint("BOTTOMLEFT", row.controls, "BOTTOMLEFT", 0, 4)
	row.noteLabel:SetText("Note")
	row.save = OL.UI:FlatButton(row.controls, "Save", 44, 18)
	row.save:SetPoint("BOTTOMRIGHT", row.controls, "BOTTOMRIGHT", 0, 4)
	row.noteFrame = CreateFrame("Frame", nil, row.controls, "BackdropTemplate")
	row.noteFrame:SetHeight(18)
	row.noteFrame:SetPoint("BOTTOMLEFT", row.noteLabel, "BOTTOMRIGHT", 4, 0)
	row.noteFrame:SetPoint("BOTTOMRIGHT", row.save, "BOTTOMLEFT", -4, 0)
	row.noteFrame:SetBackdrop({ bgFile = OL.UI.WHITE, edgeFile = OL.UI.WHITE, edgeSize = 1 })
	row.noteFrame:SetBackdropColor(0.07, 0.07, 0.08, 1)
	row.noteFrame:SetBackdropBorderColor(0.3, 0.3, 0.32, 1)
	row.noteBox = CreateFrame("EditBox", nil, row.noteFrame)
	row.noteBox:SetPoint("TOPLEFT", 3, -2)
	row.noteBox:SetPoint("BOTTOMRIGHT", -3, 2)
	row.noteBox:SetAutoFocus(false)
	row.noteBox:SetFontObject(GameFontHighlightSmall)
	OL.UI:Face(row.noteBox)
	row.noteBox:SetMaxLetters(80)
	row.noteBox:SetTextInsets(2, 2, 0, 0)

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
	row.meta:SetText(OL.Items:RowMeta(item))
	local awarded = item.awardedTo ~= nil
	local closed = item.closed == "skip" or item.closed == "disenchant"
	row.finished = awarded or closed
	local locked = item.myResponse ~= nil and not awarded and not closed
	for _, button in ipairs(row.buttons) do
		button:SetShown(not locked and not awarded and not closed)
		button:SetEnabled(not awarded and not closed)
		button:SetBaseColor(0.16, 0.16, 0.18, 1)
		button:SetScript("OnClick", function()
			OL.Session:SetResponse(index, button.responseId, item.myNote)
			self:Advance(row)
		end)
	end
	row.choice:SetShown(locked or awarded or closed)
	if item.closed == "disenchant" then
		row.choice:SetText("Disenchanted")
	elseif item.closed == "skip" then
		row.choice:SetText("Skipped")
	elseif awarded then
		row.choice:SetText("Awarded " .. OL:ShortName(item.awardedTo or ""))
	else
		row.choice:SetText(RESPONSE_TEXT[item.myResponse] or "")
	end
	row.back:SetShown(locked)
	row.back:SetScript("OnClick", function()
		OL.Session:ClearResponse(index)
	end)
	row.noteBox:SetEnabled(not awarded and not closed)
	row.save:SetShown(not awarded and not closed)
	row.save:SetScript("OnClick", function()
		OL.Session:SetResponse(index, item.myResponse, row.noteBox:GetText())
	end)
	if not row.noteBox:HasFocus() then
		row.noteBox:SetText(item.myNote or "")
	end
	row.noteBox:SetScript("OnEnterPressed", function(edit)
		edit:ClearFocus()
		if awarded or closed then
			return
		end
		OL.Session:SetResponse(index, item.myResponse, edit:GetText())
	end)
	row.noteBox:SetScript("OnEditFocusLost", nil)
	row:SetHeight(ROW_HEIGHT)
	return ROW_HEIGHT
end
