local INDICATOR_SIZE = 22
local INDICATOR_INSET = 2
local GLOW_SCALE = 1.6

-- Tracked healer spell IDs in priority order, via class buff list, to pick the displayed icon
local TRACKED_SPELLS = {
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

local indicators = {}

-- Build golden proc glow overlay via SpellAlert template to replicate action button proc highlight
local function buildGlow(frame, anchor)
    local glow = CreateFrame("Frame", nil, frame, "ActionButtonSpellAlertTemplate")
    glow:SetPoint("CENTER", anchor, "CENTER")
    glow:SetSize(INDICATOR_SIZE * GLOW_SCALE, INDICATOR_SIZE * GLOW_SCALE)
    glow.ProcStartFlipbook:Hide()
    glow:Hide()
    return glow
end

local function ensureIndicator(frame)
    if not frame or frame.cleanHealerIndicator then return end
    local icon = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    icon:SetSize(INDICATOR_SIZE, INDICATOR_SIZE)
    icon:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -INDICATOR_INSET, -INDICATOR_INSET)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:Hide()
    frame.cleanHealerIndicator = icon
    frame.cleanHealerGlow = buildGlow(frame, icon)
    indicators[frame] = true
end

-- Resolve the highest-priority tracked buff on unit, via ForEachAura scan, to pick the icon texture
local function findTrackedBuff(unit)
    if not unit or not UnitExists(unit) then return nil end
    local bestRank, bestSpell
    AuraUtil.ForEachAura(unit, "HELPFUL|PLAYER", nil, function(aura)
        if aura then
            pcall(function()
                local sid = aura.spellId
                if type(sid) ~= "number" then return end
                for rank, id in ipairs(TRACKED_SPELLS) do
                    if id == sid then
                        if not bestRank or rank < bestRank then
                            bestRank, bestSpell = rank, sid
                        end
                        break
                    end
                end
            end)
        end
    end, true)
    return bestSpell
end

local function updateFrame(frame)
    local icon = frame.cleanHealerIndicator
    if not icon then return end
    local unit = frame.displayedUnit or frame.unit
    local spellId = findTrackedBuff(unit)
    local glow = frame.cleanHealerGlow
    if spellId then
        local tex = C_Spell.GetSpellTexture(spellId)
        if tex then icon:SetTexture(tex) end
        icon:Show()
        if glow and not glow:IsShown() then
            glow:Show()
            glow.ProcLoop:Play()
        end
    else
        icon:Hide()
        if glow and glow:IsShown() then
            glow.ProcLoop:Stop()
            glow:Hide()
        end
    end
end

local function unitsMatch(a, b)
    if a == b then return true end
    local result = false
    pcall(function() if UnitIsUnit(a, b) then result = true end end)
    return result
end

local function updateAll(unit)
    for frame in pairs(indicators) do
        if not frame:IsForbidden() then
            local fu = frame.displayedUnit or frame.unit
            if fu and (not unit or unitsMatch(fu, unit)) then
                updateFrame(frame)
            end
        end
    end
end

hooksecurefunc("DefaultCompactUnitFrameSetup", function(frame)
    ensureIndicator(frame)
    updateFrame(frame)
end)
hooksecurefunc("DefaultCompactMiniFrameSetup", function(frame)
    ensureIndicator(frame)
    updateFrame(frame)
end)
hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
    ensureIndicator(frame)
    updateFrame(frame)
end)

local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_AURA")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" then
        updateAll(unit)
    else
        updateAll(nil)
    end
end)
