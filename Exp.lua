local ADDON, ns = ...
local UI = ns.UI
local issecret = issecretvalue or function() return false end

ns.defaults = {
    locked = true,
    point = { "BOTTOM", "UIParent", "BOTTOM", 0, 200 },
    scale = 1,
    width = 430,
    height = 2,
    texture = "Interface\\Buttons\\WHITE8X8",
    xpColor = { r = 0.96, g = 0.86, b = 0.50 },     -- FFXIV's gold
    restedColor = { r = 0.35, g = 0.62, b = 1.00 }, -- FFXIV's blue
    font = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF",
    outline = "OUTLINE",
    size = 13,
    -- Words: class, level, value, max, percent (percent.1), rested.
    text = "class Lv level   EXP value/max",
    hideAtMax = false,
}

-- Three-letter class tags, FFXIV-style (it shows "MCH", "PLD" and so on).
local CLASS_TAGS = {
    WARRIOR = "WAR", PALADIN = "PLD", HUNTER = "HNT", ROGUE = "ROG", PRIEST = "PRI",
    SHAMAN = "SHM", MAGE = "MAG", WARLOCK = "WLK", DRUID = "DRU", DEATHKNIGHT = "DRK",
    MONK = "MNK", DEMONHUNTER = "DHN", EVOKER = "EVK",
}

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function Commas(n)
    if issecret(n) then return n end
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

local Exp = {}
ns.Exp = Exp

function Exp:Init()
    local f = CreateFrame("Frame", "XIVExpFrame", UIParent)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local p, _, rp, x, y = frame:GetPoint()
        ns.db.point = { p, "UIParent", rp, x, y }
    end)
    f.unlockTint = f:CreateTexture(nil, "BACKGROUND")
    f.unlockTint:SetPoint("TOPLEFT", -6, 6)
    f.unlockTint:SetPoint("BOTTOMRIGHT", 6, -6)
    f.unlockTint:SetColorTexture(0.3, 0.6, 1, 0.2)
    self.frame = f

    -- Rested XP sits behind the XP gauge, running from your XP onwards in blue.
    local rested = CreateFrame("StatusBar", nil, f)
    rested:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    rested:SetPoint("TOPLEFT")
    rested:SetPoint("TOPRIGHT")
    local track = rested:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("TOPLEFT", 0, 1)
    track:SetPoint("BOTTOMRIGHT", 0, -1)
    track:SetColorTexture(0, 0, 0, 0.45)
    self.rested = rested

    local g = ns.CreateGauge(f)
    g.bar:SetPoint("TOPLEFT")
    g.bar:SetPoint("TOPRIGHT")
    g.bar:SetFrameLevel(rested:GetFrameLevel() + 1)
    -- The rested bar draws the track here, so the gauge's own would dim the blue.
    g.track:SetAlpha(0)
    g.trackCap:SetAlpha(0)
    self.gauge = g

    self.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.text:SetPoint("TOPLEFT", g.bar, "BOTTOMLEFT", 2, -5)
    self.text:SetShadowOffset(1, -1)

    for _, event in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD" }) do
        f:RegisterEvent(event)
    end
    f:SetScript("OnEvent", function() self:Update() end)
    self:Apply()
end

function Exp:Apply()
    local db = ns.db
    local f = self.frame
    f:SetScale(db.scale)
    f:ClearAllPoints()
    f:SetPoint(db.point[1], UIParent, db.point[3], db.point[4], db.point[5])
    f:SetSize(db.width, db.height + db.size + 8)
    f:EnableMouse(not db.locked)
    f.unlockTint:SetShown(not db.locked)

    self.gauge:SetHeight(db.height)
    self.gauge:SetTexture(db.texture)
    self.gauge:SetColor(db.xpColor.r, db.xpColor.g, db.xpColor.b)
    self.rested:SetHeight(db.height)
    self.rested:SetStatusBarTexture(db.texture)
    self.rested:SetStatusBarColor(db.restedColor.r, db.restedColor.g, db.restedColor.b, 0.85)
    ns.Media:SetFont(self.text, db.font, db.size, db.outline)
    local c = db.xpColor
    self.text:SetTextColor(c.r + (1 - c.r) * 0.55, c.g + (1 - c.g) * 0.55, c.b + (1 - c.b) * 0.55)

    self:Update()
    C_Timer.After(0.1, function() self:Update() end)
end

local function AtMaxLevel(max)
    if IsPlayerAtEffectiveMaxLevel then
        local ok, maxed = pcall(IsPlayerAtEffectiveMaxLevel)
        if ok and maxed and not issecret(maxed) then return true end
    end
    return not max or max == 0
end

function Exp:Update()
    local db = ns.db
    local xp, max = UnitXP("player"), UnitXPMax("player")
    local rested = GetXPExhaustion() or 0
    local _, class = UnitClass("player")
    local tag = CLASS_TAGS[class] or (class and class:sub(1, 3)) or "?"
    local level = UnitLevel("player")

    local maxed = not issecret(max) and AtMaxLevel(max)
    local show = not (maxed and db.hideAtMax) or not db.locked
    self.frame:SetShown(show)
    if not show then return end

    if maxed then
        self.gauge:SetValues(1, 1, true)
        self.rested:SetMinMaxValues(0, 1)
        self.rested:SetValue(0)
        self.text:SetFormattedText("%s Lv%d   MAX", tag, level)
        return
    end

    self.gauge:SetValues(xp, max)
    self.rested:SetMinMaxValues(0, max)
    if not issecret(xp) and not issecret(max) then
        self.rested:SetValue(math.min(max, xp + rested))
    end

    local pct = (not issecret(xp) and not issecret(max) and max > 0) and (xp / max * 100) or 0
    UI.SetTemplateText(self.text, db.text, {
        class = tag, level = tostring(level), value = Commas(xp), max = Commas(max),
        percent = pct, rested = Commas(rested),
    }, { "class", "level", "value", "max", "rested" })
end

------------------------------------------------------------------------------
-- Settings window
------------------------------------------------------------------------------

local function BuildLayout(p)
    local db = ns.db
    local place = UI.Placer()
    place(UI.Checkbox(p, "Unlock to move (drag the bar)",
        function() return not db.locked end, function(v) db.locked = not v end), 34)
    place(UI.Stepper(p, "Scale", 0.5, 2, 0.05, function() return db.scale end, function(v) db.scale = v end, "%.2f"), 26)
    place(UI.Stepper(p, "Width", 100, 1600, 10, function() return db.width end, function(v) db.width = v end), 26)
    place(UI.Stepper(p, "Height", 1, 12, 1, function() return db.height end, function(v) db.height = v end), 32)
    place(UI.Dropdown(p, "Bar texture", function() return ns.Media:List("statusbar") end,
        function() return db.texture end, function(v) db.texture = v end), 30)
    place(UI.ColorSwatch(p, "XP colour", function() return db.xpColor end,
        function(r, g, b) db.xpColor = { r = r, g = g, b = b } end), 28)
    place(UI.ColorSwatch(p, "Rested colour", function() return db.restedColor end,
        function(r, g, b) db.restedColor = { r = r, g = g, b = b } end), 36)
    place(UI.Checkbox(p, "Hide at max level",
        function() return db.hideAtMax end, function(v) db.hideAtMax = v end), 28)
end

local function BuildText(p)
    local db = ns.db
    local place = UI.Placer()
    place(UI.TextBox(p, "Text", function() return db.text end, function(v) db.text = v end), 30)
    place(UI.Help(p, "Words: |cffffd100class|r, |cffffd100level|r, |cffffd100value|r, |cffffd100max|r, "
        .. "|cffffd100percent|r (|cffffd100percent.1|r for a decimal), |cffffd100rested|r. Leave empty to hide.", 400), 36, 4)
    place(UI.Dropdown(p, "Font", function() return ns.Media:List("font") end,
        function() return db.font end, function(v) db.font = v end), 30)
    place(UI.Dropdown(p, "Font outline", UI.OUTLINES, function() return db.outline end,
        function(v) db.outline = v end), 30)
    place(UI.Stepper(p, "Text size", 8, 24, 1, function() return db.size end, function(v) db.size = v end), 26)
end

function ns.ToggleConfig()
    if not ns.window then
        ns.window = UI.Window("XIVExpConfig", "XIVExp", 440, 400, {
            { "layout", "Layout", BuildLayout },
            { "text", "Text", BuildText },
        })
        return
    end
    ns.window:SetShown(not ns.window:IsShown())
end

------------------------------------------------------------------------------
-- Startup
------------------------------------------------------------------------------

function ns.Refresh()
    Exp:Apply()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        XIVExpDB = XIVExpDB or {}
        -- Krona One was bundled briefly and then removed; move anyone using it to Michroma.
        local font = XIVExpDB.font
        if type(font) == "string" and font:find("KronaOne", 1, true) then
            XIVExpDB.font = "Interface\\AddOns\\XIVExp\\Fonts\\Michroma.ttf"
        end
        CopyDefaults(ns.defaults, XIVExpDB)
        ns.db = XIVExpDB
    elseif event == "PLAYER_LOGIN" then
        Exp:Init()
    end
end)

SLASH_XIVEXP1 = "/xivexp"
SlashCmdList.XIVEXP = ns.ToggleConfig
function XIVExp_OnCompartmentClick() ns.ToggleConfig() end

-- Its entry in the game's Options > AddOns list (Options.lua).
ns.AddOptionsPanel({
    open = function()
        if not (ns.window and ns.window:IsShown()) then ns.ToggleConfig() end
    end,
    commands = { { "/xivexp", "open or close the settings" } },
})
