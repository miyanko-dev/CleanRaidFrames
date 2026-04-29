local HRF = HealerRaidFrames

local ROW_HEIGHT = 48
local SETTINGS_ROW_HEIGHT = 40
local ROW_SPACING = 8
local ICON_SIZE = 28
local SECTION_GAP = 18
local SUBTITLE_GAP = 8
local SIDE_PAD = 16
local CONTENT_PAD = 4
local COLOR_ACTIVE_R, COLOR_ACTIVE_G, COLOR_ACTIVE_B = 1, 1, 1
local COLOR_DISABLED_R, COLOR_DISABLED_G, COLOR_DISABLED_B = 0.5, 0.5, 0.5
local HIGHLIGHT_R, HIGHLIGHT_G, HIGHLIGHT_B = 1.0, 0.82, 0.0
local GHOST_ALPHA = 0.35

local panel, scroll, content, scrollBar
local header, hint, testButton
local buffsSection, defensiveSection, ccSection, dispelSection
local buffsHint, buffListSubtitle
local dropIndicator
local rowPool = {}
local activeRows = {}
local dragState = { active = false }
local dragUpdater
local suppressRefresh = false

local function spellName(id)
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
    if type(info) == "table" and info.name then return info.name end
    if type(info) == "string" then return info end
    return "Spell " .. tostring(id)
end

local function spellTexture(id)
    return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id) or nil
end

local function setLabelEnabled(fs, enabled)
    if not fs then return end
    if enabled then
        fs:SetTextColor(COLOR_ACTIVE_R, COLOR_ACTIVE_G, COLOR_ACTIVE_B)
    else
        fs:SetTextColor(COLOR_DISABLED_R, COLOR_DISABLED_G, COLOR_DISABLED_B)
    end
end

local function makeLabel(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetText(text)
    setLabelEnabled(fs, true)
    return fs
end

local function updateGlowEnabled(glowCheck, showCheck, colorLabel)
    local enabled = showCheck:GetChecked() == true
    if enabled then
        glowCheck:Enable()
    else
        glowCheck:Disable()
    end
    setLabelEnabled(glowCheck.text, enabled)
    if colorLabel then
        local colorActive = enabled and glowCheck:GetChecked() == true
        setLabelEnabled(colorLabel, colorActive)
    end
end

local function createSwatch(parent)
    local swatch = CreateFrame("Button", nil, parent, "BackdropTemplate")
    swatch:SetSize(22, 22)
    swatch:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    swatch:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    swatch.fill = swatch:CreateTexture(nil, "BACKGROUND")
    swatch.fill:SetPoint("TOPLEFT", 3, -3)
    swatch.fill:SetPoint("BOTTOMRIGHT", -3, 3)
    swatch.fill:SetColorTexture(1, 1, 1, 1)

    function swatch:SetColor(r, g, b)
        self.fill:SetVertexColor(r, g, b)
    end
    return swatch
end

local function openColorPicker(r, g, b, onApply)
    if not ColorPickerFrame or not ColorPickerFrame.SetupColorPickerAndShow then return end
    local info = {
        swatchFunc = function()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            onApply(nr, ng, nb)
        end,
        cancelFunc = function(previous)
            if type(previous) == "table" then
                onApply(previous.r or r, previous.g or g, previous.b or b)
            else
                onApply(r, g, b)
            end
        end,
        hasOpacity = false,
        r = r, g = g, b = b,
    }
    ColorPickerFrame:SetupColorPickerAndShow(info)
end

local function styleContainer(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.35)
    frame:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
end

local function ensureDropIndicator()
    if dropIndicator then return dropIndicator end
    dropIndicator = content:CreateTexture(nil, "OVERLAY")
    dropIndicator:SetColorTexture(HIGHLIGHT_R, HIGHLIGHT_G, HIGHLIGHT_B, 1)
    dropIndicator:SetHeight(2)
    dropIndicator:Hide()
    return dropIndicator
end

local function cursorY()
    local _, y = GetCursorPosition()
    return y / UIParent:GetEffectiveScale()
end

-- Returns the 1-based insertion index (1..n+1) based on cursor Y relative to active rows.
local function computeInsertionIndex()
    local n = #activeRows
    if n == 0 then return 1 end
    local y = cursorY()
    if y >= activeRows[1]:GetTop() then return 1 end
    for i, r in ipairs(activeRows) do
        local mid = (r:GetTop() + r:GetBottom()) * 0.5
        if y >= mid then return i end
    end
    return n + 1
end

local function positionDropIndicator(insertIndex)
    if not dropIndicator then return end
    local n = #activeRows
    if n == 0 then
        dropIndicator:Hide()
        return
    end
    dropIndicator:ClearAllPoints()
    if insertIndex <= 1 then
        dropIndicator:SetPoint("BOTTOMLEFT", activeRows[1], "TOPLEFT", 0, 2)
        dropIndicator:SetPoint("BOTTOMRIGHT", activeRows[1], "TOPRIGHT", 0, 2)
    elseif insertIndex > n then
        dropIndicator:SetPoint("TOPLEFT", activeRows[n], "BOTTOMLEFT", 0, -2)
        dropIndicator:SetPoint("TOPRIGHT", activeRows[n], "BOTTOMRIGHT", 0, -2)
    else
        local above = activeRows[insertIndex - 1]
        dropIndicator:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -math.floor(ROW_SPACING / 2))
        dropIndicator:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, -math.floor(ROW_SPACING / 2))
    end
    dropIndicator:Show()
end

local function onDragUpdate()
    if not dragState.active then return end
    dragState.insertIndex = computeInsertionIndex()
    positionDropIndicator(dragState.insertIndex)
end

local function ensureDragUpdater()
    if dragUpdater then return end
    dragUpdater = CreateFrame("Frame")
    dragUpdater:Hide()
    dragUpdater:SetScript("OnUpdate", onDragUpdate)
end

local function applyGhost(row)
    row:SetAlpha(GHOST_ALPHA)
end

local function clearGhost(row)
    row:SetAlpha(1)
end

local function startDrag(row)
    if dragState.active then return end
    local index
    for i, r in ipairs(activeRows) do
        if r == row then index = i; break end
    end
    if not index then return end
    dragState.active = true
    dragState.row = row
    dragState.startIndex = index
    dragState.insertIndex = index
    dragState.specId = row._specId
    dragState.spellId = row._spellId
    applyGhost(row)
    ensureDropIndicator()
    ensureDragUpdater()
    positionDropIndicator(index)
    dragUpdater:Show()
end

local function stopDrag()
    if not dragState.active then return end
    if dragUpdater then dragUpdater:Hide() end
    if dropIndicator then dropIndicator:Hide() end
    local row = dragState.row
    if row then clearGhost(row) end

    local specId = dragState.specId
    local spellId = dragState.spellId
    local insertIndex = dragState.insertIndex or dragState.startIndex
    local startIndex = dragState.startIndex
    -- Convert insertion index to final 1-based position after removal.
    local finalPos = insertIndex
    if insertIndex > startIndex then finalPos = insertIndex - 1 end
    local changed = finalPos ~= startIndex

    dragState.active = false
    dragState.row = nil

    if changed and specId and spellId and HRF.MoveTo then
        HRF.MoveTo(specId, spellId, finalPos)
    end
    if HRF._optionsRefresh then HRF._optionsRefresh() end
end

local function acquireRow(parent)
    local row = table.remove(rowPool)
    if row then
        row:SetParent(parent)
        row:Show()
        return row
    end

    row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(ROW_HEIGHT)
    styleContainer(row)
    row:EnableMouse(true)
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function(self) startDrag(self) end)
    row:SetScript("OnDragStop", stopDrag)
    row:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and dragState.active and dragState.row == self then
            stopDrag()
        end
    end)
    row:SetScript("OnEnter", function(self)
        if not dragState.active then
            self:SetBackdropBorderColor(HIGHLIGHT_R, HIGHLIGHT_G, HIGHLIGHT_B, 1)
        end
    end)
    row:SetScript("OnLeave", function(self)
        if not dragState.active or dragState.row ~= self then
            self:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
        end
    end)

    row.position = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.position:SetPoint("LEFT", row, "LEFT", 10, 0)
    row.position:SetWidth(24)
    row.position:SetJustifyH("CENTER")

    row.iconFrame = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.iconFrame:SetSize(ICON_SIZE + 6, ICON_SIZE + 6)
    row.iconFrame:SetPoint("LEFT", row.position, "RIGHT", 4, 0)
    row.iconFrame:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    row.iconFrame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

    row.icon = row.iconFrame:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("CENTER", row.iconFrame, "CENTER", 0, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.label:SetPoint("LEFT", row.iconFrame, "RIGHT", 8, 0)
    row.label:SetJustifyH("LEFT")

    row.showLabel = makeLabel(row, "Show:")

    row.showCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.showCheck:SetSize(22, 22)
    row.showCheck.text = row.showLabel

    row.glowLabel = makeLabel(row, "Glow:")

    row.glowCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.glowCheck:SetSize(22, 22)
    row.glowCheck.text = row.glowLabel

    row.glowCheck:SetPoint("RIGHT", row, "RIGHT", -14, 0)
    row.glowLabel:SetPoint("RIGHT", row.glowCheck, "LEFT", -4, 0)
    row.showCheck:SetPoint("RIGHT", row.glowLabel, "LEFT", -14, 0)
    row.showLabel:SetPoint("RIGHT", row.showCheck, "LEFT", -4, 0)

    row.label:SetPoint("RIGHT", row.showLabel, "LEFT", -10, 0)
    return row
end

local function releaseRow(row)
    row:Hide()
    row:ClearAllPoints()
    row.showCheck:SetScript("OnClick", nil)
    row.glowCheck:SetScript("OnClick", nil)
    row._specId = nil
    row._spellId = nil
    rowPool[#rowPool + 1] = row
end

local function clearRows()
    for _, row in ipairs(activeRows) do releaseRow(row) end
    for i = #activeRows, 1, -1 do activeRows[i] = nil end
end

local function addSizeField(parent, sectionKey, anchor)
    local sizeLabel = makeLabel(parent, "Size %:")
    sizeLabel:SetPoint("LEFT", anchor, "RIGHT", 14, 0)

    local sizeEdit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    sizeEdit:SetSize(40, 20)
    sizeEdit:SetPoint("LEFT", sizeLabel, "RIGHT", 6, 0)
    sizeEdit:SetAutoFocus(false)
    sizeEdit:SetNumeric(true)
    sizeEdit:SetMaxLetters(3)

    local function commit()
        local raw = tonumber(sizeEdit:GetText()) or 0
        local minP = math.floor(HRF.SCALE_MIN * 100 + 0.5)
        local maxP = math.floor(HRF.SCALE_MAX * 100 + 0.5)
        local percent = math.max(minP, math.min(maxP, math.floor(raw + 0.5)))
        HRF.SetSectionScale(sectionKey, percent / 100)
        sizeEdit:SetText(tostring(percent))
        sizeEdit:ClearFocus()
    end
    sizeEdit:SetScript("OnEnterPressed", commit)
    sizeEdit:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(math.floor(HRF.GetSectionScale(sectionKey) * 100 + 0.5)))
        self:ClearFocus()
    end)
    sizeEdit:SetScript("OnEditFocusLost", commit)

    return sizeLabel, sizeEdit
end

-- Builds: title, "General Settings" subtitle, and a settings-row container with the
-- Enable checkbox (+ optional Glow checkbox), color swatch, size field, reset button.
local function buildSectionShell(parent, title, sectionKey, opts)
    opts = opts or {}
    local hasGlow = opts.hasGlow ~= false

    local titleFS = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    titleFS:SetText(title)

    local subtitle = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    subtitle:SetText("General Settings")
    subtitle:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -SUBTITLE_GAP)

    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(SETTINGS_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -6)
    row:SetPoint("RIGHT", parent, "RIGHT", -CONTENT_PAD, 0)
    styleContainer(row)

    local showLabel = makeLabel(row, "Enable:")
    showLabel:SetPoint("LEFT", row, "LEFT", 16, 0)

    local showCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    showCheck:SetSize(22, 22)
    showCheck.text = showLabel
    showCheck:SetPoint("LEFT", showLabel, "RIGHT", 4, 0)

    local glowCheck, glowLabel
    local anchorAfterChecks = showCheck
    if hasGlow then
        glowLabel = makeLabel(row, "Glow:")
        glowLabel:SetPoint("LEFT", showCheck, "RIGHT", 16, 0)

        glowCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        glowCheck:SetSize(22, 22)
        glowCheck.text = glowLabel
        glowCheck:SetPoint("LEFT", glowLabel, "RIGHT", 4, 0)
        anchorAfterChecks = glowCheck
    end

    local colorLabel = makeLabel(row, "Custom Color:")
    colorLabel:SetPoint("LEFT", anchorAfterChecks, "RIGHT", 16, 0)

    local customCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    customCheck:SetSize(22, 22)
    customCheck.text = colorLabel
    customCheck:SetPoint("LEFT", colorLabel, "RIGHT", 4, 0)

    local swatch = createSwatch(row)
    swatch:SetPoint("LEFT", customCheck, "RIGHT", 6, 0)
    swatch:SetScript("OnClick", function()
        if not swatch:IsEnabled() then return end
        local r, g, b = HRF.GetSectionColor(sectionKey)
        openColorPicker(r, g, b, function(nr, ng, nb)
            HRF.SetSectionColor(sectionKey, nr, ng, nb)
            swatch:SetColor(nr, ng, nb)
        end)
    end)

    local function updateSwatchEnabled(enabled)
        if enabled then
            swatch:Enable()
            swatch.fill:SetDesaturated(false)
            swatch:SetAlpha(1)
        else
            swatch:Disable()
            swatch.fill:SetDesaturated(true)
            swatch:SetAlpha(0.5)
        end
    end

    customCheck:SetScript("OnClick", function(self)
        local checked = self:GetChecked() == true
        HRF.SetSectionGlowCustom(sectionKey, checked)
        local showOn = showCheck:GetChecked() == true
        local glowOn = (glowCheck == nil) or (glowCheck:GetChecked() == true)
        updateSwatchEnabled(showOn and glowOn and checked)
    end)

    local sizeLabel, sizeEdit = addSizeField(row, sectionKey, swatch)

    local resetButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    resetButton:SetSize(130, 22)
    resetButton:SetText("Reset to defaults")
    resetButton:SetPoint("RIGHT", row, "RIGHT", -12, 0)

    local function cascadeCustom()
        local showOn = showCheck:GetChecked() == true
        local glowOn = (glowCheck == nil) or (glowCheck:GetChecked() == true)
        local customRowActive = showOn and glowOn
        if customRowActive then customCheck:Enable() else customCheck:Disable() end
        setLabelEnabled(colorLabel, customRowActive)
        updateSwatchEnabled(customRowActive and customCheck:GetChecked() == true)
    end

    showCheck:SetScript("OnClick", function(self)
        HRF.SetSectionShow(sectionKey, self:GetChecked())
        if glowCheck then updateGlowEnabled(glowCheck, showCheck, colorLabel) end
        cascadeCustom()
    end)
    if glowCheck then
        glowCheck:SetScript("OnClick", function(self)
            HRF.SetSectionGlow(sectionKey, self:GetChecked())
            updateGlowEnabled(glowCheck, showCheck, colorLabel)
            cascadeCustom()
        end)
    end

    return {
        key = sectionKey,
        title = titleFS,
        subtitle = subtitle,
        row = row,
        showCheck = showCheck,
        glowCheck = glowCheck,
        colorLabel = colorLabel,
        customCheck = customCheck,
        swatch = swatch,
        updateSwatchEnabled = updateSwatchEnabled,
        sizeEdit = sizeEdit,
        resetButton = resetButton,
    }
end

local function refreshSection(section)
    local key = section.key
    local showOn = HRF.GetSectionShow(key)
    section.showCheck:SetChecked(showOn)

    local glowOn = true
    if section.glowCheck then
        glowOn = HRF.GetSectionGlow(key)
        section.glowCheck:SetChecked(glowOn)
        updateGlowEnabled(section.glowCheck, section.showCheck, section.colorLabel)
    else
        setLabelEnabled(section.colorLabel, showOn)
    end

    local customOn = HRF.GetSectionGlowCustom(key)
    if section.customCheck then
        section.customCheck:SetChecked(customOn)
        -- Custom Color row is only meaningful when the section shows and glows.
        local customRowActive = showOn and glowOn
        if customRowActive then
            section.customCheck:Enable()
        else
            section.customCheck:Disable()
        end
        setLabelEnabled(section.colorLabel, customRowActive)
        if section.updateSwatchEnabled then
            section.updateSwatchEnabled(customRowActive and customOn)
        end
    end

    local r, g, b = HRF.GetSectionColor(key)
    section.swatch:SetColor(r, g, b)
    if section.sizeEdit and not section.sizeEdit:HasFocus() then
        section.sizeEdit:SetText(tostring(math.floor(HRF.GetSectionScale(key) * 100 + 0.5)))
    end
end

local function refresh()
    if dragState.active then return end
    clearRows()

    if testButton and HRF.IsTestModeOn then
        testButton:SetText(HRF.IsTestModeOn() and "Test mode: ON" or "Test mode: OFF")
    end

    local specId = HRF.GetActiveSpec and HRF.GetActiveSpec()
    local specName = specId and HRF.SPEC_NAMES[specId] or nil
    local tracked = specId and HRF.IsTrackedSpec(specId) or false

    refreshSection(buffsSection)
    refreshSection(defensiveSection)
    refreshSection(ccSection)
    refreshSection(dispelSection)

    if not tracked then
        header:SetText("Healer Raid Frames")
        hint:SetText("Switch to a supported healing specialization to configure its buff list.\nSupported: Discipline / Holy Priest, Holy Paladin, Restoration Shaman,\nMistweaver Monk, Restoration Druid, Preservation Evoker, Augmentation Evoker.")
        buffsSection.resetButton:Disable()
        buffsHint:SetText("")
        buffListSubtitle:Hide()
    else
        header:SetText("Healer Raid Frames: " .. specName)
        hint:SetText("")
        buffsHint:SetText("Display buffs on the raid frame in the top right corner. Glow adds a proc glow. "
            .. "Drag rows to change order. Top to bottom maps to right to left. "
            .. "Only the first " .. tostring(HRF.MAX_HIGHLIGHT_SLOTS) .. " buffs are shown.")
        buffsSection.resetButton:Enable()
        buffListSubtitle:Show()
    end

    buffListSubtitle:ClearAllPoints()
    buffListSubtitle:SetPoint("TOPLEFT", buffsSection.row, "BOTTOMLEFT", 0, -SECTION_GAP)

    buffsHint:ClearAllPoints()
    buffsHint:SetPoint("TOPLEFT", buffListSubtitle, "BOTTOMLEFT", 0, -6)
    buffsHint:SetPoint("RIGHT", content, "RIGHT", -CONTENT_PAD, 0)

    local spec = tracked and HRF.GetSpecConfig(specId) or nil
    local order = spec and spec.order or {}

    local previous
    for index, spellId in ipairs(order) do
        local row = acquireRow(content)
        row:ClearAllPoints()
        if previous then
            row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -ROW_SPACING)
            row:SetPoint("TOPRIGHT", previous, "BOTTOMRIGHT", 0, -ROW_SPACING)
        else
            row:SetPoint("TOPLEFT", buffsHint, "BOTTOMLEFT", 0, -SUBTITLE_GAP)
            row:SetPoint("RIGHT", content, "RIGHT", -CONTENT_PAD, 0)
        end

        row._specId = specId
        row._spellId = spellId
        row.position:SetText(tostring(index))
        row.icon:SetTexture(spellTexture(spellId) or 134400)
        row.label:SetText(spellName(spellId) .. "  |cff888888(" .. spellId .. ")|r")

        row.showCheck:SetChecked(spec.show[spellId] == true)
        row.glowCheck:SetChecked(spec.glow[spellId] == true)
        updateGlowEnabled(row.glowCheck, row.showCheck)

        row.showCheck:SetScript("OnClick", function(self)
            suppressRefresh = true
            HRF.SetShow(specId, spellId, self:GetChecked())
            suppressRefresh = false
            updateGlowEnabled(row.glowCheck, row.showCheck)
        end)

        row.glowCheck:SetScript("OnClick", function(self)
            suppressRefresh = true
            HRF.SetGlow(specId, spellId, self:GetChecked())
            suppressRefresh = false
        end)

        activeRows[#activeRows + 1] = row
        previous = row
    end

    local anchorAfterBuffs = previous or buffListSubtitle
    defensiveSection.title:ClearAllPoints()
    defensiveSection.title:SetPoint("TOPLEFT", anchorAfterBuffs, "BOTTOMLEFT", 0, -SECTION_GAP)

    C_Timer.After(0, function()
        if not content then return end
        local bottom = dispelSection.row:GetBottom()
        local top = content:GetTop()
        if bottom and top then
            content:SetHeight(math.max(top - bottom + CONTENT_PAD * 2, 1))
        end
    end)
end

HRF._optionsRefresh = refresh

local function build()
    panel = CreateFrame("Frame")
    panel.name = "Healer Raid Frames"

    scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", SIDE_PAD, -SIDE_PAD)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -SIDE_PAD - 16, SIDE_PAD)

    if scroll.ScrollBar then scroll.ScrollBar:Hide() end
    if scroll.scrollBarHideable ~= nil then scroll.scrollBarHideable = 1 end

    scrollBar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)

    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    if ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar then
        ScrollUtil.InitScrollFrameWithScrollBar(scroll, scrollBar)
    end

    scroll:HookScript("OnSizeChanged", function(self, width)
        content:SetWidth(math.max(width or 0, 1))
    end)

    header = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", content, "TOPLEFT", CONTENT_PAD, -CONTENT_PAD)
    header:SetText("Healer Raid Frames")

    testButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    testButton:SetSize(140, 22)
    testButton:SetPoint("RIGHT", content, "RIGHT", -CONTENT_PAD, 0)
    testButton:SetPoint("TOP", header, "TOP", 0, 0)
    testButton:SetScript("OnClick", function(self)
        if HRF.ToggleTestMode then
            local on = HRF.ToggleTestMode()
            self:SetText(on and "Test mode: ON" or "Test mode: OFF")
        end
    end)
    testButton:SetText((HRF.IsTestModeOn and HRF.IsTestModeOn()) and "Test mode: ON" or "Test mode: OFF")

    hint = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    hint:SetPoint("RIGHT", testButton, "LEFT", -8, 0)
    hint:SetJustifyH("LEFT")
    hint:SetJustifyV("TOP")
    hint:SetText("")

    buffsSection = buildSectionShell(content, "Healer Buff Display (Top Right Corner)", "highlight", { hasGlow = false })
    buffsSection.title:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -SECTION_GAP)
    buffsSection.resetButton:SetScript("OnClick", function()
        local specId = HRF.GetActiveSpec and HRF.GetActiveSpec()
        HRF.ResetHighlightDefaults(specId)
        refresh()
    end)

    buffListSubtitle = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    buffListSubtitle:SetText("Buff Settings")

    -- Section hint sits under the "Buff Settings" subtitle in yellow so it reads as an instruction.
    buffsHint = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    buffsHint:SetJustifyH("LEFT")
    buffsHint:SetJustifyV("TOP")
    buffsHint:SetTextColor(1, 0.82, 0)

    defensiveSection = buildSectionShell(content, "Defensive Buff Icons (Top Left Corner)", "defensive")
    defensiveSection.resetButton:SetScript("OnClick", function()
        HRF.ResetSection("defensive")
        refresh()
    end)

    ccSection = buildSectionShell(content, "Dispellable CC Debuff Icon (Bottom Left Corner)", "cc")
    ccSection.title:ClearAllPoints()
    ccSection.title:SetPoint("TOPLEFT", defensiveSection.row, "BOTTOMLEFT", 0, -SECTION_GAP)
    ccSection.resetButton:SetScript("OnClick", function()
        HRF.ResetSection("cc")
        refresh()
    end)

    dispelSection = buildSectionShell(content, "Dispellable Debuff Icon (Bottom Left Corner)", "dispel")
    dispelSection.title:ClearAllPoints()
    dispelSection.title:SetPoint("TOPLEFT", ccSection.row, "BOTTOMLEFT", 0, -SECTION_GAP)
    dispelSection.resetButton:SetScript("OnClick", function()
        HRF.ResetSection("dispel")
        refresh()
    end)

    panel:SetScript("OnShow", refresh)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        HRF.settingsCategoryID = category:GetID()
    end
end

local function onEvent(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "HealerRaidFrames" then
        if HRF.EnsureInitialized then HRF.EnsureInitialized() end
        build()
        self:UnregisterEvent("ADDON_LOADED")
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", onEvent)

if HRF.Subscribe then
    HRF.Subscribe(function()
        if suppressRefresh then return end
        if panel and panel:IsShown() and not dragState.active then refresh() end
    end)
end

SLASH_HRFOPTIONS1 = "/hrf"
SlashCmdList["HRFOPTIONS"] = function()
    if HRF.settingsCategoryID and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(HRF.settingsCategoryID)
    end
end
