-- ============================================================
--  PBAltManager.lua  |  Main entry point
--  Based on MultiBot-Chatless architecture
-- ============================================================

PBAM = PBAM or {}
PBAM.Version = "0.1.0"

-- Initialize config tables (SavedVariables)
PBAMConfig = PBAMConfig or {}
PBAMConfig.Minimap = PBAMConfig.Minimap or { hide = false, angle = 0 }
PBAMConfig.MainWindow = PBAMConfig.MainWindow or { width = 800, height = 600 }
PBAMConfig.RosterSort = PBAMConfig.RosterSort or "alpha"
PBAMConfig.RosterSortByTab = PBAMConfig.RosterSortByTab or {}

PBAM.MainWindow = nil
PBAM.SelectedBot = nil
PBAM.SelectedBotLower = nil
PBAM.DebugEnabled = false  -- /pbam debug toggles this
PBAM.PendingRosterInventoryRequests = PBAM.PendingRosterInventoryRequests or {}  -- [key] = timestamp when request was SENT
PBAM.PendingRosterSkillRequests = PBAM.PendingRosterSkillRequests or {}  -- [key] = timestamp when request was SENT
PBAM.LastRefreshTime = PBAM.LastRefreshTime or {}  -- [type~bot] = timestamp for throttling

-- ── Debug Print ─────────────────────────────────────────────

PBAM.DebugPrint = function(...)
    if not PBAM.DebugEnabled then return end
    local parts = { ... }
    for i = 1, #parts do parts[i] = tostring(parts[i]) end
    print("|cFF69CCF0[PBAM]|r " .. table.concat(parts, " "))
end

-- Debounced roster refresh to prevent excessive UI updates during rapid data changes
local rosterRefreshPending = false
local rosterRefreshQueue = 0
function PBAM.QueueRosterRefresh()
    rosterRefreshQueue = rosterRefreshQueue + 1
    if rosterRefreshPending then return end
    rosterRefreshPending = true
    PBAM.After(0.1, function()  -- 100ms debounce
        rosterRefreshPending = false
        local count = rosterRefreshQueue
        rosterRefreshQueue = 0
        if count > 1 then PBAM.DebugPrint("RosterRefresh: batched " .. count .. " updates") end
        if PBAM.RefreshRosterDisplay then PBAM.RefreshRosterDisplay() end
    end)
end

PBAM.LogError = function(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444[PBAltManager]|r " .. tostring(msg or ""))
    end
end

PBAM.LogInfo = function(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF69CCF0[PBAltManager]|r " .. tostring(msg or ""))
    end
end

local TREE_NAMES = {
    WARRIOR={"Arms","Fury","Protection"}, PALADIN={"Holy","Protection","Retribution"}, HUNTER={"Beast Mastery","Marksmanship","Survival"},
    ROGUE={"Assassination","Combat","Subtlety"}, PRIEST={"Discipline","Holy","Shadow"}, DEATHKNIGHT={"Blood","Frost","Unholy"},
    SHAMAN={"Elemental","Enhancement","Restoration"}, MAGE={"Arcane","Fire","Frost"}, WARLOCK={"Affliction","Demonology","Destruction"}, DRUID={"Balance","Feral","Restoration"},
}

local ROLE_BY_SPEC = {
    Protection="Tank", ["Protection Warrior"]="Tank", Blood="Tank", Feral="Tank/DPS",
    Holy="Healer", ["Holy Pala"]="Healer", Discipline="Healer", Restoration="Healer",
}

local ROLE_SORT_ORDER = { Tank=1, Healer=2, DPS=3, ["Tank/DPS"]=3, Unknown=4, ["N/A"]=4 }
local ROSTER_SORT_REQUEST_TTL = 3.0
local ROSTER_SORT_MAX_INFLIGHT = 4
local REFRESH_THROTTLE_MS = 500  -- Minimum ms between same refreshes

local sharedAfterFrame, sharedAfterJobs
function PBAM.After(delay, func)
    if C_Timer and C_Timer.After then return C_Timer.After(delay, func) end
    if not sharedAfterFrame then
        sharedAfterJobs = {}
        sharedAfterFrame = CreateFrame("Frame")
        sharedAfterFrame:SetScript("OnUpdate", function(_, elapsed)
            for i = #sharedAfterJobs, 1, -1 do
                local job = sharedAfterJobs[i]
                job.t = job.t - elapsed
                if job.t <= 0 then table.remove(sharedAfterJobs, i); job.f() end
            end
        end)
    end
    table.insert(sharedAfterJobs, { t = tonumber(delay) or 0, f = func })
end

function PBAM.RunThrottledFanout(queueNames, pendingNames, pendingSince, requestFunc, options)
    if not requestFunc then return end
    options = options or {}
    local ttl = tonumber(options.ttl) or ROSTER_SORT_REQUEST_TTL
    local maxInflight = tonumber(options.maxInflight) or ROSTER_SORT_MAX_INFLIGHT
    local onBeforeRequest = options.onBeforeRequest
    local onTimeout = options.onTimeout
    local now = GetTime and GetTime() or 0
    local inflight = 0

    for key, startedAt in pairs(pendingSince or {}) do
        if (now - (tonumber(startedAt) or 0)) < ttl then
            inflight = inflight + 1
        else
            pendingSince[key] = nil
            if onTimeout then onTimeout(key) end
        end
    end

    local available = math.max(0, maxInflight - inflight)
    if available <= 0 then return end

    for _, name in ipairs(queueNames or {}) do
        if available <= 0 then break end
        if pendingNames[name] then
            local key = string.lower(tostring(name or ""))
            if key ~= "" and not pendingSince[key] then
                if onBeforeRequest then onBeforeRequest(name, key) end
                pendingSince[key] = now
                requestFunc(name)
                PBAM.After(ttl, function()
                    local current = pendingSince[key]
                    if current and ((GetTime and GetTime() or 0) - current) >= ttl then
                        pendingSince[key] = nil
                        if onTimeout then onTimeout(key) end
                    end
                end)
                available = available - 1
            end
        end
    end
end

local function ClassKey(className)
    local s = tostring(className or ""):upper():gsub("%s+", "")
    if s == "DEATHKNIGHT" then return "DEATHKNIGHT" end
    return s
end

local function BestRoleForPlayer()
    if not GetTalentTabInfo then return "Unknown" end
    local maxI, maxV, total, tied = 1, 0, 0, false
    local names = {}
    for i=1,3 do
        local name, _, points = GetTalentTabInfo(i)
        points = tonumber(points) or 0
        names[i] = name
        total = total + points
        if points > maxV then maxI, maxV, tied = i, points, false elseif points == maxV and points > 0 then tied = true end
    end
    if total < 10 or maxV < 6 or tied then return "Unknown" end
    local spec = names[maxI] or "Unknown"
    return ROLE_BY_SPEC[spec] or "DPS"
end

local function BestRoleForDetail(detail)
    if not detail then return "Unknown" end
    local vals = { tonumber(detail.talent1) or 0, tonumber(detail.talent2) or 0, tonumber(detail.talent3) or 0 }
    local maxI, maxV, total, tied = 1, vals[1], vals[1] + vals[2] + vals[3], false
    for i=2,3 do
        if vals[i] > maxV then maxI, maxV, tied = i, vals[i], false elseif vals[i] == maxV then tied = true end
    end
    if total < 10 or maxV < 6 or tied then return "Unknown" end
    local names = TREE_NAMES[ClassKey(detail.className)] or {"Tree 1","Tree 2","Tree 3"}
    local spec = names[maxI] or "Unknown"
    return ROLE_BY_SPEC[spec] or "DPS"
end

function PBAM.GetStoredRosterSortMode(tabName)
    tabName = tostring(tabName or PBAM.CurrentTab or "")
    local byTab = PBAMConfig.RosterSortByTab or {}
    local mode = byTab[tabName]
    if mode and mode ~= "" then return tostring(mode) end
    return tostring(PBAMConfig.RosterSort or "alpha")
end

function PBAM.GetRosterSortMode()
    return PBAM.GetStoredRosterSortMode(PBAM.CurrentTab)
end

function PBAM.SetRosterSortMode(mode, tabName)
    mode = tostring(mode or "alpha")
    tabName = tostring(tabName or PBAM.CurrentTab or "")
    PBAMConfig.RosterSortByTab = PBAMConfig.RosterSortByTab or {}
    if tabName ~= "" then PBAMConfig.RosterSortByTab[tabName] = mode end
    PBAMConfig.RosterSort = mode
    PBAM.RefreshRosterDisplay()
end

function PBAM.GetRosterRole(entry)
    if not entry then return "Unknown" end
    if entry.isPlayer then return BestRoleForPlayer() end
    local detail = PBAM.Bridge and PBAM.Bridge.Details and PBAM.Bridge.Details[string.lower(tostring(entry.name or ""))] or nil
    return BestRoleForDetail(detail)
end

function PBAM.IsRosterSortVisible(mode, tabName)
    mode = tostring(mode or "")
    tabName = tostring(tabName or PBAM.CurrentTab or "")
    if mode == "profession" then return tabName == "Professions" end
    if mode == "bagspace" then return tabName == "Inventory" end
    return true
end

function PBAM.GetAppropriateRosterSortMode(tabName, mode)
    tabName = tostring(tabName or PBAM.CurrentTab or "")
    mode = tostring(mode or PBAM.GetStoredRosterSortMode(tabName))
    if PBAM.IsRosterSortVisible(mode, tabName) then return mode end
    return "alpha"
end

function PBAM.GetActiveRosterSortMode()
    return PBAM.GetAppropriateRosterSortMode(PBAM.CurrentTab, PBAM.GetStoredRosterSortMode(PBAM.CurrentTab))
end

function PBAM.GetRosterSortOptions()
    local options = {
        { value="alpha", label="Alphabetical", tooltip="Show all roster entries alphabetically in one group." },
        { value="class", label="By Class", tooltip="Group roster by class, then alphabetize names inside each class." },
        { value="level", label="By Level", tooltip="Group roster by level, then alphabetize names inside each level." },
        { value="role", label="By Role", tooltip="Group roster by role: Tank, Healer, DPS, Unknown. Names stay alphabetical inside each role." },
        { value="profession", label="By Profession", tooltip="Group roster by primary and secondary professions. Bots can appear more than once. Inside each profession, sort by highest skill first, then alphabetically." },
        { value="bagspace", label="Free Bag Space", tooltip="Sort roster by lowest free bag space first, then alphabetically." },
    }
    local visible = {}
    for _, entry in ipairs(options) do
        if PBAM.IsRosterSortVisible(entry.value) then table.insert(visible, entry) end
    end
    return visible
end

function PBAM.UpdateRosterSortDropdown()
    if not PBAM.RosterSortDropdown then return end
    local sortValues = {}
    for _, entry in ipairs(PBAM.GetRosterSortOptions()) do
        table.insert(sortValues, {
            value = entry.value,
            label = entry.label,
            tooltip = entry.tooltip,
            onSelect = function(value)
                PBAM.SetRosterSortMode(value, PBAM.CurrentTab)
            end,
        })
    end
    PBAM.RosterSortDropdown:SetValues(sortValues)
    PBAM.RosterSortDropdown:SetValue(PBAM.GetActiveRosterSortMode())
end

-- ── Bridge Message Handler ──────────────────────────────────

local msgFrame = CreateFrame("Frame")
msgFrame:RegisterEvent("CHAT_MSG_ADDON")
msgFrame:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
    PBAM.Bridge.OnAddonMessage(prefix, message, channel, sender)
end)

-- ── Bridge Callback Registration ───────────────────────────

function PBAM.RegisterCoreBridgeCallbacks()
    PBAM.Bridge.RegisterCallback("RosterUpdated", function(roster)
        PBAM.DebugPrint("RosterUpdated: " .. #roster .. " bots")
        PBAM.RefreshRosterDisplay()
    end)

    PBAM.Bridge.RegisterCallback("Connected", function()
        if not PBAM._BridgeConnectedAnnounced then
            PBAM.LogInfo("Bridge connected")
            PBAM._BridgeConnectedAnnounced = true
        end
        PBAM.UpdateConnectionDot()
    end)

    PBAM.Bridge.RegisterCallback("Disconnected", function(reason)
        PBAM._BridgeConnectedAnnounced = false
        PBAM.LogError("Bridge disconnected: " .. tostring(reason or ""))
        PBAM.UpdateConnectionDot()
    end)

    PBAM.Bridge.RegisterCallback("BotDetailUpdated", function(detail)
        PBAM.DebugPrint("BotDetailUpdated: " .. (detail.name or ""))
        PBAM.QueueRosterRefresh()
    end)

    PBAM.Bridge.RegisterCallback("BotDetailsUpdated", function()
        PBAM.QueueRosterRefresh()
    end)

    PBAM.Bridge.RegisterCallback("StatesUpdated", function()
        PBAM.QueueRosterRefresh()
    end)

    PBAM.Bridge.RegisterCallback("StatsUpdated", function()
        PBAM.QueueRosterRefresh()
    end)

    PBAM.Bridge.RegisterCallback("BotSkillsUpdated", function(botName)  
        if botName then
            local key = string.lower(tostring(botName))
            PBAM.PendingRosterSkillRequests[key] = nil
        end
        if PBAM.CurrentTab == "Professions" and PBAM.GetActiveRosterSortMode and PBAM.GetActiveRosterSortMode() == "profession" then
            PBAM.QueueRosterRefresh()
        end
    end)

    PBAM.Bridge.RegisterCallback("InventoryUpdated", function(botName)  
        if botName then
            local key = string.lower(tostring(botName))
            PBAM.PendingRosterInventoryRequests[key] = nil
        end
        if PBAM.CurrentTab == "Inventory" and PBAM.GetActiveRosterSortMode and PBAM.GetActiveRosterSortMode() == "bagspace" then
            PBAM.QueueRosterRefresh()
        end
    end)

    PBAM.Bridge.RegisterCallback("StateUpdated", function(name, state)
        PBAM.DebugPrint("StateUpdated: " .. name)
    end)
end

PBAM.RegisterCoreBridgeCallbacks()

-- ── Slash Commands ──────────────────────────────────────────

SLASH_PBAM1 = "/pbam"
SLASH_PBAM2 = "/pbaltmanager"
SlashCmdList["PBAM"] = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "hide" then
        if PBAM.MainWindow then PBAM.MainWindow:Hide() end
    elseif cmd == "show" then
        PBAM.OpenWindow()
    elseif cmd == "debug" then
        PBAM.DebugEnabled = not PBAM.DebugEnabled
        PBAM.DebugPrint("Debug mode " .. (PBAM.DebugEnabled and "enabled" or "disabled"))
    elseif cmd == "refresh" then
        PBAM.RefreshAll()

    elseif cmd == "about" then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFD4AF37[PBAltManager]|r v" .. PBAM.Version .. " - Alt management for playerbots")
    else
        if PBAM.MainWindow and PBAM.MainWindow:IsShown() then
            PBAM.MainWindow:Hide()
        else
            PBAM.OpenWindow()
        end
    end
end

-- ── Tab Registry ────────────────────────────────────────────

PBAM.Tabs = {}
PBAM.TabOrder = {}
PBAM.CurrentTab = nil

function PBAM.RegisterTab(name, label, order, buildFunc, options)
    PBAM.DebugPrint("RegisterTab: " .. name .. " label=" .. label .. " order=" .. tostring(order))
    options = options or {}
    PBAM.Tabs[name] = {
        name = name,
        label = label,
        order = order or 99,
        buildFunc = buildFunc,
        hideForPlayer = not not options.hideForPlayer,
    }
    table.insert(PBAM.TabOrder, name)
    table.sort(PBAM.TabOrder, function(a, b)
        return (PBAM.Tabs[a].order or 99) < (PBAM.Tabs[b].order or 99)
    end)
end

-- ── Open / Close ────────────────────────────────────────────

function PBAM.OpenWindow()
    if not PBAM.MainWindow then
        PBAM.CreateMainWindow()
    end
    PBAM.MainWindow:Show()

    -- Request fresh data if not connected
    if not PBAM.Bridge.Connected then
        PBAM.Bridge.SendHello()
    end

    -- Request roster and details
    PBAM.Bridge.RequestRoster()
    PBAM.Bridge.RequestBotDetails()
    PBAM.Bridge.RequestStates()
    PBAM.Bridge.RequestStats()

    -- Request inventory for selected bot if exists
    if PBAM.SelectedBot then
        PBAM.Bridge.RequestInventory(PBAM.SelectedBot)
        PBAM.RefreshTabData()
    end
end

function PBAM.RefreshAll(force)
    local now = GetTime and GetTime() or 0

    -- Throttle refreshes unless forced
    if not force then
        local key = "all"
        local last = PBAM.LastRefreshTime[key] or 0
        if (now - last) < (REFRESH_THROTTLE_MS / 1000) then
            PBAM.DebugPrint("RefreshAll throttled: " .. tostring(now - last) .. "s since last")
            return
        end
        PBAM.LastRefreshTime[key] = now
    end

    PBAM.Bridge.RequestRoster()
    PBAM.Bridge.RequestBotDetails()
    PBAM.Bridge.RequestStates()
    PBAM.Bridge.RequestStats()

    local tab = PBAM.CurrentTab and PBAM.Tabs[PBAM.CurrentTab]
    if PBAM.SelectedBot and tab and tab.panel and tab.panel.OnRefresh then
        tab.panel.OnRefresh(PBAM.SelectedBot)
        return
    end
    PBAM.RefreshTabData()
end

function PBAM.RefreshTabData()
    if not PBAM.SelectedBot or not PBAM.CurrentTab then return end
    local tab = PBAM.Tabs[PBAM.CurrentTab]
    if tab and tab.panel and tab.panel.OnBotSelect then
        tab.panel.OnBotSelect(PBAM.SelectedBot)
    end
end

-- Full window reset: rebuilds the window and tab panels to mimic a fresh addon session.
function PBAM.ResetWindow()
    local wasShown = PBAM.MainWindow and PBAM.MainWindow:IsShown()

    if PBAM.Bridge then
        PBAM.Bridge.Roster = {}
        PBAM.Bridge.Details = {}
        PBAM.Bridge.States = {}
        PBAM.Bridge.Stats = {}
        PBAM.Bridge.Inventory = {}
        PBAM.Bridge.Bank = {}
        PBAM.Bridge.GuildBank = {}
        PBAM.Bridge.TalentSpecs = {}
        PBAM.Bridge.Spells = {}
        PBAM.Bridge.Professions = {}
        PBAM.Bridge.Crafting = {}
        PBAM.Bridge.Quests = {}
        PBAM.Bridge.Reputations = {}
        PBAM.Bridge.Emblems = {}
        PBAM.Bridge.Glyphs = {}
        PBAM.Bridge.Outfits = {}
        PBAM.Bridge.Trainer = {}
        PBAM.Bridge.GameObjects = {}
        PBAM.Bridge.callbacks = {}
        PBAM.Bridge._InFlightRequests = {}
        PBAM.Bridge.Connected = false
    end

    PBAM.PendingRosterInventoryRequests = {}
    PBAM.PendingRosterSkillRequests = {}
    PBAM.LastRefreshTime = {}
    PBAM.SelectedBot = nil
    PBAM.SelectedBotLower = nil
    PBAM.CurrentTab = nil
    PBAM.PreviousTab = nil
    PBAM.BotListEntries = {}
    PBAM.BotListHeaders = {}

    if PBAM.MainWindow then
        PBAM.MainWindow:Hide()
        PBAM.MainWindow:SetParent(nil)
    end

    PBAM.MainWindow = nil
    PBAM.ContentFrame = nil
    PBAM.TabDropdown = nil
    PBAM.BotListContent = nil
    PBAM.BotListScroll = nil
    PBAM.SearchBox = nil
    PBAM.ClearSelectionButton = nil

    if PBAM.Tabs then
        for _, tab in pairs(PBAM.Tabs) do
            tab.panel = nil
        end
    end

    PBAM.RegisterCoreBridgeCallbacks()
    PBAM.CreateMainWindow()
    if wasShown ~= false and PBAM.MainWindow then PBAM.MainWindow:Show() end

    if PBAM.Bridge then
        PBAM.Bridge.SendHello()
        PBAM.Bridge.RequestRoster()
        PBAM.Bridge.RequestBotDetails()
        PBAM.Bridge.RequestStates()
        PBAM.Bridge.RequestStats()
    end

    PBAM.After(7.0, function() PBAM.RefreshAll() end)
    -- The first bridge responses can arrive before details/stats finish populating.
    -- Queue a couple of UI passes so remembered roster sorting, class colors, and
    -- class icons settle without requiring a manual Refresh click.
    --if PBAM.After then
    --    PBAM.After(0.25, function() if PBAM.RefreshRosterDisplay then PBAM.RefreshRosterDisplay() end end)
    --    PBAM.After(0.75, function() if PBAM.RefreshRosterDisplay then PBAM.RefreshRosterDisplay() end end)
    --end
end

-- ── Window Creation ─────────────────────────────────────────

local WND_W = 980
local WND_H = 640
local TITLE_H = 28
local SIDEBAR_W = 250
local TAB_BAR_H = 30
local BORDER = 4
local BG_TEXTURE = "Interface\\Buttons\\WHITE8x8"

function PBAM.SaveMainWindowPosition()
    local window = PBAM.MainWindow
    if not window or not window.GetPoint then return end
    PBAMConfig.MainWindow = PBAMConfig.MainWindow or {}
    local point, _, relativePoint, xOfs, yOfs = window:GetPoint(1)
    PBAMConfig.MainWindow.point = point or "CENTER"
    PBAMConfig.MainWindow.relativePoint = relativePoint or point or "CENTER"
    PBAMConfig.MainWindow.x = tonumber(xOfs) or 0
    PBAMConfig.MainWindow.y = tonumber(yOfs) or 0
end

function PBAM.ApplyMainWindowPosition(window)
    if not window then return end
    local cfg = PBAMConfig.MainWindow or {}
    window:ClearAllPoints()
    if cfg.point and cfg.relativePoint and cfg.x and cfg.y then
        window:SetPoint(cfg.point, UIParent, cfg.relativePoint, tonumber(cfg.x) or 0, tonumber(cfg.y) or 0)
    else
        window:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

function PBAM.CreateMainWindow()
    -- ── Main window ──────────────────────────────────
    PBAM._WindowCounter = (PBAM._WindowCounter or 0) + 1
    local window = CreateFrame("Frame", "PBAMMainWindow" .. tostring(PBAM._WindowCounter), UIParent)
    window:SetSize(WND_W, WND_H)
    PBAM.ApplyMainWindowPosition(window)
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true, tileSize = 16, edgeSize = 12,
        insets   = { left = BORDER, right = BORDER, top = BORDER, bottom = BORDER },
    })
    window:SetBackdropColor(0.04, 0.04, 0.06, 1.0)
    window:SetBackdropBorderColor(0.35, 0.30, 0.20, 1.0)
    window:EnableMouse(true)
    window:EnableKeyboard(true)

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, window)
    titleBar:SetHeight(TITLE_H)
    titleBar:SetPoint("TOPLEFT", window, "TOPLEFT", BORDER + 3, -BORDER)
    titleBar:SetPoint("TOPRIGHT", window, "TOPRIGHT", -(BORDER + 3), -BORDER)
    titleBar:SetFrameLevel(window:GetFrameLevel() + 1)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function()
        if PBAM.OnWindowDragStart then PBAM.OnWindowDragStart() end
        window:StartMoving()
    end)
    titleBar:SetScript("OnDragStop", function()
        window:StopMovingOrSizing()
        PBAM.SaveMainWindowPosition()
        if PBAM.OnWindowDragStop then PBAM.OnWindowDragStop() end
    end)

    local tbBg = titleBar:CreateTexture(nil, "BACKGROUND")
    tbBg:SetAllPoints()
    tbBg:SetTexture(BG_TEXTURE)
    tbBg:SetVertexColor(0.08, 0.08, 0.10, 1.0)

    local titleStr = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleStr:SetPoint("LEFT", titleBar, "LEFT", 6, 5)
    titleStr:SetText("Playerbot Alt Manager")
    titleStr:SetTextColor(0.83, 0.69, 0.22, 1.0)

    local goldLine = titleBar:CreateTexture(nil, "OVERLAY")
    goldLine:SetHeight(1)
    goldLine:SetPoint("BOTTOMLEFT", titleBar, "BOTTOMLEFT", 0, 4)
    goldLine:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 4)
    goldLine:SetTexture(BG_TEXTURE)
    goldLine:SetVertexColor(0.83, 0.69, 0.22, 0.45)

    local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -2, 3)
    closeBtn:SetScript("OnClick", function() window:Hide() end)

    -- ESC key handler to close window and clear focus
    window:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            window:Hide()
        end
    end)

    -- ── Left sidebar ─────────────────────────────────
    local sidebar = CreateFrame("Frame", nil, window)
    sidebar:SetPoint("TOPLEFT", window, "TOPLEFT", BORDER + 3, -(BORDER + TITLE_H + 1))
    sidebar:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", BORDER + 3, BORDER)
    sidebar:SetWidth(SIDEBAR_W)
    sidebar:SetFrameLevel(window:GetFrameLevel() + 1)

    local sbBg = sidebar:CreateTexture(nil, "BACKGROUND")
    sbBg:SetAllPoints()
    sbBg:SetTexture(BG_TEXTURE)
    sbBg:SetVertexColor(0.06, 0.06, 0.08, 1.0)

    -- Header
    local sidebarHeader = CreateFrame("Frame", nil, sidebar)
    sidebarHeader:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, 0)
    sidebarHeader:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
    sidebarHeader:SetHeight(30)
    sidebarHeader:SetFrameLevel(sidebar:GetFrameLevel() + 3)

    local hBg = sidebarHeader:CreateTexture(nil, "BACKGROUND")
    hBg:SetAllPoints()
    hBg:SetTexture(BG_TEXTURE)
    hBg:SetVertexColor(0.09, 0.09, 0.11, 1.0)

    local headerStr = sidebarHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerStr:SetPoint("LEFT", sidebarHeader, "LEFT", 8, 0)
    headerStr:SetText("PLAYERBOTS")
    headerStr:SetTextColor(0.83, 0.69, 0.22, 1.0)

    -- Connection dot + clear selection button
    local connDot = sidebarHeader:CreateTexture(nil, "OVERLAY")
    connDot:SetSize(8, 8)
    connDot:SetPoint("RIGHT", sidebarHeader, "RIGHT", -10, 0)
    connDot:SetTexture(BG_TEXTURE)
    connDot:SetVertexColor(0.80, 0.22, 0.22, 1.0)
    PBAM.ConnectionDot = connDot

    local clearBtn = CreateFrame("Button", nil, sidebarHeader)
    clearBtn:SetSize(16, 16)
    clearBtn:SetPoint("RIGHT", connDot, "LEFT", -8, 0)
    clearBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    clearBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    clearBtn:SetScript("OnClick", function()
        if IsShiftKeyDown and IsShiftKeyDown() then
            -- Full reset: clears all cached data and re-initializes like a fresh load
            PBAM.ResetWindow()
            return
        end

        -- Normal click: only deselect the current bot and return to the empty roster view.
        for _, tab in pairs(PBAM.Tabs or {}) do
            if tab.panel and tab.panel.OnBotSelect then
                tab.panel.OnBotSelect(nil)
            end
        end
        PBAM.SelectBot(nil)
        if PBAM.SwitchTab and PBAM.Tabs and PBAM.Tabs["Roster"] then PBAM.SwitchTab("Roster") end
        if PBAM.RefreshRosterDisplay then PBAM.RefreshRosterDisplay() end
    end)
    clearBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Clear Selection", 1, 0.82, 0.22, true)
        GameTooltip:AddLine("Click: deselect current bot", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Shift-click: full PBAM reset", 1, 0.82, 0.22, true)
        GameTooltip:AddLine("WARNING!", 1, 0, 0, true)
        GameTooltip:AddLine("Shift-click reset may hang the client for 15-20 seconds.", 1, 0.82, 0.22, true)
        GameTooltip:Show()
    end)
    clearBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    PBAM.ClearSelectionButton = clearBtn

    -- ── Bot list (plain ScrollFrame) ─────────────────
    local botListFrame = CreateFrame("ScrollFrame", nil, sidebar)
    botListFrame:SetPoint("TOPLEFT", sidebarHeader, "BOTTOMLEFT", 4, -4)
    botListFrame:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -4, 34)
    botListFrame:SetFrameLevel(sidebar:GetFrameLevel() + 1)
    botListFrame:EnableMouseWheel(true)
    botListFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        -- Increase scroll speed when in Professions tab with profession sort (more rows to scroll)
        local scrollMult = 1.0
        if PBAM.CurrentTab == "Professions" and PBAM.GetActiveRosterSortMode and PBAM.GetActiveRosterSortMode() == "profession" then
            scrollMult = 3.0  -- 3x faster scrolling
        end
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, cur - delta * 20 * scrollMult)))
    end)

    local botListContent = CreateFrame("Frame", nil, botListFrame)
    botListContent:SetFrameLevel(botListFrame:GetFrameLevel() + 1)
    botListContent:SetWidth(botListFrame:GetWidth())
    botListFrame:SetScrollChild(botListContent)
    PBAM.BotListContent = botListContent
    PBAM.BotListScroll = botListFrame

    -- ── Search box ───────────────────────────────────
    local searchFrame = CreateFrame("Frame", nil, sidebar)
    searchFrame:SetHeight(28)
    searchFrame:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 0, 0)
    searchFrame:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)

    local searchLabel = searchFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("LEFT", searchFrame, "LEFT", 6, 2)
    searchLabel:SetText("Filter:")
    searchLabel:SetTextColor(0.55, 0.55, 0.55, 1.0)

    PBAM._SearchBoxCounter = (PBAM._SearchBoxCounter or 0) + 1
    PBAM.SearchBox = CreateFrame("EditBox", "PBAMSearchEditBox" .. tostring(PBAM._SearchBoxCounter), searchFrame, "InputBoxTemplate")
    PBAM.SearchBox:SetAutoFocus(false)
    PBAM.SearchBox:SetWidth(75)
    PBAM.SearchBox:SetHeight(22)
    PBAM.SearchBox:SetPoint("LEFT", searchLabel, "RIGHT", 4, 0)
    PBAM.SearchBox:SetScript("OnTextChanged", function(self)
        PBAM.FilterBotList(self:GetText())
    end)
    PBAM.SearchBox:SetScript("OnEscapePressed", function(self)
        if self:GetText() == "" then
            if PBAM.MainWindow then PBAM.MainWindow:Hide() end
        else
            self:ClearFocus()
            self:SetText("")
        end
    end)

    local sortDropdown = PBAM.CreateDropdown(searchFrame, {})
    sortDropdown:SetPoint("LEFT", PBAM.SearchBox, "RIGHT", -16, -2)
    UIDropDownMenu_SetWidth(sortDropdown, 64)
    UIDropDownMenu_SetButtonWidth(sortDropdown, 94)

    PBAM.RosterSortDropdown = sortDropdown
    PBAM.UpdateRosterSortDropdown()

    local refreshBtn = CreateFrame("Button", nil, searchFrame, "UIPanelButtonTemplate")
    refreshBtn:SetSize(54, 20)
    refreshBtn:SetPoint("LEFT", sortDropdown, "RIGHT", -16, 2)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        PBAM.RefreshAll()
    end)
    refreshBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Refresh All Data", 1, 0.82, 0.22, true)
        GameTooltip:AddLine("Request fresh data for roster, details, states, and stats.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    refreshBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ── Right panel (tabs + content) ─────────────────
    local rightPanel = CreateFrame("Frame", nil, window)
    -- Align the tab bar with the PLAYERBOTS/sidebar header. The sidebar is already
    -- anchored below the title bar, so do not subtract TITLE_H here a second time.
    rightPanel:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 1, 0)
    rightPanel:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -(BORDER + 3), BORDER)
    rightPanel:SetFrameLevel(window:GetFrameLevel() + 1)

    -- Tab bar
    local tabBar = CreateFrame("Frame", nil, rightPanel)
    tabBar:SetHeight(TAB_BAR_H)
    tabBar:SetPoint("TOPLEFT", rightPanel, "TOPLEFT")
    tabBar:SetPoint("TOPRIGHT", rightPanel, "TOPRIGHT")

    local tbBarBg = tabBar:CreateTexture(nil, "BACKGROUND")
    tbBarBg:SetAllPoints()
    tbBarBg:SetTexture(BG_TEXTURE)
    tbBarBg:SetVertexColor(0.15, 0.12, 0.05, 1.0)

    local tabLabel = tabBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tabLabel:SetPoint("RIGHT", tabBar, "RIGHT", -214, 0)
    tabLabel:SetText("Tab:")
    tabLabel:SetTextColor(0.83, 0.69, 0.22, 1.0)

    local tabDropdown = PBAM.CreateDropdown(tabBar, {})
    tabDropdown:SetPoint("RIGHT", tabBar, "RIGHT", -18, 0)
    UIDropDownMenu_SetWidth(tabDropdown, 150)
    UIDropDownMenu_SetButtonWidth(tabDropdown, 170)

    -- Content frame
    local contentFrame = CreateFrame("Frame", nil, rightPanel)
    contentFrame:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -2)
    contentFrame:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", 0, 0)
    contentFrame:SetFrameLevel(rightPanel:GetFrameLevel() + 1)

    PBAM.MainWindow = window
    PBAM.TabBar = tabBar
    PBAM.ContentFrame = contentFrame
    PBAM.Sidebar = sidebar
    PBAM.BotListContainer = botListContent
    PBAM.TabDropdown = tabDropdown

    -- ── Build Tab Panels ─────────────────────────────
    PBAM.DebugPrint("Build Tab Panels: Starting, #Tabs=" .. tostring(#PBAM.TabOrder))
    for name, tab in pairs(PBAM.Tabs) do
        PBAM.DebugPrint("Build Tab Panels: Processing " .. name .. " buildFunc=" .. tostring(tab.buildFunc))
        local tabPanel = CreateFrame("Frame", nil, PBAM.ContentFrame)
        tabPanel:SetPoint("TOPLEFT", PBAM.ContentFrame, "TOPLEFT", 0, 0)
        tabPanel:SetPoint("BOTTOMRIGHT", PBAM.ContentFrame, "BOTTOMRIGHT", 0, 0)
        tabPanel:Hide()

        PBAM.Tabs[name].panel = tabPanel
        if tab.buildFunc then
            tab.buildFunc(tabPanel)
        else
            PBAM.DebugPrint("Build Tab Panels: ERROR - buildFunc is nil for " .. name)
        end

        PBAM.DebugPrint("CreateMainWindow: tab " .. name .. " OnBotSelect=" .. tostring(tabPanel.OnBotSelect))
    end

    -- ── Build Tab Dropdown ───────────────────────────
    PBAM.BuildTabButtons()

    local visibleTabs = PBAM.GetVisibleTabs and PBAM.GetVisibleTabs() or PBAM.TabOrder
    if #visibleTabs > 0 then
        PBAM.SwitchTab(visibleTabs[1])
    end
end

-- ── Tab Buttons ─────────────────────────────────────────────

function PBAM.IsTabHidden(tabName)
    local tab = PBAM.Tabs and PBAM.Tabs[tabName]
    if not tab then return true end
    return tab.hideForPlayer and PBAM.IsSelectedPlayer and PBAM.IsSelectedPlayer()
end

function PBAM.GetVisibleTabs()
    local visible = {}
    for _, name in ipairs(PBAM.TabOrder or {}) do
        if not PBAM.IsTabHidden(name) then
            table.insert(visible, name)
        end
    end
    return visible
end

function PBAM.EnsureValidCurrentTab()
    if PBAM.CurrentTab and not PBAM.IsTabHidden(PBAM.CurrentTab) then return end
    local visible = PBAM.GetVisibleTabs()
    local fallback = visible[1]
    for _, name in ipairs(visible) do
        if name == "Roster" then fallback = name break end
    end
    if fallback then
        PBAM.SwitchTab(fallback)
    end
end

-- Rebuild the compact tab selector from registered tab metadata.
-- Hidden tabs are filtered dynamically (for example when the local player is selected).
function PBAM.BuildTabButtons()
    if not PBAM.TabDropdown then return end

    local values = {}
    for _, name in ipairs(PBAM.TabOrder or {}) do
        local tabName = name
        local tab = PBAM.Tabs[tabName]
        if tab then
            table.insert(values, {
                value = tabName,
                label = tab.label,
                hidden = function() return PBAM.IsTabHidden and PBAM.IsTabHidden(tabName) end,
                onSelect = function(value)
                    if value ~= PBAM.CurrentTab then
                        PBAM.SwitchTab(value)
                    end
                end,
            })
        end
    end

    PBAM.TabDropdown:SetValues(values)
    PBAM.UpdateTabButtonStyles()
end

function PBAM.UpdateTabButtonStyles()
    if PBAM.TabDropdown then
        PBAM.TabDropdown:SetValue(PBAM.CurrentTab)
        PBAM.TabDropdown:Refresh()
    end
end

-- ── Tab Switching ───────────────────────────────────────────

-- Central tab switch path used by dropdown selection, initial open, and hidden-tab fallback.
-- Prefer each tab's OnRefresh hook so switching tabs always reloads that tab's current data.
function PBAM.SwitchTab(tabName)
    if PBAM.IsTabHidden and PBAM.IsTabHidden(tabName) then
        if tabName ~= "Roster" and PBAM.Tabs["Roster"] and not PBAM.IsTabHidden("Roster") then
            return PBAM.SwitchTab("Roster")
        end
        return
    end

    local previousTab = PBAM.CurrentTab
    local previousSortMode = PBAM.GetActiveRosterSortMode and PBAM.GetActiveRosterSortMode() or PBAM.GetRosterSortMode()
    local tab = PBAM.Tabs[tabName]
    if not tab then return end

    PBAM.PreviousTab = previousTab
    PBAM.CurrentTab = tabName
    local storedSortMode = PBAM.GetStoredRosterSortMode and PBAM.GetStoredRosterSortMode(tabName) or PBAM.GetRosterSortMode()
    local newSortMode = PBAM.GetAppropriateRosterSortMode and PBAM.GetAppropriateRosterSortMode(tabName, storedSortMode) or storedSortMode
    if PBAMConfig.RosterSortByTab then PBAMConfig.RosterSortByTab[tabName] = newSortMode end
    PBAMConfig.RosterSort = newSortMode
    PBAM.UpdateTabButtonStyles()
    if PBAM.UpdateRosterSortDropdown then PBAM.UpdateRosterSortDropdown() end

    -- Show current tab's panel
    if tab.panel then
        tab.panel:Show()
    end

    -- Hide other tabs
    for name, t in pairs(PBAM.Tabs) do
        if t.panel and name ~= tabName then
            t.panel:Hide()
        end
    end

    -- Refresh the selected tab every time it is opened/switched to.
    if PBAM.SelectedBot and tab.panel then
        if tab.panel.OnRefresh then
            tab.panel.OnRefresh(PBAM.SelectedBot)
        elseif tab.panel.OnBotSelect then
            tab.panel.OnBotSelect(PBAM.SelectedBot)
        end
    end

    if previousSortMode ~= newSortMode and PBAM.RefreshRosterDisplay then
        PBAM.RefreshRosterDisplay()
    end
end

-- ── Bot Selection ───────────────────────────────────────────

function PBAM.SelectBot(botName)
    PBAM.SelectedBot = botName
    PBAM.SelectedBotLower = PBAM.NormalizeName and PBAM.NormalizeName(botName) or (botName and string.lower(botName) or nil)
    if PBAM.BuildTabButtons then PBAM.BuildTabButtons() end
    if PBAM.EnsureValidCurrentTab then PBAM.EnsureValidCurrentTab() end
    PBAM.DebugPrint("SelectBot called: " .. tostring(botName) .. " CurrentTab=" .. tostring(PBAM.CurrentTab))

    for key, e in pairs(PBAM.BotListEntries or {}) do
        local list = e.frame and { e } or e
        for _, row in ipairs(list or {}) do
            if row.bg then
                row.bg:SetVertexColor(key == PBAM.SelectedBotLower and 0.18 or 0.06, key == PBAM.SelectedBotLower and 0.16 or 0.06, key == PBAM.SelectedBotLower and 0.10 or 0.08, key == PBAM.SelectedBotLower and 0.95 or 0.90)
            end
        end
    end

    -- Only update the CURRENT tab to avoid timing issues
    if PBAM.CurrentTab then
        local tab = PBAM.Tabs[PBAM.CurrentTab]
        PBAM.DebugPrint("  tab exists=" .. tostring(tab) .. " panel exists=" .. tostring(tab and tab.panel) .. " OnRefresh=" .. tostring(tab and tab.panel and tab.panel.OnRefresh) .. " OnBotSelect=" .. tostring(tab and tab.panel and tab.panel.OnBotSelect))
        if tab and tab.panel then
            if tab.panel.OnRefresh then
                tab.panel.OnRefresh(PBAM.SelectedBot)
            elseif tab.panel.OnBotSelect then
                tab.panel.OnBotSelect(PBAM.SelectedBot)
            else
                PBAM.DebugPrint("  Cannot refresh current tab - missing callbacks")
            end
        end
    end
end

function PBAM.RefreshRosterDisplay()
    local roster = {}
    local playerName = UnitName and UnitName("player") or nil
    if playerName and playerName ~= "" then
        table.insert(roster, {
            name = playerName,
            className = UnitClass and select(2, UnitClass("player")) or "",
            level = UnitLevel and UnitLevel("player") or 0,
            alive = not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")),
            isPlayer = true,
        })
    end
    for _, entry in ipairs(PBAM.Bridge.Roster or {}) do table.insert(roster, entry) end
    local search = string.lower(PBAM.SearchBox and PBAM.SearchBox:GetText() or "")
    local sortMode = PBAM.GetActiveRosterSortMode()

    for _, entry in pairs(PBAM.BotListEntries or {}) do
        local list = entry.frame and { entry } or entry
        for _, row in ipairs(list or {}) do
            if row.frame and row.frame:IsShown() then row.frame:Hide() end
        end
    end
    for _, header in ipairs(PBAM.BotListHeaders or {}) do
        if header and header:IsShown() then header:Hide() end
    end
    PBAM.BotListEntries = {}
    PBAM.BotListHeaders = {}

    local content = PBAM.BotListContent
    if not content then
        PBAM.DebugPrint("RefreshRosterDisplay: BotListContent is nil! Window=" .. tostring(PBAM.MainWindow))
        return
    end

    local missingInventoryNames = {}
    local missingSkillNames = {}
    local now = GetTime and GetTime() or 0

    local function BuildProfessionEntry(name, rank, maxRank, skillLine, bucket)
        if not name or name == "" then return nil end
        return {
            id = tonumber(skillLine) or 0,
            name = name,
            displayName = name,
            value = tonumber(rank) or 0,
            max = tonumber(maxRank) or 0,
            bucket = bucket,
        }
    end

    -- WotLK 3.3.5a profession categories (with common name variations)
    local PRIMARY_PROFESSIONS = {
        alchemy=true, blacksmithing=true, enchanting=true, engineering=true, herbalism=true,
        inscription=true, jewelcrafting=true, leatherworking=true, mining=true, skinning=true, tailoring=true
    }
    local SECONDARY_PROFESSIONS = {
        cooking=true, fishing=true, ["first aid"]=true, firstaid=true, ["first_aid"]=true
    }

    local function GetPlayerProfessions()
        local primary, secondary = {}, {}
        if not GetProfessions or not GetProfessionInfo then return primary, secondary end
        local p1, p2, fishing, cooking, firstAid = GetProfessions()
        for _, skillIndex in ipairs({ p1, p2 }) do
            if skillIndex then
                local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(skillIndex)
                local profession = BuildProfessionEntry(name, rank, maxRank, skillLine, "primary")
                if profession then table.insert(primary, profession) end
            end
        end
        for _, skillIndex in ipairs({ fishing, cooking, firstAid }) do
            if skillIndex then
                local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(skillIndex)
                local profession = BuildProfessionEntry(name, rank, maxRank, skillLine, "secondary")
                if profession then table.insert(secondary, profession) end
            end
        end
        return primary, secondary
    end

    local function GetEntryProfessions(entry)
        if not entry then return {}, {} end
        if entry.isPlayer then return GetPlayerProfessions() end
        local key = string.lower(tostring(entry.name or ""))
        -- Check both Professions (from BOT_SKILLS) and Crafting (from PROFESSION command)
        local skills = PBAM.Bridge and PBAM.Bridge.Professions and PBAM.Bridge.Professions[key] or nil
        local crafting = PBAM.Bridge and PBAM.Bridge.Crafting and PBAM.Bridge.Crafting[key] or nil

        if not skills and not crafting then
            if sortMode == "profession" and PBAM.CurrentTab == "Professions" and PBAM.Bridge and PBAM.Bridge.RequestBotSkills then
                -- Always queue this bot for skills request (we want ALL bots eventually)
                table.insert(missingSkillNames, entry.name)
            end
            return {}, {}
        end

        -- Merge primary and secondary from both sources
        local primary = {}
        local secondary = {}

        if skills then
            for _, prof in ipairs(skills.primary or {}) do table.insert(primary, prof) end
            for _, prof in ipairs(skills.secondary or {}) do table.insert(secondary, prof) end
        end

        -- Also check crafting data for additional professions
        if crafting and crafting.professions then
            for name, data in pairs(crafting.professions) do
                local k = string.lower(tostring(name or "")):gsub("%s+", ""):gsub("_", " ")
                -- Determine if primary or secondary based on profession name
                local isSecondary = SECONDARY_PROFESSIONS[k] or false
                local bucket = isSecondary and secondary or primary
                -- Check if we already have this profession from skills data
                local alreadyHave = false
                for _, p in ipairs(bucket) do
                    local existingKey = string.lower(p.name or ""):gsub("%s+", ""):gsub("_", " ")
                    if existingKey == k then alreadyHave = true break end
                end
                if not alreadyHave then
                    -- Normalize the profession name for display
                    local displayName = name
                    if k == "first aid" or k == "firstaid" or k == "first_aid" then
                        displayName = "First Aid"
                    elseif k == "cooking" then
                        displayName = "Cooking"
                    elseif k == "fishing" then
                        displayName = "Fishing"
                    end
                    local prof = BuildProfessionEntry(displayName, data.level or 0, data.max or 75, 0, isSecondary and "secondary" or "primary")
                    if prof then table.insert(bucket, prof) end
                end
            end
        end

        return primary, secondary
    end

    local function GetEntryFreeBagSpace(entry)
        if not entry then return math.huge end
        if entry.isPlayer then
            local free, total = 0, 0
            if GetContainerNumFreeSlots and GetContainerNumSlots then
                for bag = 0, 4 do
                    local bagFree = select(1, GetContainerNumFreeSlots(bag))
                    free = free + (tonumber(bagFree) or 0)
                    total = total + (tonumber(GetContainerNumSlots(bag)) or 0)
                end
            end
            entry._bagUsed = math.max(0, total - free)
            entry._bagTotal = total
            return free
        end
        local key = string.lower(tostring(entry.name or ""))
        local inv = PBAM.Bridge and PBAM.Bridge.Inventory and PBAM.Bridge.Inventory[key] or nil
        if not inv then
            if sortMode == "bagspace" and PBAM.CurrentTab == "Inventory" and PBAM.Bridge and PBAM.Bridge.RequestInventory then
                -- Always queue this bot for inventory request (we want ALL bots eventually)
                table.insert(missingInventoryNames, entry.name)
            end
            entry._bagUsed = 0
            entry._bagTotal = 0
            return math.huge
        end
        entry._bagUsed = tonumber(inv.bagUsed) or 0
        entry._bagTotal = tonumber(inv.bagTotal) or 0
        if inv.loading then return math.huge end
        return math.max(0, entry._bagTotal - entry._bagUsed)
    end

    local filteredPlayer, filtered = nil, {}
    for _, entry in ipairs(roster) do
        local name = entry.name or ""
        local lower = string.lower(name)
        if search == "" or lower:find(search, 1, true) ~= nil then
            entry.className = entry.className or PBAM.GetBotClassName(name)
            entry.level = entry.level or 0
            entry.role = PBAM.GetRosterRole(entry)
            entry._freeBagSpace = nil
            entry._primaryProfessions = nil
            entry._secondaryProfessions = nil
            if sortMode == "bagspace" then entry._freeBagSpace = GetEntryFreeBagSpace(entry) end
            if sortMode == "profession" then
                entry._primaryProfessions, entry._secondaryProfessions = GetEntryProfessions(entry)
            end
            if entry.isPlayer then filteredPlayer = entry else table.insert(filtered, entry) end
        end
    end

    -- Send requests for any bots that were queued this cycle, respecting throttle limits
    -- Clean up stale pending entries first (TTL expired)
    for key, sentAt in pairs(PBAM.PendingRosterInventoryRequests) do
        if (now - tonumber(sentAt)) >= ROSTER_SORT_REQUEST_TTL then
            PBAM.PendingRosterInventoryRequests[key] = nil
        end
    end
    for key, sentAt in pairs(PBAM.PendingRosterSkillRequests) do
        if (now - tonumber(sentAt)) >= ROSTER_SORT_REQUEST_TTL then
            PBAM.PendingRosterSkillRequests[key] = nil
        end
    end

    if sortMode == "bagspace" and PBAM.CurrentTab == "Inventory" and PBAM.Bridge and PBAM.Bridge.RequestInventory then
        local sentCount = 0
        for _, name in ipairs(missingInventoryNames) do
            if sentCount >= ROSTER_SORT_MAX_INFLIGHT then break end
            local key = string.lower(tostring(name or ""))
            if key ~= "" and not PBAM.PendingRosterInventoryRequests[key] then
                PBAM.PendingRosterInventoryRequests[key] = now
                PBAM.Bridge.RequestInventory(name)
                sentCount = sentCount + 1
            end
        end
    elseif sortMode == "profession" and PBAM.CurrentTab == "Professions" and PBAM.Bridge and PBAM.Bridge.RequestBotSkills then
        local sentCount = 0
        for _, name in ipairs(missingSkillNames) do
            if sentCount >= ROSTER_SORT_MAX_INFLIGHT then break end
            local key = string.lower(tostring(name or ""))
            if key ~= "" and not PBAM.PendingRosterSkillRequests[key] then
                PBAM.PendingRosterSkillRequests[key] = now
                PBAM.Bridge.RequestBotSkills(name)
                sentCount = sentCount + 1
            end
        end
    end

    local groupsByKey, groupOrder = {}, {}
    local function ensureGroup(key, label, order)
        local g = groupsByKey[key]
        if not g then
            g = { key = key, label = label, order = order or 9999, entries = {} }
            groupsByKey[key] = g
            table.insert(groupOrder, g)
        end
        return g
    end

    local function AddEntryToGroups(entry)
        local group
        if sortMode == "class" then
            local className = tostring(entry.className or "") ~= "" and tostring(entry.className) or "Unknown"
            group = ensureGroup(string.lower(className), className, 1000)
            table.insert(group.entries, entry)
        elseif sortMode == "level" then
            local level = tonumber(entry.level) or 0
            group = ensureGroup("lvl:" .. tostring(level), "Level " .. tostring(level), level)
            table.insert(group.entries, entry)
        elseif sortMode == "role" then
            local role = tostring(entry.role or "Unknown")
            local normalized = role == "Tank/DPS" and "DPS" or role
            group = ensureGroup(string.lower(normalized), normalized, ROLE_SORT_ORDER[normalized] or 9999)
            table.insert(group.entries, entry)
        elseif sortMode == "profession" then
            local hasAnyProfession = false
            local function addProfessionGroups(professions, bucketLabel, bucketOrder)
                for _, profession in ipairs(professions or {}) do
                    hasAnyProfession = true
                    -- Normalize profession name capitalization
                    local label = tostring(profession.displayName or profession.name or "Unknown")
                    -- Handle common variations like "firstaid", "first_aid" -> "First Aid"
                    local normalizedForCheck = string.lower(label:gsub("%s+", ""):gsub("_", " "))
                    if SECONDARY_PROFESSIONS[normalizedForCheck] then
                        if normalizedForCheck == "first aid" or normalizedForCheck == "firstaid" or normalizedForCheck == "first_aid" then
                            label = "First Aid"
                        elseif normalizedForCheck == "cooking" then
                            label = "Cooking"
                        elseif normalizedForCheck == "fishing" then
                            label = "Fishing"
                        end
                    elseif PRIMARY_PROFESSIONS[normalizedForCheck] then
                        -- Capitalize first letter of each word for primary professions
                        label = string.gsub(string.lower(label), "%a", function(c) return string.upper(c) end, 1)
                    end
                    group = ensureGroup("profession:" .. string.lower(bucketLabel) .. ":" .. string.lower(label), label, 1000 + bucketOrder)
                    group.mainHeader = bucketLabel
                    group.mainOrder = bucketOrder
                    group.subHeader = label
                    table.insert(group.entries, { source = entry, profession = profession })
                end
            end
            addProfessionGroups(entry._primaryProfessions or {}, "Primary", 1)
            addProfessionGroups(entry._secondaryProfessions or {}, "Secondary", 2)
        elseif sortMode == "bagspace" then
            group = ensureGroup("bagspace", "Free Bag Space", 1)
            table.insert(group.entries, entry)
        else
            group = ensureGroup("alpha", "Alphabetical", 1)
            table.insert(group.entries, entry)
        end
    end

    if filteredPlayer and (sortMode == "profession" or sortMode == "bagspace") then AddEntryToGroups(filteredPlayer) end
    for _, entry in ipairs(filtered) do AddEntryToGroups(entry) end

    table.sort(groupOrder, function(a, b)
        if sortMode == "profession" then
            local aMain, bMain = tonumber(a.mainOrder) or 9999, tonumber(b.mainOrder) or 9999
            if aMain ~= bMain then return aMain < bMain end
        end
        if a.order ~= b.order then return a.order < b.order end
        return string.lower(a.label or "") < string.lower(b.label or "")
    end)
    for _, group in ipairs(groupOrder) do
        table.sort(group.entries, function(a, b)
            if sortMode == "profession" then
                local aEntry, bEntry = a.source or a, b.source or b
                local aSkill = tonumber(a.profession and a.profession.value) or 0
                local bSkill = tonumber(b.profession and b.profession.value) or 0
                if aSkill ~= bSkill then return aSkill > bSkill end
                return string.lower(aEntry.name or "") < string.lower(bEntry.name or "")
            elseif sortMode == "bagspace" then
                local aFree = tonumber(a._freeBagSpace) or math.huge
                local bFree = tonumber(b._freeBagSpace) or math.huge
                if aFree ~= bFree then return aFree < bFree end
                return string.lower(a.name or "") < string.lower(b.name or "")
            end
            return string.lower(a.name or "") < string.lower(b.name or "")
        end)
    end

    local rowH, headerH, mainHeaderH = 28, 20, 20
    local rowY = -4
    local SIDEBAR_W = 250
    local renderedRows = 0

    local function RenderRosterRow(entry)
        local rowEntry = entry
        local profession = rowEntry and rowEntry.profession or nil
        entry = rowEntry.source or rowEntry
        local name = entry.name or ""
        local lower = string.lower(name)
        local className = entry.className or ""
        local classColor = PBAM.GetClassColor(className)
        local level = entry.level or 0
        local isAlive = entry.alive

        local rowFrame = CreateFrame("Button", nil, content)
        rowFrame:SetHeight(rowH)
        rowFrame:SetWidth(SIDEBAR_W - 20)
        rowFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 8, rowY)
        rowFrame:EnableMouse(true)

        local bg = rowFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture(BG_TEXTURE)
        local selected = lower == PBAM.SelectedBotLower
        bg:SetVertexColor(selected and 0.18 or 0.12, selected and 0.16 or 0.11, selected and 0.10 or 0.09, selected and 0.95 or 1.0)
        bg:Show()
        rowFrame.bg = bg

        local classIcon = rowFrame:CreateTexture(nil, "OVERLAY")
        classIcon:SetSize(18, 18)
        classIcon:SetPoint("LEFT", rowFrame, "LEFT", 6, 0)
        local iconTexture, left, right, top, bottom = PBAM.GetClassIcon(className)
        classIcon:SetTexture(iconTexture)
        if left then classIcon:SetTexCoord(left, right, top, bottom) else classIcon:SetTexCoord(0, 1, 0, 1) end

        local classBar = rowFrame:CreateTexture(nil, "OVERLAY")
        classBar:SetWidth(3)
        classBar:SetHeight(rowH - 4)
        classBar:SetPoint("LEFT", classIcon, "RIGHT", 5, 0)
        classBar:SetTexture(BG_TEXTURE)
        if classColor then
            local r, g, b = tonumber(classColor:sub(1,2), 16)/255, tonumber(classColor:sub(3,4), 16)/255, tonumber(classColor:sub(5,6), 16)/255
            classBar:SetVertexColor(r or 0.5, g or 0.5, b or 0.5)
        else
            classBar:SetVertexColor(0.5, 0.5, 0.5)
        end

        local nameFs = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameFs:SetPoint("LEFT", classBar, "RIGHT", 6, 0)
        nameFs:SetPoint("RIGHT", rowFrame, "RIGHT", -72, 0)
        nameFs:SetJustifyH("LEFT")
        nameFs:SetText("|cff" .. (classColor or "ffffff") .. name .. (entry.isPlayer and " |cffd4af37(You)|r" or ""))

        local levelFs = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        levelFs:SetPoint("RIGHT", rowFrame, "RIGHT", -8, 0)
        if sortMode == "bagspace" then
            local used = tonumber(entry._bagUsed) or 0
            local total = tonumber(entry._bagTotal) or 0
            local free = tonumber(entry._freeBagSpace)
            if free == nil or free == math.huge then free = math.max(0, total - used) end
            levelFs:SetPoint("RIGHT", rowFrame, "RIGHT", -60, 0)
            levelFs:SetText(string.format("%d/%d", free, total))
        elseif sortMode == "profession" and profession then
            levelFs:SetPoint("RIGHT", rowFrame, "RIGHT", -60, 0)
            levelFs:SetText(string.format("%d/%d", tonumber(profession.value) or 0, tonumber(profession.max) or 0))
        else
            levelFs:SetText("Lv." .. level)
        end
        levelFs:SetTextColor(0.55, 0.55, 0.55, 1.0)

        local dot = rowFrame:CreateTexture(nil, "OVERLAY")
        dot:SetSize(6, 6)
        dot:SetPoint("RIGHT", rowFrame, "RIGHT", -40, 1)
        dot:SetTexture(BG_TEXTURE)
        dot:SetVertexColor(isAlive and 0.27 or 0.80, 1.0, isAlive and 0.53 or 0.22)

        rowFrame:SetScript("OnMouseDown", function(self, btn)
            if btn == "LeftButton" then PBAM.SelectBot(name) end
        end)

        PBAM.BotListEntries[lower] = PBAM.BotListEntries[lower] or {}
        table.insert(PBAM.BotListEntries[lower], { frame = rowFrame, bg = bg })
        rowY = rowY - rowH
        renderedRows = renderedRows + 1
    end

    if filteredPlayer and sortMode ~= "profession" and sortMode ~= "bagspace" then
        RenderRosterRow(filteredPlayer)
    end

    local lastMainHeader = nil
    local seenProfessions = {}  -- Track which professions we've already shown headers for
    for _, group in ipairs(groupOrder) do
        if #group.entries > 0 then
            if sortMode == "profession" then
                if group.mainHeader ~= lastMainHeader then
                    local mainHeader = CreateFrame("Frame", nil, content)
                    mainHeader:SetHeight(mainHeaderH)
                    mainHeader:SetWidth(SIDEBAR_W - 20)
                    mainHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 8, rowY)
                    table.insert(PBAM.BotListHeaders, mainHeader)

                    local mainHeaderBg = mainHeader:CreateTexture(nil, "BACKGROUND")
                    mainHeaderBg:SetAllPoints()
                    mainHeaderBg:SetTexture(BG_TEXTURE)
                    mainHeaderBg:SetVertexColor(0.22, 0.18, 0.12, 0.98)

                    local mainHeaderFs = mainHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    mainHeaderFs:SetPoint("LEFT", mainHeader, "LEFT", 8, 0)
                    mainHeaderFs:SetText(group.mainHeader)
                    mainHeaderFs:SetTextColor(1.0, 0.82, 0.24, 1.0)

                    rowY = rowY - mainHeaderH
                    renderedRows = renderedRows + 1
                    lastMainHeader = group.mainHeader
                end

                -- Only show sub-header if we haven't shown this profession yet in this main section
                local professionKey = group.mainHeader .. ":" .. group.subHeader
                if not seenProfessions[professionKey] then
                    seenProfessions[professionKey] = true
                    local header = CreateFrame("Frame", nil, content)
                    header:SetHeight(headerH)
                    header:SetWidth(SIDEBAR_W - 20)
                    header:SetPoint("TOPLEFT", content, "TOPLEFT", 8, rowY)
                    table.insert(PBAM.BotListHeaders, header)

                    local headerBg = header:CreateTexture(nil, "BACKGROUND")
                    headerBg:SetAllPoints()
                    headerBg:SetTexture(BG_TEXTURE)
                    headerBg:SetVertexColor(0.18, 0.15, 0.10, 0.95)

                    local headerFs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    headerFs:SetPoint("LEFT", header, "LEFT", 16, 0)
                    headerFs:SetText(group.subHeader .. ":")
                    headerFs:SetTextColor(0.83, 0.69, 0.22, 1.0)

                    rowY = rowY - headerH
                    renderedRows = renderedRows + 1
                end
            elseif sortMode ~= "alpha" and sortMode ~= "bagspace" then
                local header = CreateFrame("Frame", nil, content)
                header:SetHeight(headerH)
                header:SetWidth(SIDEBAR_W - 20)
                header:SetPoint("TOPLEFT", content, "TOPLEFT", 8, rowY)
                table.insert(PBAM.BotListHeaders, header)

                local headerBg = header:CreateTexture(nil, "BACKGROUND")
                headerBg:SetAllPoints()
                headerBg:SetTexture(BG_TEXTURE)
                headerBg:SetVertexColor(0.18, 0.15, 0.10, 0.95)

                local headerFs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                headerFs:SetPoint("LEFT", header, "LEFT", 8, 0)
                headerFs:SetText(group.label .. ":")
                headerFs:SetTextColor(0.83, 0.69, 0.22, 1.0)

                rowY = rowY - headerH
                renderedRows = renderedRows + 1
            end

            for _, entry in ipairs(group.entries) do
                RenderRosterRow(entry)
            end
        end
    end

    local totalHeight = math.max(50, -rowY + 8)
    content:SetHeight(totalHeight)
    PBAM.BotListScroll:SetScrollChild(content)
    if PBAM.UpdateRosterSortDropdown then PBAM.UpdateRosterSortDropdown() end
    PBAM.UpdateConnectionDot()
end

function PBAM.FilterBotList(filter)
    filter = string.lower(filter or "")
    PBAM.RefreshRosterDisplay()
end

function PBAM.GetBotClassName(botName)
    local detail = PBAM.Bridge.Details and PBAM.Bridge.Details[string.lower(botName)]
    return detail and detail.className or ""
end

function PBAM.GetClassColor(className)
    if PBAM.Theme and PBAM.Theme.class_colors and className then
        local direct = PBAM.Theme.class_colors[className]
        if direct then return direct end
        local tokenMap = { WARRIOR="Warrior", PALADIN="Paladin", HUNTER="Hunter", ROGUE="Rogue", PRIEST="Priest", DEATHKNIGHT="Death Knight", SHAMAN="Shaman", MAGE="Mage", WARLOCK="Warlock", DRUID="Druid" }
        local normalized = tokenMap[string.upper(tostring(className):gsub("%s+", ""))]
        return (normalized and PBAM.Theme.class_colors[normalized]) or "ffffff"
    end
    return "ffffff"
end


function PBAM.GetClassIcon(className)
    local tokenMap = {
        warrior="WARRIOR", paladin="PALADIN", hunter="HUNTER", rogue="ROGUE", priest="PRIEST",
        deathknight="DEATHKNIGHT", shaman="SHAMAN", mage="MAGE", warlock="WARLOCK", druid="DRUID",
    }
    local key = string.lower(tostring(className or "unknown")):gsub("%s+", "")
    local token = tokenMap[key] or string.upper(tostring(className or "unknown")):gsub("%s+", "")
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]
    if coords then
        return "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes", coords[1], coords[2], coords[3], coords[4]
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

function PBAM.SameUnitName(unit, botName)
    if not unit or not UnitExists or not UnitExists(unit) or not botName then return false end
    local name = UnitName(unit)
    name = name and tostring(name):match("^[^-]+") or ""
    local wanted = tostring(botName):match("^[^-]+") or tostring(botName)
    return string.lower(name) == string.lower(wanted)
end

function PBAM.FindBotUnit(botName)
    if not botName or botName == "" then return nil end
    if PBAM.SameUnitName("target", botName) then return "target" end
    if PBAM.SameUnitName("focus", botName) then return "focus" end
    if InspectFrame and InspectFrame.unit and PBAM.SameUnitName(InspectFrame.unit, botName) then return InspectFrame.unit end
    for i=1,4 do local u="party"..i; if PBAM.SameUnitName(u, botName) then return u end end
    for i=1,40 do local u="raid"..i; if PBAM.SameUnitName(u, botName) then return u end end
    return nil
end

function PBAM.GetRosterEntry(botName)
    if not botName or not PBAM.Bridge or not PBAM.Bridge.Roster then return nil end
    local wanted = string.lower(tostring(botName))
    for _, entry in ipairs(PBAM.Bridge.Roster) do
        if entry.name and string.lower(entry.name) == wanted then return entry end
    end
    return nil
end

function PBAM.GetLiveBotStatus(botName)
    local unit = PBAM.FindBotUnit(botName)
    if not unit then return nil end
    local hp, maxHp = UnitHealth(unit) or 0, UnitHealthMax(unit) or 0
    local hpPct = maxHp > 0 and math.floor((hp / maxHp) * 100 + 0.5) or nil
    local zone = nil
    if GetRealZoneText and (UnitInParty(unit) or UnitInRaid(unit) or unit == "target" or unit == "focus") then
        zone = GetRealZoneText()
    end
    return { unit = unit, hp = hp, maxHp = maxHp, hpPct = hpPct, zone = zone, dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) }
end

function PBAM.UpdateConnectionDot()
    if not PBAM.ConnectionDot then return end
    local connected = PBAM.Bridge.Connected
    PBAM.ConnectionDot:SetVertexColor(
        connected and 0.27 or 0.80,
        1.0,
        connected and 0.53 or 0.22
    )
end

-- ── Login Handler ───────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self, event)
    self:UnregisterEvent(event)
    PBAM.DebugPrint("PBAltManager v" .. PBAM.Version .. " loaded")
    PBAM.DebugPrint("Slash commands: /pbam, /pbaltmanager")
    -- Request initial data
    PBAM.Bridge.RequestRoster()
    PBAM.Bridge.RequestBotDetails()
end)
