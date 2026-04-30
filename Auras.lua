local HRF = HealerRaidFrames

local HIGHLIGHT_SLOTS = HRF.MAX_HIGHLIGHT_SLOTS or 4
local FRAME_INSET = 2
local ICON_SPACING = 2
local GLOW_SCALE = 1.5

local activeSpecConfig = nil
local isHealer = false
local testMode = false
local trackedFrames = {}
-- Map unit-token → frame. The self-frame is registered under both its raid/party
-- token (e.g. "raid5") AND "player" so UNIT_AURA arg1="player" routes correctly
-- for self-cast defensives.
local framesByUnit = {}

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

local function createIcon(parent)
    local icon = CreateFrame("Frame", nil, parent)
    icon.texture = icon:CreateTexture(nil, "OVERLAY", nil, 7)
    icon.texture:SetAllPoints(icon)
    icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:Hide()
    return icon
end

local function showSlot(icon, glow, spellId, useGlow)
    local tex = C_Spell.GetSpellTexture(spellId)
    if tex then icon.texture:SetTexture(tex) end
    icon:Show()
    if useGlow == false then
        hideGlow(glow)
    else
        showGlow(glow)
    end
end

local function hideSlot(icon, glow)
    icon:Hide()
    hideGlow(glow)
end

local function buildIndicators(frame)
    if not isPartyFrame(frame) or frame.cleanIndicators then return end

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
    local hCustom = HRF.GetSectionGlowCustom("highlight")
    local hr, hg, hb = HRF.GetSectionColor("highlight")
    for _, slot in ipairs(ind.highlights) do applyGlowColor(slot.glow, hr, hg, hb, hCustom) end
    for _, key in ipairs(SINGLE_GLOW_SECTIONS) do
        local custom = HRF.GetSectionGlowCustom(key)
        local r, g, b = HRF.GetSectionColor(key)
        applyGlowColor(ind[key .. "Glow"], r, g, b, custom)
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
    local scale = HRF.GetSectionScale and HRF.GetSectionScale(key) or 0.4
    return math.max(8, math.floor(frameHeight * scale + 0.5))
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

local function layoutAllFrames()
    for frame in pairs(trackedFrames) do
        if not frame:IsForbidden() then
            layoutIndicators(frame)
        end
    end
end

-- Arranges the bottom-left debuff slots left→right in fixed priority order:
-- 1) dispellable CC, 2) pure CC, 3) dispellable debuff. Only shown icons take a slot.
local function layoutBottomLeftGrid(frame)
    local ind = frame.cleanIndicators
    if not ind then return end
    local entries = {
        { icon = ind.ccIcon },
        { icon = ind.pureCCIcon },
        { icon = ind.dispelIcon },
    }
    local previous
    for _, entry in ipairs(entries) do
        local icon = entry.icon
        icon:ClearAllPoints()
        if icon:IsShown() then
            if previous then
                icon:SetPoint("BOTTOMLEFT", previous, "BOTTOMRIGHT", ICON_SPACING, 0)
            else
                icon:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", FRAME_INSET, FRAME_INSET)
            end
            previous = icon
        else
            -- Park hidden icons at the anchor so the next Show picks up a valid point.
            icon:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", FRAME_INSET, FRAME_INSET)
        end
    end
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

local function safeAuraInstanceID(aura)
    if not aura then return nil end
    local ok, value = pcall(function() return aura.auraInstanceID end)
    return ok and value or nil
end

local highlights = {}
local cc = {}
local pureCC = {}
local dispel = {}
local defensive = {}
local auraByID = {}
local dispellableCCInstances = {}

local function collectHighlights(unit)
    for i = #highlights, 1, -1 do highlights[i] = nil end
    for k in pairs(auraByID) do auraByID[k] = nil end

    local spec = activeSpecConfig
    if not spec then return end

    -- Count every spell the user has enabled for this spec. The aura walk
    -- can stop once we've found all of them -- at that point every additional
    -- aura is irrelevant to us, so further iteration cannot change the result.
    -- Iterating spec.order (not spec.show) avoids counting stale keys that
    -- may have been left behind by removed/renamed spells in old saved profiles.
    local trackedCount = 0
    for _, spellId in ipairs(spec.order) do
        if spec.show[spellId] then trackedCount = trackedCount + 1 end
    end
    if trackedCount == 0 then return end

    -- HELPFUL|PLAYER is Blizzard's authoritative "buffs cast by the player" filter,
    -- evaluated on the C side. We intentionally do NOT add a Lua-side
    -- isFromPlayerOrPlayerPet guard: some auras (certain Atonement procs, Preservation
    -- Evoker Echo chains, pet-mediated applications) are approved by the filter but
    -- have the field set to nil, which would cause the icon to vanish intermittently.
    local found = 0
    AuraUtil.ForEachAura(unit, "HELPFUL|PLAYER", nil, function(aura)
        local stop = false
        pcall(function()
            if isRestrictedAura(aura) then return end
            local spellId = safeSpellId(aura)
            if spellId and spec.show[spellId] and not auraByID[spellId] then
                auraByID[spellId] = true
                found = found + 1
                if found >= trackedCount then stop = true end
            end
        end)
        if stop then return true end
    end, true)

    for _, spellId in ipairs(spec.order) do
        if spec.show[spellId] and auraByID[spellId] then
            highlights[#highlights + 1] = {
                spellId = spellId,
                useGlow = spec.glow[spellId] == true,
            }
            if #highlights >= HIGHLIGHT_SLOTS then break end
        end
    end
end

-- Captures the first dispellable CC aura and records every dispellable-CC auraInstanceID
-- in dispellableCCInstances so the other passes can skip them (an aura can match
-- multiple filters, e.g. a dispellable CC also passes HARMFUL|CROWD_CONTROL alone).
local function collectCC(unit)
    cc.spellId = nil
    for k in pairs(dispellableCCInstances) do dispellableCCInstances[k] = nil end
    AuraUtil.ForEachAura(unit, "HARMFUL|CROWD_CONTROL|RAID_PLAYER_DISPELLABLE", nil, function(aura)
        pcall(function()
            if isRestrictedAura(aura) then return end
            local spellId = safeSpellId(aura)
            if not spellId then return end
            local instanceId = safeAuraInstanceID(aura)
            if instanceId then dispellableCCInstances[instanceId] = true end
            if not cc.spellId then
                cc.spellId = spellId
            end
        end)
    end, true)
end

-- Pure CC = crowd-control that is NOT dispellable. Skips anything already captured
-- as dispellable CC so we never show the same icon in two adjacent slots.
local function collectPureCC(unit)
    pureCC.spellId = nil
    AuraUtil.ForEachAura(unit, "HARMFUL|CROWD_CONTROL", nil, function(aura)
        local stop = false
        pcall(function()
            if isRestrictedAura(aura) then return end
            local instanceId = safeAuraInstanceID(aura)
            if instanceId and dispellableCCInstances[instanceId] then return end
            local spellId = safeSpellId(aura)
            if not spellId then return end
            pureCC.spellId = spellId
            stop = true
        end)
        if stop then return true end
    end, true)
end

-- Dispellable non-CC debuff. Skips dispellable CC (which owns its own slot).
local function collectDispel(unit)
    dispel.spellId = nil
    AuraUtil.ForEachAura(unit, "HARMFUL|RAID_PLAYER_DISPELLABLE", nil, function(aura)
        local stop = false
        pcall(function()
            if isRestrictedAura(aura) then return end
            local instanceId = safeAuraInstanceID(aura)
            if instanceId and dispellableCCInstances[instanceId] then return end
            local spellId = safeSpellId(aura)
            if not spellId then return end
            dispel.spellId = spellId
            stop = true
        end)
        if stop then return true end
    end, true)
end

-- BIG_DEFENSIVE is Blizzard's curated list of "oh shit" defensive cooldowns.
-- We display whatever Blizzard already flags as big-defensive, no extra filter.
local function collectDefensive(unit)
    defensive.spellId = nil
    AuraUtil.ForEachAura(unit, "HELPFUL|BIG_DEFENSIVE", nil, function(aura)
        local stop = false
        pcall(function()
            if isRestrictedAura(aura) then return end
            local spellId = safeSpellId(aura)
            if not spellId then return end
            defensive.spellId = spellId
            stop = true
        end)
        if stop then return true end
    end, true)
end

local function hideAll(ind)
    for _, slot in ipairs(ind.highlights) do hideSlot(slot.icon, slot.glow) end
    hideSlot(ind.ccIcon, ind.ccGlow)
    hideSlot(ind.pureCCIcon, ind.pureCCGlow)
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
local TEST_CC = 118                       -- Polymorph (dispellable CC)
local TEST_PURE_CC = 408                  -- Kidney Shot (non-dispellable CC)
local TEST_DISPEL = 589                   -- Shadow Word: Pain
local TEST_DEFENSIVE = 31850              -- Ardent Defender

local function applyTest(frame)
    local ind = frame.cleanIndicators
    if not ind then return end
    local showHighlight = HRF.GetSectionShow("highlight")
    local spec = activeSpecConfig

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
            showSlot(slot.icon, slot.glow, entry.spellId, entry.useGlow)
        else
            hideSlot(slot.icon, slot.glow)
        end
    end

    local showCC = HRF.GetSectionShow("cc")
    local glowCC = HRF.GetSectionGlow("cc")
    local showPureCC = HRF.GetSectionShow("pureCC")
    local glowPureCC = HRF.GetSectionGlow("pureCC")
    local showDispel = HRF.GetSectionShow("dispel")
    local glowDispel = HRF.GetSectionGlow("dispel")

    if showCC then
        showSlot(ind.ccIcon, ind.ccGlow, TEST_CC, glowCC)
    else
        hideSlot(ind.ccIcon, ind.ccGlow)
    end
    if showPureCC then
        showSlot(ind.pureCCIcon, ind.pureCCGlow, TEST_PURE_CC, glowPureCC)
    else
        hideSlot(ind.pureCCIcon, ind.pureCCGlow)
    end
    if showDispel then
        showSlot(ind.dispelIcon, ind.dispelGlow, TEST_DISPEL, glowDispel)
    else
        hideSlot(ind.dispelIcon, ind.dispelGlow)
    end

    if HRF.GetSectionShow("defensive") then
        showSlot(ind.defensiveIcon, ind.defensiveGlow, TEST_DEFENSIVE, HRF.GetSectionGlow("defensive"))
    else
        hideSlot(ind.defensiveIcon, ind.defensiveGlow)
    end
    layoutBottomLeftGrid(frame)
end

local function updateFrame(frame)
    local ind = frame.cleanIndicators
    if not ind then return end
    if testMode then applyTest(frame); return end
    if not isHealer then hideAll(ind); return end
    local unit = frame.displayedUnit or frame.unit
    if not unit or not UnitExists(unit) then hideAll(ind); return end

    local showHighlight = HRF.GetSectionShow("highlight")
    local showDef = HRF.GetSectionShow("defensive")
    local glowDef = HRF.GetSectionGlow("defensive")
    local showCC = HRF.GetSectionShow("cc")
    local glowCC = HRF.GetSectionGlow("cc")
    local showPureCC = HRF.GetSectionShow("pureCC")
    local glowPureCC = HRF.GetSectionGlow("pureCC")
    local showDispel = HRF.GetSectionShow("dispel")
    local glowDispel = HRF.GetSectionGlow("dispel")

    if showHighlight then collectHighlights(unit) else for i = #highlights, 1, -1 do highlights[i] = nil end end
    -- Always run the dispellable-CC pass when any bottom-left slot is visible so pureCC
    -- and dispel can dedupe against it, then suppress the slot if the user disabled it.
    if showCC or showPureCC or showDispel then
        collectCC(unit)
    else
        cc.spellId = nil
        for k in pairs(dispellableCCInstances) do dispellableCCInstances[k] = nil end
    end
    if showPureCC then collectPureCC(unit) else pureCC.spellId = nil end
    if showDispel then collectDispel(unit) else dispel.spellId = nil end
    if showDef then collectDefensive(unit) else defensive.spellId = nil end

    for i, slot in ipairs(ind.highlights) do
        local h = highlights[i]
        if h then
            showSlot(slot.icon, slot.glow, h.spellId, h.useGlow)
        else
            hideSlot(slot.icon, slot.glow)
        end
    end

    if showCC and cc.spellId then
        showSlot(ind.ccIcon, ind.ccGlow, cc.spellId, glowCC)
    else
        hideSlot(ind.ccIcon, ind.ccGlow)
    end
    if showPureCC and pureCC.spellId then
        showSlot(ind.pureCCIcon, ind.pureCCGlow, pureCC.spellId, glowPureCC)
    else
        hideSlot(ind.pureCCIcon, ind.pureCCGlow)
    end
    if showDispel and dispel.spellId then
        showSlot(ind.dispelIcon, ind.dispelGlow, dispel.spellId, glowDispel)
    else
        hideSlot(ind.dispelIcon, ind.dispelGlow)
    end

    if defensive.spellId then
        showSlot(ind.defensiveIcon, ind.defensiveGlow, defensive.spellId, glowDef)
    else
        hideSlot(ind.defensiveIcon, ind.defensiveGlow)
    end

    layoutBottomLeftGrid(frame)
end

-- Index the frame under every token that resolves to the same unit:
-- * frame.unit (e.g. "raid5") -- the stable group slot
-- * frame.displayedUnit (e.g. "vehicle5") -- what the frame actually shows when the
--   player is in a vehicle or otherwise redirected
-- * "player" when the frame is the local player -- UNIT_AURA for self fires with
--   arg1="player" even when the frame is showing raidN/partyN
-- Missing any of these paths causes intermittent UNIT_AURA misses.
local function registerFrameUnit(frame)
    local unit = frame.unit
    local displayed = frame.displayedUnit
    if unit then framesByUnit[unit] = frame end
    if displayed and displayed ~= unit then framesByUnit[displayed] = frame end
    local probe = displayed or unit
    if probe and UnitIsUnit(probe, "player") then
        framesByUnit["player"] = frame
    end
end

local function rebuildFramesByUnit()
    for k in pairs(framesByUnit) do framesByUnit[k] = nil end
    for frame in pairs(trackedFrames) do
        if not frame:IsForbidden() then
            registerFrameUnit(frame)
        end
    end
end

-- Used only for full-group events (roster/spec/test/setting change). Per-unit
-- UNIT_AURA takes the fast path via updateFrame(framesByUnit[unit]).
local function refreshAllFrames()
    for frame in pairs(trackedFrames) do
        if not frame:IsForbidden() then
            updateFrame(frame)
        end
    end
end

local pendingRefresh = false
local function scheduleRefreshAllFrames()
    if pendingRefresh then return end
    pendingRefresh = true
    C_Timer.After(0, function()
        pendingRefresh = false
        rebuildFramesByUnit()
        refreshAllFrames()
    end)
end

local function refreshSpec()
    local id = HRF.GetActiveSpec and HRF.GetActiveSpec()
    isHealer = HRF.IsTrackedSpec and HRF.IsTrackedSpec(id) or false
    activeSpecConfig = (isHealer and HRF.GetSpecConfig) and HRF.GetSpecConfig(id) or nil
end

if HRF.Subscribe then
    HRF.Subscribe(function()
        -- Settings changed: recolor (cheap) and schedule a coalesced full refresh.
        applyColorsAllFrames()
        scheduleRefreshAllFrames()
    end)
end

local function onSetup(frame)
    local wasNew = not frame.cleanIndicators
    buildIndicators(frame)
    if wasNew then
        local ind = frame.cleanIndicators
        if ind then applyColors(ind) end
    end
    layoutIndicators(frame)
    registerFrameUnit(frame)
    updateFrame(frame)
end

hooksecurefunc("DefaultCompactUnitFrameSetup", onSetup)
hooksecurefunc("DefaultCompactMiniFrameSetup", onSetup)
-- Hook CompactUnitFrame_SetUnit so we track unit reassignments without paying
-- the full CompactUnitFrame_UpdateAll cost on every role/flag/range change.
hooksecurefunc("CompactUnitFrame_SetUnit", function(frame)
    if not frame or frame:IsForbidden() then return end
    if not frame.cleanIndicators then return end
    -- Remove stale unit mappings before re-registering; a frame may have shown
    -- another unit before this reassignment.
    for k, v in pairs(framesByUnit) do
        if v == frame then framesByUnit[k] = nil end
    end
    registerFrameUnit(frame)
    -- Re-layout in case the frame's size was zero at initial setup or has changed.
    layoutIndicators(frame)
    updateFrame(frame)
end)

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
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("UI_SCALE_CHANGED")
eventFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
-- UNIT_AURA stays registered globally, but the handler exits in O(1) for units we
-- don't track (nameplates, boss, target, focus, pets, arena). Only party/raid slots
-- ever find a matching frame and run updateFrame.
eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 == "HealerRaidFrames" and HRF.EnsureInitialized then
            HRF.EnsureInitialized()
        end
        return
    end
    if event == "UNIT_AURA" then
        local frame = framesByUnit[arg1]
        if frame and not frame:IsForbidden() then
            updateFrame(frame)
        end
        return
    end
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
        enforceCVars()
    end
    if event == "PLAYER_LOGIN" or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        refreshSpec()
    end
    if event == "PLAYER_ENTERING_WORLD" or event == "UI_SCALE_CHANGED" or event == "EDIT_MODE_LAYOUTS_UPDATED" then
        -- Raid profile / scale changed: re-run layout so icon sizes match the new frame height.
        layoutAllFrames()
    end
    if event == "GROUP_ROSTER_UPDATE" then
        scheduleRefreshAllFrames()
        return
    end
    if event == "PLAYER_LOGIN" and HealerRaidFramesDB and not HealerRaidFramesDB.introShown then
        HealerRaidFramesDB.introShown = true
        local prefix = "|cff33ff99[Healer Raid Frames]|r"
        print(prefix .. " enabled: adds three icon overlays to your raid frames:")
        print("  |cffffd100Top-right|r: your healer buffs on the target (configurable per spec)")
        print("  |cffffd100Top-left|r: the target's active defensive cooldown")
        print("  |cffffd100Bottom-left|r: dispellable CC, non-dispellable CC, and dispellable debuffs (grows left to right)")
        print("Type |cff33ff99/hrf|r to configure or disable any of these.")
    end
    scheduleRefreshAllFrames()
end)

function HRF.IsTestModeOn()
    return testMode
end

function HRF.ToggleTestMode()
    testMode = not testMode
    print("|cff33ff99HealerRaidFrames|r: test mode " .. (testMode and "ON" or "OFF"))
    scheduleRefreshAllFrames()
    return testMode
end
