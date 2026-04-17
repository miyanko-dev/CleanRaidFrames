-- Compact raid frame restyling with healer buff highlights and debuff glow

C_AddOns.LoadAddOn("Blizzard_ActionBar")

-- Enable raid frame debuff CVars on entering world because they must be set per session
local raidCvarFrame = CreateFrame("Frame")
raidCvarFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
raidCvarFrame:SetScript("OnEvent", function()
    SetCVar("raidFramesDisplayDebuffs", "1")
    SetCVar("raidFramesDisplayOnlyDispellableDebuffs", "1")
    SetCVar("raidFramesDisplayLargerRoleSpecificDebuffs", "1")
end)

-- Fixed aura icon sizes in pixels
local AURA_SIZE = 24
local ROLE_DEBUFF_SIZE = 32

-- Glow size relative to icon width
local GLOW_SCALE = 1.5

-- Aura layout spacing in pixels
local AURA_GAP = 2
local AURA_OFFSET = 2
local AURA_PADDING = 2

-- Health bar gradient colours (top-down darkening)
local GRADIENT_TOP    = CreateColor(0, 0, 0, 0.25)
local GRADIENT_BOTTOM = CreateColor(0, 0, 0, 0)

-- Glow colours (r, g, b)
local GLOW_RED   = { 1.0, 0.2,  0.1 }
local GLOW_GREEN = { 0.2, 1.0,  0.2 }
local GLOW_BLUE  = { 0.5, 0.5,  1.0 }

-- Frame types we should never touch
local function isFriendlyRaidFrame(frame)
    if not frame then return false end

    local unit = frame.displayedUnit or frame.unit
    if unit then
        if unit:match("^arena") or unit:match("^boss") or unit:match("^nameplate") then
            return false
        end
        return true
    end

    local name = frame:GetName()
    if name then
        if name:match("Arena") or name:match("Boss") or name:match("NamePlate") then
            return false
        end
    end

    return false
end

-- Spell IDs that receive a golden glow on buff icons
local TRACKED_HEALER_SPELL_IDS = {
    [194384]  = true,
    [156910]  = true,
    [1244893] = true,
    [53563]   = true,
    [115175]  = true,
    [33763]   = true,
    [366155]  = true,
    [383648]  = true,
    [61295]   = true,
    [119611]  = true,
}

-- Glow pool — keyed by parent frame, supports colour tinting

local glowPool = {}

local function tintGlow(glow, color)
    local r = color and color[1] or 1
    local g = color and color[2] or 1
    local b = color and color[3] or 1
    glow.ProcStartFlipbook:SetDesaturated(color ~= nil)
    glow.ProcStartFlipbook:SetVertexColor(r, g, b)
    glow.ProcLoopFlipbook:SetDesaturated(color ~= nil)
    glow.ProcLoopFlipbook:SetVertexColor(r, g, b)
end

local function acquireGlow(parentFrame, tag)
    tag = tag or "default"
    if not glowPool[parentFrame] then
        glowPool[parentFrame] = {}
    end
    local glow = glowPool[parentFrame][tag]
    if not glow then
        glow = CreateFrame("Frame", nil, parentFrame, "ActionButtonSpellAlertTemplate")
        glow:SetPoint("CENTER")
        glow.ProcStartFlipbook:Hide()
        glow:Hide()
        glowPool[parentFrame][tag] = glow
    end
    return glow
end

local function showGlow(auraFrame, color, tag)
    local glow = acquireGlow(auraFrame, tag)
    tintGlow(glow, color)
    if glow.ProcStartAnim:IsPlaying() then glow.ProcStartAnim:Stop() end
    glow:Show()
    if not glow.ProcLoop:IsPlaying() then glow.ProcLoop:Play() end
end

local function hideGlow(auraFrame, tag)
    tag = tag or "default"
    if not glowPool[auraFrame] then return end
    local glow = glowPool[auraFrame][tag]
    if not glow then return end
    glow.ProcLoop:Stop()
    glow.ProcStartAnim:Stop()
    glow:Hide()
end

local function resizeGlow(auraFrame, iconSize, tag)
    tag = tag or "default"
    if not glowPool[auraFrame] then return end
    local glow = glowPool[auraFrame][tag]
    if not glow then return end
    local glowSize = math.floor(iconSize * GLOW_SCALE)
    if glow._srfCachedSize == glowSize then return end
    glow._srfCachedSize = glowSize
    glow:SetSize(glowSize, glowSize)
    glow:ClearAllPoints()
    glow:SetPoint("CENTER")
end

-- Health bar gradient

local function applyHealthBarGradient(unitFrame)
    if not unitFrame or not unitFrame.healthBar then return end
    local healthBar = unitFrame.healthBar
    if healthBar.srfGradient then return end

    C_Timer.After(0, function()
        if healthBar.srfGradient then return end
        local gradient = healthBar:CreateTexture(nil, "ARTWORK", nil, 7)
        gradient:SetAllPoints(healthBar)
        gradient:SetColorTexture(1, 1, 1, 1)
        gradient:SetGradient("VERTICAL", GRADIENT_BOTTOM, GRADIENT_TOP)
        healthBar.srfGradient = gradient
    end)
end

hooksecurefunc("DefaultCompactUnitFrameSetup", applyHealthBarGradient)
hooksecurefunc("DefaultCompactMiniFrameSetup", applyHealthBarGradient)

-- Debuff role-enlargement and dispellability detection

hooksecurefunc("CompactUnitFrame_UtilSetDebuff", function(frame, debuffFrame)
    if not debuffFrame then return end

    -- FIX: guard here prevents running on arena/boss frames where fields like
    -- isBossAura are Blizzard-restricted secret booleans that addons cannot
    -- perform boolean tests on — doing so triggers the taint error.
    if not isFriendlyRaidFrame(frame) then return end

    -- Role enlargement: Blizzard sets size = baseSize * 1.5 for role/boss debuffs.
    -- isBossAura is intentionally NOT used here — it is a restricted field.
    local baseSize = debuffFrame.baseSize or 0
    if baseSize > 0 then
        debuffFrame.srfIsRoleEnlarged = (debuffFrame:GetWidth() > baseSize + 0.5)
    else
        debuffFrame.srfIsRoleEnlarged = false
    end

    -- Dispellability: IsAuraFilteredOutByInstanceID returns true when the aura
    -- is EXCLUDED from the filter — i.e. not result means IS dispellable.
    debuffFrame.srfCanDispel = false
    if debuffFrame.auraInstanceID and frame and frame.displayedUnit then
        local ok, result = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID,
            frame.displayedUnit, debuffFrame.auraInstanceID, "HARMFUL|RAID_PLAYER_DISPELLABLE")
        if ok and not result then
            debuffFrame.srfCanDispel = true
        end
    end
end)

-- Healer buff glow hook

local function isTrackedHealerSpell(buffFrame)
    local unitFrame = buffFrame:GetParent()
    if not unitFrame or not unitFrame.displayedUnit or not buffFrame.auraInstanceID then return false end
    local aura = C_UnitAuras.GetAuraDataByAuraInstanceID(unitFrame.displayedUnit, buffFrame.auraInstanceID)
    if not aura then return false end
    local ok, result = pcall(function() return TRACKED_HEALER_SPELL_IDS[aura.spellId] end)
    return ok and result or false
end

hooksecurefunc("CompactUnitFrame_UtilSetBuff", function(buffFrame)
    if not buffFrame then return end
    local unitFrame = buffFrame:GetParent()
    if not isFriendlyRaidFrame(unitFrame) then return end
    if isTrackedHealerSpell(buffFrame) then
        showGlow(buffFrame)
    else
        hideGlow(buffFrame)
    end
end)

-- Aura layout

hooksecurefunc("CompactUnitFrame_UpdateAuras", function(unitFrame)
    if not unitFrame then return end
    if not isFriendlyRaidFrame(unitFrame) then return end

    local auraSize       = AURA_SIZE
    local roleDebuffSize = ROLE_DEBUFF_SIZE
    local bottomOffset   = AURA_PADDING + (unitFrame.powerBarUsedHeight or 0)

    -- Resize and lay out visible buffs in a bottom-right grid
    if unitFrame.buffFrames then
        local visibleIndex = 0
        for i = 1, #unitFrame.buffFrames do
            local buffFrame = unitFrame.buffFrames[i]
            if not buffFrame then break end
            if buffFrame:IsShown() then
                buffFrame:SetSize(auraSize, auraSize)
                resizeGlow(buffFrame, auraSize)
                buffFrame:ClearAllPoints()
                buffFrame:SetPoint("BOTTOMRIGHT", unitFrame, "BOTTOMRIGHT",
                    -AURA_OFFSET - (visibleIndex % 3) * (auraSize + AURA_GAP),
                    bottomOffset + math.floor(visibleIndex / 3) * (auraSize + AURA_GAP))
                visibleIndex = visibleIndex + 1
            else
                hideGlow(buffFrame)
            end
        end
    end

    -- Pin defensive buff to top-left corner with green glow
    local defensiveFrame = unitFrame.CenterDefensiveBuff
    if defensiveFrame and defensiveFrame:IsShown() then
        defensiveFrame:SetSize(auraSize, auraSize)
        defensiveFrame:ClearAllPoints()
        defensiveFrame:SetPoint("TOPLEFT", unitFrame, "TOPLEFT", AURA_OFFSET, -AURA_OFFSET)
        resizeGlow(defensiveFrame, auraSize, "defensive")
        showGlow(defensiveFrame, GLOW_GREEN, "defensive")
    elseif defensiveFrame then
        hideGlow(defensiveFrame, "defensive")
    end

    if not unitFrame.debuffFrames then return end

    -- First debuff slot: role/boss debuff sizing and glow only — no repositioning,
    -- Blizzard's anchor is left untouched.
    -- Blue glow = dispellable role debuff, red = non-dispellable role debuff.
    local firstDebuff = unitFrame.debuffFrames[1]
    if firstDebuff and firstDebuff:IsShown() then
        local isRoleEnlarged = firstDebuff.srfIsRoleEnlarged
        local debuffSize     = isRoleEnlarged and roleDebuffSize or auraSize
        firstDebuff:SetSize(debuffSize, debuffSize)
        if isRoleEnlarged then
            local glowColor = firstDebuff.srfCanDispel and GLOW_BLUE or GLOW_RED
            resizeGlow(firstDebuff, roleDebuffSize)
            showGlow(firstDebuff, glowColor)
        else
            hideGlow(firstDebuff)
        end
    else
        if firstDebuff then hideGlow(firstDebuff) end
    end

    for i = 2, #unitFrame.debuffFrames do
        local debuffFrame = unitFrame.debuffFrames[i]
        if not debuffFrame then break end
        debuffFrame:Hide()
    end
end)
