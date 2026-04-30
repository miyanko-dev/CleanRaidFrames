local HRF = HealerRaidFrames

local HIGHLIGHT_SLOTS = HRF.MAX_HIGHLIGHT_SLOTS or 4
local FRAME_INSET = 2
local ICON_SPACING = 2
local GLOW_SCALE = 1.5
local MAX_DEFENSIVE_DURATION = 30

local activeSpec = nil
local isHealer = false
local testMode = false
local trackedFrames = {}

local function isPartyFrame(frame)
    return frame and CompactUnitFrame_IsPartyFrame and CompactUnitFrame_IsPartyFrame(frame)
end

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
    -- Desaturating the flipbook strips the baked golden tint so the vertex color fully takes over.
    -- When custom is disabled we restore the native gold by un-desaturating and forcing white.
    local loop = glow.ProcLoopFlipbook
    local start = glow.ProcStartFlipbook
    if loop and loop.SetDesaturated then loop:SetDesaturated(custom and true or false) end
    if start and start.SetDesaturated then start:SetDesaturated(custom and true or false) end
    if custom then
        loop:SetVertexColor(r, g, b)
        start:SetVertexColor(r, g, b)
    else
        loop:SetVertexColor(1, 1, 1)
        start:SetVertexColor(1, 1, 1)
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

local function formatCountdown(remaining)
    if remaining >= 60 then
        return string.format("%dm", math.floor(remaining / 60 + 0.5))
    end
    return string.format("%d", math.floor(remaining + 0.5))
end

local function updateCountdown(icon)
    local expires = icon.expires
    if not expires then
        icon.countdown:SetText("")
        return
    end
    local remaining = expires - GetTime()
    if remaining <= 0 then
        icon.countdown:SetText("")
        return
    end
    icon.countdown:SetText(formatCountdown(remaining))
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
    icon.cooldown:SetHideCountdownNumbers(true)
    icon.cooldown:SetDrawBling(false)
    icon.cooldown:SetDrawEdge(false)
    icon.countdown = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    icon.countdown:SetPoint("CENTER", icon, "CENTER", 0, 0)
    icon.countdown:SetTextColor(1, 1, 1, 1)
    icon.countdown:SetDrawLayer("OVERLAY", 7)
    icon:SetScript("OnUpdate", function(self, elapsed)
        self.countdownElapsed = (self.countdownElapsed or 0) + elapsed
        if self.countdownElapsed < 0.1 then return end
        self.countdownElapsed = 0
        updateCountdown(self)
    end)
    icon:Hide()
    return icon
end

local function setCooldown(icon, duration, expires)
    local ok = pcall(function()
        if duration and expires and duration > 0 and expires > 0 then
            icon.cooldown:SetCooldown(expires - duration, duration)
            icon.expires = expires
        else
            icon.cooldown:Clear()
            icon.expires = nil
        end
    end)
    if not ok then
        icon.cooldown:Clear()
        icon.expires = nil
    end
    updateCountdown(icon)
end

local function showSlot(icon, glow, spellId, duration, expires, useGlow)
    local tex = C_Spell.GetSpellTexture(spellId)
    if tex then icon.texture:SetTexture(tex) end
    setCooldown(icon, duration, expires)
    icon:Show()
    if useGlow == false then
        hideGlow(glow)
    else
        showGlow(glow)
    end
end

local function hideSlot(icon, glow)
    icon:Hide()
    icon.cooldown:Clear()
    icon.expires = nil
    icon.countdown:SetText("")
    hideGlow(glow)
end

local function buildIndicators(frame)
    if not isPartyFrame(frame) or frame.cleanIndicators then return end

    local overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints(frame)
    overlay:SetFrameLevel((frame:GetFrameLevel() or 0) + 250)

    local highlights = {}
    for i = 1, HIGHLIGHT_SLOTS do
        local icon = createIcon(overlay, false)
        highlights[i] = { icon = icon, glow = createGlow(overlay, icon) }
    end

    local ccIcon = createIcon(overlay, false)
    local dispelIcon = createIcon(overlay, false)
    local defensiveIcon = createIcon(overlay, false)

    frame.cleanIndicators = {
        highlights = highlights,
        ccIcon = ccIcon,
        ccGlow = createGlow(overlay, ccIcon),
        dispelIcon = dispelIcon,
        dispelGlow = createGlow(overlay, dispelIcon),
        defensiveIcon = defensiveIcon,
        defensiveGlow = createGlow(overlay, defensiveIcon),
    }
    trackedFrames[frame] = true
end

local function applyColors(ind)
    local hCustom = HRF.GetSectionGlowCustom("highlight")
    local hr, hg, hb = HRF.GetSectionColor("highlight")
    for _, slot in ipairs(ind.highlights) do applyGlowColor(slot.glow, hr, hg, hb, hCustom) end
    local dCustom = HRF.GetSectionGlowCustom("defensive")
    local dr, dg, db = HRF.GetSectionColor("defensive")
    applyGlowColor(ind.defensiveGlow, dr, dg, db, dCustom)
    local cCustom = HRF.GetSectionGlowCustom("cc")
    local cr, cg, cb = HRF.GetSectionColor("cc")
    applyGlowColor(ind.ccGlow, cr, cg, cb, cCustom)
    local pCustom = HRF.GetSectionGlowCustom("dispel")
    local pr, pg, pb = HRF.GetSectionColor("dispel")
    applyGlowColor(ind.dispelGlow, pr, pg, pb, pCustom)
end

local function sizeFor(frameHeight, key)
    local scale = HRF.GetSectionScale and HRF.GetSectionScale(key) or 0.4
    return math.max(8, math.floor(frameHeight * scale + 0.5))
end

local function styleCountdown(fs, size)
    local fontSize = math.max(8, math.floor(size * 0.6 + 0.5))
    local font = fs:GetFont()
    if font then fs:SetFont(font, fontSize, "OUTLINE") end
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
        styleCountdown(slot.icon.countdown, highlightSize)
    end

    local ccSize = sizeFor(frameHeight, "cc")
    ind.ccIcon:SetSize(ccSize, ccSize)
    ind.ccIcon:ClearAllPoints()
    ind.ccIcon:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", FRAME_INSET, FRAME_INSET)
    ind.ccGlow:SetSize(ccSize * GLOW_SCALE, ccSize * GLOW_SCALE)
    styleCountdown(ind.ccIcon.countdown, ccSize)

    local dispelSize = sizeFor(frameHeight, "dispel")
    ind.dispelIcon:SetSize(dispelSize, dispelSize)
    ind.dispelIcon:ClearAllPoints()
    ind.dispelIcon:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", FRAME_INSET, FRAME_INSET)
    ind.dispelGlow:SetSize(dispelSize * GLOW_SCALE, dispelSize * GLOW_SCALE)
    styleCountdown(ind.dispelIcon.countdown, dispelSize)

    local defSize = sizeFor(frameHeight, "defensive")
    ind.defensiveIcon:SetSize(defSize, defSize)
    ind.defensiveIcon:ClearAllPoints()
    ind.defensiveIcon:SetPoint("TOPLEFT", frame, "TOPLEFT", FRAME_INSET, -FRAME_INSET)
    ind.defensiveGlow:SetSize(defSize * GLOW_SCALE, defSize * GLOW_SCALE)
    styleCountdown(ind.defensiveIcon.countdown, defSize)
end

-- Restricted "private auras" come back from ForEachAura with most fields gated;
-- accessing those fields can leak the "secret keys" error past pcall. Blizzard's
-- own aura processors bail when icon is unreadable (see TargetFrameMixin:ProcessAura).
local function isRestrictedAura(aura)
    if not aura then return true end
    local ok, icon = pcall(function() return aura.icon end)
    if not ok then return true end
    return icon == nil
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
local dispel = {}
local defensive = {}
local auraByID = {}

local function collectHighlights(unit)
    for i = #highlights, 1, -1 do highlights[i] = nil end
    for k in pairs(auraByID) do auraByID[k] = nil end

    local spec = HRF.GetSpecConfig and HRF.GetSpecConfig(activeSpec)
    if not spec then return end

    AuraUtil.ForEachAura(unit, "HELPFUL|PLAYER", nil, function(aura)
        pcall(function()
            if isRestrictedAura(aura) then return end
            if not safeBool(aura, "isFromPlayerOrPlayerPet") then return end
            local spellId = safeSpellId(aura)
            if spellId and spec.show[spellId] and not auraByID[spellId] then
                local duration, expires = safeTiming(aura)
                auraByID[spellId] = { duration = duration, expires = expires }
            end
        end)
    end, true)

    for _, spellId in ipairs(spec.order) do
        if spec.show[spellId] and auraByID[spellId] then
            local a = auraByID[spellId]
            highlights[#highlights + 1] = {
                spellId = spellId,
                duration = a.duration,
                expires = a.expires,
                useGlow = spec.glow[spellId] == true,
            }
            if #highlights >= HIGHLIGHT_SLOTS then break end
        end
    end
end

local function collectCC(unit)
    cc.spellId, cc.duration, cc.expires = nil, nil, nil
    AuraUtil.ForEachAura(unit, "HARMFUL|CROWD_CONTROL|RAID_PLAYER_DISPELLABLE", nil, function(aura)
        local stop = false
        pcall(function()
            if isRestrictedAura(aura) then return end
            local spellId = safeSpellId(aura)
            if not spellId then return end
            local duration, expires = safeTiming(aura)
            if hasNoTimer(duration, expires) then return end
            cc.spellId, cc.duration, cc.expires = spellId, duration, expires
            stop = true
        end)
        if stop then return true end
    end, true)
end

local function collectDispel(unit)
    dispel.spellId, dispel.duration, dispel.expires = nil, nil, nil
    AuraUtil.ForEachAura(unit, "HARMFUL|RAID_PLAYER_DISPELLABLE", nil, function(aura)
        local stop = false
        pcall(function()
            if isRestrictedAura(aura) then return end
            local spellId = safeSpellId(aura)
            if not spellId then return end
            local duration, expires = safeTiming(aura)
            if hasNoTimer(duration, expires) then return end
            dispel.spellId, dispel.duration, dispel.expires = spellId, duration, expires
            stop = true
        end)
        if stop then return true end
    end, true)
end

local function collectDefensive(unit)
    defensive.spellId, defensive.duration, defensive.expires = nil, nil, nil
    AuraUtil.ForEachAura(unit, "HELPFUL|BIG_DEFENSIVE", nil, function(aura)
        local stop = false
        pcall(function()
            if isRestrictedAura(aura) then return end
            local spellId = safeSpellId(aura)
            if not spellId then return end
            local duration, expires = safeTiming(aura)
            if hasNoTimer(duration, expires) then return end
            if exceedsCap(duration, MAX_DEFENSIVE_DURATION) then return end
            defensive.spellId, defensive.duration, defensive.expires = spellId, duration, expires
            stop = true
        end)
        if stop then return true end
    end, true)
end

local function hideAll(ind)
    for _, slot in ipairs(ind.highlights) do hideSlot(slot.icon, slot.glow) end
    hideSlot(ind.ccIcon, ind.ccGlow)
    hideSlot(ind.dispelIcon, ind.dispelGlow)
    hideSlot(ind.defensiveIcon, ind.defensiveGlow)
end

local TEST_FALLBACK_HIGHLIGHTS = {
    { spellId = 33763 },  -- Lifebloom
    { spellId = 774 },    -- Rejuvenation
    { spellId = 155777 }, -- Germination
    { spellId = 8936 },   -- Regrowth
    { spellId = 48438 },  -- Wild Growth
}
local TEST_CC = 118                       -- Polymorph
local TEST_DISPEL = 589                   -- Shadow Word: Pain
local TEST_DEFENSIVE = 31850              -- Ardent Defender

local function applyTest(ind)
    local showHighlight = HRF.GetSectionShow("highlight")
    local spec = HRF.GetSpecConfig and HRF.GetSpecConfig(activeSpec)

    -- Prefer the user's configured spell order so test mode reflects their setup.
    local entries = {}
    if showHighlight and spec then
        for _, spellId in ipairs(spec.order) do
            if spec.show[spellId] then
                entries[#entries + 1] = { spellId = spellId, useGlow = spec.glow[spellId] == true }
                if #entries >= HIGHLIGHT_SLOTS then break end
            end
        end
    end
    if showHighlight and #entries == 0 then
        for i = 1, math.min(HIGHLIGHT_SLOTS, #TEST_FALLBACK_HIGHLIGHTS) do
            entries[i] = { spellId = TEST_FALLBACK_HIGHLIGHTS[i].spellId, useGlow = true }
        end
    end

    for i, slot in ipairs(ind.highlights) do
        local entry = entries[i]
        if entry then
            showSlot(slot.icon, slot.glow, entry.spellId, 15, GetTime() + 10, entry.useGlow)
        else
            hideSlot(slot.icon, slot.glow)
        end
    end

    local showCC = HRF.GetSectionShow("cc")
    local glowCC = HRF.GetSectionGlow("cc")
    local showDispel = HRF.GetSectionShow("dispel")
    local glowDispel = HRF.GetSectionGlow("dispel")

    if showCC then
        showSlot(ind.ccIcon, ind.ccGlow, TEST_CC, 8, GetTime() + 6, glowCC)
        hideSlot(ind.dispelIcon, ind.dispelGlow)
    elseif showDispel then
        hideSlot(ind.ccIcon, ind.ccGlow)
        showSlot(ind.dispelIcon, ind.dispelGlow, TEST_DISPEL, 12, GetTime() + 9, glowDispel)
    else
        hideSlot(ind.ccIcon, ind.ccGlow)
        hideSlot(ind.dispelIcon, ind.dispelGlow)
    end

    if HRF.GetSectionShow("defensive") then
        showSlot(ind.defensiveIcon, ind.defensiveGlow, TEST_DEFENSIVE, 8, GetTime() + 5, HRF.GetSectionGlow("defensive"))
    else
        hideSlot(ind.defensiveIcon, ind.defensiveGlow)
    end
end

local function updateFrame(frame)
    local ind = frame.cleanIndicators
    if not ind then return end
    applyColors(ind)
    if testMode then applyTest(ind); return end
    if not isHealer then hideAll(ind); return end
    local unit = frame.displayedUnit or frame.unit
    if not unit or not UnitExists(unit) then hideAll(ind); return end

    local showHighlight = HRF.GetSectionShow("highlight")
    local showDef = HRF.GetSectionShow("defensive")
    local glowDef = HRF.GetSectionGlow("defensive")
    local showCC = HRF.GetSectionShow("cc")
    local glowCC = HRF.GetSectionGlow("cc")
    local showDispel = HRF.GetSectionShow("dispel")
    local glowDispel = HRF.GetSectionGlow("dispel")

    if showHighlight then collectHighlights(unit) else for i = #highlights, 1, -1 do highlights[i] = nil end end
    if showCC then collectCC(unit) else cc.spellId = nil end
    if showDispel then collectDispel(unit) else dispel.spellId = nil end
    if showDef then collectDefensive(unit) else defensive.spellId = nil end

    for i, slot in ipairs(ind.highlights) do
        local h = highlights[i]
        if h then
            showSlot(slot.icon, slot.glow, h.spellId, h.duration, h.expires, h.useGlow)
        else
            hideSlot(slot.icon, slot.glow)
        end
    end

    -- CC outranks generic dispellable debuffs; they share the bottom-left slot.
    if cc.spellId then
        showSlot(ind.ccIcon, ind.ccGlow, cc.spellId, cc.duration, cc.expires, glowCC)
        hideSlot(ind.dispelIcon, ind.dispelGlow)
    elseif dispel.spellId then
        hideSlot(ind.ccIcon, ind.ccGlow)
        showSlot(ind.dispelIcon, ind.dispelGlow, dispel.spellId, dispel.duration, dispel.expires, glowDispel)
    else
        hideSlot(ind.ccIcon, ind.ccGlow)
        hideSlot(ind.dispelIcon, ind.dispelGlow)
    end

    if defensive.spellId then
        showSlot(ind.defensiveIcon, ind.defensiveGlow, defensive.spellId, defensive.duration, defensive.expires, glowDef)
    else
        hideSlot(ind.defensiveIcon, ind.defensiveGlow)
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

local function refreshSpec()
    local id = HRF.GetActiveSpec and HRF.GetActiveSpec()
    activeSpec = id
    isHealer = HRF.IsTrackedSpec and HRF.IsTrackedSpec(id) or false
end

if HRF.Subscribe then
    HRF.Subscribe(function() refreshFrames() end)
end

local function onSetup(frame)
    buildIndicators(frame)
    layoutIndicators(frame)
    updateFrame(frame)
end

hooksecurefunc("DefaultCompactUnitFrameSetup", onSetup)
hooksecurefunc("DefaultCompactMiniFrameSetup", onSetup)
hooksecurefunc("CompactUnitFrame_UpdateAll", onSetup)

-- Suppresses Blizzard's stock debuff row (bottom-right) and centered big-defensive
-- icon so they don't overlap our custom overlays.
local SUPPRESSED_CVARS = { "raidFramesDisplayDebuffs", "raidFramesCenterBigDefensive" }

local function enforceCVars()
    if InCombatLockdown and InCombatLockdown() then return false end
    for _, cvar in ipairs(SUPPRESSED_CVARS) do
        if GetCVar(cvar) ~= "0" then
            pcall(SetCVar, cvar, "0")
        end
    end
    return true
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "HealerRaidFrames" and HRF.EnsureInitialized then
            HRF.EnsureInitialized()
        end
        return
    end
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
        enforceCVars()
    end
    if event == "PLAYER_LOGIN" or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        refreshSpec()
    end
    if event == "PLAYER_LOGIN" and HealerRaidFramesDB and not HealerRaidFramesDB.introShown then
        HealerRaidFramesDB.introShown = true
        local prefix = "|cff33ff99[Healer Raid Frames]|r"
        print(prefix .. " enabled: adds three icon overlays to your raid frames:")
        print("  |cffffd100Top-right|r: your healer buffs on the target (configurable per spec)")
        print("  |cffffd100Top-left|r: the target's active defensive cooldown")
        print("  |cffffd100Bottom-left|r: dispellable CC; otherwise any dispellable debuff")
        print("Type |cff33ff99/hrf|r to configure or disable any of these.")
    end
    refreshFrames()
end)

function HRF.IsTestModeOn()
    return testMode
end

function HRF.ToggleTestMode()
    testMode = not testMode
    print("|cff33ff99HealerRaidFrames|r: test mode " .. (testMode and "ON" or "OFF"))
    refreshFrames()
    return testMode
end
