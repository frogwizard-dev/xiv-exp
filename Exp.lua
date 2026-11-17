local ADDON, ns = ...
local issecret = FrogLib.issecret

-- The settings controls are FrogLib's (UI.lua); every change calls ns.Refresh().
local UI = FrogLib.UI.Kit({ refresh = function() ns.Refresh() end })

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
    -- Leveling info under the bar's right end. Words: tolevel (kills to level, by recent kills), perhour
    -- (XP an hour this session), eta (time to level at that rate), quests (XP in finished quests).
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

local CopyDefaults = FrogLib.Util.CopyDefaults

local function Commas(number)
    if issecret(number) then return number end
    return BreakUpLargeNumbers and BreakUpLargeNumbers(number) or tostring(number)
end

-- Text in a light version of its bar's colour, as FFXIV does.
local function Light(color)
    return FrogLib.Color.Lighten(color.r, color.g, color.b, 0.55)
end

local Exp = {}
ns.Exp = Exp

------------------------------------------------------------------------------
-- Leveling info: kills to level, XP an hour, time to level, XP in finished quests
------------------------------------------------------------------------------

local KILLS_KEPT = 10 -- the average is over this many recent kills
local NONE = "-"      -- until there's something to show

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
        local template = _G[key]
        if type(template) == "string" then
            local pattern = template:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
            pattern = pattern:gsub("%%s", "(.-)"):gsub("%%d", "(%%d+)")
            killPatterns[#killPatterns + 1] = "^" .. pattern
        end
    end
    -- The longest first, so a message with a rested bonus isn't taken by the plain form.
    table.sort(killPatterns, function(first, second) return #first > #second end)
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

-- The first of a match's captures that's a number (no table made for them).
local function FirstNumber(...)
    for i = 1, select("#", ...) do
        local number = tonumber((select(i, ...)))
        if number then return number end
    end
end

function Exp:OnKillMessage(message)
    if issecret(message) or not message then return end
    for _, pattern in ipairs(KillPatterns()) do
        local xp = FirstNumber(message:match(pattern))
        if xp then
            local kills = RecentKills()
            table.insert(kills, xp)
            while #kills > KILLS_KEPT do table.remove(kills, 1) end
            return
        end
    end
end

-- XP gained this session, for the hourly rate.
function Exp:CountXP()
    local xp, max, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    if issecret(xp) or issecret(max) then return end
    local session = self.session
    if session.xp then
        local gained = xp - session.xp
        if level > session.level then gained = (session.max - session.xp) + xp end
        if gained > 0 then session.gained = session.gained + gained end
    end
    session.xp, session.max, session.level = xp, max, level
end

-- The XP in finished quests still in your log.
local function QuestXP()
    local QuestLog = C_QuestLog
    if not (QuestLog and QuestLog.GetNumQuestLogEntries and GetQuestLogRewardXP) then return 0 end
    local total = 0
    for i = 1, QuestLog.GetNumQuestLogEntries() do
        local info = QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID and QuestLog.IsComplete(info.questID) then
            total = total + (GetQuestLogRewardXP(info.questID) or 0)
        end
    end
    return total
end

local function Short(amount)
    if amount >= 1000000 then return string.format("%.1fm", amount / 1000000) end
    if amount >= 10000 then return string.format("%.0fk", amount / 1000) end
    if amount >= 1000 then return string.format("%.1fk", amount / 1000) end
    return tostring(math.floor(amount))
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
    local values = { tolevel = NONE, perhour = NONE, eta = NONE, quests = Short(self.questXP or 0) }
    local kills = RecentKills()
    if #kills > 0 then
        local sum = 0
        for _, killXP in ipairs(kills) do sum = sum + killXP end
        values.tolevel = tostring(math.ceil(left / (sum / #kills)))
    end
    local session = self.session
    local elapsed = GetTime() - session.start
    -- A rate needs a couple of minutes behind it to mean anything.
    if session.gained > 0 and elapsed >= 120 then
        local perHour = session.gained / elapsed * 3600
        values.perhour = Short(perHour)
        values.eta = Duration(left / perHour * 3600)
    end
    return values
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
    for word in name:gmatch("[^%s%-%(%)]+") do
        if not MINOR_WORDS[word:lower()] then words[#words + 1] = word end
    end
    if #words == 0 then return name end
    if #words == 1 then
        local initials, count = "", 0
        for char in words[1]:gmatch(UTF8_CHAR) do
            initials, count = initials .. char, count + 1
            if count == 3 then break end
        end
        return initials:upper()
    end
    local initials = ""
    for _, word in ipairs(words) do initials = initials .. (word:match(UTF8_CHAR) or "") end
    return initials:upper()
end

-- The watched faction, read the way Blizzard's own reputation bar reads it (friendship, renown and
-- paragon parts skipped where Forever lacks them). Returns nil when nothing is watched.
local function WatchedReputation()
    local Reputation = C_Reputation
    local data = Reputation and Reputation.GetWatchedFactionData and Reputation.GetWatchedFactionData()
    if not data or not data.factionID or data.factionID == 0 or not data.name or data.name == "" then return nil end
    local id, reaction = data.factionID, data.reaction
    local low, high, value = data.currentReactionThreshold, data.nextReactionThreshold, data.currentStanding
    local standing = (GetText and GetText("FACTION_STANDING_LABEL" .. reaction, UnitSex("player")))
        or _G["FACTION_STANDING_LABEL" .. reaction] or ""
    local capped = MAX_REPUTATION_REACTION and reaction >= MAX_REPUTATION_REACTION

    if Reputation.IsFactionParagonForCurrentPlayer and Reputation.IsFactionParagonForCurrentPlayer(id) then
        local current, threshold = Reputation.GetFactionParagonInfo(id)
        if current and threshold then
            low, high, value, capped = 0, threshold, current % threshold, false
        end
    elseif Reputation.IsMajorFaction and Reputation.IsMajorFaction(id) and C_MajorFactions then
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
    return { name = data.name, short = Initials(data.name), standing = standing, value = value, max = max,
        reaction = reaction, capped = capped }
end

------------------------------------------------------------------------------
-- Blizzard's XP and reputation bars
------------------------------------------------------------------------------

-- Two containers swap these bars with fade animations, which stall if a container is hidden: so the bars
-- we replace, and a container's frame holding one, go see-through. Fine in combat; their space stays.
local hookedContainers = {}

local function Replaced(barIndex)
    local bars = StatusTrackingBarInfo.BarsEnum
    if barIndex == bars.Experience then return ns.db.hideBlizzard end
    if barIndex == bars.Reputation then return ns.db.rep.enabled and ns.db.rep.hideBlizzard end
    return false
end

local function DressContainer(container)
    local bars = StatusTrackingBarInfo.BarsEnum
    for _, index in ipairs({ bars.Experience, bars.Reputation }) do
        local bar = container.bars and container.bars[index]
        if bar then
            local hide = Replaced(index)
            bar:SetAlpha(hide and 0 or 1)
            bar:EnableMouse(not hide) -- its tooltip
            if bar.ExhaustionTick then bar.ExhaustionTick:EnableMouse(not hide) end
        end
    end
    local frameAlpha = Replaced(container.shownBarIndex) and 0 or 1
    if container.BarFrameTexture then container.BarFrameTexture:SetAlpha(frameAlpha) end
    if container.HorizontalDividersPool then
        for divider in container.HorizontalDividersPool:EnumerateActive() do divider:SetAlpha(frameAlpha) end
    end
end

function Exp:DressBlizzardBar()
    local manager = StatusTrackingBarManager
    if not (manager and manager.barContainers and StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum) then
        return
    end
    for _, container in ipairs(manager.barContainers) do
        if not hookedContainers[container] then
            hookedContainers[container] = true
            -- A new bar moved in; the dividers are re-made when the layout changes.
            hooksecurefunc(container, "ApplyPendingBarToShow", DressContainer)
            hooksecurefunc(container, "UpdateDividers", DressContainer)
        end
        DressContainer(container)
    end
end

function Exp:Init()
    local frame = CreateFrame("Frame", "XIVExpFrame", UIParent)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    -- Dragged while unlocked; the tint marks it (FrogLib's Mover.lua).
    FrogLib.Mover.Make(frame, { save = function(point) ns.db.point = point end, tint = 6 })
    self.frame = frame

    -- Rested XP sits behind the XP gauge, running from your XP onwards in blue.
    local rested = CreateFrame("StatusBar", nil, frame)
    rested:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    rested:SetPoint("TOPLEFT")
    rested:SetPoint("TOPRIGHT")
    local track = rested:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("TOPLEFT", 0, 1)
    track:SetPoint("BOTTOMRIGHT", 0, -1)
    track:SetColorTexture(0, 0, 0, 0.45)
    self.rested = rested

    local gauge = FrogLib.Gauge.New(frame)
    gauge.bar:SetPoint("TOPLEFT")
    gauge.bar:SetPoint("TOPRIGHT")
    gauge.bar:SetFrameLevel(rested:GetFrameLevel() + 1)
    -- The rested bar draws the track here, so the gauge's own would dim the blue.
    gauge.track:SetAlpha(0)
    gauge.trackCap:SetAlpha(0)
    self.gauge = gauge

    -- XP in finished quests: between the rested bar and the XP gauge, from your XP onwards.
    local quests = CreateFrame("StatusBar", nil, frame)
    quests:SetPoint("TOPLEFT")
    quests:SetPoint("TOPRIGHT")
    quests:SetFrameLevel(rested:GetFrameLevel() + 1)
    gauge.bar:SetFrameLevel(quests:GetFrameLevel() + 1)
    self.quests = quests

    self.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.text:SetPoint("TOPLEFT", gauge.bar, "BOTTOMLEFT", 2, -5)
    self.text:SetShadowOffset(1, -1)
    self.info = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.info:SetPoint("TOPRIGHT", gauge.bar, "BOTTOMRIGHT", -2, -5)
    self.info:SetJustifyH("RIGHT")
    self.info:SetShadowOffset(1, -1)

    -- Reputation: the same gauge-and-text block, above the XP one (placed in Update).
    self.rep = FrogLib.Gauge.New(frame)
    self.repText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.repText:SetPoint("TOPLEFT", self.rep.bar, "BOTTOMLEFT", 2, -5)
    self.repText:SetShadowOffset(1, -1)

    for _, event in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD",
        "UPDATE_FACTION", "QUEST_LOG_UPDATE", "CHAT_MSG_COMBAT_XP_GAIN" }) do
        frame:RegisterEvent(event)
    end
    pcall(frame.RegisterEvent, frame, "MAJOR_FACTION_RENOWN_LEVEL_CHANGED")
    self.session = { start = GetTime(), gained = 0 }
    self.questXP = QuestXP()
    -- The quest log changes in bursts (several QUEST_LOG_UPDATE at once): walked once, a quarter second after.
    local questsQueued = false
    local function QuestsSettled()
        questsQueued = false
        self.questXP = QuestXP()
        self:Update()
    end
    frame:SetScript("OnEvent", function(_, event, message)
        if event == "CHAT_MSG_COMBAT_XP_GAIN" then
            self:OnKillMessage(message)
        elseif event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" then
            self:CountXP()
        elseif event == "QUEST_LOG_UPDATE" then
            if not questsQueued then
                questsQueued = true
                C_Timer.After(0.25, QuestsSettled)
            end
            return
        end
        self:Update()
    end)
    self:CountXP()
    -- The time to level moves with the clock, not only with XP: looked at every 15 seconds while the bar shows.
    frame:HookScript("OnShow", function()
        self.clock = self.clock or C_Timer.NewTicker(15, function() self:Update() end)
    end)
    frame:HookScript("OnHide", function()
        if self.clock then
            self.clock:Cancel()
            self.clock = nil
        end
    end)
    if frame:IsShown() then self.clock = C_Timer.NewTicker(15, function() self:Update() end) end
    self:Apply()
end

function Exp:Apply()
    local db = ns.db
    local frame = self.frame
    frame:SetScale(db.scale)
    frame:ClearAllPoints()
    frame:SetPoint(db.point[1], UIParent, db.point[3], db.point[4], db.point[5])
    frame:SetSize(db.width, db.height + db.size + 8)
    frame:EnableMouse(not db.locked)
    frame.unlockTint:SetShown(not db.locked)

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

    local percent = (not issecret(xp) and not issecret(max) and max > 0) and (xp / max * 100) or 0
    UI.SetTemplateText(self.text, db.text, {
        class = tag, level = Commas(level), value = Commas(xp), max = Commas(max),
        percent = percent, rested = Commas(rested),
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

    local color = cfg.color
    if cfg.standingColors then
        local standingColor = FACTION_BAR_COLORS and FACTION_BAR_COLORS[rep.reaction]
        if standingColor then color = standingColor end
    end
    self.rep:SetColor(color.r, color.g, color.b)
    self.repText:SetTextColor(Light(color))
    self.rep:SetValues(rep.value, rep.max)

    local values = { name = rep.name, short = rep.short, standing = rep.standing,
        value = Commas(rep.value), max = Commas(rep.max), percent = rep.value / rep.max * 100 }
    local words = { "name", "short", "standing", "value", "max" }
    local template = cfg.text
    if rep.capped then
        -- At the top there's nothing left to count: only the faction and standing.
        template = template:lower():find("name", 1, true) and "name standing" or "short standing"
    end
    UI.SetTemplateText(self.repText, template, values, words)
    return true
end

------------------------------------------------------------------------------
-- Settings window
------------------------------------------------------------------------------

local function BuildLayout(page)
    local db = ns.db
    local place = UI.Placer()
    place(UI.Checkbox(page, "Unlock to move (drag the bar)",
        function() return not db.locked end, function(value) db.locked = not value end), 34)
    place(UI.Stepper(page, "Scale", 0.5, 2, 0.05, db, "scale", "%.2f"), 26)
    place(UI.Stepper(page, "Width", 100, 1600, 10, db, "width"), 26)
    place(UI.Stepper(page, "Height", 1, 12, 1, db, "height"), 32)
    place(UI.Dropdown(page, "Bar texture", function() return ns.Media:List("statusbar") end, db, "texture"), 30)
    place(UI.ColorSwatch(page, "XP colour", db, "xpColor"), 28)
    place(UI.ColorSwatch(page, "Rested colour", db, "restedColor"), 36)
    place(UI.Checkbox(page, "Hide at max level", db, "hideAtMax"), 28)
    place(UI.Checkbox(page, "Hide Blizzard's XP bar", db, "hideBlizzard"), 28)
end

local function BuildText(page)
    local db = ns.db
    local place = UI.Placer()
    place(UI.TextBox(page, "Text", db, "text"), 30)
    place(UI.Help(page, "Words: |cffffd100class|r, |cffffd100level|r, |cffffd100value|r, |cffffd100max|r, "
        .. "|cffffd100percent|r (|cffffd100percent.1|r for a decimal), |cffffd100rested|r. Leave empty to hide.", 400), 36, 4)
    place(UI.Dropdown(page, "Font", function() return ns.Media:List("font") end, db, "font"), 30)
    place(UI.Dropdown(page, "Font outline", UI.OUTLINES, db, "outline"), 30)
    place(UI.Stepper(page, "Text size", 8, 24, 1, db, "size"), 34)
    place(UI.TextBox(page, "Right-hand text", db, "info"), 30)
    place(UI.Help(page, "Words: |cffffd100tolevel|r (kills to level, from your last few kills), "
        .. "|cffffd100perhour|r (XP an hour this session), |cffffd100eta|r (time to level at that rate), "
        .. "|cffffd100quests|r (XP in finished quests you haven't handed in). Leave empty to hide.", 400), 48, 4)
    place(UI.Checkbox(page, "Show finished quests' XP on the bar", db, "showQuests"), 28)
    place(UI.ColorSwatch(page, "Quest XP colour", db, "questColor"), 30)
end

local function BuildRep(page)
    local rep = ns.db.rep
    local place = UI.Placer()
    place(UI.Checkbox(page, "Show my watched reputation above the XP bar", rep, "enabled"), 28)
    place(UI.Checkbox(page, "Hide Blizzard's reputation bar", rep, "hideBlizzard"), 34)
    place(UI.TextBox(page, "Text", rep, "text"), 30)
    place(UI.Help(page, "Words: |cffffd100short|r (the faction's initials, e.g. AD), |cffffd100name|r, "
        .. "|cffffd100standing|r, |cffffd100value|r, |cffffd100max|r, |cffffd100percent|r. "
        .. "At Exalted it shows only the faction and standing.", 400), 44, 4)
    place(UI.Checkbox(page, "Colour by standing (red hostile to green friendly)", rep, "standingColors"), 30)
    place(UI.ColorSwatch(page, "Colour otherwise", rep, "color"), 36)
    place(UI.Help(page, "To choose the reputation, open your character window's Reputation tab, click a "
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
loader:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" and addonName == ADDON then
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
