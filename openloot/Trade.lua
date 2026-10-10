local OL = OpenLoot

OL.Trade = {}
local Trade = OL.Trade

local function plainText(value)
	if value == nil then
		return nil
	end
	local ok, secret = pcall(function()
		return issecretvalue and issecretvalue(value)
	end)
	if ok and secret then
		return nil
	end
	if type(value) ~= "string" or value == "" then
		return nil
	end
	return value
end

local function sameLink(left, right)
	if not left or not right then
		return false
	end
	if left == right then
		return true
	end
	local leftID = C_Item.GetItemInfoInstant(left)
	local rightID = C_Item.GetItemInfoInstant(right)
	return leftID and leftID == rightID
end

function Trade:Init()
	self.list = OL.db.trades
	self.trading = false
	self.partner = nil
	self.lastTarget = nil
	self.accepted = {}
	self.rows = {}
	self:SyncListen()
end

function Trade:WatchInfo(on)
	if on and self.infoTimer then
		self.infoTimer:Cancel()
		self.infoTimer = nil
	end
	OL:Listen("UI_INFO_MESSAGE", on)
end

function Trade:SyncListen()
	local watch = self.list and #self.list > 0 or false
	OL:Listen("TRADE_SHOW", watch)
	OL:Listen("TRADE_CLOSED", watch)
	OL:Listen("TRADE_ACCEPT_UPDATE", watch)
	if not watch then
		OL:Listen("UI_INFO_MESSAGE", false)
	end
end

function Trade:Save()
	OL.db.trades = self.list
	self:SyncListen()
end

function Trade:Holds(item)
	local holder = item and item.holder and OL:ShortName(item.holder) or ""
	return holder ~= "" and holder == OL:Me()
end

function Trade:Add(item, winner, sessionId, index)
	if not item or not self:Holds(item) then
		return
	end
	local short = OL:ShortName(winner)
	if short == "" or short == OL:Me() then
		return
	end
	-- The holder's own scan says where the item sat, and has the bag's own link.
	local held = item.ref and OL.db.scan and OL.db.scan[item.ref]
	if held and not sameLink(held.link, item.link) then
		held = nil
	end
	local key = tostring(sessionId or "") .. ":" .. tostring(index or item.link)
	local entry
	for _, existing in ipairs(self.list) do
		if existing.key == key then
			entry = existing
			break
		end
	end
	if not entry then
		entry = { key = key }
		self.list[#self.list + 1] = entry
	end
	entry.winner = short
	entry.link = held and held.link or item.link
	entry.texture = item.texture
	entry.bag = held and held.bag
	entry.slot = held and held.slot
	entry.guid = held and held.guid
	self:Save()
	self:Show()
end

function Trade:ShowIfPending()
	if #self.list > 0 then
		self:Show()
	end
end

function Trade:Show()
	if #self.list == 0 then
		if OL.Session:IsHolder() then
			OL:Print("No trades waiting.")
		end
		self:Hide()
		return
	end
	self:Ensure()
	if not self.frame.userSized then
		self.frame:SetWidth(OL.UI:Snap(310))
	end
	self.frame:Show()
	self:WatchRange(true)
	self:Refresh()
end

function Trade:Hide()
	self:WatchRange(false)
	if self.frame then
		self.frame:Hide()
	end
end

function Trade:WatchRange(on)
	if self.rangeTimer then
		self.rangeTimer:Cancel()
		self.rangeTimer = nil
	end
	if on then
		self.rangeTimer = C_Timer.NewTicker(1, function()
			self:PaintRange()
		end)
	end
end

function Trade:Ensure()
	if self.frame then
		return
	end
	local frame = OL.UI:CreateWindow("OpenLoot Trades", 310, 200)
	self.frame = frame
	OL:WatchWindow(frame, "trade")
	frame:HookScript("OnHide", function()
		self:WatchRange(false)
	end)
	self.scroll = OL.UI:CreateScroll(frame.content)
	self.scroll:SetPoint("TOPLEFT", 0, 0)
	self.scroll:SetPoint("BOTTOMRIGHT", 0, 0)
end

function Trade:ClassOf(name)
	local member = OL:Roster().byShort[name]
	return member and member.classFile or nil
end

function Trade:InRange(name)
	if not name or name == "" then
		return false
	end
	local unit = OL:GroupUnit(name)
	if not unit or not CheckInteractDistance then
		return false
	end
	local ok, near = pcall(CheckInteractDistance, unit, 2)
	return ok and near or false
end

function Trade:WinnerColor(name)
	if self:InRange(name) then
		return 0.2, 0.9, 0.3
	end
	return OL.UI:ClassColor(self:ClassOf(name))
end

function Trade:PaintRange()
	if not self.frame or not self.frame:IsShown() or not self.rows then
		return
	end
	for index, entry in ipairs(self.list) do
		local row = self.rows[index]
		if row and row:IsShown() and row.winner then
			row.winner:SetTextColor(self:WinnerColor(entry.winner))
		end
	end
end

function Trade:Refresh()
	if not self.frame or not self.frame:IsShown() then
		return
	end
	local rowH = OL.UI:P(30)
	local stride = OL.UI:Snap(rowH + 3 * OL.UI:Pixel())
	local y = 0
	for index, entry in ipairs(self.list) do
		local row = self.rows[index]
		if not row then
			row = self:CreateRow(self.scroll.content)
			self.rows[index] = row
		end
		row.icon:SetIcon(entry.texture or select(5, C_Item.GetItemInfoInstant(entry.link)))
		row.icon:SetScript("OnEnter", function(icon)
			OL.UI:ItemTip(icon, entry.link)
		end)
		row.link:SetText(entry.link or "")
		row.winner:SetText(OL:ShortName(entry.winner or ""))
		row.winner:SetTextColor(self:WinnerColor(entry.winner))
		row.trade:SetScript("OnClick", function()
			self:Start(entry)
		end)
		row.remove:SetScript("OnClick", function(button)
			if button.lastClick and GetTime() - button.lastClick <= 0.5 then
				button.lastClick = nil
				self:Remove(entry.key)
			else
				button.lastClick = GetTime()
			end
		end)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", self.scroll.content, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", self.scroll.content, "RIGHT", 0, 0)
		row:Show()
		y = y + stride
	end
	for index = #self.list + 1, #self.rows do
		self.rows[index]:Hide()
	end
	self.scroll.content:SetHeight(math.max(1, y))
	if not self.frame.collapsed and not self.frame.gripSized then
		local contentH = 4 * stride + rowH * 0.5
		local height = OL.UI:FitHeight(contentH)
		self.frame:SetHeight(height)
		self.frame.expandedHeight = height
		if not self.frame.userSized then
			self.frame:SetWidth(OL.UI:Snap(310))
		end
	end
	if #self.list == 0 then
		self.frame:Hide()
	end
end

function Trade:CreateRow(parent)
	local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	row:SetHeight(OL.UI:P(30))
	row:SetClipsChildren(true)
	row:SetBackdrop({ bgFile = OL.UI.WHITE })
	row:SetBackdropColor(0.1, 0.1, 0.12, 1)
	row.icon = OL.UI:Icon(row, 22)
	row.icon:SetPoint("LEFT", 4, 0)
	row.icon:SetScript("OnLeave", function()
		OL.UI:HideTip()
	end)
	row.remove = OL.UI:FlatButton(row, "X", 18, 18)
	row.remove:SetPoint("RIGHT", -4, 0)
	row.remove:SetScript("OnEnter", function(button)
		GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
		GameTooltip:SetText("Double-click to remove")
		GameTooltip:Show()
	end)
	row.remove:SetScript("OnLeave", function()
		OL.UI:HideTip()
	end)
	row.trade = OL.UI:FlatButton(row, "Trade", 64, 18)
	row.trade:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
	row.winner = OL.UI:Text(row, "OVERLAY", "GameFontHighlightSmall")
	row.winner:SetWidth(72)
	row.winner:SetJustifyH("RIGHT")
	row.winner:SetPoint("RIGHT", row.trade, "LEFT", -4, 0)
	row.link = OL.UI:Text(row, "OVERLAY", "GameFontHighlightSmall")
	row.link:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
	row.link:SetPoint("RIGHT", row.winner, "LEFT", -4, 0)
	row.link:SetJustifyH("LEFT")
	return row
end

function Trade:Remove(key)
	for index, entry in ipairs(self.list) do
		if entry.key == key then
			table.remove(self.list, index)
			break
		end
	end
	self:Save()
	self:Refresh()
end

function Trade:Start(entry)
	local unit = OL:GroupUnit(entry.winner)
	if not unit then
		OL:Print(OL:ShortName(entry.winner) .. " is not in the group.")
		return
	end
	if CheckInteractDistance then
		local ok, near = pcall(CheckInteractDistance, unit, 2)
		if ok and not near then
			OL:Print("Move closer to trade with " .. OL:ShortName(entry.winner) .. ".")
			return
		end
	end
	self.lastTarget = entry.winner
	self.lastTargetAt = GetTime()
	if not pcall(InitiateTrade, unit) then
		OL:Print("Couldn't open a trade with " .. OL:ShortName(entry.winner) .. ".")
	end
end

function Trade:FrameTarget()
	if not TradeFrameRecipientNameText or not TradeFrameRecipientNameText.GetText then
		return nil
	end
	local ok, value = pcall(TradeFrameRecipientNameText.GetText, TradeFrameRecipientNameText)
	local text = ok and plainText(value) or nil
	if not text then
		return nil
	end
	return text:gsub("%s*%(%*%)%s*$", "")
end

function Trade:NpcTarget()
	if not UnitExists("NPC") or UnitIsUnit("NPC", "player") then
		return nil
	end
	local ok, name = pcall(UnitName, "NPC")
	return ok and plainText(name) or nil
end

function Trade:OnTradeClosed()
	self.trading = false
	if self.infoTimer then
		self.infoTimer:Cancel()
	end
	self.infoTimer = C_Timer.NewTimer(1, function()
		self.infoTimer = nil
		self.accepted = {}
		self:WatchInfo(false)
	end)
end

function Trade:ForWinner(name)
	local short = OL:ShortName(name)
	local matches = {}
	for _, entry in ipairs(self.list) do
		if entry.winner == short then
			matches[#matches + 1] = entry
		end
	end
	return matches
end

function Trade:PartnerFromUnit()
	if not UnitExists("NPC") or UnitIsUnit("NPC", "player") then
		return nil
	end
	for _, entry in ipairs(self.list) do
		local unit = OL:GroupUnit(entry.winner)
		if unit and UnitIsUnit(unit, "NPC") then
			return entry.winner
		end
	end
	return self:NpcTarget()
end

function Trade:OnTradeShow()
	self.trading = true
	self.accepted = {}
	self:WatchInfo(true)
	local recent = self.lastTarget
	if not self.lastTargetAt or GetTime() - self.lastTargetAt > 5 then
		recent = nil
	end
	local target = self:FrameTarget() or self:PartnerFromUnit() or recent
	if not target then
		return
	end
	self.partner = target
	local matches = self:ForWinner(target)
	if #matches > 0 then
		self:Place(matches)
	end
end

function Trade:PlaceOne(bag, slot, tradeSlot, entry)
	if not self.trading then
		return
	end
	local function fail()
		pcall(ClearCursor)
		OL:Print("Couldn't add " .. entry.link .. " to the trade.")
	end
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if not info or info.isLocked or not info.hyperlink then
		fail()
		return
	end
	pcall(ClearCursor)
	if not pcall(C_Container.PickupContainerItem, bag, slot) or not pcall(ClickTradeButton, tradeSlot) then
		fail()
	end
end

function Trade:Place(entries)
	local reserved = {}
	local tradeSlot = 1
	local maxSlots = 6
	for _, entry in ipairs(entries) do
		if tradeSlot > maxSlots then
			break
		end
		local bag, slot = OL.Items:FindTradeSlot(entry, reserved)
		if bag and slot then
			reserved[bag .. ":" .. slot] = true
			local delay = (tradeSlot - 1) * 0.1
			local placeBag, placeSlot, placeIndex = bag, slot, tradeSlot
			if delay <= 0 then
				self:PlaceOne(placeBag, placeSlot, placeIndex, entry)
			else
				C_Timer.After(delay, function()
					self:PlaceOne(placeBag, placeSlot, placeIndex, entry)
				end)
			end
			tradeSlot = tradeSlot + 1
		else
			OL:Print("Couldn't find " .. entry.link .. " in your bags.")
		end
	end
	if tradeSlot > maxSlots then
		OL:Print("Added 6 items. Trade again for the rest.")
	end
end

function Trade:OnAccept()
	self.accepted = {}
	local maxSlots = 6
	for index = 1, maxSlots do
		local ok, link = pcall(GetTradePlayerItemLink, index)
		if ok and plainText(link) then
			self.accepted[#self.accepted + 1] = link
		end
	end
end

function Trade:OnInfo(errorType, message)
	if errorType ~= LE_GAME_ERR_TRADE_COMPLETE and message ~= ERR_TRADE_COMPLETE then
		return
	end
	local partner = self.partner and OL:ShortName(self.partner) or nil
	local removed = false
	for _, link in ipairs(self.accepted) do
		local matchIndex
		local wrong
		for index, entry in ipairs(self.list) do
			if sameLink(entry.link, link) then
				if partner and entry.winner == partner then
					matchIndex = index
					wrong = nil
					break
				end
				wrong = wrong or entry
			end
		end
		if matchIndex then
			table.remove(self.list, matchIndex)
			removed = true
		elseif wrong then
			local other = partner and OL:ShortName(partner) or "someone else"
			OL:Print(wrong.link .. " was traded to " .. other .. " instead of " .. OL:ShortName(wrong.winner) .. ".")
		end
	end
	if removed then
		self:Save()
		self:Refresh()
	end
	self.accepted = {}
end
