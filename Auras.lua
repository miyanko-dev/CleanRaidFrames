local _, ns = ...

-- =========================================================================
-- Shared constants
-- =========================================================================

local INSET = 2
local GLOW_SCALE = 1.5

local HEALER_SIZE = 22
local CC_SIZE = 32
local DEFENSIVE_SIZE = 24

local DISPEL_GLOW_COLOR = {1.0, 0.1, 0.1}
local DEFENSIVE_GLOW_COLOR = {0.1, 1.0, 0.1}

local CC_TEXTURE = 135894
local NON_DISPEL_TEXTURE = 135860
local DEFENSIVE_TEXTURE = 132341

-- Healer spell IDs in priority order, via class buff list, to pick the displayed icon
local HEALER_SPELLS = {
    194384, -- Atonement (Priest)
    214206, -- Atonement (Shadow PvP talent variant)
    53563,  -- Beacon of Light (Paladin)
    156910, -- Beacon of Faith (Paladin)
    200025, -- Beacon of Virtue (Paladin)
    115175, -- Soothing Mist (Monk)
    33763,  -- Lifebloom (Druid)
    188550, -- Lifebloom (Undergrowth talent)
    366155, -- Reversion (Evoker)
    974,    -- Earth Shield (Shaman)
    61295,  -- Riptide (Shaman)
    774,    -- Rejuvenation (Druid)
    139,    -- Renew (Priest)
}

-- Build static spellId→rank lookup so PvP-talent variants match even when IsPlayerSpell returns false
local HEALER_RANK = {}
for rank, id in ipairs(HEALER_SPELLS) do
    HEALER_RANK[id] = rank
end

-- =========================================================================
-- Shared helpers
-- =========================================================================

local healerFrames = {}
local ccFrames = {}
local nonDispelFrames = {}
local defensiveFrames = {}
ns.healerFrames = healerFrames
ns.ccFrames = ccFrames
ns.nonDispelFrames = nonDispelFrames
ns.defensiveFrames = defensiveFrames

-- Restrict attachment to raid and party compact frames via groupType to exclude arena and nameplates
local function isAllowedFrame(frame)
    if not frame or not CompactUnitFrame_IsPartyFrame then return false end
    return CompactUnitFrame_IsPartyFrame(frame)
end

local function unitsMatch(a, b)
    if a == b then return true end
    local result = false
    pcall(function() if UnitIsUnit(a, b) then result = true end end)
    return result
end

-- Build proc glow overlay via SpellAlert template; color nil keeps the default gold flipbook
local function buildGlow(frame, anchor, size, color)
    local glow = CreateFrame("Frame", nil, frame, "ActionButtonSpellAlertTemplate")
    glow:SetPoint("CENTER", anchor, "CENTER")
    glow:SetSize(size * GLOW_SCALE, size * GLOW_SCALE)
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
        glow.ProcLoop:Play()
    end
end

local function hideGlow(glow)
    if glow and glow:IsShown() then
        glow.ProcLoop:Stop()
        glow:Hide()
    end
end

-- =========================================================================
-- Healer HoT indicator (top-right): shows highest-priority helpful buff
-- =========================================================================

-- Resolve the highest-priority tracked buff on unit; pcall the table lookup since arena secret-strings type as "number" but throw on indexing
local function findHealerBuff(unit)
    if not unit or not UnitExists(unit) then return nil end
    local bestRank, bestSpell
    AuraUtil.ForEachAura(unit, "HELPFUL|PLAYER", nil, function(aura)
        if aura then
            local ok, rank = pcall(function() return HEALER_RANK[aura.spellId] end)
            if ok and rank and (not bestRank or rank < bestRank) then
                bestRank, bestSpell = rank, aura.spellId
                if rank == 1 then return true end
            end
        end
    end, true)
    return bestSpell
end

local function ensureHealer(frame)
    if not frame or frame.cleanHealerIndicator then return end
    if not isAllowedFrame(frame) then return end
    local icon = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    icon:SetSize(HEALER_SIZE, HEALER_SIZE)
    icon:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -INSET, -INSET)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:Hide()
    frame.cleanHealerIndicator = icon
    frame.cleanHealerGlow = buildGlow(frame, icon, HEALER_SIZE, nil)
    healerFrames[frame] = true
end

local function updateHealer(frame)
    local icon = frame.cleanHealerIndicator
    if not icon then return end
    local unit = frame.displayedUnit or frame.unit
    if not unit or not UnitExists(unit) then
        icon:Hide()
        hideGlow(frame.cleanHealerGlow)
        return
    end
    local spellId = findHealerBuff(unit)
    if spellId then
        local tex = C_Spell.GetSpellTexture(spellId)
        if tex then icon:SetTexture(tex) end
        icon:Show()
        showGlow(frame.cleanHealerGlow)
    else
        icon:Hide()
        hideGlow(frame.cleanHealerGlow)
    end
end

-- =========================================================================
-- Dispellable CC indicator (bottom-left slot 0): red glow
-- =========================================================================

-- Scan harmful auras via combined CROWD_CONTROL and RAID_PLAYER_DISPELLABLE filter to detect dispellable CC
local function hasDispellableCC(unit)
    if not unit or not UnitExists(unit) then return false end
    local found = false
    AuraUtil.ForEachAura(unit, "HARMFUL|CROWD_CONTROL|RAID_PLAYER_DISPELLABLE", nil, function(aura)
        if aura then
            found = true
            return true
        end
    end, true)
    return found
end

local function ensureDispelCC(frame)
    if not frame or frame.cleanCCIndicator then return end
    if not isAllowedFrame(frame) then return end
    local icon = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    icon:SetTexture(CC_TEXTURE)
    icon:SetSize(CC_SIZE, CC_SIZE)
    icon:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", INSET, INSET)
    icon:Hide()
    frame.cleanCCIndicator = icon
    frame.cleanCCGlow = buildGlow(frame, icon, CC_SIZE, DISPEL_GLOW_COLOR)
    ccFrames[frame] = true
end

local function updateDispelCC(frame)
    local icon = frame.cleanCCIndicator
    if not icon then return end
    local unit = frame.displayedUnit or frame.unit
    if not unit or not UnitExists(unit) then
        icon:Hide()
        hideGlow(frame.cleanCCGlow)
        return
    end
    local show = hasDispellableCC(unit)
    icon:SetShown(show)
    if show then
        showGlow(frame.cleanCCGlow)
    else
        hideGlow(frame.cleanCCGlow)
    end
end

-- =========================================================================
-- Non-dispellable CC indicator (bottom-left slot 1): icon only, no border
-- =========================================================================

-- Scan harmful CC auras; pcall the dispelName compare since arena secret-strings throw on equality with regular strings
local function hasNonDispellableCC(unit)
    if not unit or not UnitExists(unit) then return false end
    local found = false
    AuraUtil.ForEachAura(unit, "HARMFUL|CROWD_CONTROL", nil, function(aura)
        if aura then
            local ok, dispellable = pcall(function()
                local name = aura.dispelName
                return name ~= nil and name ~= ""
            end)
            if ok and not dispellable then
                found = true
                return true
            end
        end
    end, true)
    return found
end

local function ensureNonDispelCC(frame)
    if not frame or frame.cleanNonDispelIndicator then return end
    if not isAllowedFrame(frame) then return end
    local icon = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    icon:SetTexture(NON_DISPEL_TEXTURE)
    icon:SetSize(CC_SIZE, CC_SIZE)
    icon:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", INSET, INSET)
    icon:Hide()
    frame.cleanNonDispelIndicator = icon
    nonDispelFrames[frame] = true
end

-- Suppress non-dispel icon when dispellable CC is present so only the actionable icon shows
local function updateNonDispelCC(frame)
    local icon = frame.cleanNonDispelIndicator
    if not icon then return end
    local unit = frame.displayedUnit or frame.unit
    if not unit or not UnitExists(unit) then
        icon:Hide()
        return
    end
    local dispel = frame.cleanCCIndicator
    if dispel and dispel:IsShown() then
        icon:Hide()
        return
    end
    icon:SetShown(hasNonDispellableCC(unit))
end

-- =========================================================================
-- Big Defensive indicator (top-left): green glow
-- =========================================================================

-- Use server-side BIG_DEFENSIVE and EXTERNAL_DEFENSIVE filters so the slot list is pre-filtered and no aura fields need to be read
local function hasBigDefensive(unit)
    if not unit or not UnitExists(unit) then return false end
    local found = false
    local mark = function() found = true return true end
    AuraUtil.ForEachAura(unit, "HELPFUL|BIG_DEFENSIVE", nil, mark, true)
    if found then return true end
    AuraUtil.ForEachAura(unit, "HELPFUL|EXTERNAL_DEFENSIVE", nil, mark, true)
    return found
end

local function ensureDefensive(frame)
    if not frame or frame.cleanDefensiveIndicator then return end
    if not isAllowedFrame(frame) then return end
    local icon = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    icon:SetTexture(DEFENSIVE_TEXTURE)
    icon:SetSize(DEFENSIVE_SIZE, DEFENSIVE_SIZE)
    icon:SetPoint("TOPLEFT", frame, "TOPLEFT", INSET, -INSET)
    icon:Hide()
    frame.cleanDefensiveIndicator = icon
    frame.cleanDefensiveGlow = buildGlow(frame, icon, DEFENSIVE_SIZE, DEFENSIVE_GLOW_COLOR)
    defensiveFrames[frame] = true
end

local function updateDefensive(frame)
    local icon = frame.cleanDefensiveIndicator
    if not icon then return end
    local unit = frame.displayedUnit or frame.unit
    if not unit or not UnitExists(unit) then
        icon:Hide()
        hideGlow(frame.cleanDefensiveGlow)
        return
    end
    local show = hasBigDefensive(unit)
    icon:SetShown(show)
    if show then
        showGlow(frame.cleanDefensiveGlow)
    else
        hideGlow(frame.cleanDefensiveGlow)
    end
end

-- =========================================================================
-- Shared wiring: hook frame setup and dispatch aura events
-- =========================================================================

local function ensureAll(frame)
    ensureHealer(frame)
    ensureDispelCC(frame)
    ensureNonDispelCC(frame)
    ensureDefensive(frame)
end

local function updateAll(frame)
    updateHealer(frame)
    updateDispelCC(frame)
    updateNonDispelCC(frame)
    updateDefensive(frame)
end

local function dispatch(unit)
    for frame in pairs(healerFrames) do
        if not frame:IsForbidden() then
            local fu = frame.displayedUnit or frame.unit
            if fu and (not unit or unitsMatch(fu, unit)) then
                updateAll(frame)
            end
        end
    end
end

hooksecurefunc("DefaultCompactUnitFrameSetup", function(frame)
    ensureAll(frame)
    updateAll(frame)
end)
hooksecurefunc("DefaultCompactMiniFrameSetup", function(frame)
    ensureAll(frame)
    updateAll(frame)
end)
hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
    ensureAll(frame)
    updateAll(frame)
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("UNIT_AURA")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
-- Skip UNIT_AURA payloads that report no aura churn to avoid redundant ForEachAura scans across all tracked frames
local function unitAuraChanged(info)
    if info == nil then return true end
    if info.isFullUpdate then return true end
    if info.addedAuras and #info.addedAuras > 0 then return true end
    if info.updatedAuraInstanceIDs and #info.updatedAuraInstanceIDs > 0 then return true end
    if info.removedAuraInstanceIDs and #info.removedAuraInstanceIDs > 0 then return true end
    return false
end

events:SetScript("OnEvent", function(_, event, unit, info)
    if event == "PLAYER_LOGIN" then
        if GetCVar("raidFramesDisplayDebuffs") ~= "0" then
            SetCVar("raidFramesDisplayDebuffs", "0")
        end
        if GetCVar("raidFramesCenterBigDefensive") ~= "0" then
            SetCVar("raidFramesCenterBigDefensive", "0")
        end
    elseif event == "UNIT_AURA" then
        if unitAuraChanged(info) then dispatch(unit) end
    else
        dispatch(nil)
    end
end)
