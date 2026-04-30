local ADDON_NAME = ...
HealerRaidFrames = HealerRaidFrames or {}
local HRF = HealerRaidFrames

HRF.MAX_HIGHLIGHT_SLOTS = 4

HRF.SPEC_NAMES = {
    [256]  = "Discipline Priest",
    [257]  = "Holy Priest",
    [264]  = "Restoration Shaman",
    [65]   = "Holy Paladin",
    [270]  = "Mistweaver Monk",
    [105]  = "Restoration Druid",
    [1468] = "Preservation Evoker",
    [1473] = "Augmentation Evoker",
}

-- Per-spec ordered defaults. Position 1 = rightmost in the buff row.
-- show/glow booleans are the initial values.
local DEFAULTS = {
    [256] = { -- Discipline Priest
        { id = 17,      show = true, glow = true  }, -- Power Word: Shield
        { id = 194384,  show = true, glow = true  }, -- Atonement
        { id = 1253593, show = true, glow = true  }, -- Void Shield
    },
    [257] = { -- Holy Priest
        { id = 41635,   show = true, glow = true  }, -- Prayer of Mending
        { id = 139,     show = true, glow = false }, -- Renew
        { id = 77489,   show = true, glow = false }, -- Echo of Light
    },
    [264] = { -- Restoration Shaman
        { id = 974,     show = true, glow = true  }, -- Earth Shield
        { id = 383648,  show = true, glow = true  }, -- Earth Shield (alt)
        { id = 61295,   show = true, glow = false }, -- Riptide
    },
    [65]  = { -- Holy Paladin
        { id = 53563,   show = true, glow = true  }, -- Beacon of Light
        { id = 156910,  show = true, glow = true  }, -- Beacon of Faith
        { id = 1244893, show = true, glow = true  }, -- Beacon of the Savior
        { id = 156322,  show = true, glow = false }, -- Eternal Flame
    },
    [270] = { -- Mistweaver Monk
        { id = 119611,  show = true, glow = true  }, -- Renewing Mist
        { id = 124682,  show = true, glow = true  }, -- Enveloping Mist
        { id = 115175,  show = true, glow = false }, -- Soothing Mist
        { id = 450769,  show = true, glow = false }, -- Aspect of Harmony
    },
    [105] = { -- Restoration Druid
        { id = 33763,   show = true, glow = true  }, -- Lifebloom
        { id = 774,     show = true, glow = false }, -- Rejuvenation
        { id = 155777,  show = true, glow = false }, -- Germination
        { id = 8936,    show = true, glow = false }, -- Regrowth
        { id = 48438,   show = true, glow = false }, -- Wild Growth
    },
    [1468] = { -- Preservation Evoker
        { id = 366155,  show = true, glow = true  }, -- Reversion
        { id = 367364,  show = true, glow = false }, -- Echo: Reversion
        { id = 355941,  show = true, glow = false }, -- Dream Breath
        { id = 376788,  show = true, glow = false }, -- Echo: Dream Breath
        { id = 363502,  show = true, glow = false }, -- Dream Flight
        { id = 364343,  show = true, glow = false }, -- Echo
        { id = 373267,  show = true, glow = false }, -- Lifebind
    },
    [1473] = { -- Augmentation Evoker
        { id = 395152,  show = true, glow = true  }, -- Ebon Might
        { id = 410089,  show = true, glow = true  }, -- Prescience
        { id = 360827,  show = true, glow = false }, -- Blistering Scales
        { id = 410263,  show = true, glow = false }, -- Inferno's Blessing
        { id = 410686,  show = true, glow = false }, -- Symbiotic Bloom
        { id = 413984,  show = true, glow = false }, -- Shifting Sands
    },
}

HRF.DEFAULTS = DEFAULTS

local DEFAULT_SCALE = 0.4 -- 40% of raid frame height
local MIN_SCALE, MAX_SCALE = 0.05, 1.0

local GLOBAL_DEFAULTS = {
    highlightEnabled = true,
    highlightColor = { 1.0, 1.0, 1.0 }, -- native (untinted proc glow)
    highlightScale = DEFAULT_SCALE,
    highlightGlowCustom = false,
    defensive = { show = true, glow = true, glowCustom = true,  color = { 0.1, 1.0, 0.1 }, scale = DEFAULT_SCALE },
    cc        = { show = true, glow = true, glowCustom = true,  color = { 1.0, 0.1, 0.1 }, scale = DEFAULT_SCALE },
    pureCC    = { show = true, glow = true, glowCustom = true,  color = { 1.0, 0.6, 0.0 }, scale = DEFAULT_SCALE },
    dispel    = { show = true, glow = true, glowCustom = true,  color = { 0.4, 0.6, 1.0 }, scale = DEFAULT_SCALE },
}

HRF.SCALE_MIN = MIN_SCALE
HRF.SCALE_MAX = MAX_SCALE
HRF.SCALE_DEFAULT = DEFAULT_SCALE

HRF.GLOBAL_DEFAULTS = GLOBAL_DEFAULTS

local listeners = {}

function HRF.Subscribe(callback)
    listeners[#listeners + 1] = callback
end

local function notify()
    for _, cb in ipairs(listeners) do
        pcall(cb)
    end
end

function HRF.IsTrackedSpec(specId)
    return specId ~= nil and DEFAULTS[specId] ~= nil
end

function HRF.GetActiveSpec()
    local idx = GetSpecialization and GetSpecialization()
    if not idx then return nil end
    local id = GetSpecializationInfo and GetSpecializationInfo(idx)
    return id
end

local function cloneDefaults(specId)
    local src = DEFAULTS[specId]
    if not src then return nil end
    local order, show, glow = {}, {}, {}
    for i, entry in ipairs(src) do
        order[i] = entry.id
        show[entry.id] = entry.show ~= false
        glow[entry.id] = entry.glow == true
    end
    return { order = order, show = show, glow = glow }
end

local function getSpecDB(specId)
    if not specId or not DEFAULTS[specId] then return nil end
    local db = HealerRaidFramesDB
    if not db then return nil end
    db.specs = db.specs or {}
    local spec = db.specs[specId]
    if not spec then
        spec = cloneDefaults(specId)
        db.specs[specId] = spec
        return spec
    end
    -- Merge any newly-added default spells into an existing saved profile.
    local seen = {}
    for _, id in ipairs(spec.order) do seen[id] = true end
    for _, entry in ipairs(DEFAULTS[specId]) do
        if not seen[entry.id] then
            spec.order[#spec.order + 1] = entry.id
            if spec.show[entry.id] == nil then spec.show[entry.id] = entry.show ~= false end
            if spec.glow[entry.id] == nil then spec.glow[entry.id] = entry.glow == true end
        end
    end
    return spec
end

HRF.GetSpecConfig = getSpecDB

local function copyColor(c)
    return { c[1], c[2], c[3] }
end

local function clampScale(v)
    if type(v) ~= "number" then return DEFAULT_SCALE end
    if v < MIN_SCALE then return MIN_SCALE end
    if v > MAX_SCALE then return MAX_SCALE end
    return v
end

local function ensureSection(db, key)
    local src = GLOBAL_DEFAULTS[key]
    local section = db[key]
    if type(section) ~= "table" then
        section = {
            show = src.show,
            glow = src.glow,
            glowCustom = src.glowCustom,
            color = copyColor(src.color),
            scale = src.scale,
        }
        db[key] = section
        return section
    end
    if section.show == nil then section.show = src.show end
    if section.glow == nil then section.glow = src.glow end
    if section.glowCustom == nil then section.glowCustom = src.glowCustom end
    if type(section.color) ~= "table" or #section.color < 3 then
        section.color = copyColor(src.color)
    end
    section.scale = clampScale(section.scale)
    return section
end

function HRF.EnsureInitialized()
    HealerRaidFramesDB = HealerRaidFramesDB or {}
    local db = HealerRaidFramesDB
    db.specs = db.specs or {}
    if type(db.highlightColor) ~= "table" or #db.highlightColor < 3 then
        db.highlightColor = copyColor(GLOBAL_DEFAULTS.highlightColor)
    end
    db.highlightScale = clampScale(db.highlightScale)
    if db.highlightEnabled == nil then
        db.highlightEnabled = GLOBAL_DEFAULTS.highlightEnabled
    end
    if db.highlightGlowCustom == nil then
        db.highlightGlowCustom = GLOBAL_DEFAULTS.highlightGlowCustom
    end
    ensureSection(db, "defensive")
    ensureSection(db, "cc")
    ensureSection(db, "pureCC")
    ensureSection(db, "dispel")
end

local function getSectionDB(key)
    HRF.EnsureInitialized()
    return HealerRaidFramesDB[key]
end

function HRF.GetSectionShow(key)
    if key == "highlight" then
        HRF.EnsureInitialized()
        return HealerRaidFramesDB.highlightEnabled == true
    end
    local s = getSectionDB(key)
    return s ~= nil and s.show == true
end

function HRF.GetSectionGlow(key)
    local s = getSectionDB(key)
    return s ~= nil and s.glow == true
end

function HRF.GetSectionColor(key)
    if key == "highlight" then
        HRF.EnsureInitialized()
        local c = HealerRaidFramesDB.highlightColor
        return c[1], c[2], c[3]
    end
    local s = getSectionDB(key)
    if not s then return 1, 1, 1 end
    return s.color[1], s.color[2], s.color[3]
end

function HRF.SetSectionShow(key, value)
    if key == "highlight" then
        HRF.EnsureInitialized()
        HealerRaidFramesDB.highlightEnabled = value and true or false
        notify()
        return
    end
    local s = getSectionDB(key)
    if not s then return end
    s.show = value and true or false
    notify()
end

function HRF.SetSectionGlow(key, value)
    local s = getSectionDB(key)
    if not s then return end
    s.glow = value and true or false
    notify()
end

function HRF.GetSectionGlowCustom(key)
    if key == "highlight" then
        HRF.EnsureInitialized()
        return HealerRaidFramesDB.highlightGlowCustom == true
    end
    local s = getSectionDB(key)
    return s ~= nil and s.glowCustom == true
end

function HRF.SetSectionGlowCustom(key, value)
    if key == "highlight" then
        HRF.EnsureInitialized()
        HealerRaidFramesDB.highlightGlowCustom = value and true or false
        notify()
        return
    end
    local s = getSectionDB(key)
    if not s then return end
    s.glowCustom = value and true or false
    notify()
end

function HRF.ResetSection(key)
    HRF.EnsureInitialized()
    local src = GLOBAL_DEFAULTS[key]
    if not src then return end
    HealerRaidFramesDB[key] = {
        show = src.show,
        glow = src.glow,
        glowCustom = src.glowCustom,
        color = copyColor(src.color),
        scale = src.scale,
    }
    notify()
end

function HRF.ResetHighlightDefaults(specId)
    HRF.EnsureInitialized()
    HealerRaidFramesDB.highlightEnabled = GLOBAL_DEFAULTS.highlightEnabled
    HealerRaidFramesDB.highlightGlowCustom = GLOBAL_DEFAULTS.highlightGlowCustom
    HealerRaidFramesDB.highlightColor = copyColor(GLOBAL_DEFAULTS.highlightColor)
    HealerRaidFramesDB.highlightScale = GLOBAL_DEFAULTS.highlightScale
    if specId and DEFAULTS[specId] then
        local db = HealerRaidFramesDB
        db.specs = db.specs or {}
        local spec = db.specs[specId]
        if spec then
            for id in pairs(spec.show) do spec.show[id] = false end
            for id in pairs(spec.glow) do spec.glow[id] = false end
        end
    end
    notify()
end

function HRF.GetSectionScale(key)
    HRF.EnsureInitialized()
    if key == "highlight" then
        return clampScale(HealerRaidFramesDB.highlightScale)
    end
    local s = HealerRaidFramesDB[key]
    return s and clampScale(s.scale) or DEFAULT_SCALE
end

function HRF.SetSectionScale(key, value)
    HRF.EnsureInitialized()
    local v = clampScale(value)
    if key == "highlight" then
        HealerRaidFramesDB.highlightScale = v
    else
        local s = HealerRaidFramesDB[key]
        if not s then return end
        s.scale = v
    end
    notify()
end

function HRF.SetSectionColor(key, r, g, b)
    HRF.EnsureInitialized()
    if key == "highlight" then
        HealerRaidFramesDB.highlightColor = { r, g, b }
    else
        local s = getSectionDB(key)
        if not s then return end
        s.color = { r, g, b }
    end
    notify()
end

-- Returns the 1-based position of spellId in the visible (show=true) order list, or nil.
function HRF.GetVisibleOrder(specId, spellId)
    local spec = getSpecDB(specId)
    if not spec then return nil end
    local pos = 0
    for _, id in ipairs(spec.order) do
        if spec.show[id] then
            pos = pos + 1
            if id == spellId then return pos end
        end
    end
    return nil
end

function HRF.ShouldShow(specId, spellId)
    local spec = getSpecDB(specId)
    return spec ~= nil and spec.show[spellId] == true
end

function HRF.ShouldGlow(specId, spellId)
    local spec = getSpecDB(specId)
    return spec ~= nil and spec.glow[spellId] == true
end

function HRF.SetShow(specId, spellId, value)
    local spec = getSpecDB(specId)
    if not spec then return end
    spec.show[spellId] = value and true or false
    notify()
end

function HRF.SetGlow(specId, spellId, value)
    local spec = getSpecDB(specId)
    if not spec then return end
    spec.glow[spellId] = value and true or false
    notify()
end

local function indexOf(list, value)
    for i, v in ipairs(list) do
        if v == value then return i end
    end
    return nil
end

function HRF.MoveUp(specId, spellId)
    local spec = getSpecDB(specId)
    if not spec then return end
    local i = indexOf(spec.order, spellId)
    if not i or i == 1 then return end
    spec.order[i], spec.order[i - 1] = spec.order[i - 1], spec.order[i]
    notify()
end

function HRF.MoveDown(specId, spellId)
    local spec = getSpecDB(specId)
    if not spec then return end
    local i = indexOf(spec.order, spellId)
    if not i or i == #spec.order then return end
    spec.order[i], spec.order[i + 1] = spec.order[i + 1], spec.order[i]
    notify()
end

function HRF.MoveTo(specId, spellId, finalPos)
    local spec = getSpecDB(specId)
    if not spec then return end
    local i = indexOf(spec.order, spellId)
    if not i then return end
    local n = #spec.order
    finalPos = math.max(1, math.min(n, finalPos))
    if i == finalPos then return end
    table.remove(spec.order, i)
    table.insert(spec.order, finalPos, spellId)
    notify()
end
