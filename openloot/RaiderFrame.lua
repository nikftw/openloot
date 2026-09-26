local OL = OpenLoot

OL.RaiderFrame = {}
local Frame = OL.RaiderFrame

local ROW_HEIGHT = 48

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

local FULL_WIDTH = CONTROL_WIDTH * 2 + 16
local ICON_COLUMN = 44
local COMPACT_WIDTH = 8 + ICON_COLUMN + 4 + CONTROL_WIDTH + 4

local function rowStride()
	return OL.UI:Snap(OL.UI:P(ROW_HEIGHT) + OL.UI:P(4) - OL.UI:Pixel())
end

function Frame:Ensure()
	if self.frame then
		return
	end
	local frame = OL.UI:CreateWindow("OpenLoot", FULL_WIDTH, 596)
	self.frame = frame
	OL:WatchWindow(frame, "raider")
	self.rows = {}
	self.showAll = false
	self.onlyVoted = false
	self.compact = false

	local px = OL.UI:Pixel()
	local side = OL.UI:P(4)
	self.layout = OL.UI:FlatButton(frame.content, "<", 18, 18)
	self.layout:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", side, px * 4)

	local scroll = OL.UI:CreateScroll(frame.content)
	scroll:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, 0)
	scroll:SetPoint("TOPRIGHT", frame.content, "TOPRIGHT", 0, 0)
	scroll:SetPoint("BOTTOM", self.layout, "TOP", 0, OL.UI:P(4))
	self.scroll = scroll

	self.empty = OL.UI:Text(frame.content, "OVERLAY", "GameFontDisable")
	self.empty:SetPoint("TOP", 0, -OL.UI:P(12))
	self.empty:SetText("No usable items.")
	self.empty:Hide()
	self:ShowLayoutMark()
	self.layout:SetScript("OnClick", function()
		if not self.compact then
			self.expandedWidth = self.frame:GetWidth()
		end
		self.compact = not self.compact
		self:ShowLayoutMark()
		self:ApplyWidth()
		self:RememberView()
		self:Refresh()
	end)

	self.toggle = OL.UI:FlatButton(frame.content, "Show all", 90, 18)
	self.toggle:SetPoint("BOTTOMLEFT", self.layout, "BOTTOMRIGHT", OL.UI:P(4), 0)
	self.toggle:SetScript("OnClick", function()
		self.showAll = not self.showAll
		self.toggle:SetText(self.showAll and "Show usable" or "Show all")
		self:RememberView()
		self:Refresh()
	end)

	self.voted = OL.UI:FlatButton(frame.content, "Only voted", 92, 18)
	self.voted:SetPoint("BOTTOMLEFT", self.toggle, "BOTTOMRIGHT", OL.UI:P(4), 0)
	self.voted:SetScript("OnClick", function()
		self.onlyVoted = not self.onlyVoted
		if self.onlyVoted then
			self.voted:SetBaseColor(0.22, 0.26, 0.32, 1)
		else
			self.voted:SetBaseColor(0.16, 0.16, 0.18, 1)
		end
		self:RememberView()
		self:Refresh()
		self.scroll:SetVerticalScroll(0)
	end)
	self:ApplySavedView()
end

function Frame:RememberView()
	OL.db.windows = OL.db.windows or {}
	OL.db.windows.showAll = self.showAll and true or false
	OL.db.windows.onlyVoted = self.onlyVoted and true or false
	OL.db.windows.compact = self.compact and true or false
end

function Frame:ApplySavedView()
	local windows = OL.db and OL.db.windows
	if not windows then
		return
	end
	self.showAll = windows.showAll and true or false
	self.onlyVoted = windows.onlyVoted and true or false
	self.compact = windows.compact and true or false
	self.toggle:SetText(self.showAll and "Show usable" or "Show all")
	if self.onlyVoted then
		self.voted:SetBaseColor(0.22, 0.26, 0.32, 1)
	end
	self:ShowLayoutMark()
	if self.compact then
		self.expandedWidth = self.frame:GetWidth()
		self:ApplyWidth()
	end
end

function Frame:ShowLayoutMark()
	self.layout:SetText(self.compact and ">" or "<")
end

function Frame:ApplyWidth()
	local frame = self.frame
	for _, row in ipairs(self.rows) do
		row.compact = self.compact
	end
	if self.compact then
		frame.layoutWidth = self.expandedWidth or FULL_WIDTH
		frame:SetWidth(COMPACT_WIDTH)
	else
		frame.layoutWidth = nil
		frame:SetWidth(self.expandedWidth or FULL_WIDTH)
	end
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

local function caresAbout(item)
	return item.myResponse == "BIS" or item.myResponse == "UPGRADE" or item.myResponse == "OFFSPEC"
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
		local shown = self.showAll or usable(item)
		if shown and self.onlyVoted then
			shown = caresAbout(item)
		end
		if shown then
			visible[#visible + 1] = { index = index, item = item }
		end
	end
	if self.onlyVoted then
		self.empty:SetText("No voted items.")
	else
		self.empty:SetText("No usable items.")
	end
	self.empty:SetShown(#visible == 0)

	local stride = rowStride()
	local y = 0
	for rowIndex, entry in ipairs(visible) do
		local row = self.rows[rowIndex]
		if not row then
			row = self:CreateRow(self.scroll.content)
			self.rows[rowIndex] = row
		end
		row:Show()
		self:FillRow(row, entry.index, entry.item)
		y = OL.UI:Snap((rowIndex - 1) * stride)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", self.scroll.content, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", self.scroll.content, "RIGHT", 0, 0)
	end
	for rowIndex = #visible + 1, #self.rows do
		self.rows[rowIndex]:Hide()
	end
	local view = self.scroll:GetHeight() or 0
	local step = stride
	local overscroll = 0
	if view > step then
		overscroll = view - step
	end
	local filled = #visible > 0 and OL.UI:Snap(#visible * stride) or 0
	self.scroll.content:SetHeight(math.max(1, OL.UI:Snap(filled + overscroll)))
	local maxScroll = self.scroll:GetVerticalScrollRange() or 0
	local current = OL.UI:Snap(self.scroll:GetVerticalScroll() or 0)
	if current > maxScroll then
		current = maxScroll
	end
	if current < 0 then
		current = 0
	end
	self.scroll:SetVerticalScroll(OL.UI:Snap(current))
	self.refreshing = false
end

function Frame:AtTop(row)
	local content = self.scroll and self.scroll.content
	if not content or not row then
		return false
	end
	local rowTop = row:GetTop()
	local contentTop = content:GetTop()
	if not rowTop or not contentTop then
		return self.rows[1] == row
	end
	local offset = contentTop - rowTop
	local scroll = self.scroll:GetVerticalScroll() or 0
	return offset <= scroll + 8
end

function Frame:Advance(row)
	local step = rowStride()
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
	scroll:SetVerticalScroll(OL.UI:Snap(nextScroll))
end

function Frame:CreateRow(parent)
	local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	row:SetHeight(OL.UI:P(ROW_HEIGHT))
	row:SetBackdrop({ bgFile = OL.UI.WHITE })
	row:SetBackdropColor(0.1, 0.1, 0.12, 1)
	row:SetClipsChildren(false)

	row.item = CreateFrame("Frame", nil, row)
	row.item:SetPoint("TOPLEFT", 0, 0)
	row.item:SetPoint("BOTTOMLEFT", 0, 0)
	row.item:SetClipsChildren(true)
	row:SetScript("OnSizeChanged", function(self, width)
		if not width or width <= 0 then
			return
		end
		if self.compact then
			self.item:SetWidth(OL.UI:P(ICON_COLUMN))
		else
			self.item:SetWidth(OL.UI:Snap((width - OL.UI:P(8)) * 0.5))
		end
	end)

	row.icon = OL.UI:Icon(row.item, 36)
	row.icon:SetPoint("LEFT", OL.UI:P(4), 0)
	row.link = OL.UI:Text(row.item, "OVERLAY", "GameFontHighlight")
	row.link:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", OL.UI:P(4), -OL.UI:P(4))
	row.link:SetPoint("RIGHT", -OL.UI:P(4), 0)
	row.link:SetJustifyH("LEFT")
	row.link:SetWordWrap(false)
	row.meta = OL.UI:Text(row.item, "OVERLAY", "GameFontHighlight")
	row.meta:SetPoint("TOPLEFT", row.link, "BOTTOMLEFT", 0, -OL.UI:P(4))
	row.meta:SetPoint("RIGHT", -OL.UI:P(4), 0)
	row.meta:SetJustifyH("LEFT")
	row.meta:SetWordWrap(false)

	row.controls = CreateFrame("Frame", nil, row)
	row.controls:SetPoint("TOPRIGHT", -OL.UI:P(4), 0)
	row.controls:SetPoint("BOTTOMRIGHT", -OL.UI:P(4), 0)

	row.buttons = {}
	local gap = OL.UI:P(4)
	local x = 0
	local used = 0
	for _, spec in ipairs(ROW_BUTTONS) do
		local buttonWidth = OL.UI:P(spec.width)
		local button = OL.UI:FlatButton(row.controls, spec.text, buttonWidth, 18)
		button.responseId = spec.id
		button:SetPoint("TOPLEFT", row.controls, "TOPLEFT", x, -gap)
		row.buttons[#row.buttons + 1] = button
		x = x + buttonWidth + gap
		used = used + buttonWidth
	end
	if #ROW_BUTTONS > 1 then
		used = used + gap * (#ROW_BUTTONS - 1)
	end
	row.controls:SetWidth(used)
	row.choice = OL.UI:Text(row, "OVERLAY", "GameFontHighlightSmall")
	row.choice:SetPoint("LEFT", row.controls, "TOPLEFT", 0, -13)
	row.choice:Hide()
	row.back = OL.UI:FlatButton(row.controls, "Back", 44, 18)
	row.back:SetPoint("LEFT", row.choice, "RIGHT", OL.UI:P(4), 0)
	row.back:Hide()

	row.noteLabel = OL.UI:Text(row.controls, "OVERLAY", "GameFontDisableSmall")
	local noteH = OL.UI:P(18)
	row.noteLabel:SetPoint("BOTTOMLEFT", row.controls, "BOTTOMLEFT", 0, gap)
	row.noteLabel:SetText("NB")
	local labelW = OL.UI:Snap((row.noteLabel:GetStringWidth() or 0) + OL.UI:Pixel())
	if not labelW or labelW < OL.UI:P(14) then
		labelW = OL.UI:P(14)
	end
	row.save = OL.UI:FlatButton(row.controls, "Save", 40, 18)
	row.save:SetPoint("BOTTOMRIGHT", row.controls, "BOTTOMRIGHT", 0, gap)
	row.noteFrame = CreateFrame("Frame", nil, row.controls, "BackdropTemplate")
	row.noteFrame:SetHeight(noteH)
	row.noteFrame:SetPoint("BOTTOMLEFT", row.controls, "BOTTOMLEFT", OL.UI:Snap(labelW + gap), gap)
	row.noteFrame:SetPoint("BOTTOMRIGHT", row.save, "BOTTOMLEFT", -gap, 0)
	row.noteFrame:SetBackdrop({ bgFile = OL.UI.WHITE })
	row.noteFrame:SetBackdropColor(0.07, 0.07, 0.08, 1)
	OL.UI:Hairline(row.noteFrame, 0.26, 0.26, 0.28, 1)
	row.noteBox = CreateFrame("EditBox", nil, row.noteFrame)
	local inset = OL.UI:Pixel()
	row.noteBox:SetPoint("TOPLEFT", inset, -inset)
	row.noteBox:SetPoint("BOTTOMRIGHT", -inset, inset)
	row.noteBox:SetAutoFocus(false)
	row.noteBox:SetFontObject(GameFontHighlightSmall)
	OL.UI:Face(row.noteBox)
	row.noteBox:SetMaxLetters(80)
	row.noteBox:SetTextInsets(inset, inset, 0, 0)

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
	row.compact = self.compact
	row.link:SetShown(not self.compact)
	row.meta:SetShown(not self.compact)
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
			local atTop = self:AtTop(row)
			OL.Session:SetResponse(index, button.responseId, item.myNote)
			if atTop then
				self:Advance(row)
			end
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
		row.choice:SetText(OL:ResponseText(item.myResponse))
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
	local height = OL.UI:P(ROW_HEIGHT)
	row:SetHeight(height)
	return height
end
