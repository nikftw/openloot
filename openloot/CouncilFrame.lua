local OL = OpenLoot

OL.CouncilFrame = {}
local Frame = OL.CouncilFrame

local COLS = {
	{ key = "name", label = "Name", width = 110 },
	{ key = "rank", label = "Rank", width = 80 },
	{ key = "officerNote", label = "Note", width = 72 },
	{ key = "response", label = "Response", width = 72 },
	{ key = "slotIlvl", label = "ilvl", width = 40 },
	{ key = "diff", label = "Diff", width = 40 },
	{ key = "s1", label = "s1", width = 24 },
	{ key = "s2", label = "s2", width = 24 },
	{ key = "roll", label = "Roll", width = 36 },
}

function Frame:Ensure()
	if self.frame then
		return
	end
	local frame = OL.UI:CreateWindow("OpenLoot Council", 760, 480)
	self.frame = frame
	self.selected = 1
	self.icons = {}
	self.rows = {}

	self.iconPane = CreateFrame("Frame", nil, frame.content)
	self.iconPane:SetPoint("TOPLEFT", 0, 0)
	self.iconPane:SetPoint("BOTTOMLEFT", 0, 0)
	self.iconPane:SetWidth(40)

	self.main = CreateFrame("Frame", nil, frame.content)
	self.main:SetPoint("TOPLEFT", self.iconPane, "TOPRIGHT", 8, 0)
	self.main:SetPoint("BOTTOMRIGHT", 0, 0)

	self.itemText = self.main:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	self.itemText:SetPoint("TOPLEFT", 0, 0)
	self.itemText:SetJustifyH("LEFT")
	self.itemIlvl = self.main:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.itemIlvl:SetPoint("LEFT", self.itemText, "RIGHT", 8, 0)

	self.header = CreateFrame("Frame", nil, self.main)
	self.header:SetPoint("TOPLEFT", 0, -24)
	self.header:SetPoint("TOPRIGHT", 0, -24)
	self.header:SetHeight(18)
	local x = 0
	for _, col in ipairs(COLS) do
		local label = self.header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		label:SetPoint("LEFT", self.header, "LEFT", x, 0)
		label:SetWidth(col.width)
		label:SetJustifyH("LEFT")
		label:SetText(col.label)
		x = x + col.width + 4
	end

	local scroll = OL.UI:CreateScroll(self.main)
	scroll:SetPoint("TOPLEFT", 0, -44)
	scroll:SetPoint("BOTTOMRIGHT", 0, 0)
	self.scroll = scroll
	frame:SetScript("OnHide", function()
		if self.menu then
			self.menu:Hide()
		end
	end)
end

function Frame:Show()
	self:Ensure()
	self.frame:Show()
	self:Refresh()
end

function Frame:Hide()
	if self.frame then
		self.frame:Hide()
	end
end

function Frame:Refresh()
	if not self.frame or not self.frame:IsShown() then
		return
	end
	if self.menu then
		self.menu:Hide()
	end
	local session = OL.Session.active
	local items = session and session.items or {}
	local count = #items
	if self.selected > count then
		self.selected = 1
	end
	local cols = math.max(1, math.ceil(math.max(count, 1) / 10))
	local iconWidth = cols * 40
	self.iconPane:SetWidth(iconWidth)
	if not self.frame.collapsed then
		self.frame:SetWidth(iconWidth + 720)
		self.frame.expandedHeight = self.frame:GetHeight()
	end

	for index = 1, count do
		local button = self.icons[index]
		if not button then
			button = self:CreateIcon()
			self.icons[index] = button
		end
		local item = items[index]
		local col = math.floor((index - 1) / 10)
		local row = (index - 1) % 10
		button:ClearAllPoints()
		button:SetPoint("TOPRIGHT", self.iconPane, "TOPRIGHT", -col * 40, -row * 40)
		button:SetIcon(item.texture)
		if index == self.selected then
			button:SetEdge(0.95, 0.8, 0.15)
		elseif item.awardedTo then
			button:SetEdge(0.2, 0.75, 0.24)
		else
			button:ClearEdge()
		end
		button:SetScript("OnClick", function()
			self.selected = index
			self:Refresh()
		end)
		button:SetScript("OnEnter", function(selfIcon)
			OL.UI:ItemTip(selfIcon, item.link)
		end)
		button:Show()
	end
	for index = count + 1, #self.icons do
		self.icons[index]:Hide()
	end

	local item = items[self.selected]
	self.itemText:SetText(item and item.link or "No items")
	self.itemIlvl:SetText(item and item.ilvl and item.ilvl > 0 and ("ilvl " .. item.ilvl) or "")
	self:FillRoster(item)
end

function Frame:CreateIcon()
	local button = OL.UI:Icon(self.iconPane, 36)
	button:EnableMouse(true)
	button:SetScript("OnLeave", function()
		OL.UI:HideTip()
	end)
	return button
end

function Frame:FillRoster(item)
	local roster = item and OL.Session:Roster() or {}
	local y = 0
	for rowIndex, member in ipairs(roster) do
		local row = self.rows[rowIndex]
		if not row then
			row = self:CreateRow(self.scroll.content)
			self.rows[rowIndex] = row
		end
		local short = OL:ShortName(member.name)
		local vote = item.votes[short]
		local info = OL.Council:Info(member.name)
		local data = {
			name = short,
			class = member.classFile,
			rank = info and info.rankName or "",
			officerNote = info and info.officerNote or "",
			response = vote and vote.response or nil,
			slotIlvl = vote and vote.slotIlvl or nil,
			diff = vote and vote.diff or nil,
			roll = item.rolls[short],
			note = vote and vote.note or nil,
			s1 = vote and vote.s1 or nil,
			s2 = vote and vote.s2 or nil,
			winner = item.awardedTo == short,
		}
		self:FillRow(row, data, item)
		local function openMenu(_, button)
			if button == "RightButton" and not item.awardedTo then
				self:Menu(row, item, short)
			end
		end
		row:SetScript("OnMouseUp", openMenu)
		row.cells.response:SetScript("OnMouseUp", openMenu)
		row.cells.s1.icon:SetScript("OnMouseUp", openMenu)
		row.cells.s2.icon:SetScript("OnMouseUp", openMenu)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", self.scroll.content, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", self.scroll.content, "RIGHT", 0, 0)
		row:Show()
		y = y + 22
	end
	for rowIndex = #roster + 1, #self.rows do
		self.rows[rowIndex]:Hide()
	end
	self.scroll.content:SetHeight(math.max(1, y))
end

function Frame:CreateRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(22)
	row:EnableMouse(true)
	row.cells = {}
	local x = 0
	for _, col in ipairs(COLS) do
		local cell = CreateFrame("Frame", nil, row)
		cell:SetPoint("LEFT", row, "LEFT", x, 0)
		cell:SetSize(col.width, 22)
		cell:EnableMouse(col.key == "response")
		if col.key == "s1" or col.key == "s2" then
			cell.icon = OL.UI:Icon(cell, 18)
			cell.icon:SetPoint("LEFT", 0, 0)
		else
			cell.text = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			cell.text:SetAllPoints()
			cell.text:SetJustifyH("LEFT")
		end
		row.cells[col.key] = cell
		x = x + col.width + 4
	end
	return row
end

function Frame:FillRow(row, data, item)
	local name = row.cells.name
	name.text:SetText(data.winner and ("* " .. data.name) or data.name)
	name.text:SetTextColor(OL.UI:ClassColor(data.class))
	row.cells.rank.text:SetText(data.rank or "")
	row.cells.officerNote.text:SetText(data.officerNote or "")
	row.cells.response.text:SetText(data.response and OL:ResponseText(data.response) or "")
	row.cells.response:SetScript("OnEnter", function(cell)
		OL.UI:NoteTip(cell, data.note)
	end)
	row.cells.response:SetScript("OnLeave", function()
		OL.UI:HideTip()
	end)
	row.cells.slotIlvl.text:SetText(data.slotIlvl and tostring(data.slotIlvl) or "")
	row.cells.diff.text:SetText(OL.UI:DiffText(data.diff))
	local red, green, blue = OL.UI:DiffColor(data.diff)
	row.cells.diff.text:SetTextColor(red, green, blue)
	self:GearCell(row.cells.s1, data.s1)
	self:GearCell(row.cells.s2, data.s2)
	row.cells.roll.text:SetText(data.roll and tostring(data.roll) or "")
	row.item = item
end

function Frame:GearCell(cell, link)
	if link and link ~= "" then
		cell.icon:Show()
		local _, _, _, _, icon = C_Item.GetItemInfoInstant(link)
		cell.icon:SetIcon(icon)
		cell.icon:SetScript("OnEnter", function(self)
			OL.UI:ItemTip(self, link)
		end)
		cell.icon:SetScript("OnLeave", function()
			OL.UI:HideTip()
		end)
	else
		cell.icon:Hide()
	end
end

function Frame:Menu(owner, item, name)
	local index = self.selected
	if not self.menu then
		local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
		menu:SetFrameStrata("DIALOG")
		menu:SetSize(130, 52)
		menu:SetBackdrop({ bgFile = OL.UI.WHITE, edgeFile = OL.UI.WHITE, edgeSize = 1 })
		menu:SetBackdropColor(0.1, 0.1, 0.12, 0.98)
		menu:SetBackdropBorderColor(0.3, 0.3, 0.32, 1)
		menu.award = OL.UI:FlatButton(menu, "Award", 114, 18)
		menu.award:SetPoint("TOP", 0, -6)
		menu.roll = OL.UI:FlatButton(menu, "Request roll", 114, 18)
		menu.roll:SetPoint("TOP", menu.award, "BOTTOM", 0, -4)
		menu:Hide()
		self.menu = menu
	end
	self.menu.award:SetScript("OnClick", function()
		self.menu:Hide()
		OL.UI:Prompt("OpenLoot", "Award " .. item.link .. " to " .. name .. "?", {
			{ text = "Award", onClick = function()
				OL.Session:Award(index, name)
			end },
			{ text = "Cancel" },
		})
	end)
	self.menu.roll:SetScript("OnClick", function()
		self.menu:Hide()
		OL.Session:RequestRoll(index, name)
	end)
	self.menu:ClearAllPoints()
	self.menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
	self.menu:Show()
end
