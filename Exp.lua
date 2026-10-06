local ADDON, ns = ...
local UI = ns.UI
local issecret = FrogLib.issecret

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
    -- Leveling info, on the right under the bar. Words: tolevel (kills to level, from your
    -- recent kills), perhour (XP an hour this session), eta (time to level at that rate), quests
    -- (XP in finished quests not yet handed in). Empty hides it.
    info = "tolevel kills   eta",
    -- XP waiting in finished quests, as a stretch of the bar after your XP (like rested).
    showQuests = true,
    questColor = { r = 1.00, g = 0.62, b = 0.25 },
    kills = {}, -- each character's last few kills' XP, for "tolevel"
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

-- Text in a light version of its bar's colour, as FFXIV does.
local function Light(c)
    return FrogLib.Color.Lighten(c.r, c.g, c.b, 0.55)
end

local Exp = {}
ns.Exp = Exp

------------------------------------------------------------------------------
-- Leveling info: kills to level, XP an hour, time to level, XP in finished quests
------------------------------------------------------------------------------

local KILLS_KEPT = 10 -- the average is over this many recent kills
local NONE = "\226\128\147" -- an en dash, until there's something to show

-- "Kobold dies, you gain 45 experience. (+45 exp Rested bonus)" and its group and raid
-- forms: the game's own strings, made into patterns, whose first number is the XP.
local killPatterns
local function KillPatterns()
    if killPatterns then return killPatterns end
    killPatterns = {}
    local keys = { "COMBATLOG_XPGAIN_FIRSTPERSON" }
    for i = 1, 5 do keys[#keys + 1] = "COMBATLOG_XPGAIN_EXHAUSTION" .. i end
    for _, base in ipairs({ unpack(keys) }) do
        keys[#keys + 1] = base .. "_GROUP"
        keys[#keys + 1] = base .. "_RAID"
    end
    for _, key in ipairs(keys) do
        local fmt = _G[key]
        if type(fmt) == "string" then
            local pattern = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
            pattern = pattern:gsub("%%s", "(.-)"):gsub("%%d", "(%%d+)")
            killPatterns[#killPatterns + 1] = "^" .. pattern
        end
    end
    -- The longest first, so a message with a rested bonus isn't taken by the plain form.
    table.sort(killPatterns, function(a, b) return #a > #b end)
    return killPatterns
end

local function CharacterKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function RecentKills()
    local key = CharacterKey()
    ns.db.kills[key] = ns.db.kills[key] or {}
    return ns.db.kills[key]
end

function Exp:OnKillMessage(msg)
    if issecret(msg) or not msg then return end
    for _, pattern in ipairs(KillPatterns()) do
        local caps = { msg:match(pattern) }
        for _, cap in ipairs(caps) do
            local xp = tonumber(cap)
            if xp then
                local kills = RecentKills()
                table.insert(kills, xp)
                while #kills > KILLS_KEPT do table.remove(kills, 1) end
                return
            end
        end
    end
end

-- XP gained this session, for the hourly rate.
function Exp:CountXP()
    local xp, max, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    if issecret(xp) or issecret(max) then return end
    local s = self.session
    if s.xp then
        local gained = xp - s.xp
        if level > s.level then gained = (s.max - s.xp) + xp end
        if gained > 0 then s.gained = s.gained + gained end
    end
    s.xp, s.max, s.level = xp, max, level
end

-- The XP in finished quests still in your log.
local function QuestXP()
    local Q = C_QuestLog
    if not (Q and Q.GetNumQuestLogEntries and GetQuestLogRewardXP) then return 0 end
    local total = 0
    for i = 1, Q.GetNumQuestLogEntries() do
        local info = Q.GetInfo(i)
        if info and not info.isHeader and info.questID and Q.IsComplete(info.questID) then
            total = total + (GetQuestLogRewardXP(info.questID) or 0)
        end
    end
    return total
end

local function Short(n)
    if n >= 1000000 then return string.format("%.1fm", n / 1000000) end
    if n >= 10000 then return string.format("%.0fk", n / 1000) end
    if n >= 1000 then return string.format("%.1fk", n / 1000) end
    return tostring(math.floor(n))
end

local function Duration(seconds)
    if seconds >= 3600 then
        return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
    end
    return string.format("%dm", math.max(1, math.floor(seconds / 60)))
end

-- The words' values, for xp of max.
function Exp:Leveling(xp, max)
    local left = max - xp
    local vals = { tolevel = NONE, perhour = NONE, eta = NONE, quests = Short(self.questXP or 0) }
    local kills = RecentKills()
    if #kills > 0 then
        local sum = 0
        for _, k in ipairs(kills) do sum = sum + k end
        vals.tolevel = tostring(math.ceil(left / (sum / #kills)))
    end
    local s = self.session
    local elapsed = GetTime() - s.start
    -- A rate needs a couple of minutes behind it to mean anything.
    if s.gained > 0 and elapsed >= 120 then
        local perHour = s.gained / elapsed * 3600
        vals.perhour = Short(perHour)
        vals.eta = Duration(left / perHour * 3600)
    end
    return vals
end

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

    -- XP in finished quests: between the rested bar and the XP gauge, from your XP onwards.
    local quests = CreateFrame("StatusBar", nil, f)
    quests:SetPoint("TOPLEFT")
    quests:SetPoint("TOPRIGHT")
    quests:SetFrameLevel(rested:GetFrameLevel() + 1)
    g.bar:SetFrameLevel(quests:GetFrameLevel() + 1)
    self.quests = quests

    self.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.text:SetPoint("TOPLEFT", g.bar, "BOTTOMLEFT", 2, -5)
    self.text:SetShadowOffset(1, -1)
    self.info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.info:SetPoint("TOPRIGHT", g.bar, "BOTTOMRIGHT", -2, -5)
    self.info:SetJustifyH("RIGHT")
    self.info:SetShadowOffset(1, -1)

    -- Reputation: the same gauge-and-text block, above the XP one (placed in Update).
    self.rep = ns.CreateGauge(f)
    self.repText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.repText:SetPoint("TOPLEFT", self.rep.bar, "BOTTOMLEFT", 2, -5)
    self.repText:SetShadowOffset(1, -1)

    for _, event in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD",
        "UPDATE_FACTION", "QUEST_LOG_UPDATE", "CHAT_MSG_COMBAT_XP_GAIN" }) do
        f:RegisterEvent(event)
    end
    pcall(f.RegisterEvent, f, "MAJOR_FACTION_RENOWN_LEVEL_CHANGED")
    self.session = { start = GetTime(), gained = 0 }
    self.questXP = QuestXP()
    f:SetScript("OnEvent", function(_, event, msg)
        if event == "CHAT_MSG_COMBAT_XP_GAIN" then
            self:OnKillMessage(msg)
        elseif event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" then
            self:CountXP()
        elseif event == "QUEST_LOG_UPDATE" then
            self.questXP = QuestXP()
        end
        self:Update()
    end)
    self:CountXP()
    -- The time to level moves with the clock, not just with XP.
    C_Timer.NewTicker(15, function() self:Update() end)
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
    self.quests:SetHeight(db.height)
    self.quests:SetStatusBarTexture(db.texture)
    self.quests:SetStatusBarColor(db.questColor.r, db.questColor.g, db.questColor.b, 0.9)
    ns.Media:SetFont(self.text, db.font, db.size, db.outline)
    self.text:SetTextColor(Light(db.xpColor))
    ns.Media:SetFont(self.info, db.font, db.size, db.outline)
    self.info:SetTextColor(Light(db.xpColor))
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
        if ok and not issecret(maxed) and maxed then return true end
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
    self.quests:SetShown(showXP and db.showQuests and not maxed)
    self.info:SetShown(showXP and not maxed)
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
    self.quests:SetMinMaxValues(0, max)
    if not issecret(xp) and not issecret(max) then
        self.rested:SetValue(math.min(max, xp + rested))
        self.quests:SetValue(math.min(max, xp + (self.questXP or 0)))
        UI.SetTemplateText(self.info, db.info, self:Leveling(xp, max), { "tolevel", "perhour", "eta", "quests" })
    else
        self.info:Hide()
    end

    local pct = (not issecret(xp) and not issecret(max) and max > 0) and (xp / max * 100) or 0
    UI.SetTemplateText(self.text, db.text, {
        class = tag, level = Commas(level), value = Commas(xp), max = Commas(max),
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
    place(UI.Stepper(p, "Text size", 8, 24, 1, function() return db.size end, function(v) db.size = v end), 34)
    place(UI.TextBox(p, "Right-hand text", function() return db.info end, function(v) db.info = v end), 30)
    place(UI.Help(p, "Words: |cffffd100tolevel|r (kills to level, from your last few kills), "
        .. "|cffffd100perhour|r (XP an hour this session), |cffffd100eta|r (time to level at that rate), "
        .. "|cffffd100quests|r (XP in finished quests you haven't handed in). Leave empty to hide.", 400), 48, 4)
    place(UI.Checkbox(p, "Show finished quests' XP on the bar",
        function() return db.showQuests end, function(v) db.showQuests = v end), 28)
    place(UI.ColorSwatch(p, "Quest XP colour", function() return db.questColor end,
        function(r, g, b) db.questColor = { r = r, g = g, b = b } end), 30)
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
        ns.window = UI.Window("XIVExpConfig", "XIVExp", 440, 470, {
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
FrogLib.Options.Add("XIVExp", ns, {
    open = function()
        if not (ns.window and ns.window:IsShown()) then ns.ToggleConfig() end
    end,
    commands = { { "/xivexp", "open or close the settings" } },
})
