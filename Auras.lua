local HRF = CleanRaidFrames

local HIGHLIGHT_SLOTS = HRF.MAX_HIGHLIGHT_SLOTS or 4
local FRAME_INSET = 2
local ICON_SPACING = 2
local GLOW_SCALE = 1.5

local activeSpecConfig = nil
local isHealer = false
local testMode = false
local trackedFrames = {}

local function createGlow(parent, anchor)
    local glow = CreateFrame("Frame", nil, parent, "ActionButtonSpellAlertTemplate")
    glow:SetPoint("CENTER", anchor, "CENTER")
    glow:SetFrameLevel((anchor:GetFrameLevel() or 0) + 10)
    glow.ProcStartFlipbook:Hide()
    glow:Hide()
    return glow
end

local function applyGlowColor(glow, r, g, b, custom)
    if not glow then return end
    glow.ProcLoopFlipbook:SetDesaturated(custom)
    glow.ProcStartFlipbook:SetDesaturated(custom)
    if custom then
        glow.ProcLoopFlipbook:SetVertexColor(r, g, b)
        glow.ProcStartFlipbook:SetVertexColor(r, g, b)
    else
        glow.ProcLoopFlipbook:SetVertexColor(1, 1, 1)
        glow.ProcStartFlipbook:SetVertexColor(1, 1, 1)
    end
end

local function showGlow(glow)
    if not glow:IsShown() then
        glow:Show()
        glow.ProcLoop:Play()
    end
end

local function hideGlow(glow)
    if glow:IsShown() then
        glow.ProcLoop:Stop()
        glow:Hide()
    end
end

local function createIcon(parent)
    local icon = CreateFrame("Frame", nil, parent)
    icon.texture = icon:CreateTexture(nil, "OVERLAY", nil, 6)
    icon.texture:SetAllPoints(icon)
    icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = icon:CreateTexture(nil, "OVERLAY", nil, 7)
    border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
    border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
    border:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
    border:Hide()
    icon.border = border
    icon:Hide()
    return icon
end

local function showBorder(icon)
    if icon.border then
        icon.border:Show()
    end
end

local function hideBorder(icon)
    if icon.border then
        icon.border:Hide()
    end
end

local function showSlot(icon, glow, texture, useGlow)
    if not texture then
        icon:Hide()
        hideBorder(icon)
        hideGlow(glow)
        return
    end
    icon.texture:SetTexture(texture)
    icon:Show()
    if useGlow == false then
        hideGlow(glow)
        showBorder(icon)
    else
        showGlow(glow)
        hideBorder(icon)
    end
end

local function hideSlot(icon, glow)
    icon:Hide()
    hideBorder(icon)
    hideGlow(glow)
end

local function buildIndicators(frame)
    if not CompactUnitFrame_IsPartyFrame(frame) or frame.cleanIndicators then return end

    local overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints(frame)
    overlay:SetFrameLevel((frame:GetFrameLevel() or 0) + 250)

    local highlights = {}
    for i = 1, HIGHLIGHT_SLOTS do
        local icon = createIcon(overlay)
        highlights[i] = { icon = icon, glow = createGlow(overlay, icon) }
    end

    local ccIcon = createIcon(overlay)
    local pureCCIcon = createIcon(overlay)
    local dispelIcon = createIcon(overlay)
    local defensiveIcon = createIcon(overlay)

    frame.cleanIndicators = {
        highlights = highlights,
        ccIcon = ccIcon,
        ccGlow = createGlow(overlay, ccIcon),
        pureCCIcon = pureCCIcon,
        pureCCGlow = createGlow(overlay, pureCCIcon),
        dispelIcon = dispelIcon,
        dispelGlow = createGlow(overlay, dispelIcon),
        defensiveIcon = defensiveIcon,
        defensiveGlow = createGlow(overlay, defensiveIcon),
    }
    trackedFrames[frame] = true
end

local SINGLE_GLOW_SECTIONS = { "defensive", "cc", "pureCC", "dispel" }

local function applyColors(ind)
    local hr, hg, hb = HRF.GetSectionColor("highlight")
    for _, slot in ipairs(ind.highlights) do
        applyGlowColor(slot.glow, hr, hg, hb, true)
        slot.icon.border:SetVertexColor(hr, hg, hb)
    end
    for _, key in ipairs(SINGLE_GLOW_SECTIONS) do
        local r, g, b = HRF.GetSectionColor(key)
        applyGlowColor(ind[key .. "Glow"], r, g, b, true)
        ind[key .. "Icon"].border:SetVertexColor(r, g, b)
    end
end

local function applyColorsAllFrames()
    for frame in pairs(trackedFrames) do
        if not frame:IsForbidden() and frame.cleanIndicators then
            applyColors(frame.cleanIndicators)
        end
    end
end

local function sizeFor(frameHeight, key)
    return math.max(8, math.floor(frameHeight * HRF.GetSectionScale(key) + 0.5))
end

local function layoutIndicators(frame)
    local ind = frame.cleanIndicators
    if not ind then return end
    local frameHeight = frame:GetHeight() or 0
    if frameHeight <= 0 then return end

    local highlightSize = sizeFor(frameHeight, "highlight")
    for i, slot in ipairs(ind.highlights) do
        slot.icon:SetSize(highlightSize, highlightSize)
        slot.icon:ClearAllPoints()
        if i == 1 then
            slot.icon:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -FRAME_INSET, -FRAME_INSET)
        else
            slot.icon:SetPoint("TOPRIGHT", ind.highlights[i - 1].icon, "TOPLEFT", -ICON_SPACING, 0)
        end
        slot.glow:SetSize(highlightSize * GLOW_SCALE, highlightSize * GLOW_SCALE)
    end

    local ccSize = sizeFor(frameHeight, "cc")
    ind.ccIcon:SetSize(ccSize, ccSize)
    ind.ccGlow:SetSize(ccSize * GLOW_SCALE, ccSize * GLOW_SCALE)

    local pureCCSize = sizeFor(frameHeight, "pureCC")
    ind.pureCCIcon:SetSize(pureCCSize, pureCCSize)
    ind.pureCCGlow:SetSize(pureCCSize * GLOW_SCALE, pureCCSize * GLOW_SCALE)

    local dispelSize = sizeFor(frameHeight, "dispel")
    ind.dispelIcon:SetSize(dispelSize, dispelSize)
    ind.dispelGlow:SetSize(dispelSize * GLOW_SCALE, dispelSize * GLOW_SCALE)

    local defSize = sizeFor(frameHeight, "defensive")
    ind.defensiveIcon:SetSize(defSize, defSize)
    ind.defensiveIcon:ClearAllPoints()
    ind.defensiveIcon:SetPoint("TOPLEFT", frame, "TOPLEFT", FRAME_INSET, -FRAME_INSET)
    ind.defensiveGlow:SetSize(defSize * GLOW_SCALE, defSize * GLOW_SCALE)
end

local function layoutBottomLeftGrid(frame)
    local ind = frame.cleanIndicators
    if not ind then return end
    local previous
    for _, icon in ipairs({ ind.ccIcon, ind.pureCCIcon, ind.dispelIcon }) do
        icon:ClearAllPoints()
        if icon:IsShown() then
            if previous then
                icon:SetPoint("BOTTOMLEFT", previous, "BOTTOMRIGHT", ICON_SPACING, 0)
            else
                icon:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", FRAME_INSET, FRAME_INSET)
            end
            previous = icon
        else
            icon:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", FRAME_INSET, FRAME_INSET)
        end
    end
end

local presentAuras = {}
local dispellableCCInstances = {}

local noErr = function() end

local function collectHighlights(unit, spec, out)
    if not spec then return 0 end
    local show = spec.show

    wipe(presentAuras)
    AuraUtil.ForEachAura(unit, "HELPFUL|PLAYER", nil, function(aura)
        xpcall(function()
            local id = aura.spellId
            if id and show[id] then
                presentAuras[id] = aura.icon
            end
        end, noErr)
    end, true)

    local n = 0
    for _, spellId in ipairs(spec.order) do
        if presentAuras[spellId] then
            n = n + 1
            out[n] = spellId
            if n >= HIGHLIGHT_SLOTS then break end
        end
    end
    return n
end

local function collectCC(unit)
    local icon
    wipe(dispellableCCInstances)
    AuraUtil.ForEachAura(unit, "HARMFUL|CROWD_CONTROL|RAID_PLAYER_DISPELLABLE", nil, function(aura)
        xpcall(function()
            local instID = aura.auraInstanceID
            if instID then
                dispellableCCInstances[instID] = true
                if not icon then
                    icon = aura.icon
                end
            end
        end, noErr)
    end, true)
    return icon, dispellableCCInstances
end

local function collectPureCC(unit, dispellable)
    local icon
    AuraUtil.ForEachAura(unit, "HARMFUL|CROWD_CONTROL", nil, function(aura)
        if icon then return true end
        xpcall(function()
            local instID = aura.auraInstanceID
            if instID and dispellable[instID] then return end
            icon = aura.icon
        end, noErr)
        if icon then return true end
    end, true)
    return icon
end

local function collectDispel(unit, dispellable)
    local icon
    AuraUtil.ForEachAura(unit, "HARMFUL|RAID_PLAYER_DISPELLABLE", nil, function(aura)
        if icon then return true end
        xpcall(function()
            local instID = aura.auraInstanceID
            if instID and dispellable[instID] then return end
            icon = aura.icon
        end, noErr)
        if icon then return true end
    end, true)
    return icon
end

local function collectDefensive(unit)
    local icon
    AuraUtil.ForEachAura(unit, "HELPFUL|BIG_DEFENSIVE", nil, function(aura)
        if icon then return true end
        xpcall(function()
            icon = aura.icon
        end, noErr)
        if icon then return true end
    end, true)
    return icon
end

local function hideAll(ind)
    for _, slot in ipairs(ind.highlights) do hideSlot(slot.icon, slot.glow) end
    hideSlot(ind.ccIcon, ind.ccGlow)
    hideSlot(ind.pureCCIcon, ind.pureCCGlow)
    hideSlot(ind.dispelIcon, ind.dispelGlow)
    hideSlot(ind.defensiveIcon, ind.defensiveGlow)
end

local function textureForSpell(spellId)
    local ok, tex = pcall(C_Spell.GetSpellTexture, spellId)
    return ok and tex or nil
end

local TEST_FALLBACK_HIGHLIGHTS = { 33763, 774, 155777, 8936, 48438 }
local TEST_CC = 118
local TEST_PURE_CC = 408
local TEST_DISPEL = 589
local TEST_DEFENSIVE = 31850

local function applyTest(frame)
    local ind = frame.cleanIndicators
    if not ind then return end
    local showHighlight = HRF.GetSectionShow("highlight")

    local entries = {}
    if showHighlight and activeSpecConfig then
        for _, spellId in ipairs(activeSpecConfig.order) do
            if activeSpecConfig.show[spellId] then
                entries[#entries + 1] = { icon = textureForSpell(spellId), useGlow = activeSpecConfig.glow[spellId] == true }
                if #entries >= HIGHLIGHT_SLOTS then break end
            end
        end
    end
    if showHighlight and #entries == 0 then
        for i = 1, math.min(HIGHLIGHT_SLOTS, #TEST_FALLBACK_HIGHLIGHTS) do
            entries[i] = { icon = textureForSpell(TEST_FALLBACK_HIGHLIGHTS[i]), useGlow = true }
        end
    end

    for i, slot in ipairs(ind.highlights) do
        local entry = entries[i]
        if entry and entry.icon then
            showSlot(slot.icon, slot.glow, entry.icon, entry.useGlow)
        else
            hideSlot(slot.icon, slot.glow)
        end
    end

    if HRF.GetSectionShow("cc") then
        showSlot(ind.ccIcon, ind.ccGlow, textureForSpell(TEST_CC), HRF.GetSectionGlow("cc"))
    else
        hideSlot(ind.ccIcon, ind.ccGlow)
    end
    if HRF.GetSectionShow("pureCC") then
        showSlot(ind.pureCCIcon, ind.pureCCGlow, textureForSpell(TEST_PURE_CC), HRF.GetSectionGlow("pureCC"))
    else
        hideSlot(ind.pureCCIcon, ind.pureCCGlow)
    end
    if HRF.GetSectionShow("dispel") then
        showSlot(ind.dispelIcon, ind.dispelGlow, textureForSpell(TEST_DISPEL), HRF.GetSectionGlow("dispel"))
    else
        hideSlot(ind.dispelIcon, ind.dispelGlow)
    end
    if HRF.GetSectionShow("defensive") then
        showSlot(ind.defensiveIcon, ind.defensiveGlow, textureForSpell(TEST_DEFENSIVE), HRF.GetSectionGlow("defensive"))
    else
        hideSlot(ind.defensiveIcon, ind.defensiveGlow)
    end
    layoutBottomLeftGrid(frame)
end

local function refreshSpec()
    local id = HRF.GetActiveSpec()
    isHealer = HRF.IsTrackedSpec(id)
    activeSpecConfig = isHealer and HRF.GetSpecConfig(id) or nil
end

local function updateFrame(frame)
    local ind = frame.cleanIndicators
    if not ind then return end
    if testMode then applyTest(frame); return end
    if not isHealer then hideAll(ind); return end
    local unit = frame.displayedUnit or frame.unit
    if not unit or not UnitExists(unit) or UnitIsDeadOrGhost(unit) then hideAll(ind); return end

    if not activeSpecConfig then
        refreshSpec()
        if not activeSpecConfig then hideAll(ind); return end
    end

    local showHighlight = HRF.GetSectionShow("highlight")
    local showCC = HRF.GetSectionShow("cc")
    local showPureCC = HRF.GetSectionShow("pureCC")
    local showDispel = HRF.GetSectionShow("dispel")
    local showDef = HRF.GetSectionShow("defensive")

    local highlightOut = ind._highlightOut
    if not highlightOut then
        highlightOut = {}
        ind._highlightOut = highlightOut
    end
    wipe(highlightOut)

    local highlightCount = 0
    if showHighlight then
        highlightCount = collectHighlights(unit, activeSpecConfig, highlightOut)
    end

    local ccIcon, dispellable
    if showCC or showPureCC or showDispel then
        ccIcon, dispellable = collectCC(unit)
    end
    local pureCCIcon
    if showPureCC then pureCCIcon = collectPureCC(unit, dispellable) end
    local dispelIcon
    if showDispel then dispelIcon = collectDispel(unit, dispellable) end
    local defIcon
    if showDef then defIcon = collectDefensive(unit) end

    local glow = activeSpecConfig.glow
    for i, slot in ipairs(ind.highlights) do
        local spellId = highlightOut[i]
        if i <= highlightCount and spellId then
            showSlot(slot.icon, slot.glow, presentAuras[spellId], glow[spellId] == true)
        else
            hideSlot(slot.icon, slot.glow)
        end
    end

    if showCC and ccIcon then
        showSlot(ind.ccIcon, ind.ccGlow, ccIcon, HRF.GetSectionGlow("cc"))
    else
        hideSlot(ind.ccIcon, ind.ccGlow)
    end
    if showPureCC and pureCCIcon then
        showSlot(ind.pureCCIcon, ind.pureCCGlow, pureCCIcon, HRF.GetSectionGlow("pureCC"))
    else
        hideSlot(ind.pureCCIcon, ind.pureCCGlow)
    end
    if showDispel and dispelIcon then
        showSlot(ind.dispelIcon, ind.dispelGlow, dispelIcon, HRF.GetSectionGlow("dispel"))
    else
        hideSlot(ind.dispelIcon, ind.dispelGlow)
    end
    if showDef and defIcon then
        showSlot(ind.defensiveIcon, ind.defensiveGlow, defIcon, HRF.GetSectionGlow("defensive"))
    else
        hideSlot(ind.defensiveIcon, ind.defensiveGlow)
    end

    layoutBottomLeftGrid(frame)
end

local function updateFramesForUnit(unit)
    if not unit then return end
    for frame in pairs(trackedFrames) do
        if not frame:IsForbidden() then
            local frameUnit = frame.displayedUnit or frame.unit
            if frameUnit == unit then
                updateFrame(frame)
            end
        end
    end
end

local function refreshFrames()
    for frame in pairs(trackedFrames) do
        if not frame:IsForbidden() then
            layoutIndicators(frame)
            updateFrame(frame)
        end
    end
end

HRF.Subscribe(function()
    applyColorsAllFrames()
    refreshFrames()
end)

local function onSetup(frame)
    local wasNew = not frame.cleanIndicators
    buildIndicators(frame)
    if wasNew and frame.cleanIndicators then
        applyColors(frame.cleanIndicators)
    end
    layoutIndicators(frame)
    updateFrame(frame)
end

hooksecurefunc("CompactUnitFrame_UpdateAll", onSetup)

local SUPPRESSED_CVARS = { "raidFramesDisplayDebuffs", "raidFramesCenterBigDefensive" }

local function enforceCVars()
    if InCombatLockdown() then return end
    for _, cvar in ipairs(SUPPRESSED_CVARS) do
        if GetCVar(cvar) ~= "0" then
            pcall(SetCVar, cvar, "0")
        end
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "CleanRaidFrames" then HRF.EnsureInitialized() end
        return
    end
    if event == "UNIT_AURA" then
        updateFramesForUnit(arg1)
        return
    end
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
        enforceCVars()
    end
    if event == "PLAYER_LOGIN" or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        refreshSpec()
    end
    if event == "PLAYER_LOGIN" and CleanRaidFramesDB and not CleanRaidFramesDB.introShown then
        CleanRaidFramesDB.introShown = true
        local prefix = "|cff33ff99[Healer Raid Frames]|r"
        print(prefix .. " enabled: adds three icon overlays to your raid frames:")
        print("  |cffffd100Top-right|r: your healer buffs on the target (configurable per spec)")
        print("  |cffffd100Top-left|r: the target's active defensive cooldown")
        print("  |cffffd100Bottom-left|r: dispellable CC, non-dispellable CC, and dispellable debuffs (grows left to right)")
        print("Type |cff33ff99/hrf|r to configure or disable any of these.")
    end
    refreshFrames()
end)

function HRF.IsTestModeOn()
    return testMode
end

function HRF.ToggleTestMode()
    testMode = not testMode
    print("|cff33ff99CleanRaidFrames|r: test mode " .. (testMode and "ON" or "OFF"))
    refreshFrames()
    return testMode
end
