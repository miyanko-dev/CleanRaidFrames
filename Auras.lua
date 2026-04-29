local _, ns = ...

local INSET = 2
local GLOW_SCALE = 1.5
local HEALER_SIZE = 22
local CC_SIZE = 32
local DEFENSIVE_SIZE = 22

local CC_TEXTURE = 135860
local DEFENSIVE_TEXTURE = 132341
local DISPEL_GLOW_COLOR = {1.0, 0.1, 0.1}
local DEFENSIVE_GLOW_COLOR = {0.1, 1.0, 0.1}

-- Tracked healer buff spellIds; any match is shown in discovery order with a golden glow
local HEALER_SPELLS = {
    [364343] = true,  -- Echo (Evoker)
    [366155] = true,  -- Reversion (Evoker)
    [33763]  = true,  -- Lifebloom (Druid)
    [8936]   = true,  -- Regrowth (Druid)
    [194384] = true,  -- Atonement (Priest)
    [115175] = true,  -- Soothing Mist (Monk)
    [124682] = true,  -- Enveloping Mist (Monk)
    [53563]  = true,  -- Beacon of Light (Paladin)
    [156910] = true,  -- Beacon of Faith (Paladin)
    [1244893]= true,  -- Beacon of the Savior (Paladin)
}

local frames = {}
ns.frames = frames

local function isAllowedFrame(frame)
    return frame and CompactUnitFrame_IsPartyFrame and CompactUnitFrame_IsPartyFrame(frame)
end

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

local HEALER_SLOT_COUNT = 4

-- Collect tracked healer buffs in discovery order, capped at HEALER_SLOT_COUNT
local function collectHealerBuffs(unit, out)
    local count = 0
    AuraUtil.ForEachAura(unit, "HELPFUL|PLAYER", nil, function(aura)
        if aura then
            local ok, match = pcall(function() return HEALER_SPELLS[aura.spellId] end)
            if ok and match then
                count = count + 1
                out[count] = aura.spellId
                if count >= HEALER_SLOT_COUNT then return true end
            end
        end
    end, true)
    return count
end

-- Detect CC in one pass: any CROWD_CONTROL aura sets hasCC; an entry that is also RAID_PLAYER_DISPELLABLE sets dispellable
local function scanCC(unit)
    local hasCC, dispellable = false, false
    AuraUtil.ForEachAura(unit, "HARMFUL|CROWD_CONTROL", nil, function()
        hasCC = true
        return true
    end, true)
    if hasCC then
        AuraUtil.ForEachAura(unit, "HARMFUL|CROWD_CONTROL|RAID_PLAYER_DISPELLABLE", nil, function()
            dispellable = true
            return true
        end, true)
    end
    return hasCC, dispellable
end

local function hasBigDefensive(unit)
    local found = false
    local mark = function(a)
        local ok, exp = pcall(function() return a and a.expirationTime end)
        if ok and exp and exp > 0 then
            found = true
            return true
        end
    end
    AuraUtil.ForEachAura(unit, "HELPFUL|BIG_DEFENSIVE", nil, mark, true)
    return found
end

local function ensureIndicators(frame)
    if not isAllowedFrame(frame) or frame.cleanIndicators then return end

    local healerIcons = {}
    local healerGlows = {}
    for i = 1, HEALER_SLOT_COUNT do
        local icon = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        icon:SetSize(HEALER_SIZE, HEALER_SIZE)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        if i == 1 then
            icon:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -INSET, -INSET)
        else
            icon:SetPoint("TOPRIGHT", healerIcons[i - 1], "TOPLEFT", -INSET, 0)
        end
        icon:Hide()
        healerIcons[i] = icon
        healerGlows[i] = buildGlow(frame, icon, HEALER_SIZE, nil)
    end

    local cc = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    cc:SetTexture(CC_TEXTURE)
    cc:SetSize(CC_SIZE, CC_SIZE)
    cc:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", INSET, INSET)
    cc:Hide()

    local defensive = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    defensive:SetTexture(DEFENSIVE_TEXTURE)
    defensive:SetSize(DEFENSIVE_SIZE, DEFENSIVE_SIZE)
    defensive:SetPoint("TOPLEFT", frame, "TOPLEFT", INSET, -INSET)
    defensive:Hide()

    frame.cleanIndicators = {
        healerIcons = healerIcons,
        healerGlows = healerGlows,
        cc = cc,
        defensive = defensive,
        ccGlow = buildGlow(frame, cc, CC_SIZE, DISPEL_GLOW_COLOR),
        defensiveGlow = buildGlow(frame, defensive, DEFENSIVE_SIZE, DEFENSIVE_GLOW_COLOR),
    }
    frames[frame] = true
end

local healerScratch = {}

local function updateFrame(frame)
    local ind = frame.cleanIndicators
    if not ind then return end
    local unit = frame.displayedUnit or frame.unit
    if not unit or not UnitExists(unit) then
        for i = 1, HEALER_SLOT_COUNT do
            ind.healerIcons[i]:Hide()
            hideGlow(ind.healerGlows[i])
        end
        ind.cc:Hide()
        ind.defensive:Hide()
        hideGlow(ind.ccGlow)
        hideGlow(ind.defensiveGlow)
        return
    end

    for i = #healerScratch, 1, -1 do healerScratch[i] = nil end
    local healerCount = collectHealerBuffs(unit, healerScratch)
    for i = 1, HEALER_SLOT_COUNT do
        local spellId = healerScratch[i]
        if spellId and i <= healerCount then
            local tex = C_Spell.GetSpellTexture(spellId)
            if tex then ind.healerIcons[i]:SetTexture(tex) end
            ind.healerIcons[i]:Show()
            showGlow(ind.healerGlows[i])
        else
            ind.healerIcons[i]:Hide()
            hideGlow(ind.healerGlows[i])
        end
    end

    local hasCC, dispellable = scanCC(unit)
    if hasCC then
        ind.cc:Show()
        if dispellable then
            showGlow(ind.ccGlow)
        else
            hideGlow(ind.ccGlow)
        end
    else
        ind.cc:Hide()
        hideGlow(ind.ccGlow)
    end

    if hasBigDefensive(unit) then
        ind.defensive:Show()
        showGlow(ind.defensiveGlow)
    else
        ind.defensive:Hide()
        hideGlow(ind.defensiveGlow)
    end
end

-- Refresh every tracked frame; avoids UnitIsUnit cross-token match which throws under tainted execution
local function dispatch()
    for frame in pairs(frames) do
        if not frame:IsForbidden() then
            updateFrame(frame)
        end
    end
end

hooksecurefunc("DefaultCompactUnitFrameSetup", function(frame)
    ensureIndicators(frame)
    updateFrame(frame)
end)
hooksecurefunc("DefaultCompactMiniFrameSetup", function(frame)
    ensureIndicators(frame)
    updateFrame(frame)
end)
hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
    ensureIndicators(frame)
    updateFrame(frame)
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("UNIT_AURA")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if GetCVar("raidFramesDisplayDebuffs") ~= "0" then
            SetCVar("raidFramesDisplayDebuffs", "0")
        end
        if GetCVar("raidFramesCenterBigDefensive") ~= "0" then
            SetCVar("raidFramesCenterBigDefensive", "0")
        end
    end
    dispatch()
end)
