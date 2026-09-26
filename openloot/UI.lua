local OL = OpenLoot

OL.UI = {}
local UI = OL.UI

UI.WHITE = "Interface\\Buttons\\WHITE8X8"
UI.FONT = "Fonts\\ARIALN.ttf"
UI.FONT_SIZE = 12

function UI:Face(widget)
	if not widget or not widget.SetFont then
		return widget
	end
	pcall(widget.SetFont, widget, self.FONT, self.FONT_SIZE, "")
	if widget.SetShadowOffset then
		pcall(widget.SetShadowOffset, widget, 0, 0)
	end
	return widget
end

function UI:Text(parent, layer, template)
	local text = parent:CreateFontString(nil, layer or "OVERLAY", template or "GameFontHighlightSmall")
	return self:Face(text)
end
UI.ICON_CROP = { 0.08, 0.92, 0.08, 0.92 }
UI.UNKNOWN_ICON = "Interface\\InventoryItems\\WoWUnknownItem01"
UI.UNKNOWN_CROP = { 0.22, 0.78, 0.22, 0.78 }

local function missingIcon(icon)
	if not icon or icon == "" or icon == 0 or icon == "0" then
		return true
	end
	if icon == 134400 or icon == 136235 then
		return true
	end
	if type(icon) == "string" then
		local lower = icon:lower()
		if lower:find("questionmark", 1, true) or lower:find("wowunknownitem", 1, true) then
			return true
		end
	end
	return false
end

local function paint(frame, red, green, blue, alpha)
	frame:SetBackdrop({ bgFile = UI.WHITE, edgeFile = UI.WHITE, edgeSize = 1 })
	frame:SetBackdropColor(red, green, blue, alpha or 1)
	frame:SetBackdropBorderColor(0.18, 0.18, 0.2, 1)
end

function UI:FlatButton(parent, text, width, height)
	local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
	button:SetSize(width or 64, height or 18)
	paint(button, 0.16, 0.16, 0.18, 1)
	local label = self:Text(button, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("CENTER")
	button:SetFontString(label)
	button:SetText(text or "")
	button:SetScript("OnEnter", function(self)
		if self:IsEnabled() then
			self:SetBackdropColor(0.24, 0.24, 0.27, 1)
		end
	end)
	button:SetScript("OnLeave", function(self)
		local color = self.baseColor or { 0.16, 0.16, 0.18, 1 }
		self:SetBackdropColor(color[1], color[2], color[3], color[4])
	end)
	function button:SetBaseColor(red, green, blue, alpha)
		self.baseColor = { red, green, blue, alpha or 1 }
		self:SetBackdropColor(red, green, blue, alpha or 1)
	end
	return button
end

function UI:Icon(parent, size)
	local holder = CreateFrame("Button", nil, parent, "BackdropTemplate")
	holder:SetSize(size, size)
	holder:SetFrameLevel((parent:GetFrameLevel() or 0) + 10)
	holder:SetClipsChildren(true)
	holder:SetBackdrop({ bgFile = UI.WHITE })
	holder:SetBackdropColor(0, 0, 0, 1)
	local texture = holder:CreateTexture(nil, "ARTWORK")
	texture:SetAllPoints()
	texture:SetTexCoord(unpack(self.ICON_CROP))
	holder.texture = texture
	function holder:ApplyCrop()
		local crop = self.crop or UI.ICON_CROP
		texture:SetTexCoord(crop[1], crop[2], crop[3], crop[4])
	end
	function holder:SetIcon(icon)
		local missing = missingIcon(icon)
		self.crop = missing and UI.UNKNOWN_CROP or UI.ICON_CROP
		if missing then
			texture:SetTexture(UI.UNKNOWN_ICON)
		else
			texture:SetTexture(icon)
		end
		self:ApplyCrop()
		if C_Timer and C_Timer.After then
			C_Timer.After(0, function()
				local shown = texture:GetTexture()
				if missingIcon(shown) then
					holder.crop = UI.UNKNOWN_CROP
					if shown ~= UI.UNKNOWN_ICON then
						texture:SetTexture(UI.UNKNOWN_ICON)
					end
				end
				holder:ApplyCrop()
			end)
		end
	end
	function holder:SetEdge(red, green, blue)
		holder:SetBackdrop({ bgFile = UI.WHITE, edgeFile = UI.WHITE, edgeSize = 1 })
		holder:SetBackdropColor(0, 0, 0, 1)
		holder:SetBackdropBorderColor(red, green, blue, 1)
		texture:ClearAllPoints()
		texture:SetPoint("TOPLEFT", 1, -1)
		texture:SetPoint("BOTTOMRIGHT", -1, 1)
	end
	function holder:ClearEdge()
		holder:SetBackdrop({ bgFile = UI.WHITE })
		holder:SetBackdropColor(0, 0, 0, 1)
		texture:ClearAllPoints()
		texture:SetAllPoints()
	end
	return holder
end

function UI:CreateScroll(parent)
	local scroll = CreateFrame("ScrollFrame", nil, parent)
	scroll:SetClipsChildren(true)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(100, 1)
	scroll:SetScrollChild(child)
	scroll.content = child
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local nextScroll = self:GetVerticalScroll() - delta * 28
		local maxScroll = self:GetVerticalScrollRange()
		if nextScroll < 0 then
			nextScroll = 0
		elseif nextScroll > maxScroll then
			nextScroll = maxScroll
		end
		self:SetVerticalScroll(nextScroll)
	end)
	scroll:SetScript("OnSizeChanged", function(self, width)
		child:SetWidth(width)
	end)
	return scroll
end

local titleOrder = 0

local function rememberPlace(frame)
	if not OL.db or not frame.placeKey then
		return
	end
	local left = frame:GetLeft()
	local top = frame:GetTop()
	local parentLeft = UIParent:GetLeft() or 0
	local parentTop = UIParent:GetTop()
	if not left or not top or not parentTop then
		return
	end
	OL.db.frames = OL.db.frames or {}
	OL.db.frames[frame.placeKey] = { x = left - parentLeft, y = top - parentTop }
end

local function pinTop(frame)
	local left = frame:GetLeft()
	local top = frame:GetTop()
	local parentLeft = UIParent:GetLeft() or 0
	local parentTop = UIParent:GetTop()
	if not left or not top or not parentTop then
		return
	end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", left - parentLeft, top - parentTop)
	rememberPlace(frame)
end

local function placeWindow(frame)
	local saved = OL.db and OL.db.frames and frame.placeKey and OL.db.frames[frame.placeKey]
	local x = 100
	local y = -100
	if saved and saved.x and saved.y then
		x = saved.x
		y = saved.y
	end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
end

local function raiseWindow(frame)
	titleOrder = titleOrder + 1
	if titleOrder > 100 then
		titleOrder = 1
	end
	frame:Raise()
	if frame.titleBar then
		frame.titleBar:SetFrameLevel(200 + titleOrder)
	end
	if frame.closeButton and frame.titleBar then
		frame.closeButton:SetFrameLevel(frame.titleBar:GetFrameLevel() + 2)
	end
end

function UI:CreateWindow(title, width, height, placeKey)
	local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	frame:SetSize(width, height)
	frame.placeKey = placeKey or title
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:SetFrameStrata("DIALOG")
	frame:SetFrameLevel(1)
	frame:SetClipsChildren(true)
	frame:EnableMouse(true)
	paint(frame, 0.07, 0.07, 0.08, 1)
	frame:HookScript("OnShow", function(self)
		self.titleBar:Show()
		if self.closeButton then
			self.closeButton:Show()
		end
		raiseWindow(self)
	end)
	frame:HookScript("OnHide", function(self)
		self.titleBar:Hide()
		if self.closeButton then
			self.closeButton:Hide()
		end
	end)
	frame.expandedHeight = height

	local titleBar = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
	titleBar:SetParent(UIParent)
	titleBar:SetFrameStrata("FULLSCREEN")
	titleBar:SetFrameLevel(200)
	titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	titleBar:SetHeight(24)
	paint(titleBar, 0.12, 0.12, 0.14, 1)
	titleBar:Hide()
	titleBar:RegisterForDrag("LeftButton")
	titleBar:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" then
			return
		end
		self.downX, self.downY = GetCursorPosition()
		self.dragging = true
		self.moved = false
		raiseWindow(frame)
	end)
	titleBar:SetScript("OnUpdate", function(self)
		if not self.dragging or self.moved then
			return
		end
		local x, y = GetCursorPosition()
		if self.downX and (math.abs(x - self.downX) > 4 or math.abs(y - self.downY) > 4) then
			self.moved = true
			frame:StartMoving()
		end
	end)
	titleBar:SetScript("OnMouseUp", function(self, button)
		if self.moved then
			frame:StopMovingOrSizing()
			pinTop(frame)
		end
		self.dragging = false
		self.moved = false
		if button ~= "LeftButton" then
			return
		end
		local x, y = GetCursorPosition()
		local moved = self.downX and (math.abs(x - self.downX) > 4 or math.abs(y - self.downY) > 4)
		if moved then
			self.lastClick = nil
			return
		end
		if self.lastClick and GetTime() - self.lastClick <= 0.5 then
			self.lastClick = nil
			frame:ToggleCollapse()
		else
			self.lastClick = GetTime()
		end
	end)

	local titleText = self:Text(titleBar, "OVERLAY", "GameFontHighlightSmall")
	titleText:SetPoint("LEFT", 4, 0)
	titleText:SetText(title)
	frame.titleText = titleText

	local close = self:FlatButton(UIParent, "X", 16, 16)
	close:SetFrameStrata("FULLSCREEN")
	close:SetFrameLevel(titleBar:GetFrameLevel() + 2)
	close:SetPoint("RIGHT", titleBar, "RIGHT", -4, 0)
	close:Hide()
	frame.closeButton = close
	close:SetScript("OnClick", function()
		frame:Hide()
	end)

	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", 4, -27)
	content:SetPoint("BOTTOMRIGHT", -4, 3)
	frame.content = content
	frame.titleBar = titleBar

	function frame:ToggleCollapse()
		pinTop(self)
		if self.collapsed then
			self.collapsed = false
			self.content:Show()
			self:SetHeight(self.expandedHeight)
		else
			self.collapsed = true
			self.expandedHeight = self:GetHeight()
			self.content:Hide()
			self:SetHeight(self.titleBar:GetHeight())
		end
	end

	placeWindow(frame)
	frame:Hide()
	return frame
end

local prompt
local promptQueue = {}

local function showPrompt(title, body, buttons)
	if not prompt then
		prompt = UI:CreateWindow("OpenLoot", 420, 118, "OpenLoot Prompt")
		prompt:SetFrameStrata("FULLSCREEN_DIALOG")
		prompt.titleBar:SetFrameStrata("FULLSCREEN_DIALOG")
		prompt.closeButton:SetFrameStrata("FULLSCREEN_DIALOG")
		prompt:SetFrameLevel(20)
		prompt.body = UI:Text(prompt.content, "OVERLAY", "GameFontHighlight")
		prompt.body:SetPoint("TOPLEFT", 0, 0)
		prompt.body:SetPoint("TOPRIGHT", 0, 0)
		prompt.body:SetJustifyH("LEFT")
		prompt.body:SetWordWrap(true)
		prompt.buttons = {}
	end
	prompt.titleText:SetText(title)
	prompt.body:SetText(body)
	for _, button in ipairs(prompt.buttons) do
		button:Hide()
	end
	local previous
	for index, entry in ipairs(buttons) do
		local button = prompt.buttons[index]
		if not button then
			button = UI:FlatButton(prompt.content, entry.text, 90, 20)
			prompt.buttons[index] = button
		end
		button:SetText(entry.text)
		button:SetScript("OnClick", function()
			prompt:Hide()
			if entry.onClick then
				entry.onClick()
			end
			local nextPrompt = table.remove(promptQueue, 1)
			if nextPrompt then
				showPrompt(nextPrompt[1], nextPrompt[2], nextPrompt[3])
			end
		end)
		button:ClearAllPoints()
		if not previous then
			button:SetPoint("BOTTOMLEFT", prompt.content, "BOTTOMLEFT", 0, 0)
		else
			button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
		end
		button:Show()
		previous = button
	end
	prompt:Show()
end

function UI:Prompt(title, body, buttons)
	if prompt and prompt:IsShown() then
		promptQueue[#promptQueue + 1] = { title, body, buttons }
		return
	end
	showPrompt(title, body, buttons)
end

function UI:ItemTip(owner, link)
	if not link or link == "" then
		return
	end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink(link)
	GameTooltip:Show()
end

function UI:NoteTip(owner, note)
	if not note or note == "" then
		return
	end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine("Note", 1, 1, 1)
	GameTooltip:AddLine(note, 0.9, 0.9, 0.9, true)
	GameTooltip:Show()
end

function UI:HideTip()
	GameTooltip:Hide()
end

function UI:ClassColor(classFile)
	local color = classFile and RAID_CLASS_COLORS[classFile]
	if not color then
		return 1, 1, 1
	end
	return color.r, color.g, color.b
end

function UI:DiffColor(diff)
	if diff == nil then
		return 0.6, 0.6, 0.6
	end
	if diff > 0 then
		return 0.2, 0.9, 0.3
	end
	if diff < 0 then
		return 0.95, 0.25, 0.2
	end
	return 0.7, 0.7, 0.7
end

function UI:DiffText(diff)
	if diff == nil then
		return ""
	end
	if diff > 0 then
		return "+" .. diff
	end
	return tostring(diff)
end
