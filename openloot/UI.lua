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

local function parentPoint(frame)
	local frameScale = frame:GetEffectiveScale()
	local parentScale = UIParent:GetEffectiveScale()
	if not frameScale or frameScale == 0 or not parentScale or parentScale == 0 then
		return nil
	end
	local left = frame:GetLeft()
	local top = frame:GetTop()
	local parentTop = UIParent:GetTop()
	if not left or not top or not parentTop then
		return nil
	end
	local x = left * frameScale / parentScale - (UIParent:GetLeft() or 0)
	local y = top * frameScale / parentScale - parentTop
	return x, y
end

local function clampPoint(frame, x, y)
	local frameScale = frame:GetEffectiveScale()
	local parentScale = UIParent:GetEffectiveScale()
	local width = frame:GetWidth() * frameScale / parentScale
	local height = frame:GetHeight() * frameScale / parentScale
	local parentWidth = UIParent:GetWidth()
	local parentHeight = UIParent:GetHeight()
	if width >= parentWidth then
		x = 0
	elseif x < 0 then
		x = 0
	elseif x > parentWidth - width then
		x = parentWidth - width
	end
	if height >= parentHeight then
		y = 0
	elseif y > 0 then
		y = 0
	elseif y < height - parentHeight then
		y = height - parentHeight
	end
	return x, y
end

local function rememberPlace(frame, x, y)
	if not OL.db or not frame.placeKey then
		return
	end
	if not x or not y then
		x, y = parentPoint(frame)
	end
	if not x or not y then
		return
	end
	OL.db.frames = OL.db.frames or {}
	OL.db.frames[frame.placeKey] = {
		x = x,
		y = y,
		w = frame:GetWidth(),
		h = frame:GetHeight(),
		a = frame.alphaValue or 1,
		s = frame.scaleValue or 1,
	}
end

local function pinTop(frame)
	local x, y = parentPoint(frame)
	if not x then
		return
	end
	x, y = clampPoint(frame, x, y)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
	rememberPlace(frame, x, y)
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
	if saved and saved.w and saved.h and saved.w > 40 and saved.h > 24 then
		frame:SetSize(saved.w, saved.h)
		frame.userSized = true
	end
	if frame.ApplyAlpha then
		frame:ApplyAlpha((saved and saved.a) or 1)
	end
	if frame.alphaSlider then
		frame.alphaSlider:SetValue(frame.alphaValue or 1)
	end
	if frame.ApplyScale then
		frame:ApplyScale((saved and saved.s) or 1)
	end
	if frame.scaleSlider then
		frame.scaleSlider:SetValue(frame.scaleValue or 1)
		frame.scaleSlider:SetScale(frame.scaleValue or 1)
	end
end

local function raiseWindow(frame)
	titleOrder = titleOrder + 1
	if titleOrder > 40 then
		titleOrder = 1
	end
	local strata = frame:GetFrameStrata() or "DIALOG"
	local level = 10 + titleOrder * 6
	frame:SetFrameLevel(level)
	local function lift(widget, offset)
		if not widget then
			return
		end
		widget:SetFrameStrata(strata)
		widget:SetFrameLevel(level + offset)
	end
	lift(frame.titleBar, 2)
	lift(frame.closeButton, 4)
	lift(frame.alphaSlider, 4)
	lift(frame.scaleSlider, 4)
	if frame.grip then
		frame.grip:SetFrameStrata(strata)
		frame.grip:SetFrameLevel(level + 80)
	end
end

function UI:CreateWindow(title, width, height, placeKey)
	local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	frame:SetSize(width, height)
	frame.placeKey = placeKey or title
	frame:SetMovable(true)
	frame:SetClampedToScreen(false)
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
		if self.alphaSlider then
			self.alphaSlider:Show()
		end
		if self.scaleSlider then
			self.scaleSlider:Show()
		end
		if self.grip then
			self.grip:SetShown(not self.collapsed)
		end
		raiseWindow(self)
	end)
	frame:HookScript("OnHide", function(self)
		self.titleBar:Hide()
		if self.closeButton then
			self.closeButton:Hide()
		end
		if self.alphaSlider then
			self.alphaSlider:Hide()
		end
		if self.scaleSlider then
			self.scaleSlider:Hide()
		end
		self.sizing = false
	end)
	frame.expandedHeight = height

	local titleBar = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
	titleBar:SetParent(UIParent)
	titleBar:SetFrameStrata("DIALOG")
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
		if not self.dragging then
			return
		end
		local x, y = GetCursorPosition()
		if not IsMouseButtonDown("LeftButton") then
			if self.moved then
				pinTop(frame)
			end
			self.dragging = false
			self.moved = false
			return
		end
		if not self.moved then
			if self.downX and (math.abs(x - self.downX) > 4 or math.abs(y - self.downY) > 4) then
				local left = frame:GetLeft()
				local top = frame:GetTop()
				if not left or not top then
					return
				end
				local parentScale = UIParent:GetEffectiveScale()
				local frameScale = frame:GetEffectiveScale()
				self.moved = true
				self.grabX = x / parentScale - left * frameScale / parentScale
				self.grabY = y / parentScale - top * frameScale / parentScale
			end
			return
		end
		local parentScale = UIParent:GetEffectiveScale()
		local pointX = x / parentScale - self.grabX - (UIParent:GetLeft() or 0)
		local pointY = y / parentScale - self.grabY - (UIParent:GetTop() or 0)
		pointX, pointY = clampPoint(frame, pointX, pointY)
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pointX, pointY)
	end)
	titleBar:SetScript("OnMouseUp", function(self, button)
		if self.moved then
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
	close:SetFrameStrata("DIALOG")
	close:SetFrameLevel(titleBar:GetFrameLevel() + 2)
	close:SetPoint("RIGHT", titleBar, "RIGHT", -4, 0)
	close:Hide()
	frame.closeButton = close
	close:SetScript("OnClick", function()
		if frame.CloseAction then
			frame:CloseAction()
		end
		frame:Hide()
	end)

	local slider = CreateFrame("Slider", nil, UIParent)
	slider:SetFrameStrata("DIALOG")
	slider:SetFrameLevel(titleBar:GetFrameLevel() + 3)
	slider:SetSize(52, 10)
	slider:SetPoint("RIGHT", close, "LEFT", -6, 0)
	slider:SetOrientation("HORIZONTAL")
	slider:SetMinMaxValues(0.45, 1)
	slider:SetValueStep(0.05)
	if slider.SetObeyStepOnDrag then
		slider:SetObeyStepOnDrag(true)
	end
	local track = slider:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	track:SetTexture(UI.WHITE)
	track:SetVertexColor(0.07, 0.07, 0.08, 1)
	local thumb = slider:CreateTexture(nil, "OVERLAY")
	thumb:SetTexture(UI.WHITE)
	thumb:SetVertexColor(0.82, 0.82, 0.86, 1)
	slider:SetThumbTexture(thumb)
	thumb:SetSize(8, 10)
	slider:Hide()
	frame.alphaSlider = slider
	function frame:ApplyAlpha(value)
		if value < 0.45 then
			value = 0.45
		elseif value > 1 then
			value = 1
		end
		self.alphaValue = value
		self:SetAlpha(value)
		if self.titleBar then
			self.titleBar:SetAlpha(value)
		end
		if self.closeButton then
			self.closeButton:SetAlpha(value)
		end
		if self.alphaSlider then
			self.alphaSlider:SetAlpha(value)
		end
		if self.scaleSlider then
			self.scaleSlider:SetAlpha(value)
		end
	end
	slider:SetScript("OnValueChanged", function(_, value)
		frame:ApplyAlpha(value)
		rememberPlace(frame)
	end)
	local scaleSlider = CreateFrame("Slider", nil, UIParent)
	scaleSlider:SetFrameStrata("DIALOG")
	scaleSlider:SetFrameLevel(titleBar:GetFrameLevel() + 3)
	scaleSlider:SetSize(52, 10)
	scaleSlider:SetPoint("RIGHT", slider, "LEFT", -6, 0)
	scaleSlider:SetOrientation("HORIZONTAL")
	scaleSlider:SetMinMaxValues(0.5, 1)
	scaleSlider:SetValueStep(0.05)
	if scaleSlider.SetObeyStepOnDrag then
		scaleSlider:SetObeyStepOnDrag(true)
	end
	local scaleTrack = scaleSlider:CreateTexture(nil, "BACKGROUND")
	scaleTrack:SetAllPoints()
	scaleTrack:SetTexture(UI.WHITE)
	scaleTrack:SetVertexColor(0.07, 0.07, 0.08, 1)
	local scaleThumb = scaleSlider:CreateTexture(nil, "OVERLAY")
	scaleThumb:SetTexture(UI.WHITE)
	scaleThumb:SetVertexColor(0.82, 0.82, 0.86, 1)
	scaleSlider:SetThumbTexture(scaleThumb)
	scaleThumb:SetSize(8, 10)
	scaleSlider:Hide()
	frame.scaleSlider = scaleSlider
	function frame:ApplyScale(value)
		if value < 0.5 then
			value = 0.5
		elseif value > 1 then
			value = 1
		end
		self.scaleValue = value
		self:SetScale(value)
		if self.titleBar then
			self.titleBar:SetScale(value)
		end
		if self.closeButton then
			self.closeButton:SetScale(value)
		end
		if self.alphaSlider then
			self.alphaSlider:SetScale(value)
		end
		if self.grip then
			self.grip:SetScale(value)
		end
	end
	local function endScaleDrag(self)
		if not self.dragging then
			return
		end
		self.dragging = false
		self:ClearAllPoints()
		self:SetPoint("RIGHT", slider, "LEFT", -6, 0)
		self:SetScale(frame.scaleValue or 1)
		rememberPlace(frame)
	end
	local function holdScaleSlider(self)
		if self.dragging then
			return
		end
		local left = self:GetLeft()
		local bottom = self:GetBottom()
		if not left or not bottom then
			return
		end
		self.dragging = true
		self:ClearAllPoints()
		self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
	end
	scaleSlider:SetScript("OnValueChanged", function(self, value)
		if IsMouseButtonDown("LeftButton") then
			holdScaleSlider(self)
		end
		frame:ApplyScale(value)
		if self.dragging then
			return
		end
		self:SetScale(frame.scaleValue or 1)
		rememberPlace(frame)
	end)
	scaleSlider:HookScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then
			holdScaleSlider(self)
		end
	end)
	scaleSlider:HookScript("OnMouseUp", function(self, button)
		if button == "LeftButton" then
			endScaleDrag(self)
		end
	end)
	scaleSlider:SetScript("OnUpdate", function(self)
		if self.dragging and not IsMouseButtonDown("LeftButton") then
			endScaleDrag(self)
		end
	end)
	titleText:SetPoint("RIGHT", scaleSlider, "LEFT", -6, 0)
	titleText:SetJustifyH("LEFT")
	titleText:SetWordWrap(false)

	local grip = CreateFrame("Button", nil, UIParent)
	grip:SetFrameStrata("DIALOG")
	grip:SetFrameLevel(400)
	grip:SetSize(14, 14)
	grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
	local gripMark = grip:CreateTexture(nil, "OVERLAY")
	gripMark:SetTexture(UI.WHITE)
	gripMark:SetVertexColor(0.55, 0.55, 0.58, 0.9)
	gripMark:SetSize(8, 1)
	gripMark:SetPoint("BOTTOMRIGHT", -2, 3)
	local gripMark2 = grip:CreateTexture(nil, "OVERLAY")
	gripMark2:SetTexture(UI.WHITE)
	gripMark2:SetVertexColor(0.55, 0.55, 0.58, 0.9)
	gripMark2:SetSize(5, 1)
	gripMark2:SetPoint("BOTTOMRIGHT", -2, 6)
	grip:Hide()
	frame.grip = grip
	frame.minW = width * 0.6
	frame.minH = math.max(48, height * 0.5)
	frame.maxW = 1400
	frame.maxH = 1000
	local function finishSizing(target)
		if not target.sizing then
			return
		end
		target.sizing = false
		target:StopMovingOrSizing()
		target.userSized = true
		target.expandedHeight = target:GetHeight()
		pinTop(target)
	end
	grip:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" then
			return
		end
		local cursorX, cursorY = GetCursorPosition()
		local scale = frame:GetEffectiveScale()
		frame.sizing = true
		frame.sizeX = cursorX / scale
		frame.sizeY = cursorY / scale
		frame.sizeW = frame:GetWidth()
		frame.sizeH = frame:GetHeight()
	end)
	grip:SetScript("OnUpdate", function()
		if not frame.sizing then
			return
		end
		if not IsMouseButtonDown("LeftButton") then
			finishSizing(frame)
			return
		end
		local cursorX, cursorY = GetCursorPosition()
		local scale = frame:GetEffectiveScale()
		local nextW = frame.sizeW + (cursorX / scale - frame.sizeX)
		local nextH = frame.sizeH + (frame.sizeY - cursorY / scale)
		if nextW < frame.minW then
			nextW = frame.minW
		elseif nextW > frame.maxW then
			nextW = frame.maxW
		end
		if nextH < frame.minH then
			nextH = frame.minH
		elseif nextH > frame.maxH then
			nextH = frame.maxH
		end
		frame:SetSize(nextW, nextH)
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
			if self.grip then
				self.grip:Show()
			end
		else
			self.collapsed = true
			self.expandedHeight = self:GetHeight()
			self.content:Hide()
			self:SetHeight(self.titleBar:GetHeight())
			if self.grip then
				self.grip:Hide()
			end
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
		if prompt.alphaSlider then
			prompt.alphaSlider:SetFrameStrata("FULLSCREEN_DIALOG")
		end
		if prompt.scaleSlider then
			prompt.scaleSlider:SetFrameStrata("FULLSCREEN_DIALOG")
		end
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
