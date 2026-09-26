local OL = OpenLoot

OL.UI = {}
local UI = OL.UI

UI.WHITE = "Interface\\Buttons\\WHITE8X8"
UI.ICON_CROP = { 0.08, 0.92, 0.08, 0.92 }

local function paint(frame, red, green, blue, alpha)
	frame:SetBackdrop({ bgFile = UI.WHITE, edgeFile = UI.WHITE, edgeSize = 1 })
	frame:SetBackdropColor(red, green, blue, alpha or 1)
	frame:SetBackdropBorderColor(0.22, 0.22, 0.24, 1)
end

function UI:FlatButton(parent, text, width, height)
	local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
	button:SetSize(width or 64, height or 18)
	paint(button, 0.16, 0.16, 0.18, 1)
	local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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

function UI:CircleButton(parent, text, size)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(size or 16, size or 16)
	local disc = button:CreateTexture(nil, "BACKGROUND")
	disc:SetAllPoints()
	disc:SetTexture(UI.WHITE)
	disc:SetVertexColor(0.16, 0.16, 0.18, 1)
	if disc.SetMask then
		pcall(disc.SetMask, disc, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
	end
	local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("CENTER", 0, 1)
	label:SetText(text or "")
	button.label = label
	button:SetScript("OnEnter", function(self)
		if self:IsEnabled() then
			disc:SetVertexColor(0.24, 0.24, 0.27, 1)
		end
	end)
	button:SetScript("OnLeave", function()
		disc:SetVertexColor(0.16, 0.16, 0.18, 1)
	end)
	return button
end

function UI:Icon(parent, size)
	local holder = CreateFrame("Button", nil, parent, "BackdropTemplate")
	holder:SetSize(size, size)
	holder:SetBackdrop({ bgFile = UI.WHITE })
	holder:SetBackdropColor(0, 0, 0, 0)
	local texture = holder:CreateTexture(nil, "ARTWORK")
	texture:SetAllPoints()
	texture:SetTexCoord(unpack(self.ICON_CROP))
	holder.texture = texture
	function holder:SetIcon(icon)
		texture:SetTexture(icon or "Interface\\InventoryItems\\WoWUnknownItem01")
		texture:SetTexCoord(unpack(UI.ICON_CROP))
	end
	function holder:SetEdge(red, green, blue)
		holder:SetBackdrop({ bgFile = UI.WHITE, edgeFile = UI.WHITE, edgeSize = 1 })
		holder:SetBackdropColor(0, 0, 0, 0)
		holder:SetBackdropBorderColor(red, green, blue, 1)
		texture:ClearAllPoints()
		texture:SetPoint("TOPLEFT", 1, -1)
		texture:SetPoint("BOTTOMRIGHT", -1, 1)
	end
	function holder:ClearEdge()
		holder:SetBackdrop({ bgFile = UI.WHITE })
		holder:SetBackdropColor(0, 0, 0, 0)
		texture:ClearAllPoints()
		texture:SetAllPoints()
	end
	return holder
end

function UI:CreateScroll(parent)
	local scroll = CreateFrame("ScrollFrame", nil, parent)
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

function UI:CreateWindow(title, width, height)
	local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	frame:SetSize(width, height)
	frame:SetPoint("CENTER")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:SetFrameStrata("MEDIUM")
	frame:EnableMouse(true)
	paint(frame, 0.07, 0.07, 0.08, 0.96)
	frame.expandedHeight = height

	local titleBar = CreateFrame("Button", nil, frame, "BackdropTemplate")
	titleBar:SetPoint("TOPLEFT", 0, 0)
	titleBar:SetPoint("TOPRIGHT", 0, 0)
	titleBar:SetHeight(22)
	paint(titleBar, 0.12, 0.12, 0.14, 1)
	titleBar:RegisterForDrag("LeftButton")
	titleBar:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" then
			return
		end
		self.downX, self.downY = GetCursorPosition()
		frame:StartMoving()
	end)
	titleBar:SetScript("OnMouseUp", function(self, button)
		frame:StopMovingOrSizing()
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

	local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	titleText:SetPoint("LEFT", 8, 0)
	titleText:SetText(title)
	frame.titleText = titleText

	local close = self:FlatButton(titleBar, "X", 18, 16)
	close:SetPoint("RIGHT", -3, 0)
	close:SetScript("OnClick", function()
		frame:Hide()
	end)

	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", 8, -30)
	content:SetPoint("BOTTOMRIGHT", -8, 8)
	frame.content = content
	frame.titleBar = titleBar

	function frame:ToggleCollapse()
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

	frame:Hide()
	return frame
end

local prompt
local promptQueue = {}

local function showPrompt(title, body, buttons)
	if not prompt then
		prompt = UI:CreateWindow("OpenLoot", 420, 120)
		prompt:SetFrameStrata("DIALOG")
		prompt.body = prompt.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
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
			button:SetPoint("LEFT", previous, "RIGHT", 8, 0)
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
