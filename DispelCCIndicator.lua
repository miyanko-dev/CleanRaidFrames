local INDICATOR_TEXTURE = 135894
local INDICATOR_SIZE = 32
local INDICATOR_INSET = 2
local GLOW_SCALE = 1.6
local GLOW_COLOR = {1.0, 0.1, 0.1}

local indicators = {}

-- Restrict attachment to raid and party compact frames via groupType to exclude arena and nameplates
local function isAllowedFrame(frame)
    if not frame or not CompactUnitFrame_IsPartyFrame then return false end
    return CompactUnitFrame_IsPartyFrame(frame)
end

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
    if not frame or frame.cleanCCIndicator then return end
    if not isAllowedFrame(frame) then return end
    local icon = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    icon:SetTexture(INDICATOR_TEXTURE)
    icon:SetSize(INDICATOR_SIZE, INDICATOR_SIZE)
    icon:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", INDICATOR_INSET, INDICATOR_INSET)
    icon:Hide()
    frame.cleanCCIndicator = icon
    frame.cleanCCGlow = buildGlow(frame, icon)
    indicators[frame] = true
end

-- Scan harmful auras via combined CROWD_CONTROL and RAID_PLAYER_DISPELLABLE filter to detect dispellable CC
local function unitHasDispellableCC(unit)
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

local function updateFrame(frame)
    local icon = frame.cleanCCIndicator
    if not icon then return end
    local unit = frame.displayedUnit or frame.unit
    if not unit or not UnitExists(unit) then
        icon:Hide()
        local g = frame.cleanCCGlow
        if g and g:IsShown() then g.ProcLoop:Stop() g:Hide() end
        return
    end
    local show = unitHasDispellableCC(unit)
    icon:SetShown(show)
    local glow = frame.cleanCCGlow
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
        if GetCVar("raidFramesDisplayDebuffs") ~= "0" then
            SetCVar("raidFramesDisplayDebuffs", "0")
        end
    elseif event == "UNIT_AURA" then
        updateAll(unit)
    else
        updateAll(nil)
    end
end)
