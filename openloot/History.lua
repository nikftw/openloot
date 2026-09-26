local OL = OpenLoot

OL.History = {}
local History = OL.History

function History:Init()
	self.selected = nil
	self.detailAward = nil
end

function History:Ensure(id, when)
	local store = OL.db.history
	if store.sessions[id] then
		return store.sessions[id]
	end
	local entry = { id = id, time = when or time(), awards = {} }
	store.sessions[id] = entry
	table.insert(store.order, 1, id)
	if self.frame and self.frame:IsShown() then
		self:Refresh()
	end
	return entry
end

function History:AddAward(sessionId, award)
	local session = self:Ensure(sessionId, award.time)
	session.awards[#session.awards + 1] = award
	if self.frame and self.frame:IsShown() then
		self:Refresh()
	end
	if self.detail and self.detail:IsShown() and self.detailAward == award then
		self:FillDetail(award)
	end
end

function History:Toggle()
	self:EnsureFrame()
	if self.frame:IsShown() then
		self.frame:Hide()
		if self.detail then
			self.detail:Hide()
		end
	else
		self.frame:Show()
		self:Refresh()
	end
end

function History:EnsureFrame()
	if self.frame then
		return
	end
	local frame = OL.UI:CreateWindow("OpenLoot History", 640, 420)
	self.frame = frame
	self.sessionButtons = {}
	self.awardRows = {}

	self.sessionPane = CreateFrame("Frame", nil, frame.content)
	self.sessionPane:SetPoint("TOPLEFT", 0, 0)
	self.sessionPane:SetPoint("BOTTOMLEFT", 0, 0)
	self.sessionPane:SetWidth(130)

	local sessionScroll = OL.UI:CreateScroll(self.sessionPane)
	sessionScroll:SetAllPoints()
	self.sessionScroll = sessionScroll

	self.main = CreateFrame("Frame", nil, frame.content)
	self.main:SetPoint("TOPLEFT", self.sessionPane, "TOPRIGHT", 8, 0)
	self.main:SetPoint("BOTTOMRIGHT", 0, 0)

	self.header = self.main:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	self.header:SetPoint("TOPLEFT", 0, 0)
	self.header:SetText("Name    Time    Item    Response")

	local scroll = OL.UI:CreateScroll(self.main)
	scroll:SetPoint("TOPLEFT", 0, -18)
	scroll:SetPoint("BOTTOMRIGHT", 0, 0)
	self.scroll = scroll

	local detail = OL.UI:CreateWindow("OpenLoot Session", 760, 360)
	detail:SetFrameStrata("HIGH")
	self.detail = detail
	self.detailRows = {}
	self.detailTitle = detail.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	self.detailTitle:SetPoint("TOPLEFT", 0, 0)
	self.detailTitle:SetPoint("TOPRIGHT", 0, 0)
	self.detailTitle:SetJustifyH("LEFT")
	self.detailHeader = detail.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	self.detailHeader:SetPoint("TOPLEFT", 0, -18)
	self.detailHeader:SetText("Name    Rank    Note    Response    ilvl    Diff    s1    s2    Roll")
	self.detailScroll = OL.UI:CreateScroll(detail.content)
	self.detailScroll:SetPoint("TOPLEFT", 0, -36)
	self.detailScroll:SetPoint("BOTTOMRIGHT", 0, 0)
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
	local y = 0
	for index, id in ipairs(order) do
		local button = self.sessionButtons[index]
		if not button then
			button = OL.UI:FlatButton(self.sessionScroll.content, "", 120, 22)
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
				if self.selected == id then
					self.selected = nil
				else
					self.selected = id
				end
				self:Refresh()
			end)
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", self.sessionScroll.content, "TOPLEFT", 0, -y)
			button:Show()
			y = y + 26
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
		row.icon:SetScript("OnEnter", function(selfIcon)
			OL.UI:ItemTip(selfIcon, award.link)
		end)
		row.name:SetText(award.winner or "")
		row.time:SetText(date("%H:%M", award.time or entry.session.time))
		row.link:SetText(award.link or "")
		row.response:SetText(award.response and OL:ResponseText(award.response) or "")
		row:SetScript("OnMouseUp", function()
			self:ShowDetail(award)
		end)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", self.scroll.content, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", self.scroll.content, "RIGHT", 0, 0)
		row:Show()
		y = y + 28
	end
	for index = #awards + 1, #self.awardRows do
		self.awardRows[index]:Hide()
	end
	self.scroll.content:SetHeight(math.max(1, y))
end

function History:CreateAwardRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(26)
	row:EnableMouse(true)
	row.icon = OL.UI:Icon(row, 22)
	row.icon:SetPoint("LEFT", 0, 0)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.name:SetWidth(90)
	row.name:SetJustifyH("LEFT")
	row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.time:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
	row.time:SetWidth(48)
	row.link = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.link:SetPoint("LEFT", row.time, "RIGHT", 4, 0)
	row.link:SetWidth(220)
	row.link:SetJustifyH("LEFT")
	row.response = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.response:SetPoint("LEFT", row.link, "RIGHT", 4, 0)
	row.response:SetJustifyH("LEFT")
	row.icon:SetScript("OnLeave", function()
		OL.UI:HideTip()
	end)
	return row
end

function History:ShowDetail(award)
	self:EnsureFrame()
	self.detailAward = award
	self.detail:Show()
	self:FillDetail(award)
end

function History:FillDetail(award)
	self.detailTitle:SetText((award.winner or "") .. "  " .. (award.link or ""))
	local cols = {
		{ key = "name", width = 110 },
		{ key = "rank", width = 80 },
		{ key = "officerNote", width = 72 },
		{ key = "response", width = 72 },
		{ key = "slotIlvl", width = 40 },
		{ key = "diff", width = 40 },
		{ key = "s1", width = 24 },
		{ key = "s2", width = 24 },
		{ key = "roll", width = 36 },
	}
	local y = 0
	for index, data in ipairs(award.rows or {}) do
		local row = self.detailRows[index]
		if not row then
			row = CreateFrame("Frame", nil, self.detailScroll.content)
			row:SetHeight(22)
			row.cells = {}
			local x = 0
			for _, col in ipairs(cols) do
				local cell = CreateFrame("Frame", nil, row)
				cell:SetPoint("LEFT", x, 0)
				cell:SetSize(col.width, 22)
				cell:EnableMouse(true)
				if col.key == "s1" or col.key == "s2" then
					cell.icon = OL.UI:Icon(cell, 18)
					cell.icon:SetPoint("LEFT")
				else
					cell.text = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
					cell.text:SetAllPoints()
					cell.text:SetJustifyH("LEFT")
				end
				row.cells[col.key] = cell
				x = x + col.width + 4
			end
			self.detailRows[index] = row
		end
		local winner = data.name == award.winner
		row.cells.name.text:SetText(winner and ("* " .. data.name) or data.name)
		row.cells.name.text:SetTextColor(OL.UI:ClassColor(data.class))
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
		self:Gear(row.cells.s1, data.s1)
		self:Gear(row.cells.s2, data.s2)
		row.cells.roll.text:SetText(data.roll and tostring(data.roll) or "")
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", self.detailScroll.content, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", self.detailScroll.content, "RIGHT", 0, 0)
		row:Show()
		y = y + 22
	end
	for index = #(award.rows or {}) + 1, #self.detailRows do
		self.detailRows[index]:Hide()
	end
	self.detailScroll.content:SetHeight(math.max(1, y))
end

function History:Gear(cell, link)
	if link and link ~= "" and C_Item.GetItemInfoInstant(link) then
		local _, _, _, _, icon = C_Item.GetItemInfoInstant(link)
		cell.icon:Show()
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
