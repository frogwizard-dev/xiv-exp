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
    hideBlizzard = true, -- hide Blizzard's XP bar
    -- The reputation you watch ("Show as Experience Bar"), on its own gauge above the XP one.
    -- Words: short (the faction's initials), name, standing, value, max, percent (percent.1).
    -- standingColors: tint by standing (red hostile ... green friendly); off: always `color`.
    rep = { enabled = true, text = "short standing   value/max", hideBlizzard = true,
        standingColors = true, color = { r = 0.45, g = 0.80, b = 0.30 } },
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

local function Light(c)
    return c.r + (1 - c.r) * 0.55, c.g + (1 - c.g) * 0.55, c.b + (1 - c.b) * 0.55
end

local Exp = {}
ns.Exp = Exp

------------------------------------------------------------------------------
-- Reputation
------------------------------------------------------------------------------

-- A faction's initials, FFXIV-style: "Argent Dawn" -> "AD", "The League of Arathor" -> "LA";
-- a one-word name gives its first three letters ("Stormwind" -> "STO"). UTF-8 safe.
local MINOR_WORDS = { ["the"] = true, ["of"] = true, ["and"] = true }
local UTF8_CHAR = "[%z\1-\127\194-\244][\128-\191]*"

local function Initials(name)
    local words = {}
    for w in name:gmatch("[^%s%-%(%)]+") do
        if not MINOR_WORDS[w:lower()] then words[#words + 1] = w end
    end
    if #words == 0 then return name end
    if #words == 1 then
        local out, n = "", 0
        for ch in words[1]:gmatch(UTF8_CHAR) do
            out, n = out .. ch, n + 1
            if n == 3 then break end
        end
        return out:upper()
    end
    local out = ""
    for _, w in ipairs(words) do out = out .. (w:match(UTF8_CHAR) or "") end
    return out:upper()
end

-- The watched faction, read the way Blizzard's own reputation bar reads it (Forever has the
-- retail reputation API; the friendship, renown and paragon parts are skipped where it lacks
-- them). Returns nil when nothing is watched.
local function WatchedReputation()
    local R = C_Reputation
    local d = R and R.GetWatchedFactionData and R.GetWatchedFactionData()
    if not d or not d.factionID or d.factionID == 0 or not d.name or d.name == "" then return nil end
    local id, reaction = d.factionID, d.reaction
    local low, high, value = d.currentReactionThreshold, d.nextReactionThreshold, d.currentStanding
    local standing = (GetText and GetText("FACTION_STANDING_LABEL" .. reaction, UnitSex("player")))
        or _G["FACTION_STANDING_LABEL" .. reaction] or ""
    local capped = MAX_REPUTATION_REACTION and reaction >= MAX_REPUTATION_REACTION

    if R.IsFactionParagonForCurrentPlayer and R.IsFactionParagonForCurrentPlayer(id) then
        local current, threshold = R.GetFactionParagonInfo(id)
        if current and threshold then
            low, high, value, capped = 0, threshold, current % threshold, false
        end
    elseif R.IsMajorFaction and R.IsMajorFaction(id) and C_MajorFactions then
        local major = C_MajorFactions.GetMajorFactionData(id)
        if major and major.renownLevelThreshold then
            low, high, value, capped = 0, major.renownLevelThreshold, major.renownReputationEarned or 0, false
            standing = (RENOWN_LEVEL_LABEL and RENOWN_LEVEL_LABEL:format(major.renownLevel)) or ("Renown " .. major.renownLevel)
        end
    elseif C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
        local friend = C_GossipInfo.GetFriendshipReputation(id)
        if friend and friend.friendshipFactionID and friend.friendshipFactionID > 0 then
            standing, reaction = friend.reaction or standing, 5
            if friend.nextThreshold then
                low, high, value, capped = friend.reactionThreshold, friend.nextThreshold, friend.standing, false
            else
                capped = true
            end
        end
    end

    local max = high - low
    value = value - low
    if capped or max <= 0 then max, value, capped = 1, 1, true end
    return { name = d.name, short = Initials(d.name), standing = standing, value = value, max = max,
        reaction = reaction, capped = capped }
end

------------------------------------------------------------------------------
-- Blizzard's XP and reputation bars
------------------------------------------------------------------------------

-- They live in two bar containers, which swap bars with fade animations. Hiding a container
-- stalls those animations and with them the swapping, so the bars we replace, and a
-- container's frame while it holds one, go see-through instead. Nothing moves, so it works in
-- combat, but the space the bars took stays.
local hookedContainers = {}

local function Replaced(barIndex)
    local bars = StatusTrackingBarInfo.BarsEnum
    if barIndex == bars.Experience then return ns.db.hideBlizzard end
    if barIndex == bars.Reputation then return ns.db.rep.enabled and ns.db.rep.hideBlizzard end
    return false
end

local function DressContainer(c)
    local bars = StatusTrackingBarInfo.BarsEnum
    for _, index in ipairs({ bars.Experience, bars.Reputation }) do
        local bar = c.bars and c.bars[index]
        if bar then
            local hide = Replaced(index)
            bar:SetAlpha(hide and 0 or 1)
            bar:EnableMouse(not hide) -- its tooltip
            if bar.ExhaustionTick then bar.ExhaustionTick:EnableMouse(not hide) end
        end
    end
    local frameAlpha = Replaced(c.shownBarIndex) and 0 or 1
    if c.BarFrameTexture then c.BarFrameTexture:SetAlpha(frameAlpha) end
    if c.HorizontalDividersPool then
        for divider in c.HorizontalDividersPool:EnumerateActive() do divider:SetAlpha(frameAlpha) end
    end
end

function Exp:DressBlizzardBar()
    local manager = StatusTrackingBarManager
    if not (manager and manager.barContainers and StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum) then
        return
    end
    for _, c in ipairs(manager.barContainers) do
        if not hookedContainers[c] then
            hookedContainers[c] = true
            -- A new bar moved in; the dividers are re-made when the layout changes.
            hooksecurefunc(c, "ApplyPendingBarToShow", DressContainer)
            hooksecurefunc(c, "UpdateDividers", DressContainer)
        end
        DressContainer(c)
    end
end

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

    -- Reputation: the same gauge-and-text block, above the XP one (placed in Update).
    self.rep = ns.CreateGauge(f)
    self.repText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.repText:SetPoint("TOPLEFT", self.rep.bar, "BOTTOMLEFT", 2, -5)
    self.repText:SetShadowOffset(1, -1)

    for _, event in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD",
        "UPDATE_FACTION" }) do
        f:RegisterEvent(event)
    end
    pcall(f.RegisterEvent, f, "MAJOR_FACTION_RENOWN_LEVEL_CHANGED")
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
    self.text:SetTextColor(Light(db.xpColor))
    self.rep:SetHeight(db.height)
    self.rep:SetTexture(db.texture)
    ns.Media:SetFont(self.repText, db.font, db.size, db.outline)
    self:DressBlizzardBar()

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
    local showXP = not (maxed and db.hideAtMax) or not db.locked
    local showRep = self:UpdateRep(showXP)
    self.frame:SetShown(showXP or showRep)
    self.gauge.bar:SetShown(showXP)
    self.rested:SetShown(showXP)
    self.text:SetShown(showXP)
    if not showXP then return end

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

-- A sample while the bar is unlocked and nothing is watched, so you can see where it goes.
local SAMPLE_REP = { name = "Argent Dawn", short = "AD", standing = FACTION_STANDING_LABEL5 or "Friendly",
    value = 2400, max = 6000, reaction = 5 }

-- Returns whether the reputation gauge is shown. It sits above the XP gauge, or in its place
-- when the XP gauge is hidden (at max level, with "Hide at max level").
function Exp:UpdateRep(xpShown)
    local db, cfg = ns.db, ns.db.rep
    local rep = cfg.enabled and (WatchedReputation() or (not db.locked and SAMPLE_REP))
    self.rep.bar:SetShown(rep and true or false)
    self.repText:SetShown(rep and true or false)
    if not rep then return false end

    local bar, xpBar = self.rep.bar, self.gauge.bar
    bar:ClearAllPoints()
    if xpShown then
        -- Its text, under it, ends a few pixels above the XP gauge.
        local up = db.size + 13
        bar:SetPoint("BOTTOMLEFT", xpBar, "TOPLEFT", 0, up)
        bar:SetPoint("BOTTOMRIGHT", xpBar, "TOPRIGHT", 0, up)
    else
        bar:SetPoint("TOPLEFT", xpBar, "TOPLEFT")
        bar:SetPoint("TOPRIGHT", xpBar, "TOPRIGHT")
    end

    local c = cfg.color
    if cfg.standingColors then
        local fc = FACTION_BAR_COLORS and FACTION_BAR_COLORS[rep.reaction]
        if fc then c = fc end
    end
    self.rep:SetColor(c.r, c.g, c.b)
    self.repText:SetTextColor(Light(c))
    self.rep:SetValues(rep.value, rep.max)

    local vals = { name = rep.name, short = rep.short, standing = rep.standing,
        value = Commas(rep.value), max = Commas(rep.max), percent = rep.value / rep.max * 100 }
    local words = { "name", "short", "standing", "value", "max" }
    local template = cfg.text
    if rep.capped then
        -- At the top there's nothing left to count: just the faction and standing.
        template = template:lower():find("name", 1, true) and "name standing" or "short standing"
    end
    UI.SetTemplateText(self.repText, template, vals, words)
    return true
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
    place(UI.Checkbox(p, "Hide Blizzard's XP bar",
        function() return db.hideBlizzard end, function(v) db.hideBlizzard = v end), 28)
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

local function BuildRep(p)
    local cfg = ns.db.rep
    local place = UI.Placer()
    place(UI.Checkbox(p, "Show my watched reputation above the XP bar",
        function() return cfg.enabled end, function(v) cfg.enabled = v end), 28)
    place(UI.Checkbox(p, "Hide Blizzard's reputation bar",
        function() return cfg.hideBlizzard end, function(v) cfg.hideBlizzard = v end), 34)
    place(UI.TextBox(p, "Text", function() return cfg.text end, function(v) cfg.text = v end), 30)
    place(UI.Help(p, "Words: |cffffd100short|r (the faction's initials, e.g. AD), |cffffd100name|r, "
        .. "|cffffd100standing|r, |cffffd100value|r, |cffffd100max|r, |cffffd100percent|r. "
        .. "At Exalted it shows just the faction and standing.", 400), 44, 4)
    place(UI.Checkbox(p, "Colour by standing (red hostile to green friendly)",
        function() return cfg.standingColors end, function(v) cfg.standingColors = v end), 30)
    place(UI.ColorSwatch(p, "Colour otherwise", function() return cfg.color end,
        function(r, g, b) cfg.color = { r = r, g = g, b = b } end), 36)
    place(UI.Help(p, "To choose the reputation, open your character window's Reputation tab, click a "
        .. "faction and tick \"Show as Experience Bar\".", 400), 36, 4)
end

function ns.ToggleConfig()
    if not ns.window then
        ns.window = UI.Window("XIVExpConfig", "XIVExp", 440, 400, {
            { "layout", "Layout", BuildLayout },
            { "text", "Text", BuildText },
            { "rep", "Reputation", BuildRep },
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
