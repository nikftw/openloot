local OL = OpenLoot

OL.CouncilFrame = {}
local Frame = OL.CouncilFrame

local RESPONSE_ORDER = {
	BIS = 1,
	UPGRADE = 2,
	OFFSPEC = 3,
}

local function noteOrder(note)
	local text = tostring(note or ""):lower():match("^%s*(.-)%s*$") or ""
	if text == "main" then
		return 0
	end
	local clone = text:match("^clone%s*(%d+)$")
	if clone then
		return tonumber(clone)
	end
	return 1000
end

local function byRank(a, b)
	if a.pass ~= b.pass then
		return not a.pass
	end
	if a.group ~= b.group then
		return a.group < b.group
	end
	if a.rank ~= b.rank then
		return a.rank < b.rank
	end
	return a.lower < b.lower
end

local function hideTip()
	OL.UI:HideTip()
end

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

local function walkCols(apply)
	local x = 0
	local gap = OL.UI:P(4)
	for _, col in ipairs(COLS) do
		local width = OL.UI:P(col.width)
		apply(col, gap + x, width)
		x = x + width + gap
	end
end

function Frame:Ensure()
	if self.frame then
		return
	end
	local frame = OL.UI:CreateWindow("OpenLoot Council", 790, 430)
	if not frame.gripSized then
		local height = OL.UI:Snap(OL.UI:P(430) - 7 * OL.UI:Pixel())
		frame:SetHeight(height)
		frame.expandedHeight = height
	end
	frame.CloseAction = function()
		if UnitIsGroupLeader("player") and OL.Session and OL.Session:IsActive() then
			OL.Session:End()
		end
	end
	local edge = OL.UI:Pixel()
	local side = OL.UI:P(4)
	local inner = side - edge
	if inner < edge then
		inner = edge
	end
	frame.content:SetPoint("BOTTOMRIGHT", -side, inner + edge)
	self.frame = frame
	OL:WatchWindow(frame, "council")
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
	self.skip:SetScript("OnClick", function()
		OL.Session:Close(self.selected, "skip")
	end)
	self.disenchant:SetScript("OnClick", function()
		OL.Session:Close(self.selected, "disenchant")
	end)
	self.itemText = OL.UI:Text(self.main, "OVERLAY", "GameFontHighlight")
	self.itemText:SetPoint("TOPLEFT", 2 * OL.UI:Pixel(), 0)
	self.itemText:SetPoint("TOPRIGHT", self.skip, "TOPLEFT", -4, 0)
	self.itemText:SetJustifyH("LEFT")
	self.itemText:SetWordWrap(false)
	self.itemIlvl = OL.UI:Text(self.main, "OVERLAY", "GameFontHighlightSmall")
	self.itemIlvl:SetPoint("TOPLEFT", 2 * OL.UI:Pixel(), -22)
	self.itemIlvl:SetPoint("TOPRIGHT", 0, -22)
	self.itemIlvl:SetJustifyH("LEFT")
	self.itemIlvl:SetWordWrap(false)

	self.header = CreateFrame("Frame", nil, self.main)
	self.header:SetPoint("TOPLEFT", 0, -OL.UI:P(38))
	self.header:SetPoint("TOPRIGHT", 0, -OL.UI:P(38))
	self.header:SetHeight(OL.UI:P(16))
	walkCols(function(col, left, width)
		local label = OL.UI:Text(self.header, "OVERLAY", "GameFontDisableSmall")
		label:SetPoint("LEFT", self.header, "LEFT", left, 0)
		label:SetWidth(width)
		label:SetJustifyH("LEFT")
		label:SetText(col.label)
	end)

	local scroll = OL.UI:CreateScroll(self.main)
	scroll:SetPoint("TOPLEFT", 0, -OL.UI:P(58))
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
	local iconSize = OL.UI:P(36)
	local colStep = OL.UI:P(40)
	local rowStep = OL.UI:Snap(iconSize + 3 * OL.UI:Pixel())
	local iconWidth = (cols - 1) * colStep + iconSize
	self.iconPane:SetWidth(iconWidth)
	if not self.frame.collapsed then
		local want = iconWidth + 788
		if not self.frame.userSized or self.frame:GetWidth() < want then
			self.frame:SetWidth(want)
		end
		self.frame.expandedHeight = self.frame:GetHeight()
	end

	local roster = OL.Session:Roster()
	local total = #roster
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
		button:SetPoint("TOPLEFT", self.iconPane, "TOPLEFT", col * colStep, -row * rowStep)
		button:SetIcon(item.texture)
		local responded = 0
		for _, member in ipairs(roster) do
			local vote = item.votes[member.short]
			if vote and vote.response and vote.response ~= "" then
				responded = responded + 1
			end
		end
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
		button.index = index
		button.link = item.link
		button:Show()
	end
	for index = count + 1, #self.icons do
		self.icons[index]:Hide()
	end

	local item = items[self.selected]
	local open = item and not item.awardedTo and not item.closed
	self.skip:SetShown(open and true or false)
	self.disenchant:SetShown(open and true or false)
	local namePad = 2 * OL.UI:Pixel()
	self.itemText:ClearAllPoints()
	self.itemText:SetPoint("LEFT", self.main, "TOPLEFT", namePad, -9)
	if open then
		self.itemText:SetPoint("RIGHT", self.skip, "LEFT", -4, 0)
	else
		self.itemText:SetPoint("RIGHT", self.main, "TOPRIGHT", 0, -9)
	end
	self.itemText:SetText(item and item.link or "No items")
	self.itemIlvl:ClearAllPoints()
	self.itemIlvl:SetPoint("TOPLEFT", namePad, -22)
	self.itemIlvl:SetPoint("TOPRIGHT", 0, -22)
	self.itemIlvl:SetText(item and OL.Items:RowMeta(item) or "")
	self:FillRoster(item, item and roster or {})
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
end

local function iconClick(button)
	Frame.selected = button.index
	Frame:Refresh()
end

local function iconEnter(button)
	OL.UI:ItemTip(button, button.link)
end

function Frame:CreateIcon()
	local button = OL.UI:Icon(self.iconPane, 36)
	button:EnableMouse(true)
	button:SetScript("OnClick", iconClick)
	button:SetScript("OnEnter", iconEnter)
	button:SetScript("OnLeave", hideTip)
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

local sorted = {}

function Frame:FillRoster(item, shared)
	wipe(sorted)
	local roster = sorted
	if item then
		for index, member in ipairs(shared) do
			local vote = item.votes[member.short]
			local response = vote and vote.response or nil
			local info = OL.Council:Info(member.name)
			sorted[index] = {
				name = member.name,
				short = member.short,
				classFile = member.classFile,
				pass = response == "PASS",
				group = noteOrder(info and info.officerNote or ""),
				rank = RESPONSE_ORDER[response] or 4,
				lower = member.short:lower(),
			}
		end
		table.sort(sorted, byRank)
	end
	local done = item and (item.awardedTo ~= nil or item.closed ~= nil) or false
	local mine = OL:Me()
	local y = 0
	for rowIndex, member in ipairs(roster) do
		local row = self.rows[rowIndex]
		if not row then
			row = self:CreateRow(self.scroll.content)
			self.rows[rowIndex] = row
		end
		self:FillRow(row, member, item, mine)
		row.awarded = done
		if done then
			row.actions:Hide()
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", self.scroll.content, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", self.scroll.content, "RIGHT", 0, 0)
		row:Show()
		y = y + OL.UI:P(26)
	end
	for rowIndex = #roster + 1, #self.rows do
		self:ClearRowHover(self.rows[rowIndex])
		self.rows[rowIndex]:Hide()
	end
	self.scroll.content:SetHeight(math.max(1, y))
end

local function rowOf(widget)
	while widget and not widget.isCouncilRow do
		widget = widget:GetParent()
	end
	return widget
end

local function rowEnter(widget)
	Frame:HoverRow(rowOf(widget))
end

local function rowLeave(widget)
	Frame:QueueHoverCheck(rowOf(widget))
end

local function tipLeave(widget)
	OL.UI:HideTip()
	Frame:QueueHoverCheck(rowOf(widget))
end

local function noteEnter(cell)
	local row = rowOf(cell)
	OL.UI:NoteTip(cell, row.note)
	Frame:HoverRow(row)
end

local function votesEnter(cell)
	local row = rowOf(cell)
	Frame:HoverRow(row)
	if not row.voters then
		return
	end
	GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
	GameTooltip:AddLine("Votes", 1, 1, 1)
	GameTooltip:AddLine(row.voters, 0.9, 0.9, 0.9, true)
	GameTooltip:Show()
end

local function gearEnter(icon)
	OL.UI:ItemTip(icon, icon.link)
	Frame:HoverRow(rowOf(icon))
end

local function voteClick(button)
	OL.Session:CastBallot(Frame.selected, rowOf(button).short)
end

local function awardClick(button)
	OL.Session:Award(Frame.selected, rowOf(button).short)
end

function Frame:CreateRow(parent)
	local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	row.isCouncilRow = true
	row:SetHeight(OL.UI:P(26))
	row:SetBackdrop({ bgFile = OL.UI.WHITE })
	row:SetBackdropColor(0.1, 0.1, 0.12, 1)
	row:EnableMouse(true)
	row.cells = {}
	walkCols(function(col, left, width)
		local cell = CreateFrame("Frame", nil, row)
		cell:SetPoint("LEFT", row, "LEFT", left, 0)
		cell:SetSize(width, OL.UI:P(26))
		cell:SetClipsChildren(true)
		cell:EnableMouse(col.key == "playerNote" or col.key == "votes")
		if col.key == "playerNote" then
			cell.icon = cell:CreateTexture(nil, "ARTWORK")
			cell.icon:SetSize(10, 12)
			cell.icon:SetPoint("LEFT", 0, 0)
			cell.icon:SetTexture(OL.UI.WHITE)
			cell.icon:SetVertexColor(0.45, 0.45, 0.45, 1)
			cell:SetScript("OnEnter", noteEnter)
			cell:SetScript("OnLeave", tipLeave)
		elseif col.key == "s1" or col.key == "s2" then
			cell.icon = OL.UI:Icon(cell, 18)
			cell.icon:SetPoint("LEFT", 0, 0)
			cell.icon:SetScript("OnEnter", gearEnter)
			cell.icon:SetScript("OnLeave", tipLeave)
		else
			cell.text = OL.UI:Text(cell, "OVERLAY", "GameFontHighlightSmall")
			cell.text:SetAllPoints()
			cell.text:SetJustifyH("LEFT")
		end
		if col.key == "votes" then
			cell:SetScript("OnEnter", votesEnter)
			cell:SetScript("OnLeave", tipLeave)
		end
		row.cells[col.key] = cell
	end)
	row.actions = CreateFrame("Frame", nil, row)
	row.actions:SetSize(118, 18)
	row.actions:SetPoint("RIGHT", -4, 0)
	row.actions.vote = OL.UI:FlatButton(row.actions, "Vote", 52, 18)
	row.actions.vote:SetPoint("LEFT", 0, 0)
	row.actions.vote:SetScript("OnClick", voteClick)
	row.actions.award = OL.UI:FlatButton(row.actions, "Award", 58, 18)
	row.actions.award:SetPoint("LEFT", row.actions.vote, "RIGHT", 4, 0)
	row.actions.award:SetScript("OnClick", awardClick)
	row.actions:EnableMouse(true)
	row.actions:Hide()
	row:SetScript("OnEnter", rowEnter)
	row:SetScript("OnLeave", rowLeave)
	row.actions:SetScript("OnEnter", rowEnter)
	row.actions:SetScript("OnLeave", rowLeave)
	row.actions.vote:HookScript("OnEnter", rowEnter)
	row.actions.vote:HookScript("OnLeave", rowLeave)
	row.actions.award:HookScript("OnEnter", rowEnter)
	row.actions.award:HookScript("OnLeave", rowLeave)
	return row
end

function Frame:FillRow(row, member, item, mine)
	local short = member.short
	local vote = item.votes[short]
	local info = OL.Council:Info(member.name)
	row.short = short
	row.note = vote and vote.note or nil
	row.cells.name.text:SetText(item.awardedTo == short and ("* " .. short) or short)
	row.cells.name.text:SetTextColor(OL.UI:ClassColor(member.classFile))
	row.cells.rank.text:SetText(info and info.rankName or "")
	row.cells.officerNote.text:SetText(info and info.officerNote or "")
	row.cells.response.text:SetText(vote and vote.response and OL:ResponseText(vote.response) or "")
	if row.note and row.note ~= "" then
		row.cells.playerNote.icon:SetVertexColor(1, 1, 1, 1)
	else
		row.cells.playerNote.icon:SetVertexColor(0.45, 0.45, 0.45, 1)
	end
	row.cells.slotIlvl.text:SetText(vote and vote.slotIlvl and tostring(vote.slotIlvl) or "")
	local diff = vote and vote.slotIlvl and item.ilvl and item.ilvl > 0 and (item.ilvl - vote.slotIlvl) or nil
	row.cells.diff.text:SetText(OL.UI:DiffText(diff))
	row.cells.diff.text:SetTextColor(OL.UI:DiffColor(diff))
	self:GearCell(row.cells.s1, vote and OL.Items:Unpack(vote.s1))
	self:GearCell(row.cells.s2, vote and OL.Items:Unpack(vote.s2))
	self:FillVotes(row, item, short, mine)
	row.item = item
end

local voterScratch = {}

function Frame:FillVotes(row, item, name, mine)
	local ballots = item and item.ballots or {}
	wipe(voterScratch)
	for voter, choice in pairs(ballots) do
		if choice == name then
			voterScratch[#voterScratch + 1] = voter
		end
	end
	local count = #voterScratch
	if count > 0 then
		table.sort(voterScratch)
		row.voters = table.concat(voterScratch, ", ")
	else
		row.voters = nil
	end
	local cell = row.cells.votes
	cell.text:SetText(count > 0 and tostring(count) or "")
	if ballots[mine] == name then
		cell.text:SetTextColor(1, 1, 1)
	else
		cell.text:SetTextColor(0.7, 0.7, 0.7)
	end
end

function Frame:GearCell(cell, link)
	if link and link ~= "" then
		cell.icon:Show()
		local _, _, _, _, icon = C_Item.GetItemInfoInstant(link)
		cell.icon:SetIcon(icon)
		cell.icon.link = link
	else
		cell.icon:Hide()
	end
end
