local OL = OpenLoot

OL.CouncilFrame = {}
local Frame = OL.CouncilFrame

local COLS = {
	{ key = "name", label = "Name", width = 150 },
	{ key = "rank", label = "Rank", width = 108 },
	{ key = "officerNote", label = "Note", width = 72 },
	{ key = "response", label = "Response", width = 72 },
	{ key = "playerNote", label = "", width = 22 },
	{ key = "slotIlvl", label = "ilvl", width = 40 },
	{ key = "diff", label = "Diff", width = 40 },
	{ key = "s1", label = "s1", width = 24 },
	{ key = "s2", label = "s2", width = 24 },
	{ key = "votes", label = "Votes", width = 44 },
}

function Frame:Ensure()
	if self.frame then
		return
	end
	local frame = OL.UI:CreateWindow("OpenLoot Council", 790, 432)
	self.frame = frame
	self.selected = 1
	self.icons = {}
	self.rows = {}

	self.iconPane = CreateFrame("Frame", nil, frame.content)
	self.iconPane:SetPoint("TOPLEFT", 0, 0)
	self.iconPane:SetPoint("BOTTOMLEFT", 0, 0)
	self.iconPane:SetWidth(40)
	self.iconPane:SetFrameLevel(frame:GetFrameLevel() + 20)

	self.main = CreateFrame("Frame", nil, frame.content)
	self.main:SetPoint("TOPLEFT", self.iconPane, "TOPRIGHT", 4, 0)
	self.main:SetPoint("BOTTOMRIGHT", 0, 0)

	self.disenchant = OL.UI:FlatButton(self.main, "Disenchant", 96, 18)
	self.disenchant:SetPoint("TOPRIGHT", 0, 0)
	self.skip = OL.UI:FlatButton(self.main, "Skip", 52, 18)
	self.skip:SetPoint("TOPRIGHT", self.disenchant, "TOPLEFT", -4, 0)
	self.itemText = OL.UI:Text(self.main, "OVERLAY", "GameFontHighlight")
	self.itemText:SetPoint("TOPLEFT", 0, 0)
	self.itemText:SetPoint("TOPRIGHT", self.skip, "TOPLEFT", -4, 0)
	self.itemText:SetJustifyH("LEFT")
	self.itemText:SetWordWrap(false)
	self.itemIlvl = OL.UI:Text(self.main, "OVERLAY", "GameFontHighlightSmall")
	self.itemIlvl:SetPoint("TOPLEFT", 0, -16)
	self.itemIlvl:SetPoint("TOPRIGHT", 0, -16)
	self.itemIlvl:SetJustifyH("LEFT")
	self.itemIlvl:SetWordWrap(false)

	self.header = CreateFrame("Frame", nil, self.main)
	self.header:SetPoint("TOPLEFT", 0, -32)
	self.header:SetPoint("TOPRIGHT", 0, -32)
	self.header:SetHeight(16)
	local x = 0
	for _, col in ipairs(COLS) do
		local label = OL.UI:Text(self.header, "OVERLAY", "GameFontDisableSmall")
		label:SetPoint("LEFT", self.header, "LEFT", 4 + x, 0)
		label:SetWidth(col.width)
		label:SetJustifyH("LEFT")
		label:SetText(col.label)
		x = x + col.width + 4
	end

	local scroll = OL.UI:CreateScroll(self.main)
	scroll:SetPoint("TOPLEFT", 0, -52)
	scroll:SetPoint("BOTTOMRIGHT", 0, 0)
	local wheel = scroll:GetScript("OnMouseWheel")
	scroll:SetScript("OnMouseWheel", function(selfScroll, delta)
		if wheel then
			wheel(selfScroll, delta)
		end
		Frame:ReleaseHover()
	end)
	self.scroll = scroll
end

function Frame:ClearRowHover(row)
	row:SetBackdropColor(0.1, 0.1, 0.12, 1)
	if row.actions then
		row.actions:Hide()
	end
end

function Frame:HoverRow(row)
	for _, other in ipairs(self.rows) do
		if other ~= row then
			self:ClearRowHover(other)
		end
	end
	if not row then
		return
	end
	row:SetBackdropColor(0.18, 0.18, 0.22, 1)
	if row.actions and not row.awarded then
		row.actions:Show()
	elseif row.actions then
		row.actions:Hide()
	end
end

function Frame:QueueHoverCheck(row)
	if row.hoverTimer then
		row.hoverTimer:Cancel()
		row.hoverTimer = nil
	end
	row.hoverTimer = C_Timer.NewTimer(0, function()
		row.hoverTimer = nil
		if row:IsShown() and row:IsMouseOver() then
			self:HoverRow(row)
		else
			self:ClearRowHover(row)
		end
	end)
end

function Frame:ReleaseHover()
	for _, row in ipairs(self.rows) do
		if row.hoverTimer then
			row.hoverTimer:Cancel()
			row.hoverTimer = nil
		end
		self:ClearRowHover(row)
	end
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
		self.frame:SetWidth(iconWidth + 788)
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
		local responded = 0
		local roster = OL.Session:Roster()
		for _, member in ipairs(roster) do
			local vote = item.votes[OL:ShortName(member.name)]
			if vote and vote.response and vote.response ~= "" then
				responded = responded + 1
			end
		end
		local total = #roster
		button.count:SetText(responded .. "/" .. total)
		local done = item.awardedTo or item.closed
		local complete = total > 0 and responded >= total
		if done then
			button.tint:SetVertexColor(0.15, 0.75, 0.28, 0.5)
			button.tint:Show()
		elseif complete then
			button.tint:SetVertexColor(0.2, 0.45, 0.95, 0.5)
			button.tint:Show()
		elseif index ~= self.selected then
			button.tint:SetVertexColor(0, 0, 0, 0.4)
			button.tint:Show()
		else
			button.tint:Hide()
		end
		button:ClearEdge()
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
	local open = item and not item.awardedTo and not item.closed
	self.skip:SetShown(open and true or false)
	self.disenchant:SetShown(open and true or false)
	if open then
		self.skip:SetScript("OnClick", function()
			OL.Session:Close(self.selected, "skip")
		end)
		self.disenchant:SetScript("OnClick", function()
			OL.Session:Close(self.selected, "disenchant")
		end)
	end
	self.itemText:ClearAllPoints()
	self.itemText:SetPoint("TOPLEFT", 0, 0)
	if open then
		self.itemText:SetPoint("TOPRIGHT", self.skip, "TOPLEFT", -4, 0)
	else
		self.itemText:SetPoint("TOPRIGHT", 0, 0)
	end
	self.itemText:SetText(item and item.link or "No items")
	self.itemIlvl:SetText(item and OL.Items:RowMeta(item) or "")
	self:FillRoster(item)
end

function Frame:AdvanceFrom(index)
	local items = OL.Session.active and OL.Session.active.items or {}
	if self.selected == index then
		local nextIndex = index + 1
		while items[nextIndex] and (items[nextIndex].awardedTo or items[nextIndex].closed) do
			nextIndex = nextIndex + 1
		end
		if items[nextIndex] then
			self.selected = nextIndex
		end
	end
	self:Refresh()
end

function Frame:CreateIcon()
	local button = OL.UI:Icon(self.iconPane, 36)
	button:EnableMouse(true)
	button:SetScript("OnLeave", function()
		OL.UI:HideTip()
	end)
	local tint = button:CreateTexture(nil, "OVERLAY")
	tint:SetDrawLayer("OVERLAY", 0)
	tint:SetAllPoints()
	tint:SetTexture(OL.UI.WHITE)
	tint:Hide()
	button.tint = tint
	local band = button:CreateTexture(nil, "OVERLAY")
	band:SetDrawLayer("OVERLAY", 1)
	band:SetTexture(OL.UI.WHITE)
	band:SetVertexColor(0, 0, 0, 0.72)
	band:SetPoint("CENTER")
	band:SetSize(36, 14)
	button.count = OL.UI:Text(button, "OVERLAY", "GameFontHighlightSmall")
	button.count:SetFont(OL.UI.FONT, 10, "")
	button.count:SetShadowOffset(0, 0)
	button.count:SetDrawLayer("OVERLAY", 2)
	button.count:SetPoint("CENTER", 0, 0)
	button.count:SetWidth(34)
	button.count:SetJustifyH("CENTER")
	button.count:SetWordWrap(false)
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
			note = vote and vote.note or nil,
			s1 = vote and vote.s1 or nil,
			s2 = vote and vote.s2 or nil,
			winner = item.awardedTo == short,
		}
		self:FillRow(row, data, item)
		row.awarded = item.awardedTo ~= nil or item.closed ~= nil
		if row.awarded then
			row.actions:Hide()
		end
		row.actions.vote:SetScript("OnClick", function()
			OL.Session:CastBallot(self.selected, short)
		end)
		row.actions.award:SetScript("OnClick", function()
			OL.UI:Prompt("OpenLoot", "Award " .. item.link .. " to " .. short .. "?", {
				{ text = "Award", onClick = function()
					OL.Session:Award(self.selected, short)
				end },
				{ text = "Cancel" },
			})
		end)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", self.scroll.content, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", self.scroll.content, "RIGHT", 0, 0)
		row:Show()
		y = y + 26
	end
	for rowIndex = #roster + 1, #self.rows do
		self:ClearRowHover(self.rows[rowIndex])
		self.rows[rowIndex]:Hide()
	end
	self.scroll.content:SetHeight(math.max(1, y))
end

function Frame:CreateRow(parent)
	local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	row:SetHeight(26)
	row:SetBackdrop({ bgFile = OL.UI.WHITE })
	row:SetBackdropColor(0.1, 0.1, 0.12, 1)
	row:EnableMouse(true)
	row.cells = {}
	local x = 0
	for _, col in ipairs(COLS) do
		local cell = CreateFrame("Frame", nil, row)
		cell:SetPoint("LEFT", row, "LEFT", 4 + x, 0)
		cell:SetSize(col.width, 26)
		cell:SetClipsChildren(true)
		cell:EnableMouse(col.key == "response" or col.key == "playerNote")
		if col.key == "playerNote" then
			cell.icon = cell:CreateTexture(nil, "ARTWORK")
			cell.icon:SetSize(10, 12)
			cell.icon:SetPoint("LEFT", 0, 0)
			cell.icon:SetTexture(OL.UI.WHITE)
			cell.icon:SetVertexColor(0.45, 0.45, 0.45, 1)
		elseif col.key == "s1" or col.key == "s2" then
			cell.icon = OL.UI:Icon(cell, 18)
			cell.icon:SetPoint("LEFT", 0, 0)
		else
			cell.text = OL.UI:Text(cell, "OVERLAY", "GameFontHighlightSmall")
			cell.text:SetAllPoints()
			cell.text:SetJustifyH("LEFT")
		end
		row.cells[col.key] = cell
		x = x + col.width + 4
	end
	row.actions = CreateFrame("Frame", nil, row)
	row.actions:SetSize(118, 18)
	row.actions:SetPoint("RIGHT", -4, 0)
	row.actions.vote = OL.UI:FlatButton(row.actions, "Vote", 52, 16)
	row.actions.vote:SetPoint("LEFT", 0, 0)
	row.actions.award = OL.UI:FlatButton(row.actions, "Award", 58, 16)
	row.actions.award:SetPoint("LEFT", row.actions.vote, "RIGHT", 4, 0)
	row.actions:EnableMouse(true)
	row.actions:Hide()
	local function enter()
		Frame:HoverRow(row)
	end
	local function leave()
		Frame:QueueHoverCheck(row)
	end
	row:SetScript("OnEnter", enter)
	row:SetScript("OnLeave", leave)
	row.actions:SetScript("OnEnter", enter)
	row.actions:SetScript("OnLeave", leave)
	row.actions.vote:HookScript("OnEnter", enter)
	row.actions.vote:HookScript("OnLeave", leave)
	row.actions.award:HookScript("OnEnter", enter)
	row.actions.award:HookScript("OnLeave", leave)
	return row
end

function Frame:FillRow(row, data, item)
	local name = row.cells.name
	name.text:SetText(data.winner and ("* " .. OL:ShortName(data.name)) or OL:ShortName(data.name))
	name.text:SetTextColor(OL.UI:ClassColor(data.class))
	row.cells.rank.text:SetText(data.rank or "")
	row.cells.officerNote.text:SetText(data.officerNote or "")
	row.cells.response.text:SetText(data.response and OL:ResponseText(data.response) or "")
	local hasNote = data.note and data.note ~= ""
	if hasNote then
		row.cells.playerNote.icon:SetVertexColor(1, 1, 1, 1)
	else
		row.cells.playerNote.icon:SetVertexColor(0.45, 0.45, 0.45, 1)
	end
	row.cells.playerNote:SetScript("OnEnter", function(cell)
		OL.UI:NoteTip(cell, data.note)
		self:HoverRow(row)
	end)
	row.cells.playerNote:SetScript("OnLeave", function()
		OL.UI:HideTip()
		self:QueueHoverCheck(row)
	end)
	row.cells.slotIlvl.text:SetText(data.slotIlvl and tostring(data.slotIlvl) or "")
	row.cells.diff.text:SetText(OL.UI:DiffText(data.diff))
	local red, green, blue = OL.UI:DiffColor(data.diff)
	row.cells.diff.text:SetTextColor(red, green, blue)
	self:GearCell(row.cells.s1, data.s1, row)
	self:GearCell(row.cells.s2, data.s2, row)
	self:FillVotes(row, item, data.name)
	row.item = item
end

function Frame:FillVotes(row, item, name)
	local ballots = item and item.ballots or {}
	local names = {}
	for voter, choice in pairs(ballots) do
		if choice == name then
			names[#names + 1] = OL:ShortName(voter)
		end
	end
	table.sort(names)
	local cell = row.cells.votes
	cell.text:SetText(#names > 0 and tostring(#names) or "")
	local mine = OL:ShortName(OL:FullName("player"))
	if ballots[mine] == name then
		cell.text:SetTextColor(1, 1, 1)
	else
		cell.text:SetTextColor(0.7, 0.7, 0.7)
	end
	cell:EnableMouse(true)
	cell:SetScript("OnEnter", function(self)
		Frame:HoverRow(row)
		if #names == 0 then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Votes", 1, 1, 1)
		GameTooltip:AddLine(table.concat(names, ", "), 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)
	cell:SetScript("OnLeave", function()
		OL.UI:HideTip()
		Frame:QueueHoverCheck(row)
	end)
end

function Frame:GearCell(cell, link, row)
	if link and link ~= "" then
		cell.icon:Show()
		local _, _, _, _, icon = C_Item.GetItemInfoInstant(link)
		cell.icon:SetIcon(icon)
		cell.icon:SetScript("OnEnter", function(self)
			OL.UI:ItemTip(self, link)
			if row then
				Frame:HoverRow(row)
			end
		end)
		cell.icon:SetScript("OnLeave", function()
			OL.UI:HideTip()
			if row then
				Frame:QueueHoverCheck(row)
			end
		end)
	else
		cell.icon:Hide()
	end
end
