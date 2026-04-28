local _, ns = ...

local ATONEMENT_SPELL_ID = 194384
local DISPEL_CC_TEXTURE = 135894
local NON_DISPEL_CC_TEXTURE = 135860
local DEFENSIVE_TEXTURE = 132341

local testMode = false
local refresher

-- Iterate tracked frames via shared namespace set to apply per-frame callback
local function eachFrame(set, callback)
    if not set then return end
    for frame in pairs(set) do
        if frame and not frame:IsForbidden() then
            callback(frame)
        end
    end
end

local function showIndicator(icon, glow, texture)
    if not icon then return end
    if texture then icon:SetTexture(texture) end
    icon:Show()
    if glow and not glow:IsShown() then
        glow:Show()
        if glow.ProcLoop then glow.ProcLoop:Play() end
    end
end

local function hideIndicator(icon, glow)
    if icon then icon:Hide() end
    if glow and glow:IsShown() then
        if glow.ProcLoop then glow.ProcLoop:Stop() end
        glow:Hide()
    end
end

-- Force all three indicators visible on tracked frames via cached textures to drive screenshot mode
local function refreshAll()
    local atonement = C_Spell.GetSpellTexture(ATONEMENT_SPELL_ID)
    eachFrame(ns.healerFrames, function(frame)
        showIndicator(frame.cleanHealerIndicator, frame.cleanHealerGlow, atonement)
    end)
    eachFrame(ns.ccFrames, function(frame)
        showIndicator(frame.cleanCCIndicator, frame.cleanCCGlow, DISPEL_CC_TEXTURE)
    end)
    eachFrame(ns.nonDispelFrames, function(frame)
        showIndicator(frame.cleanNonDispelIndicator, frame.cleanNonDispelGlow, NON_DISPEL_CC_TEXTURE)
    end)
    eachFrame(ns.defensiveFrames, function(frame)
        showIndicator(frame.cleanDefensiveIndicator, frame.cleanDefensiveGlow, DEFENSIVE_TEXTURE)
    end)
end

local function hideAll()
    eachFrame(ns.healerFrames, function(frame)
        hideIndicator(frame.cleanHealerIndicator, frame.cleanHealerGlow)
    end)
    eachFrame(ns.ccFrames, function(frame)
        hideIndicator(frame.cleanCCIndicator, frame.cleanCCGlow)
    end)
    eachFrame(ns.nonDispelFrames, function(frame)
        hideIndicator(frame.cleanNonDispelIndicator, frame.cleanNonDispelGlow)
    end)
    eachFrame(ns.defensiveFrames, function(frame)
        hideIndicator(frame.cleanDefensiveIndicator, frame.cleanDefensiveGlow)
    end)
end

local function ensureRefresher()
    if refresher then return end
    refresher = CreateFrame("Frame")
    refresher:Hide()
    refresher:SetScript("OnUpdate", refreshAll)
end

local function setTest(enabled)
    testMode = enabled
    ensureRefresher()
    if enabled then
        refreshAll()
        refresher:Show()
    else
        refresher:Hide()
        hideAll()
    end
end

SLASH_CRFTEST1 = "/crftest"
SlashCmdList["CRFTEST"] = function()
    setTest(not testMode)
    print("|cff33ff99Clean Raid Frames|r test mode " .. (testMode and "|cff00ff00ON|r" or "|cffff5555OFF|r"))
end
