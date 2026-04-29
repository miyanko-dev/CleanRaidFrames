local _, ns = ...

local HIGHLIGHT_SLOTS = 2
local FRAME_INSET = 2
local ICON_SPACING = 4
local AURA_SCALE = 0.4
local GLOW_SCALE = 1.5
local MAX_DEFENSIVE_DURATION = 30

local DEFENSIVE_COLOR = {0.1, 1.0, 0.1}
local DISPEL_COLOR = {1.0, 0.1, 0.1}

local HEALER_SPECS = {
    [256]  = true,  -- Discipline Priest
    [257]  = true,  -- Holy Priest
    [264]  = true,  -- Restoration Shaman
    [65]   = true,  -- Holy Paladin
    [270]  = true,  -- Mistweaver Monk
    [105]  = true,  -- Restoration Druid
    [1468] = true,  -- Preservation Evoker
}

local HIGHLIGHT_SPELLS = {
    [156910]  = true, -- Beacon of Faith
    [1244893] = true, -- Beacon of the Savior
    [53563]   = true, -- Beacon of Light
    [974]     = true, -- Earth Shield
    [383648]  = true, -- Earth Shield (alt)
    [119611]  = true, -- Renewing Mist
    [124682]  = true, -- Enveloping Mist
    [194384]  = true, -- Atonement
    [33763]   = true, -- Lifebloom
    [366155]  = true, -- Reversion
}

local isHealer = false
local trackedFrames = {}
ns.frames = trackedFrames

local function isPartyFrame(frame)
    return frame and CompactUnitFrame_IsPartyFrame and CompactUnitFrame_IsPartyFrame(frame)
end

local function createGlow(parent, anchor, color)
    local glow = CreateFrame("Frame", nil, parent, "ActionButtonSpellAlertTemplate")
    glow:SetPoint("CENTER", anchor, "CENTER")
    glow:SetFrameLevel((anchor:GetFrameLevel() or 0) + 10)
    glow.ProcStartFlipbook:Hide()
    if color then
        glow.ProcLoopFlipbook:SetVertexColor(unpack(color))
        glow.ProcStartFlipbook:SetVertexColor(unpack(color))
    end
    glow:Hide()
    return glow
end

local function showGlow(glow)
    if glow and not glow:IsShown() then
        glow:Show()
        if glow.ProcLoop then glow.ProcLoop:Play() end
    end
end

local function hideGlow(glow)
    if glow and glow:IsShown() then
        if glow.ProcLoop then glow.ProcLoop:Stop() end
        glow:Hide()
    end
end

local function createIcon(parent, useSwipe)
    local button = CreateFrame("Frame", nil, parent)
    button.texture = button:CreateTexture(nil, "OVERLAY", nil, 7)
    button.texture:SetAllPoints(button)
    button.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button)
    button.cooldown:SetDrawSwipe(useSwipe == true)
    button.cooldown:SetReverse(useSwipe == true)
    button.cooldown:SetDrawBling(false)
    button.cooldown:SetDrawEdge(false)
    button.cooldown:SetHideCountdownNumbers(useSwipe == true)
    button:Hide()
    return button
end

local function setIconTexture(icon, spellId)
    local tex = C_Spell.GetSpellTexture(spellId)
    if tex then icon.texture:SetTexture(tex) end
end

local function setIconCooldown(icon, duration, expires)
    local ok = pcall(function()
        if duration and expires and duration > 0 and expires > 0 then
            icon.cooldown:SetCooldown(expires - duration, duration)
        else
            icon.cooldown:Clear()
        end
    end)
    if not ok then
        icon.cooldown:Clear()
    end
end

local function buildIndicators(frame)
    if not isPartyFrame(frame) or frame.cleanIndicators then return end

    local overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints(frame)
    overlay:SetFrameLevel((frame:GetFrameLevel() or 0) + 250)

    local highlightIcons, highlightGlows = {}, {}
    for i = 1, HIGHLIGHT_SLOTS do
        highlightIcons[i] = createIcon(overlay, true)
        highlightGlows[i] = createGlow(overlay, highlightIcons[i], nil)
    end

    local ccIcon = createIcon(overlay, false)
    local ccGlow = createGlow(overlay, ccIcon, DISPEL_COLOR)

    local defensiveIcon = createIcon(overlay, false)
    local defensiveGlow = createGlow(overlay, defensiveIcon, DEFENSIVE_COLOR)

    frame.cleanIndicators = {
        overlay = overlay,
        highlightIcons = highlightIcons,
        highlightGlows = highlightGlows,
        ccIcon = ccIcon,
        ccGlow = ccGlow,
        defensiveIcon = defensiveIcon,
        defensiveGlow = defensiveGlow,
    }
    trackedFrames[frame] = true
end

local function layoutIndicators(frame)
    local indicators = frame.cleanIndicators
    if not indicators then return end
    local frameHeight = frame:GetHeight() or 0
    if frameHeight <= 0 then return end

    local auraSize = math.max(8, math.floor(frameHeight * AURA_SCALE + 0.5))
    local glowSize = auraSize * GLOW_SCALE

    for i = 1, HIGHLIGHT_SLOTS do
        local icon = indicators.highlightIcons[i]
        icon:SetSize(auraSize, auraSize)
        icon:ClearAllPoints()
        if i == 1 then
            icon:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -FRAME_INSET, -FRAME_INSET)
        else
            icon:SetPoint("TOPRIGHT", indicators.highlightIcons[i - 1], "TOPLEFT", -ICON_SPACING, 0)
        end
        indicators.highlightGlows[i]:SetSize(glowSize, glowSize)
    end

    indicators.ccIcon:SetSize(auraSize, auraSize)
    indicators.ccIcon:ClearAllPoints()
    indicators.ccIcon:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", FRAME_INSET, FRAME_INSET)
    indicators.ccGlow:SetSize(glowSize, glowSize)

    indicators.defensiveIcon:SetSize(auraSize, auraSize)
    indicators.defensiveIcon:ClearAllPoints()
    indicators.defensiveIcon:SetPoint("TOPLEFT", frame, "TOPLEFT", FRAME_INSET, -FRAME_INSET)
    indicators.defensiveGlow:SetSize(glowSize, glowSize)
end

local highlightIds = {}
local highlightDurations = {}
local highlightExpires = {}
local ccInfo = {}
local defensiveInfo = {}

local function clearScratch()
    for i = #highlightIds, 1, -1 do
        highlightIds[i] = nil
        highlightDurations[i] = nil
        highlightExpires[i] = nil
    end
    ccInfo.spellId = nil
    ccInfo.duration = nil
    ccInfo.expires = nil
    defensiveInfo.spellId = nil
    defensiveInfo.duration = nil
    defensiveInfo.expires = nil
end

local function safeLookup(tbl, key)
    local ok, value = pcall(function() return tbl[key] end)
    if ok then return value end
    return nil
end

local function safeSpellId(aura)
    if not aura then return nil end
    local ok, value = pcall(function() return aura.spellId end)
    if ok and type(value) == "number" then return value end
    return nil
end

local function safeBoolField(aura, field)
    local ok, value = pcall(function() return aura[field] end)
    if ok and value == true then return true end
    return false
end

local function safeTiming(aura)
    local ok, duration, expires = pcall(function() return aura.duration, aura.expirationTime end)
    if not ok then return nil, nil end
    if type(duration) ~= "number" then duration = nil end
    if type(expires) ~= "number" then expires = nil end
    return duration, expires
end

-- Reject only when we can prove no active timer. Missing/unreadable timing passes through.
local function isNoTimerAura(duration, expires)
    if duration == nil or expires == nil then return false end
    local ok, zero = pcall(function() return duration == 0 and expires == 0 end)
    return ok and zero == true
end

-- Reject only when we can prove the aura is long-lived. Missing/unreadable timing passes through.
local function exceedsDefensiveDuration(duration)
    if duration == nil then return false end
    local ok, over = pcall(function() return duration > MAX_DEFENSIVE_DURATION end)
    return ok and over == true
end

local function collectHighlights(unit)
    local count = 0
    AuraUtil.ForEachAura(unit, "HELPFUL|PLAYER", nil, function(aura)
        if not safeBoolField(aura, "isFromPlayerOrPlayerPet") then return end
        local spellId = safeSpellId(aura)
        if spellId and safeLookup(HIGHLIGHT_SPELLS, spellId) then
            local duration, expires = safeTiming(aura)
            count = count + 1
            highlightIds[count] = spellId
            highlightDurations[count] = duration
            highlightExpires[count] = expires
            if count >= HIGHLIGHT_SLOTS then return true end
        end
    end, true)
    return count
end

local function collectCC(unit)
    AuraUtil.ForEachAura(unit, "HARMFUL|CROWD_CONTROL|RAID_PLAYER_DISPELLABLE", nil, function(aura)
        local spellId = safeSpellId(aura)
        if not spellId then return end
        local duration, expires = safeTiming(aura)
        if isNoTimerAura(duration, expires) then return end
        ccInfo.spellId = spellId
        ccInfo.duration = duration
        ccInfo.expires = expires
        return true
    end, true)
    return ccInfo.spellId
end

local function findDefensive(unit)
    AuraUtil.ForEachAura(unit, "HELPFUL|BIG_DEFENSIVE", nil, function(aura)
        local spellId = safeSpellId(aura)
        if not spellId then return end
        local duration, expires = safeTiming(aura)
        if isNoTimerAura(duration, expires) then return end
        if exceedsDefensiveDuration(duration) then return end
        defensiveInfo.spellId = spellId
        defensiveInfo.duration = duration
        defensiveInfo.expires = expires
        return true
    end, true)
    return defensiveInfo.spellId
end

local function hideIcon(icon)
    icon:Hide()
    icon.cooldown:Clear()
end

local function hideAllIndicators(indicators)
    for i = 1, HIGHLIGHT_SLOTS do
        hideIcon(indicators.highlightIcons[i])
        hideGlow(indicators.highlightGlows[i])
    end
    hideIcon(indicators.ccIcon)
    hideGlow(indicators.ccGlow)
    hideIcon(indicators.defensiveIcon)
    hideGlow(indicators.defensiveGlow)
end

local testMode = false
local TEST_HIGHLIGHTS = {33763, 194384}  -- Lifebloom, Atonement
local TEST_CC = 118                       -- Polymorph
local TEST_DEFENSIVE = 31850              -- Ardent Defender

local function applyTestFrame(indicators)
    for i = 1, HIGHLIGHT_SLOTS do
        local icon = indicators.highlightIcons[i]
        local spellId = TEST_HIGHLIGHTS[i]
        if spellId then
            setIconTexture(icon, spellId)
            setIconCooldown(icon, 15, GetTime() + 10)
            icon:Show()
            showGlow(indicators.highlightGlows[i])
        end
    end
    setIconTexture(indicators.ccIcon, TEST_CC)
    setIconCooldown(indicators.ccIcon, 8, GetTime() + 6)
    indicators.ccIcon:Show()
    showGlow(indicators.ccGlow)
    setIconTexture(indicators.defensiveIcon, TEST_DEFENSIVE)
    setIconCooldown(indicators.defensiveIcon, 8, GetTime() + 5)
    indicators.defensiveIcon:Show()
    showGlow(indicators.defensiveGlow)
end

local function updateFrame(frame)
    local indicators = frame.cleanIndicators
    if not indicators then return end
    if testMode then applyTestFrame(indicators); return end
    if not isHealer then hideAllIndicators(indicators); return end
    local unit = frame.displayedUnit or frame.unit
    if not unit or not UnitExists(unit) then hideAllIndicators(indicators); return end

    clearScratch()
    local highlightCount = collectHighlights(unit)
    local ccSpell = collectCC(unit)
    local defensiveSpell = findDefensive(unit)

    for i = 1, HIGHLIGHT_SLOTS do
        local icon = indicators.highlightIcons[i]
        if i <= highlightCount then
            setIconTexture(icon, highlightIds[i])
            setIconCooldown(icon, highlightDurations[i], highlightExpires[i])
            icon:Show()
            showGlow(indicators.highlightGlows[i])
        else
            hideIcon(icon)
            hideGlow(indicators.highlightGlows[i])
        end
    end

    if ccSpell then
        setIconTexture(indicators.ccIcon, ccSpell)
        setIconCooldown(indicators.ccIcon, ccInfo.duration, ccInfo.expires)
        indicators.ccIcon:Show()
        showGlow(indicators.ccGlow)
    else
        hideIcon(indicators.ccIcon)
        hideGlow(indicators.ccGlow)
    end

    if defensiveSpell then
        setIconTexture(indicators.defensiveIcon, defensiveSpell)
        setIconCooldown(indicators.defensiveIcon, defensiveInfo.duration, defensiveInfo.expires)
        indicators.defensiveIcon:Show()
        showGlow(indicators.defensiveGlow)
    else
        hideIcon(indicators.defensiveIcon)
        hideGlow(indicators.defensiveGlow)
    end
end

local function refreshFrames()
    for frame in pairs(trackedFrames) do
        if not frame:IsForbidden() then
            updateFrame(frame)
        end
    end
end

local function refreshSpec()
    local idx = GetSpecialization and GetSpecialization()
    local id = idx and GetSpecializationInfo and GetSpecializationInfo(idx)
    isHealer = id and HEALER_SPECS[id] or false
end

hooksecurefunc("DefaultCompactUnitFrameSetup", function(frame)
    buildIndicators(frame)
    layoutIndicators(frame)
    updateFrame(frame)
end)
hooksecurefunc("DefaultCompactMiniFrameSetup", function(frame)
    buildIndicators(frame)
    layoutIndicators(frame)
    updateFrame(frame)
end)
hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
    buildIndicators(frame)
    layoutIndicators(frame)
    updateFrame(frame)
end)

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        refreshSpec()
    end
    refreshFrames()
end)

SLASH_HRFTEST1 = "/hrftest"
SlashCmdList["HRFTEST"] = function()
    testMode = not testMode
    print("|cff33ff99HealerRaidFrames|r: test mode " .. (testMode and "ON" or "OFF"))
    refreshFrames()
end
