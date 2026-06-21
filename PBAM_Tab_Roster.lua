-- ============================================================
--  PBAM_Tab_Roster.lua  |  Roster tab — selected character overview
-- ============================================================

PBAM = PBAM or {}

local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:0:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:0:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:0:0|t"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local POWERLESS = { WARRIOR=true, ROGUE=true, DEATHKNIGHT=true }

local TREE_NAMES = {
    WARRIOR={"Arms","Fury","Protection"}, PALADIN={"Holy","Protection","Retribution"}, HUNTER={"Beast Mastery","Marksmanship","Survival"},
    ROGUE={"Assassination","Combat","Subtlety"}, PRIEST={"Discipline","Holy","Shadow"}, DEATHKNIGHT={"Blood","Frost","Unholy"},
    SHAMAN={"Elemental","Enhancement","Restoration"}, MAGE={"Arcane","Fire","Frost"}, WARLOCK={"Affliction","Demonology","Destruction"}, DRUID={"Balance","Feral","Restoration"},
}

local ROLE_BY_SPEC = {
    Protection="Tank", ["Protection Warrior"]="Tank", Blood="Tank", Feral="Tank/DPS",
    Holy="Healer", ["Holy Pala"]="Healer", Discipline="Healer", Restoration="Healer",
}

-- Global variable for reputation section Y position (updated dynamically)
local repStartY = -80

local function ClassKey(className)
    local s = tostring(className or ""):upper():gsub("%s+", "")
    if s == "DEATHKNIGHT" then return "DEATHKNIGHT" end
    return s
end

local function MoneyText(stats)
    local total = tonumber(stats and stats.totalCopper)
    local g, s, c
    if total then
        g = math.floor(total / 10000)
        s = math.floor((total % 10000) / 100)
        c = total % 100
    else
        g = tonumber(stats and stats.gold) or 0
        s = tonumber(stats and stats.silver) or 0
        c = tonumber(stats and stats.copper) or 0
    end
    return string.format("Money: %s %d  %s %d  %s %d", GOLD_ICON, g, SILVER_ICON, s, COPPER_ICON, c)
end

local function QuestStatusText(status)
    status = tostring(status or "")
    if status == "C" then return "C" end
    if status == "I" then return "I" end
    return status ~= "" and status or "Quest"
end

local function TooltipQuestName(questId)
    questId = tonumber(questId) or 0
    if questId <= 0 or not CreateFrame then return nil end
    PBAMHiddenQuestTooltip = PBAMHiddenQuestTooltip or CreateFrame("GameTooltip", "PBAMHiddenQuestTooltip", UIParent, "GameTooltipTemplate")
    local tt = PBAMHiddenQuestTooltip
    tt:SetOwner(UIParent, "ANCHOR_NONE")
    tt:ClearLines()
    if tt.SetHyperlink then pcall(tt.SetHyperlink, tt, "quest:" .. tostring(questId) .. ":0") end
    local line = _G["PBAMHiddenQuestTooltipTextLeft1"]
    local text = line and line:GetText()
    tt:Hide()
    if text and text ~= "" and text ~= tostring(questId) then return text end
    return nil
end

local function LocalQuestName(questId, questName)
    questId = tonumber(questId) or 0
    questName = tostring(questName or "")
    if questName ~= "" and questName ~= tostring(questId) then return questName end
    local tooltipName = TooltipQuestName(questId)
    if tooltipName then return tooltipName end
    if questId > 0 and GetNumQuestLogEntries and GetQuestLogTitle then
        for i=1, GetNumQuestLogEntries() do
            local title, _, _, _, _, _, _, id = GetQuestLogTitle(i)
            if tonumber(id) == questId and title and title ~= "" then return title end
        end
    end
    return questId > 0 and ("Quest #" .. tostring(questId)) or "Unknown Quest"
end

local function QuestLink(questId, questName)
    questId = tonumber(questId) or 0
    local name = LocalQuestName(questId, questName)
    if questId > 0 then return ("|cff00ff00|Hquest:%d:0|h[%s]|h|r"):format(questId, name) end
    return name
end

local function After(delay, func)
    return PBAM.After(delay, func)
end

local function BestPlayerSpec()
    if not GetTalentTabInfo then return "N/A", "N/A" end
    local maxI, maxV, total, tied = 1, 0, 0, false
    local names = {}
    for i=1,3 do
        local name, _, points = GetTalentTabInfo(i)
        points = tonumber(points) or 0
        names[i] = name
        total = total + points
        if points > maxV then maxI, maxV, tied = i, points, false elseif points == maxV and points > 0 then tied = true end
    end
    if total < 10 or maxV < 6 or tied then return "N/A", "N/A" end
    local spec = names[maxI] or "N/A"
    return spec, ROLE_BY_SPEC[spec] or "DPS"
end

local function BestSpec(detail)
    if not detail then return "N/A", "N/A" end
    local vals = { tonumber(detail.talent1) or 0, tonumber(detail.talent2) or 0, tonumber(detail.talent3) or 0 }
    local maxI, maxV, total, tied = 1, vals[1], vals[1] + vals[2] + vals[3], false
    for i=2,3 do
        if vals[i] > maxV then maxI, maxV, tied = i, vals[i], false elseif vals[i] == maxV then tied = true end
    end
    if total < 10 or maxV < 6 or tied then return "N/A", "N/A" end
    local names = TREE_NAMES[ClassKey(detail.className)] or {"Tree 1","Tree 2","Tree 3"}
    local spec = names[maxI] or "N/A"
    return spec, ROLE_BY_SPEC[spec] or "DPS"
end

local function Line(parent, y, icon, text)
    local tex = parent:CreateTexture(nil, "OVERLAY")
    tex:SetSize(16,16); tex:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y + 1); tex:SetTexture(icon or UNKNOWN_ICON)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", tex, "TOPRIGHT", 6, 1)
    PBAM.WrapFontString(fs, 320)
    fs:SetText(text or "")
    fs:SetTextColor(0.72,0.72,0.72,1)
    return fs, tex
end

local function LocalPlayerQuests()
    local quests = {}
    if not GetNumQuestLogEntries or not GetQuestLogTitle then return quests end
    for i=1, GetNumQuestLogEntries() do
        local title, _, _, _, isHeader, _, isComplete, questId = GetQuestLogTitle(i)
        if not isHeader and title and title ~= "" and questId and questId > 0 then
            table.insert(quests, { questId=questId, questName=title, status=(isComplete and isComplete > 0) and "C" or "I", isPlayer=true })
        end
    end
    return quests
end

local function LocalPlayerReputations()
    local reps = {}
    if not GetNumFactions or not GetFactionInfo then return reps end
    for i=1, GetNumFactions() do
        local name, _, standingId, bottomValue, topValue, earnedValue, _, _, isHeader, _, hasRep = GetFactionInfo(i)
        if name and name ~= "" and (not isHeader or hasRep) then
            reps[name] = { standing=standingId or 0, value=earnedValue or 0, max=topValue or 0 }
        end
    end
    return { name=UnitName and UnitName("player") or "player", reputations=reps }
end

local function RequestSelectedAux(botName)
    if not botName or not PBAM.Bridge then return end
    -- Player rows are selected locally; bridge/legacy bot requests may not apply to the logged-in character.
    if string.lower(tostring(UnitName and UnitName("player") or "")) == string.lower(tostring(botName)) then return end
    if PBAM.Bridge.RequestQuests then PBAM.Bridge.RequestQuests("ALL", botName) end
    if PBAM.Bridge.RequestBotReputations then PBAM.Bridge.RequestBotReputations(botName) end
end

PBAM.RegisterTab("Roster", "Roster", 1, function(panel)
    local MARGIN, LEFT_W, RIGHT_CONTENT_W = 12, 360, 340
    local QUEST_TEXT_W, REP_TEXT_W = 240, 300
    local questRows, repRows = {}, {}
    local repsOpen = false

    local emptyFs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyFs:SetPoint("CENTER", panel, "CENTER", 0, 0)
    emptyFs:SetText("Select a bot or player from the sidebar to view details")
    emptyFs:SetTextColor(0.5,0.5,0.5,1)

    local left = CreateFrame("Frame", nil, panel)
    left:SetPoint("TOPLEFT", panel, "TOPLEFT", MARGIN, -MARGIN)
    left:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", MARGIN, MARGIN)
    left:SetWidth(LEFT_W)
    PBAM.ApplyBackdrop(left, 0.45)
    left:Hide()

    local right = CreateFrame("Frame", nil, panel)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
    right:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -MARGIN, MARGIN)
    PBAM.ApplyBackdrop(right, 0.35)
    right:Hide()

    local rightScroll = CreateFrame("ScrollFrame", nil, right)
    rightScroll:SetPoint("TOPLEFT", right, "TOPLEFT", 0, 0)
    rightScroll:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -4, 0)
    rightScroll:EnableMouseWheel(true)
    rightScroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), cur - delta * 24)))
    end)
    local rightContent = CreateFrame("Frame", nil, rightScroll)
    rightContent:SetWidth(RIGHT_CONTENT_W)
    rightScroll:SetScrollChild(rightContent)

    PBAM.CreateSectionHeader(left, "Selected Character", -10, 12)
    local nameFs = left:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    nameFs:SetPoint("TOPLEFT", left, "TOPLEFT", 12, -32); PBAM.WrapFontString(nameFs, LEFT_W - 24)

    local lines, lineIcons = {}, {}
    local y = -62
    local lineDefs = {
        {"Interface\\Icons\\Achievement_Character_Human_Male", "identity"}, {"Interface\\Icons\\Achievement_Level_80", "level"},
        {"Interface\\Icons\\Achievement_General", "spec"}, {"Interface\\Icons\\INV_Chest_Plate03", "gear"},
        {"Interface\\Icons\\Ability_DualWield", "status"}, {"Interface\\Icons\\Spell_Holy_Heal", "hp"},
        {"Interface\\Icons\\Spell_Frost_ManaRecharge", "mana"}, {"Interface\\Icons\\INV_Misc_Coin_01", "money"},
        {"Interface\\Icons\\INV_Misc_Map_01", "location"}, {"Interface\\Icons\\Ability_Hunter_MarkedForDeath", "target"},
    }
    local lineOrder = {}
    for _, d in ipairs(lineDefs) do
        lines[d[2]], lineIcons[d[2]] = Line(left, y, d[1], "")
        table.insert(lineOrder, d[2])
        y = y - 24
    end

    local suggest = left:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    suggest:SetPoint("TOPLEFT", left, "TOPLEFT", 12, y - 8); PBAM.WrapFontString(suggest, LEFT_W - 24)
    suggest:SetTextColor(0.55,0.55,0.55,1)
    suggest:SetText("Other useful future info: rested XP, durability, bags/free slots, hearth location, current strategy, follow target, and recent loot/needs.")

    local function LayoutLeftLines()
        local curY = -62
        for _, key in ipairs(lineOrder) do
            local fs, icon = lines[key], lineIcons[key]
            if fs and fs:GetText() and fs:GetText() ~= "" then
                if icon then icon:Show(); icon:ClearAllPoints(); icon:SetPoint("TOPLEFT", left, "TOPLEFT", 10, curY + 1) end
                fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", left, "TOPLEFT", 32, curY + 1)
                local h = fs.GetStringHeight and fs:GetStringHeight() or 14
                curY = curY - math.max(24, h + 8)
            else
                if icon then icon:Hide() end
            end
        end
        suggest:ClearAllPoints(); suggest:SetPoint("TOPLEFT", left, "TOPLEFT", 12, curY - 8)
    end

    PBAM.CreateSectionHeader(rightContent, "Current Quests", -10, 12)
    local questStatus = rightContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    questStatus:SetPoint("TOPLEFT", rightContent, "TOPLEFT", 12, -32); PBAM.WrapFontString(questStatus, RIGHT_CONTENT_W - 24); questStatus:SetTextColor(0.55,0.55,0.55,1)
    panel.StatusText = questStatus

    local function QuestRow(i)
        if questRows[i] then questRows[i]:Show(); return questRows[i] end
        local r = CreateFrame("Frame", nil, rightContent); r:SetHeight(20); 
        r:SetPoint("TOPLEFT", rightContent, "TOPLEFT", 10, -30 - (i-1)*20); 
        r:SetPoint("RIGHT", rightContent, "RIGHT", -10, 0); r:EnableMouse(true)
        r.icon = r:CreateTexture(nil, "OVERLAY"); 
        r.icon:SetSize(16,16); 
        r.icon:SetPoint("LEFT", r, "LEFT", 0, 0); r.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); 
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 0, 0); PBAM.WrapFontString(r.name, QUEST_TEXT_W)
        r.abandon = CreateFrame("Button", nil, r, "UIPanelButtonTemplate"); r.abandon:SetSize(24,20);
        r.abandon:SetPoint("RIGHT", r, "RIGHT", -36, 0); r.abandon:SetText("A")
        r.abandon:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Abandon quest", 1, 0.82, 0.22, true)
            GameTooltip:AddLine("Ask the selected bot to abandon this quest.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        r.abandon:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r.share = CreateFrame("Button", nil, r, "UIPanelButtonTemplate"); r.share:SetSize(24,20);
        r.share:SetPoint("RIGHT", r, "RIGHT", -12, 0); r.share:SetText("S")
        r.share:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Share quest", 1, 0.82, 0.22, true)
            GameTooltip:AddLine("Playerbot does not support bot-to-bot quest sharing.", 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Use /w <botname> q <questId> in chat to share with a bot.", 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end)
        r.share:SetScript("OnLeave", function() GameTooltip:Hide() end)
        questRows[i]=r; return r
    end

    local repHeader = PBAM.CreateSectionHeader(rightContent, "Reputation", repStartY, 12)

    local repBtn = CreateFrame("Button", nil, rightContent, "UIPanelButtonTemplate")
    repBtn:SetSize(190,22); repBtn:SetPoint("TOPLEFT", rightContent, "TOPLEFT", 12, -272); repBtn:SetText("Reputation list v")
    local repPanel = CreateFrame("Frame", nil, rightContent)
    repPanel:SetPoint("TOPLEFT", rightContent, "TOPLEFT", 14, -300)
    repPanel:SetPoint("RIGHT", rightContent, "RIGHT", -14, 0)
    PBAM.ApplyBackdrop(repPanel, 0.22)
    repPanel:Hide()
    local repStatus = rightContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    repStatus:SetPoint("LEFT", repBtn, "RIGHT", 8, 0); PBAM.WrapFontString(repStatus, 120); repStatus:SetTextColor(0.55,0.55,0.55,1)

    local function HideReps() for _, r in ipairs(repRows) do r:Hide() end end
    local function RefreshReps(botName, isPlayer)
        HideReps()
        local reps = isPlayer and LocalPlayerReputations() or (PBAM.Bridge.BotReputations and PBAM.Bridge.BotReputations[string.lower(botName or "")])
        local arr = {}
        for faction, rep in pairs((reps and reps.reputations) or {}) do table.insert(arr, { faction=faction, rep=rep }) end
        table.sort(arr, function(a,b) return tostring(a.faction) < tostring(b.faction) end)
        repStatus:SetText(#arr == 0 and "No reputation data" or (#arr .. " factions"))
        
        -- Position the header at repStartY (which is set by RefreshQuests)
        repHeader:ClearAllPoints()
        repHeader:SetPoint("TOPLEFT", rightContent, "TOPLEFT", 20, repStartY)
        
        -- Also move the gold line to match the header position.
        -- Section header textures are regions, not child frames, so the helper stores this reference.
        if repHeader.goldLine then
            repHeader.goldLine:ClearAllPoints()
            repHeader.goldLine:SetPoint("TOPLEFT", rightContent, "TOPLEFT", 20, repStartY - 14)
            repHeader.goldLine:SetPoint("TOPRIGHT", rightContent, "TOPRIGHT", -20, repStartY - 14)
        end
        
        repBtn:ClearAllPoints(); repBtn:SetPoint("TOPLEFT", rightContent, "TOPLEFT", 12, repStartY - 22)
        repStatus:ClearAllPoints(); repStatus:SetPoint("LEFT", repBtn, "RIGHT", 8, 0)
        repBtn:SetText(repsOpen and "Reputation list ^" or "Reputation list v")
        
        local contentBottom = repStartY - 54
        if not repsOpen then 
            repPanel:Hide()
            rightContent:SetHeight(math.max(520, -contentBottom))
            return 
        end
        repPanel:Show()
        repPanel:ClearAllPoints()
        repPanel:SetPoint("TOPLEFT", rightContent, "TOPLEFT", 14, repStartY - 48)
        repPanel:SetPoint("RIGHT", rightContent, "RIGHT", -14, 0)
        for i, e in ipairs(arr) do
            local r = repRows[i]
            if not r then
                r = CreateFrame("Frame", nil, repPanel)
                r:SetHeight(24)
                r.bg = r:CreateTexture(nil, "BACKGROUND")
                r.bg:SetAllPoints()
                r.bg:SetTexture(PBAM.textures.white)
                r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                r.text:SetPoint("LEFT", r, "LEFT", 8, 0)
                r.text:SetPoint("RIGHT", r, "RIGHT", -8, 0)
                r.text:SetJustifyH("LEFT")
                repRows[i] = r
            end
            r:Show(); r:ClearAllPoints(); r:SetPoint("TOPLEFT", repPanel, "TOPLEFT", 6, -6 - (i-1)*24); r:SetPoint("RIGHT", repPanel, "RIGHT", -6, 0)
            r.bg:SetVertexColor(0.10, 0.10, 0.12, i % 2 == 0 and 0.28 or 0.16)
            local standingName = PBAM.GetReputationStandingName(e.rep.standing)
            r.text:SetText(string.format("%s  |cffffd100%s|r  |cffaaaaaa%s/%s|r", tostring(e.faction), standingName, tostring(e.rep.value or 0), tostring(e.rep.max or 0)))
            contentBottom = repStartY - 56 - i*24
        end
        for i = #arr + 1, #repRows do if repRows[i] then repRows[i]:Hide() end end
        repPanel:SetHeight(math.max(34, 12 + #arr * 24))
        rightContent:SetHeight(math.max(520, -contentBottom))
    end

    repBtn:SetScript("OnClick", function()
        if not PBAM.SelectedBot then return end
        local isPlayer = PBAM.IsSelectedPlayer and PBAM.IsSelectedPlayer()
        repsOpen = not repsOpen; RefreshReps(PBAM.SelectedBot, isPlayer)
    end)

    local function RefreshQuests(botName, isPlayer)
        for _, r in ipairs(questRows) do r:Hide() end
        local quests
        if isPlayer then
            quests = LocalPlayerQuests()
        else
            local key = string.lower(botName or "")
            local data = PBAM.Bridge.Quests and PBAM.Bridge.Quests[key]
            -- Also try with normalized name as fallback
            if not data and PBAM.NormalizeName then
                local normKey = PBAM.NormalizeName(botName)
                data = PBAM.Bridge.Quests[normKey]
            end
            quests = data and data.quests or {}
        end
        questStatus:SetText(#quests == 0 and (isPlayer and "No local player quests found." or "No quest data yet. Refreshing from bridge if available...") or (#quests .. " quests"))
        local nextY = -58
        for i=1, #quests do
            local q = quests[i]; local r = QuestRow(i)
            r:ClearAllPoints(); r:SetPoint("TOPLEFT", rightContent, "TOPLEFT", 10, nextY); r:SetPoint("RIGHT", rightContent, "RIGHT", -10, 0)
            local questId = tonumber(q.questId) or 0
            local questTitle = LocalQuestName(questId, q.questName)
            local statusText = QuestStatusText(q.status)
            r.name:SetText(string.format("[%s] %s", statusText, QuestLink(questId, q.questName)))
            r:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                local usedHyperlink = false
                if questId > 0 and GameTooltip.SetHyperlink then
                    usedHyperlink = pcall(GameTooltip.SetHyperlink, GameTooltip, "quest:" .. tostring(questId) .. ":0")
                end
                if not usedHyperlink then GameTooltip:SetText(questTitle, 1, 0.82, 0.22, true) end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Quest ID: " .. tostring(questId > 0 and questId or "?"), 0.8,0.8,0.8)
                GameTooltip:AddLine("Status: " .. statusText, 0.8,0.8,0.8)
                if tostring(q.questName or "") == tostring(questId) then
                    GameTooltip:AddLine("Bridge sent quest ID only; using local quest log name if cached.", 0.55,0.55,0.55, true)
                end
                GameTooltip:Show()
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            PBAM.SetButtonEnabled(r.abandon, not isPlayer, "Quest actions are only available for bots.")
            PBAM.SetButtonEnabled(r.share, isPlayer, "Bot-to-bot quest sharing is not supported by playerbot.")
            local questId = tonumber(q.questId) or 0
            r.abandon:SetScript("OnClick", function()
                if not isPlayer then
                    local fullCommand = "drop " .. questId
                    DEFAULT_CHAT_FRAME:AddMessage("[PBAM] Abandon: bot=" .. tostring(botName) .. " cmd=" .. tostring(fullCommand))
                    if SendChatMessage then
                        SendChatMessage(fullCommand, "WHISPER", nil, botName)
                        -- Request bridge refresh first, then update UI after a short delay
                        After(0.5, function()
                            if PBAM.SelectedBot == botName and PBAM.Bridge.RequestQuests then
                                PBAM.Bridge.RequestQuests(botName)
                            end
                        end)
                        After(1.5, function()
                            if panel.OnRefresh and PBAM.SelectedBot == botName then panel.OnRefresh(botName) end
                        end)
                    end
                else
                    DEFAULT_CHAT_FRAME:AddMessage("[PBAM] Cannot abandon: player selected")
                end
            end)
            r.share:SetScript("OnClick", function()
                if not isPlayer then
                    -- Playerbot does not support bot-initiated quest sharing.
                    -- Only the master (player) can share quests with bots via /w bot q <id>
                    DEFAULT_CHAT_FRAME:AddMessage("[PBAM] Bot quest sharing not supported by playerbot. Use /w " .. botName .. " q " .. questId .. " from chat to share a quest with this bot.")
                else
                    -- For local player, use the normal quest share mechanism
                    if GetQuestLogLink then
                        local questLink = GetQuestLogLink(questId)
                        if questLink then
                            SendChatMessage("share " .. questLink, "SAY")
                        end
                    end
                end
            end)
            local rowH = math.max(20, (r.name.GetStringHeight and r.name:GetStringHeight() or 14) + 20)
            r:SetHeight(rowH)
            nextY = nextY - rowH
        end
        
        -- Ensure minimum space before Reputation section (at least 50px below quest status)
        repStartY = math.min(nextY - 22, -80)
        
        RefreshReps(botName, isPlayer)
    end

    PBAM.Bridge.RegisterCallback("QuestsUpdated", function(botName)
        if not botName or not PBAM.SelectedBot then return end
        local key = string.lower(tostring(botName))
        if key == string.lower(tostring(PBAM.SelectedBot)) then
            RefreshQuests(PBAM.SelectedBot, false)
        end
    end)
    PBAM.Bridge.RegisterCallback("BotReputationsUpdated", function(botName) if botName == PBAM.SelectedBot then RefreshReps(botName, false) end end)
    PBAM.Bridge.RegisterCallback("BotDetailUpdated", function(detail) if detail and detail.name == PBAM.SelectedBot and panel.OnBotSelect then panel.OnBotSelect(detail.name) end end)
    PBAM.Bridge.RegisterCallback("StateUpdated", function(botName) if botName == PBAM.SelectedBot and panel.OnBotSelect then panel.OnBotSelect(botName) end end)
    PBAM.Bridge.RegisterCallback("StatsUpdated", function(stats) if stats and stats.name == PBAM.SelectedBot and panel.OnBotSelect then panel.OnBotSelect(stats.name) end end)

    panel.OnRefresh = function(botName)
        if not botName then return end
        RequestSelectedAux(botName)
        if panel.OnBotSelect then panel.OnBotSelect(botName) end
    end

    panel.OnRosterUpdated = function() emptyFs:Show(); left:Hide(); right:Hide() end

    panel.OnBotSelect = function(botName)
        PBAM.SetButtonEnabled(repBtn, botName and botName ~= "", "Select a character to view reputation.")
        if not botName then emptyFs:Show(); left:Hide(); right:Hide(); return end
        emptyFs:Hide(); left:Show(); right:Show()
        RequestSelectedAux(botName)

        local key = string.lower(botName)
        local isPlayer = PBAM.NormalizeName(UnitName and UnitName("player") or nil) == key
        local detail = PBAM.Bridge.Details and PBAM.Bridge.Details[key]
        local state = (not isPlayer) and PBAM.Bridge.States and PBAM.Bridge.States[key] or nil
        local stats = (not isPlayer) and PBAM.Bridge.Stats and PBAM.Bridge.Stats[key] or nil
        local rosterEntry = PBAM.GetRosterEntry and PBAM.GetRosterEntry(botName) or nil
        local live = (isPlayer and { unit="player", hp=UnitHealth("player"), maxHp=UnitHealthMax("player"), hpPct=math.floor(((UnitHealth("player") or 0)/math.max(1, UnitHealthMax("player") or 1))*100+0.5), dead=UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") }) or (PBAM.GetLiveBotStatus and PBAM.GetLiveBotStatus(botName))
        local raceName = isPlayer and UnitRace and UnitRace("player") or (detail and detail.race)
        local genderName = detail and detail.gender or ""
        if isPlayer and UnitSex then local sex = UnitSex("player"); genderName = sex == 2 and "Male" or (sex == 3 and "Female" or "") end
        local className = (isPlayer and UnitClass and UnitClass("player")) or (detail and detail.className) or (rosterEntry and rosterEntry.className) or "Unknown"
        local classColor = PBAM.GetClassColor(className)
        local level = (isPlayer and UnitLevel and UnitLevel("player")) or (stats and stats.level) or (detail and detail.level) or (rosterEntry and rosterEntry.level) or 0
        local spec, role
        if isPlayer then spec, role = BestPlayerSpec() else spec, role = BestSpec(detail) end
        spec, role = spec or "N/A", role or "N/A"

        nameFs:SetText("|cff" .. (classColor or "ffffff") .. botName .. (isPlayer and " |cffd4af37(You)|r" or ""))
        lines.identity:SetText(string.format("%s %s %s", tostring(genderName or ""), tostring(raceName or ""), tostring(className or "Unknown")))
        lines.level:SetText("Level: " .. tostring(level))
        lines.spec:SetText(string.format("Spec: %s   Role: %s", spec, role))
        local avgItemLevel = isPlayer and GetAverageItemLevel and math.floor((GetAverageItemLevel() or 0) + 0.5) or nil
        lines.gear:SetText(string.format("iLvl: %s   GS/Score: %s", tostring(avgItemLevel or (detail and detail.itemLevel) or "N/A"), tostring((detail and detail.score and detail.score > 0) and detail.score or "N/A")))
        local alive = live and not live.dead or (state and state.normal ~= "dead")
        local inCombat = isPlayer and UnitAffectingCombat and (UnitAffectingCombat("player") and "Yes" or "No") or tostring(state and state.combat or "No")
        local casting = "No"
        if isPlayer and UnitCastingInfo then casting = UnitCastingInfo("player") or "No" else casting = tostring(state and state.casting or "No") end
        lines.status:SetText("Status: " .. (alive and "|cff40ff40Alive|r" or "|cffff4040Dead|r") .. "   Combat: " .. inCombat .. "   Casting: " .. casting)
        local hp, maxHp = (live and live.hp) or 0, (live and live.maxHp) or 0
        local hpPct = (live and live.hpPct) or (stats and stats.hpPct) or (rosterEntry and rosterEntry.hpPct)
        lines.hp:SetText(maxHp > 0 and string.format("HP: %d%% (%d / %d)", hpPct or 0, hp, maxHp) or ("HP: " .. tostring(hpPct or "Unknown") .. (hpPct and "%" or "")))
        local powerType = isPlayer and UnitPowerType and select(2, UnitPowerType("player")) or nil
        if POWERLESS[ClassKey(className)] or (powerType and powerType ~= "MANA") then lines.mana:SetText(""); if lineIcons.mana then lineIcons.mana:Hide() end
        else
            if lineIcons.mana then lineIcons.mana:Show() end
            local mp, maxMp = isPlayer and UnitMana and UnitMana("player") or 0, isPlayer and UnitManaMax and UnitManaMax("player") or 0
            local pct = maxMp > 0 and math.floor((mp / maxMp) * 100 + 0.5) or (stats and stats.manaPct)
            lines.mana:SetText(maxMp > 0 and string.format("Mana: %d%% (%d / %d)", pct or 0, mp, maxMp) or ("Mana: " .. tostring(pct or "Unknown") .. (pct and "%" or "")))
        end
        lines.money:SetText(MoneyText(isPlayer and { totalCopper = GetMoney and GetMoney() or 0 } or stats))
        lines.location:SetText("Location: " .. tostring((isPlayer and GetRealZoneText and GetRealZoneText()) or (state and state.zone) or (live and live.zone) or (rosterEntry and rosterEntry.mapId and ("Map " .. rosterEntry.mapId)) or "Unknown"))
        local targetName = isPlayer and UnitExists and UnitExists("target") and UnitName("target") or (live and live.unit and UnitExists and UnitExists(live.unit .. "target") and UnitName(live.unit .. "target") or nil)
        lines.target:SetText("Target: " .. tostring(targetName or (state and state.target) or "None"))
        LayoutLeftLines()

        RefreshQuests(botName, isPlayer)
    end
end)
