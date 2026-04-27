local INDICATOR_TEXTURE = 132341
local INDICATOR_SIZE = 24
local INDICATOR_INSET = 2
local GLOW_SCALE = 1.6
local GLOW_COLOR = {0.1, 1.0, 0.1}

local indicators = {}

-- Build proc glow overlay via SpellAlert template to tint icon highlight
local function buildGlow(frame, anchor)
    local glow = CreateFrame("Frame", nil, frame, "ActionButtonSpellAlertTemplate")
    glow:SetPoint("CENTER", anchor, "CENTER")
    glow:SetSize(INDICATOR_SIZE * GLOW_SCALE, INDICATOR_SIZE * GLOW_SCALE)
    glow.ProcStartFlipbook:Hide()
    glow.ProcLoopFlipbook:SetVertexColor(unpack(GLOW_COLOR))
    glow.ProcStartFlipbook:SetVertexColor(unpack(GLOW_COLOR))
    glow:Hide()
    return glow
end

local function ensureIndicator(frame)
    if not frame or frame.cleanDefensiveIndicator then return end
    local icon = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    icon:SetTexture(INDICATOR_TEXTURE)
    icon:SetSize(INDICATOR_SIZE, INDICATOR_SIZE)
    icon:SetPoint("TOPLEFT", frame, "TOPLEFT", INDICATOR_INSET, -INDICATOR_INSET)
    icon:Hide()
    frame.cleanDefensiveIndicator = icon
    frame.cleanDefensiveGlow = buildGlow(frame, icon)
    indicators[frame] = true
end

local function unitHasBigDefensive(unit)
    if not unit or not UnitExists(unit) then return false end
    local found = false
    AuraUtil.ForEachAura(unit, "HELPFUL", nil, function(aura)
        if aura then
            local ok, isBig = pcall(AuraUtil.IsBigDefensive, aura)
            if ok and isBig then
                found = true
                return true
            end
        end
    end, true)
    return found
end

local function updateFrame(frame)
    local icon = frame.cleanDefensiveIndicator
    if not icon then return end
    local unit = frame.displayedUnit or frame.unit
    local show = unitHasBigDefensive(unit)
    icon:SetShown(show)
    local glow = frame.cleanDefensiveGlow
    if not glow then return end
    if show and not glow:IsShown() then
        glow:Show()
        glow.ProcLoop:Play()
    elseif not show and glow:IsShown() then
        glow.ProcLoop:Stop()
        glow:Hide()
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
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("UNIT_AURA")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        if GetCVar("raidFramesCenterBigDefensive") ~= "0" then
            SetCVar("raidFramesCenterBigDefensive", "0")
        end
    elseif event == "UNIT_AURA" then
        updateAll(unit)
    else
        updateAll(nil)
    end
end)
