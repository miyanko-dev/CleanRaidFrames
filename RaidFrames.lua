-- Add a top-down shadow gradient to raid frame health bars

local GRADIENT_TOP    = CreateColor(0, 0, 0, 0.25)
local GRADIENT_BOTTOM = CreateColor(0, 0, 0, 0)

local function applyHealthBarGradient(frame)
    if not frame or not frame.healthBar then return end
    local healthBar = frame.healthBar
    if healthBar.srfGradient then return end
    local gradient = healthBar:CreateTexture(nil, "ARTWORK", nil, 7)
    gradient:SetAllPoints(healthBar)
    gradient:SetColorTexture(1, 1, 1, 1)
    gradient:SetGradient("VERTICAL", GRADIENT_BOTTOM, GRADIENT_TOP)
    healthBar.srfGradient = gradient
end

hooksecurefunc("DefaultCompactUnitFrameSetup", applyHealthBarGradient)
hooksecurefunc("DefaultCompactMiniFrameSetup", applyHealthBarGradient)
