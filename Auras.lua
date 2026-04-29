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
local testMode = false
local trackedFrames = {}

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

local function createIcon(parent, useSwipe)
    local icon = CreateFrame("Frame", nil, parent)
    icon.texture = icon:CreateTexture(nil, "OVERLAY", nil, 7)
    icon.texture:SetAllPoints(icon)
    icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints(icon)
    icon.cooldown:SetDrawSwipe(useSwipe)
    icon.cooldown:SetReverse(useSwipe)
    icon.cooldown:SetHideCountdownNumbers(useSwipe)
    icon.cooldown:SetDrawBling(false)
    icon.cooldown:SetDrawEdge(false)
    icon:Hide()
    return icon
end

local function setCooldown(icon, duration, expires)
    local ok = pcall(function()
        if duration and expires and duration > 0 and expires > 0 then
            icon.cooldown:SetCooldown(expires - duration, duration)
        else
            icon.cooldown:Clear()
        end
    end)
    if not ok then icon.cooldown:Clear() end
end

local function showSlot(icon, glow, spellId, duration, expires)
    local tex = C_Spell.GetSpellTexture(spellId)
    if tex then icon.texture:SetTexture(tex) end
    setCooldown(icon, duration, expires)
    icon:Show()
    showGlow(glow)
end

local function hideSlot(icon, glow)
    icon:Hide()
    icon.cooldown:Clear()
    hideGlow(glow)
end

local function buildIndicators(frame)
    if not isPartyFrame(frame) or frame.cleanIndicators then return end

    local overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints(frame)
    overlay:SetFrameLevel((frame:GetFrameLevel() or 0) + 250)

    local highlights = {}
    for i = 1, HIGHLIGHT_SLOTS do
        local icon = createIcon(overlay, true)
        highlights[i] = { icon = icon, glow = createGlow(overlay, icon, nil) }
    end

    local ccIcon = createIcon(overlay, false)
    local defensiveIcon = createIcon(overlay, false)

    frame.cleanIndicators = {
        highlights = highlights,
        ccIcon = ccIcon,
        ccGlow = createGlow(overlay, ccIcon, DISPEL_COLOR),
        defensiveIcon = defensiveIcon,
        defensiveGlow = createGlow(overlay, defensiveIcon, DEFENSIVE_COLOR),
    }
    trackedFrames[frame] = true
end

local function layoutIndicators(frame)
    local ind = frame.cleanIndicators
    if not ind then return end
    local frameHeight = frame:GetHeight() or 0
    if frameHeight <= 0 then return end

    local size = math.max(8, math.floor(frameHeight * AURA_SCALE + 0.5))
    local glowSize = size * GLOW_SCALE

    for i, slot in ipairs(ind.highlights) do
        slot.icon:SetSize(size, size)
        slot.icon:ClearAllPoints()
        if i == 1 then
            slot.icon:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -FRAME_INSET, -FRAME_INSET)
        else
            slot.icon:SetPoint("TOPRIGHT", ind.highlights[i - 1].icon, "TOPLEFT", -ICON_SPACING, 0)
        end
        slot.glow:SetSize(glowSize, glowSize)
    end

    ind.ccIcon:SetSize(size, size)
    ind.ccIcon:ClearAllPoints()
    ind.ccIcon:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", FRAME_INSET, FRAME_INSET)
    ind.ccGlow:SetSize(glowSize, glowSize)

    ind.defensiveIcon:SetSize(size, size)
    ind.defensiveIcon:ClearAllPoints()
    ind.defensiveIcon:SetPoint("TOPLEFT", frame, "TOPLEFT", FRAME_INSET, -FRAME_INSET)
    ind.defensiveGlow:SetSize(glowSize, glowSize)
end

local function safeLookup(tbl, key)
    local ok, value = pcall(function() return tbl[key] end)
    return ok and value or nil
end

local function safeSpellId(aura)
    if not aura then return nil end
    local ok, value = pcall(function() return aura.spellId end)
    return ok and type(value) == "number" and value or nil
end

local function safeBool(aura, field)
    local ok, value = pcall(function() return aura[field] end)
    return ok and value == true
end

local function safeTiming(aura)
    local ok, duration, expires = pcall(function() return aura.duration, aura.expirationTime end)
    if not ok then return nil, nil end
    if type(duration) ~= "number" then duration = nil end
    if type(expires) ~= "number" then expires = nil end
    return duration, expires
end

-- Returns true only when we can prove the aura has no active timer.
local function hasNoTimer(duration, expires)
    if duration == nil or expires == nil then return false end
    local ok, zero = pcall(function() return duration == 0 and expires == 0 end)
    return ok and zero == true
end

-- Returns true only when duration is readable and exceeds the cap.
local function exceedsCap(duration, cap)
    if duration == nil then return false end
    local ok, over = pcall(function() return duration > cap end)
    return ok and over == true
end

local highlights = {}
local cc = {}
local defensive = {}

local function collectHighlights(unit)
    for i = #highlights, 1, -1 do highlights[i] = nil end
    AuraUtil.ForEachAura(unit, "HELPFUL|PLAYER", nil, function(aura)
        if not safeBool(aura, "isFromPlayerOrPlayerPet") then return end
        local spellId = safeSpellId(aura)
        if spellId and safeLookup(HIGHLIGHT_SPELLS, spellId) then
            local duration, expires = safeTiming(aura)
            highlights[#highlights + 1] = { spellId = spellId, duration = duration, expires = expires }
            if #highlights >= HIGHLIGHT_SLOTS then return true end
        end
    end, true)
end

local function collectCC(unit)
    cc.spellId, cc.duration, cc.expires = nil, nil, nil
    AuraUtil.ForEachAura(unit, "HARMFUL|CROWD_CONTROL|RAID_PLAYER_DISPELLABLE", nil, function(aura)
        local spellId = safeSpellId(aura)
        if not spellId then return end
        local duration, expires = safeTiming(aura)
        if hasNoTimer(duration, expires) then return end
        cc.spellId, cc.duration, cc.expires = spellId, duration, expires
        return true
    end, true)
end

local function collectDefensive(unit)
    defensive.spellId, defensive.duration, defensive.expires = nil, nil, nil
    AuraUtil.ForEachAura(unit, "HELPFUL|BIG_DEFENSIVE", nil, function(aura)
        local spellId = safeSpellId(aura)
        if not spellId then return end
        local duration, expires = safeTiming(aura)
        if hasNoTimer(duration, expires) then return end
        if exceedsCap(duration, MAX_DEFENSIVE_DURATION) then return end
        defensive.spellId, defensive.duration, defensive.expires = spellId, duration, expires
        return true
    end, true)
end

local function hideAll(ind)
    for _, slot in ipairs(ind.highlights) do hideSlot(slot.icon, slot.glow) end
    hideSlot(ind.ccIcon, ind.ccGlow)
    hideSlot(ind.defensiveIcon, ind.defensiveGlow)
end

local TEST_HIGHLIGHTS = {33763, 194384}  -- Lifebloom, Atonement
local TEST_CC = 118                       -- Polymorph
local TEST_DEFENSIVE = 31850              -- Ardent Defender

local function applyTest(ind)
    for i, slot in ipairs(ind.highlights) do
        showSlot(slot.icon, slot.glow, TEST_HIGHLIGHTS[i], 15, GetTime() + 10)
    end
    showSlot(ind.ccIcon, ind.ccGlow, TEST_CC, 8, GetTime() + 6)
    showSlot(ind.defensiveIcon, ind.defensiveGlow, TEST_DEFENSIVE, 8, GetTime() + 5)
end

local function updateFrame(frame)
    local ind = frame.cleanIndicators
    if not ind then return end
    if testMode then applyTest(ind); return end
    if not isHealer then hideAll(ind); return end
    local unit = frame.displayedUnit or frame.unit
    if not unit or not UnitExists(unit) then hideAll(ind); return end

    collectHighlights(unit)
    collectCC(unit)
    collectDefensive(unit)

    for i, slot in ipairs(ind.highlights) do
        local h = highlights[i]
        if h then
            showSlot(slot.icon, slot.glow, h.spellId, h.duration, h.expires)
        else
            hideSlot(slot.icon, slot.glow)
        end
    end

    if cc.spellId then
        showSlot(ind.ccIcon, ind.ccGlow, cc.spellId, cc.duration, cc.expires)
    else
        hideSlot(ind.ccIcon, ind.ccGlow)
    end

    if defensive.spellId then
        showSlot(ind.defensiveIcon, ind.defensiveGlow, defensive.spellId, defensive.duration, defensive.expires)
    else
        hideSlot(ind.defensiveIcon, ind.defensiveGlow)
    end
end

local function refreshFrames()
    for frame in pairs(trackedFrames) do
        if not frame:IsForbidden() then updateFrame(frame) end
    end
end

local function refreshSpec()
    local idx = GetSpecialization and GetSpecialization()
    local id = idx and GetSpecializationInfo and GetSpecializationInfo(idx)
    isHealer = HEALER_SPECS[id] == true
end

local function onSetup(frame)
    buildIndicators(frame)
    layoutIndicators(frame)
    updateFrame(frame)
end

hooksecurefunc("DefaultCompactUnitFrameSetup", onSetup)
hooksecurefunc("DefaultCompactMiniFrameSetup", onSetup)
hooksecurefunc("CompactUnitFrame_UpdateAll", onSetup)

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
