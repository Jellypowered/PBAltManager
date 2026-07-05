-- ============================================================
--  PBAM_Tab_Trainer.lua  |  Trainer tab
-- ============================================================

PBAM = PBAM or {}

local function Money(c) c=tonumber(c or 0) or 0; return c>0 and string.format("%dg %ds %dc", math.floor(c/10000), math.floor((c%10000)/100), c%100) or "Free" end
local function LearnReason(reason)
    reason = tostring(reason or "")
    local map = {
        OK="Learned.", NO_BOT="Bot is unavailable.", NO_TRAINER="No trainer selected.", NO_TRAINER_TARGET="No trainer selected.",
        INVALID_TRAINER="That trainer is not valid for this bot.", NO_SPELL="Invalid trainer spell.", TOO_EXPENSIVE="Bot cannot afford this training.",
        NO_MATCHING_SPELL="That spell is no longer trainable from this trainer.", WRONG_TRAINER="Selected trainer changed; refresh trainer data.",
    }
    return map[reason] or (reason ~= "" and reason or "Unknown trainer result.")
end

local TRAINER_PROFESSION_ALIASES = {
    alchemy = { "master alchemy trainer", "alchemy trianer", "alchemist", "journeyman alchemist", "expert alchemist", "artisan alchemist" },
    blacksmithing = { "blacksmithing", "blacksmith", "armorsmith", "weaponsmith" },
    enchanting = { "enchanting", "enchanter" },
    engineering = { "engineering", "engineer" },
    herbalism = { "herbalism", "herbalist" },
    inscription = { "inscription", "inscriber", "scribe" },
    jewelcrafting = { "jewelcrafting", "jewelcrafter", "gem cutting", "gemcutting" },
    leatherworking = { "leatherworking", "leatherworker" },
    mining = { "mining", "miner" },
    skinning = { "skinning", "skinner" },
    tailoring = { "tailoring", "tailor" },
    cooking = { "cooking trainer", "cooking trainer & supplies", "grand master cooking trainer", "superior cook", "cook",
                "barmaid", "chef", "baker" },
    fishing = { "fishing trainer", "grand master fishing trainer", "fishing trianer & supplies", "grand master fishing trianer & supplies" },
    firstaid = { "first aid trainer", "physician", "grand master first aid trainer" },
}

local function NormalizeProfessionKey(value)
    return string.lower(tostring(value or "")):gsub("[_%s%-]+", "")
end

local function DetectTrainerProfessionFromText(text)
    text = string.lower(tostring(text or ""))
    if text == "" then return nil end
    for professionKey, aliases in pairs(TRAINER_PROFESSION_ALIASES) do
        for _, alias in ipairs(aliases) do
            if text:find(string.lower(alias), 1, true) then return professionKey end
        end
    end
    return nil
end

local function GetOpenTrainerProfessionKey()
    if not GetNumTrainerServices or not GetTrainerServiceInfo then return nil end
    local count = tonumber(GetNumTrainerServices()) or 0
    for i = 1, count do
        local serviceName = GetTrainerServiceInfo(i)
        local detected = DetectTrainerProfessionFromText(serviceName)
        if detected then return detected end
    end
    return nil
end

local function GetTrainerProfessionKey(trainer)
    local detected = trainer and DetectTrainerProfessionFromText(trainer.trainerName) or nil
    if detected then return detected end
    for _, spell in ipairs((trainer and trainer.spells) or {}) do
        detected = DetectTrainerProfessionFromText(spell and spell.name)
        if detected then return detected end
    end
    detected = GetOpenTrainerProfessionKey()
    if detected then return detected end
    return nil
end

local function BotHasProfession(botName, professionKey)
    local key = string.lower(tostring(botName or ""))
    local wanted = NormalizeProfessionKey(professionKey)
    if key == "" or wanted == "" then return false end

    local skills = PBAM.Bridge and PBAM.Bridge.Professions and PBAM.Bridge.Professions[key] or nil
    for _, bucket in ipairs({ skills and skills.primary, skills and skills.secondary, skills and skills.other }) do
        for _, entry in ipairs(bucket or {}) do
            if NormalizeProfessionKey(entry.key or entry.displayName or entry.name) == wanted then return true end
        end
    end

    local crafting = PBAM.Bridge and PBAM.Bridge.Crafting and PBAM.Bridge.Crafting[key] or nil
    if crafting and crafting.professions then
        for name in pairs(crafting.professions) do
            if NormalizeProfessionKey(name) == wanted then return true end
        end
    end

    return false
end

local function TrainerSpellIcon(spellId, spellName)
    if GetSpellTexture and tonumber(spellId) and tonumber(spellId) > 0 then
        local tex = GetSpellTexture(tonumber(spellId))
        if tex and tex ~= "" then return tex end
    end
    local name = string.lower(tostring(spellName or ""))
    local byName = {
        alchemy="Interface\\Icons\\Trade_Alchemy", blacksmithing="Interface\\Icons\\Trade_BlackSmithing", enchanting="Interface\\Icons\\Trade_Engraving",
        engineering="Interface\\Icons\\Trade_Engineering", herbalism="Interface\\Icons\\Trade_Herbalism", inscription="Interface\\Icons\\INV_Inscription_Tradeskill01",
        jewelcrafting="Interface\\Icons\\INV_Misc_Gem_01", leatherworking="Interface\\Icons\\INV_Misc_ArmorKit_17", mining="Interface\\Icons\\Trade_Mining",
        skinning="Interface\\Icons\\INV_Misc_Pelt_Wolf_01", tailoring="Interface\\Icons\\Trade_Tailoring", cooking="Interface\\Icons\\INV_Misc_Food_15",
        fishing="Interface\\Icons\\Trade_Fishing", firstaid="Interface\\Icons\\Spell_Holy_SealOfSacrifice", ["first aid"]="Interface\\Icons\\Spell_Holy_SealOfSacrifice",
    }
    for key, tex in pairs(byName) do if name:find(key, 1, true) then return tex end end
    return "Interface\\Icons\\INV_Misc_Book_09"
end

PBAM.RegisterTab("Trainer", "Trainer", 6, function(panel)
    local MARGIN, ROW_H = 12, 72
    local rows = {}
    local statusFs
    
    -- Batch mode state
    local batchModeEnabled = false
    local professionFilterEnabled = false
    local pendingBatchScanAfterSkillLoad = false
    local trainerDataByBot = {}  -- { [botName] = trainerData }
    local batchEligibleBots = {}
    local isBatchTraining = false
    local batchScanExpected = 0
    local batchScanCompleted = 0
    local batchScanPending = {}
    local batchScanQueue = {}
    local batchScanPendingSince = {}
    local BATCH_SCAN_REQUEST_TTL = 5.0
    local BATCH_SCAN_MAX_INFLIGHT = 4
    
    -- Forward declare helpers/locals used by callbacks
    local UpdateTrainAllButtonState
    local StartBatchScan
    local RenderBatchSummary
    local LogStatus
    local Row
    local content
    local KickBatchScanQueue
    
    PBAM.Bridge.RegisterCallback("TrainerUpdated", function(botName)
        -- Guard: botName must be a valid string
        if not botName or botName == "" then return end
        
        if batchModeEnabled then
            local key = string.lower(botName)
            local trainer = PBAM.Bridge.Trainer and PBAM.Bridge.Trainer[key]
            if trainer then trainerDataByBot[botName] = trainer end
            batchScanPendingSince[key] = nil
            if batchScanPending[botName] then
                batchScanPending[botName] = nil
                batchScanCompleted = batchScanCompleted + 1
                if batchScanExpected > 0 then
                    LogStatus(string.format("Scanning trainer data... %d/%d", batchScanCompleted, batchScanExpected), 0.95, 0.8, 0.25)
                    local r = Row(1)
                    r.name:SetText("Scanning trainer data for roster...")
                    r.cost:SetText(string.format("%d/%d complete", batchScanCompleted, batchScanExpected))
                    r.btn:Hide()
                    content:SetHeight(60)
                end
                if batchScanCompleted >= batchScanExpected and RenderBatchSummary then RenderBatchSummary() end
                if KickBatchScanQueue then KickBatchScanQueue() end
            end
            if UpdateTrainAllButtonState then UpdateTrainAllButtonState() end
        end
        
        -- Existing single-bot logic
        if not batchModeEnabled and PBAM.SelectedBot and botName == PBAM.SelectedBot and PBAM.CurrentTab == "Trainer" and panel.OnBotSelect then
            panel.OnBotSelect(botName)
        end
    end)
    
    PBAM.Bridge.RegisterCallback("TrainerLearnResult", function(result)
        if result and result.botName == PBAM.SelectedBot and PBAM.CurrentTab == "Trainer" then
            local ok = result.result == "OK"
            local msg = LearnReason(ok and "OK" or result.reason)
            if ok then msg = msg .. " " .. tostring(result.learnedCount or 0) .. " spell(s), " .. Money(result.spent or 0) .. "." end
            statusFs:SetText((ok and "|cff40ff40" or "|cffff6060") .. msg .. "|r")
            PBAM.Bridge.Trainer[string.lower(result.botName)] = nil
            PBAM.Bridge.RequestTrainer(result.botName)
        end
    end)

    PBAM.Bridge.RegisterCallback("BotSkillsBulkUpdated", function()
        if pendingBatchScanAfterSkillLoad and batchModeEnabled and professionFilterEnabled and PBAM.CurrentTab == "Trainer" and StartBatchScan then
            pendingBatchScanAfterSkillLoad = false
            StartBatchScan()
        end
    end)

    local emptyFs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyFs:SetPoint("CENTER", panel, "CENTER"); emptyFs:SetText("Select a bot to view trainer spells"); emptyFs:SetTextColor(0.55,0.55,0.55,1)
    
    -- After() helper for delayed execution (token-aware rate limiting)
    local function After(delay, func)
        return PBAM.After(delay, func)
    end
    
    LogStatus = function(msg, r, g, b)
        if statusFs then
            statusFs:SetText(tostring(msg or ""))
            statusFs:SetTextColor(r or 0.8, g or 0.8, b or 0.8, 1)
        end
    end

    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", MARGIN, -MARGIN); header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -MARGIN, -MARGIN); header:SetHeight(90)
    PBAM.ApplyBackdrop(header, 0.55); PBAM.CreateSectionHeader(header, "Trainer", -10, 13)
    statusFs = header:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); statusFs:SetPoint("TOPLEFT", header, "TOPLEFT", 18, -34); statusFs:SetPoint("RIGHT", header, "RIGHT", -290, 0); statusFs:SetJustifyH("LEFT"); statusFs:SetTextColor(0.7,0.7,0.7,1)
    -- Refresh button (rightmost)
    local refreshBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    refreshBtn:SetSize(88, 22)
    refreshBtn:SetPoint("RIGHT", header, "RIGHT", -18, -2)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Refresh Trainer Data", 1, 0.82, 0.22, true)
        GameTooltip:AddLine(batchModeEnabled and "Scan trainer data for all roster bots." or "Request fresh trainer data for the selected bot.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    refreshBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    -- Train All button (leftmost of the button group)
    local trainAllBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    trainAllBtn:SetSize(88, 22)
    trainAllBtn:SetPoint("RIGHT", header, "RIGHT", -18, -26) --button is 22 high so 4px gap
    trainAllBtn:SetText("Train All")
    trainAllBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Train All Spells", 1, 0.82, 0.22, true)
        GameTooltip:AddLine(batchModeEnabled and "Train all trainable spells for all roster bots." or "Teach the selected bot all trainable spells.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Requires sufficient gold for training costs.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    trainAllBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    -- Batch Mode checkbox
    local batchCheckbox = CreateFrame("CheckButton", nil, header, "UICheckButtonTemplate")
    batchCheckbox:SetSize(24, 24)
    batchCheckbox:SetPoint("RIGHT", trainAllBtn, "RIGHT", -96, 0)
    batchCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Batch Mode", 1, 0.82, 0.22, true)
        GameTooltip:AddLine("Enable batch operations for all roster bots.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("When enabled, Refresh scans all bots and Train All trains everyone.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    batchCheckbox:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    -- Batch Mode label
    local batchLabel = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    batchLabel:SetPoint("RIGHT", batchCheckbox, "RIGHT", -28, 0)
    batchLabel:SetText("Batch Mode")
    batchLabel:SetTextColor(0.9, 0.9, 0.9, 1)

    local professionFilterCheckbox = CreateFrame("CheckButton", nil, header, "UICheckButtonTemplate")
    professionFilterCheckbox:SetSize(24, 24)
    professionFilterCheckbox:SetPoint("RIGHT", batchLabel, "LEFT", -120, 0)
    professionFilterCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Profession Owners Only", 1, 0.82, 0.22, true)
        GameTooltip:AddLine("In batch mode, only scan/train bots that already have this trainer's profession.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Requires cached profession data for the roster.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    professionFilterCheckbox:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local professionFilterLabel = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    professionFilterLabel:SetPoint("RIGHT", professionFilterCheckbox, "RIGHT", -28, 0)
    professionFilterLabel:SetText("Profession Only")
    professionFilterLabel:SetTextColor(0.9, 0.9, 0.9, 1)

    local function UpdateProfessionFilterCheckboxState()
        local enabled = batchModeEnabled and true or false
        professionFilterCheckbox:SetEnabled(enabled)
        if not enabled then
            professionFilterCheckbox:SetChecked(false)
            professionFilterEnabled = false
            professionFilterLabel:SetTextColor(0.45, 0.45, 0.45, 1)
        else
            professionFilterCheckbox:SetChecked(professionFilterEnabled and true or false)
            professionFilterLabel:SetTextColor(0.9, 0.9, 0.9, 1)
        end
    end
    UpdateProfessionFilterCheckboxState()

    panel.StatusText = statusFs

    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8); scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -MARGIN, MARGIN)
    scroll:EnableMouseWheel(true); scroll:SetScript("OnMouseWheel", function(self, delta) self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 28))) end)
    content = CreateFrame("Frame", nil, scroll); content:SetWidth(660); scroll:SetScrollChild(content); PBAM.ApplyBackdrop(content, 0.35)

    local function ClearRows() for _,r in ipairs(rows) do r:Hide() end end
    
    RenderBatchSummary = function()
        ClearRows()
        emptyFs:Hide(); header:Show(); scroll:Show()
        local rosterCount, botsWithSpells, errorCount = 0, 0, 0
        local spellMap, orderedSpells = {}, {}
        for _, botName in ipairs(batchEligibleBots or {}) do
            if botName and botName ~= "" then
                rosterCount = rosterCount + 1
                local trainer = trainerDataByBot[botName]
                if not trainer or trainer.error then
                    errorCount = errorCount + 1
                elseif trainer.spells then
                    local botHasSpells = false
                    for _, spell in ipairs(trainer.spells) do
                        if spell then
                            local spellKey = tonumber(spell.spellId) or tostring(spell.name or "")
                            local entry = spellMap[spellKey]
                            if not entry then
                                entry = {
                                    spellId = tonumber(spell.spellId) or 0,
                                    name = spell.name or ("Spell #" .. tostring(spell.spellId)),
                                    trainerEntry = spell.trainerEntry or trainer.trainerEntry or 0,
                                    bots = {},
                                }
                                spellMap[spellKey] = entry
                                table.insert(orderedSpells, entry)
                            end
                            table.insert(entry.bots, botName)
                            botHasSpells = true
                        end
                    end
                    if botHasSpells then botsWithSpells = botsWithSpells + 1 end
                end
            end
        end
        table.sort(orderedSpells, function(a, b) return tostring(a.name) < tostring(b.name) end)
        for i, entry in ipairs(orderedSpells) do
            table.sort(entry.bots)
            local r = Row(i)
            r.btn:Hide()
            r.icon:SetTexture(TrainerSpellIcon(entry.spellId, entry.name))
            r.name:SetText(entry.name)
            r.cost:SetText("Can be learned by: " .. table.concat(entry.bots, ", "))
            r.cost:SetTextColor(0.85, 0.82, 0.72, 1)
        end
        content:SetHeight(math.max(60, 20 + math.max(1, #orderedSpells) * ROW_H))
        if rosterCount == 0 then
            local r = Row(1); r.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09"); r.name:SetText("No bots in roster."); r.cost:SetText(""); r.btn:Hide(); content:SetHeight(60)
            LogStatus("No bots in roster. Add bots to your party or raid first.", 1, 0.6, 0.4)
        elseif #orderedSpells > 0 then
            LogStatus(string.format("Batch scan complete: %d spell(s) learnable across %d bot(s).", #orderedSpells, botsWithSpells), 0.6, 1, 0.6)
        elseif errorCount == rosterCount then
            local r = Row(1); r.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09"); r.name:SetText("No trainer data available."); r.cost:SetText("Select a trainer target and refresh."); r.btn:Hide(); content:SetHeight(60)
            LogStatus("Batch scan complete: no trainer data available. Select a trainer target and refresh.", 1, 0.6, 0.4)
        else
            local r = Row(1); r.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09"); r.name:SetText("Nothing new to learn."); r.cost:SetText("No trainer spells found for the current roster."); r.btn:Hide(); content:SetHeight(60)
            LogStatus(string.format("Batch scan complete: %d bot(s) scanned, nothing new to learn.", rosterCount), 0.75, 0.9, 0.75)
        end
        if UpdateTrainAllButtonState then UpdateTrainAllButtonState() end
    end
    Row = function(i)
        if rows[i] then rows[i]:Show(); return rows[i] end
        local r=CreateFrame("Frame", nil, content); r:SetHeight(ROW_H); r:SetPoint("TOPLEFT", content,"TOPLEFT",8,-8-(i-1)*ROW_H); r:SetPoint("RIGHT", content,"RIGHT",-8,0)
        r.icon=r:CreateTexture(nil,"OVERLAY"); r.icon:SetSize(26,26); r.icon:SetPoint("LEFT",r,"LEFT",6,12); r.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
        r.name=r:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); r.name:SetPoint("TOPLEFT",r.icon,"TOPRIGHT",8,3); r.name:SetPoint("RIGHT",r,"RIGHT",-76,0); r.name:SetJustifyH("LEFT")
        r.cost=r:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); r.cost:SetPoint("TOPLEFT",r.name,"BOTTOMLEFT",0,-6); r.cost:SetPoint("RIGHT",r,"RIGHT",-76,0); r.cost:SetJustifyH("LEFT"); PBAM.WrapFontString(r.cost, 500)
        r.btn=CreateFrame("Button", nil, r, "UIPanelButtonTemplate"); r.btn:SetSize(62,22); r.btn:SetPoint("RIGHT",r,"RIGHT",-4,0); r.btn:SetText("Learn")
        rows[i]=r; return r
    end
    panel.OnRefresh = function(botName)
        if not botName then return end
        PBAM.Bridge.Trainer[string.lower(botName)] = nil
        PBAM.Bridge.RequestTrainer(botName)
        if panel.OnBotSelect then panel.OnBotSelect(botName) end
    end
    
    KickBatchScanQueue = function()
        if not batchModeEnabled or not PBAM.RunThrottledFanout then return end
        PBAM.RunThrottledFanout(batchScanQueue, batchScanPending, batchScanPendingSince, PBAM.Bridge.RequestTrainer, {
            ttl = BATCH_SCAN_REQUEST_TTL,
            maxInflight = BATCH_SCAN_MAX_INFLIGHT,
            onBeforeRequest = function(name, key)
                PBAM.Bridge.Trainer[key] = nil
            end,
            onTimeout = function()
                if batchModeEnabled and KickBatchScanQueue then KickBatchScanQueue() end
            end,
        })
    end

    StartBatchScan = function()
        local roster = PBAM.Bridge.Roster or {}
        local existingTrainerDataByBot = trainerDataByBot
        trainerDataByBot = {}
        batchEligibleBots = {}
        batchScanExpected = 0
        batchScanCompleted = 0
        batchScanPending = {}
        batchScanQueue = {}
        batchScanPendingSince = {}

        local trainerProfessionKey = nil
        if professionFilterEnabled then
            local selectedKey = PBAM.SelectedBot and string.lower(PBAM.SelectedBot) or nil
            local selectedTrainer = selectedKey and PBAM.Bridge.Trainer and PBAM.Bridge.Trainer[selectedKey] or nil
            trainerProfessionKey = GetTrainerProfessionKey(selectedTrainer)
            if not trainerProfessionKey then
                local anyTrainer = next(existingTrainerDataByBot or {})
                trainerProfessionKey = anyTrainer and GetTrainerProfessionKey(existingTrainerDataByBot[anyTrainer]) or nil
            end
            if not trainerProfessionKey then
                local r = Row(1)
                r.name:SetText("Refresh the selected bot's trainer first.")
                r.cost:SetText("PBAM needs a known trainer profession before Profession Only batch mode can filter the roster.")
                r.btn:Hide()
                content:SetHeight(68)
                LogStatus("Profession-only batch mode needs a detected trainer profession first.", 1, 0.6, 0.4)
                return
            end

            local missingProfessionData = {}
            for _, bot in ipairs(roster) do
                if bot and bot.name and bot.name ~= "" then
                    local key = string.lower(bot.name)
                    local hasSkills = PBAM.Bridge and PBAM.Bridge.Professions and PBAM.Bridge.Professions[key]
                    local hasCrafting = PBAM.Bridge and PBAM.Bridge.Crafting and PBAM.Bridge.Crafting[key]
                    if not hasSkills and not hasCrafting then table.insert(missingProfessionData, bot.name) end
                end
            end
            if #missingProfessionData > 0 then
                if PBAM.Bridge and PBAM.Bridge.RequestBotSkillsBulk then
                    pendingBatchScanAfterSkillLoad = true
                    PBAM.Bridge.RequestBotSkillsBulk()
                    local r = Row(1)
                    r.name:SetText("Loading roster profession data...")
                    r.cost:SetText("Please wait while PBAM fetches BOT_SKILLS for profession filtering.")
                    r.btn:Hide()
                    content:SetHeight(60)
                    LogStatus("Loading profession data for profession-only batch scan...", 0.95, 0.8, 0.25)
                    return
                end
            end
        end
        
        for _, bot in ipairs(roster) do
            if bot and bot.name and bot.name ~= "" then
                local name = bot.name
                if (not trainerProfessionKey) or BotHasProfession(name, trainerProfessionKey) then
                    batchScanExpected = batchScanExpected + 1
                    batchScanPending[name] = true
                    table.insert(batchScanQueue, name)
                    table.insert(batchEligibleBots, name)
                end
            end
        end
        
        if batchScanExpected == 0 then
            RenderBatchSummary()
            return
        end
        
        ClearRows()
        emptyFs:Hide(); header:Show(); scroll:Show()
        local r = Row(1)
        r.name:SetText("Scanning trainer data for roster...")
        r.cost:SetText(string.format("0/%d complete", batchScanExpected))
        r.btn:Hide()
        content:SetHeight(60)
        LogStatus(string.format("Scanning trainer data... 0/%d", batchScanExpected), 0.95, 0.8, 0.25)
        if UpdateTrainAllButtonState then UpdateTrainAllButtonState() end
        KickBatchScanQueue()
    end
    
    -- Update button state when bot is selected
    local originalOnBotSelect = function(botName)
        ClearRows()
        PBAM.SetButtonEnabled(refreshBtn, batchModeEnabled or (botName and botName ~= ""), batchModeEnabled and "Refresh trainer data for the whole roster." or "Select a bot to refresh trainer data.")
        PBAM.SetButtonEnabled(trainAllBtn, false, batchModeEnabled and "Scan trainer data first." or "Select a bot first")
        if not botName then
            if batchModeEnabled then
                emptyFs:Hide(); header:Show(); scroll:Show()
                if next(trainerDataByBot) then RenderBatchSummary() else
                    local r = Row(1); r.name:SetText("Enable Batch Mode to scan all roster bots."); r.cost:SetText("Select a trainer target first if needed, then Refresh."); r.btn:Hide(); content:SetHeight(60)
                end
                return
            end
            emptyFs:Show(); header:Hide(); scroll:Hide(); return
        end
        emptyFs:Hide(); header:Show(); scroll:Show()
        local key=string.lower(botName); local trainer=PBAM.Bridge.Trainer and PBAM.Bridge.Trainer[key]
        if not trainer then
            PBAM.Bridge.RequestTrainer(botName)
            statusFs:SetText("Requesting trainer data...")
            local r=Row(1); r.name:SetText("Select a trainer NPC in-game if this stays empty."); r.cost:SetText(""); r.btn:Hide(); content:SetHeight(60); return
        end
        statusFs:SetText((trainer.trainerName and trainer.trainerName ~= "" and trainer.trainerName or "Trainer") .. "  #" .. tostring(trainer.trainerEntry or 0))
        if trainer.error then
            local message = "Trainer error: " .. tostring(trainer.error)
            if tostring(trainer.error) == "NO_TRAINER_TARGET" then
                message = "Select " .. tostring(botName) .. "'s Trainer and Refresh"
            end
            local r=Row(1); r.name:SetText(message); r.cost:SetText(""); r.btn:Hide(); content:SetHeight(68); return
        end
        if not trainer.spells or #trainer.spells == 0 then
            local r=Row(1); r.name:SetText("No trainable spells available."); r.cost:SetText(""); r.btn:Hide(); content:SetHeight(60); return
        end
        table.sort(trainer.spells, function(a,b) return tostring(a.name) < tostring(b.name) end)
        for i,spell in ipairs(trainer.spells) do
            local r=Row(i); r.name:SetText(spell.name or ("Spell #"..tostring(spell.spellId))); r.cost:SetText(Money(spell.cost) .. (spell.canAfford and "" or "  |cffff6060(not enough money)|r")); r.cost:SetTextColor(spell.canAfford and 0.95 or 0.85, spell.canAfford and 0.80 or 0.20, 0.22, 1)
            r.btn:Show(); PBAM.SetButtonEnabled(r.btn, spell.canAfford, "This bot cannot afford this training right now."); r.btn:SetScript("OnClick", function() statusFs:SetText("Learning " .. tostring(spell.name or spell.spellId) .. "..."); PBAM.Bridge.LearnTrainerSpell(botName, spell.trainerEntry or trainer.trainerEntry, spell.spellId) end)
        end
        content:SetHeight(20 + #trainer.spells*ROW_H)
        
        -- Update Train All button state after rendering
        UpdateTrainAllButtonState()
    end
    panel.OnBotSelect = originalOnBotSelect

    -- Helper to update Train All button state
    UpdateTrainAllButtonState = function()
        if batchModeEnabled then
            -- Check if any cached bot has trainable spells
            local hasTrainable = false
            for _, trainerData in pairs(trainerDataByBot) do
                if trainerData and trainerData.spells and #trainerData.spells > 0 then
                    hasTrainable = true
                    break
                end
            end
            PBAM.SetButtonEnabled(trainAllBtn, hasTrainable and not isBatchTraining,
                isBatchTraining and "Batch training in progress..." or "No trainer spells found")
        else
            -- Single mode: check current bot
            local trainer = PBAM.SelectedBot and PBAM.Bridge.Trainer and PBAM.Bridge.Trainer[string.lower(PBAM.SelectedBot)]
            local hasSpells = trainer and trainer.spells and #trainer.spells > 0
            PBAM.SetButtonEnabled(trainAllBtn, hasSpells, PBAM.SelectedBot and "No trainable spells available" or "Select a bot first")
        end
    end
    
    professionFilterCheckbox:SetScript("OnClick", function(self)
        if not batchModeEnabled then
            self:SetChecked(false)
            professionFilterEnabled = false
            return
        end
        professionFilterEnabled = not not self:GetChecked()
        if batchModeEnabled then StartBatchScan() end
        UpdateTrainAllButtonState()
    end)

    -- Batch Mode checkbox handler
    batchCheckbox:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        batchModeEnabled = checked
        
        if checked then
            UpdateProfessionFilterCheckboxState()
            StartBatchScan()
        else
            -- Disable batch mode
            batchModeEnabled = false
            trainerDataByBot = {}
            batchEligibleBots = {}
            batchScanQueue = {}
            batchScanPending = {}
            batchScanPendingSince = {}
            pendingBatchScanAfterSkillLoad = false
            professionFilterEnabled = false
            LogStatus("Batch mode disabled.", 0.75, 0.75, 0.75)
        end
        
        UpdateProfessionFilterCheckboxState()
        UpdateTrainAllButtonState()
    end)
    
    -- Train All button handler
    trainAllBtn:SetScript("OnClick", function()
        if batchModeEnabled then
            -- Batch mode: train all bots with rate limiting
            if isBatchTraining then return end  -- Prevent spam
            
            -- Collect eligible bots
            local botsToTrain = {}
            for botName, trainerData in pairs(trainerDataByBot) do
                if trainerData and trainerData.spells and #trainerData.spells > 0 then
                    table.insert(botsToTrain, { name = botName, trainerEntry = trainerData.trainerEntry })
                end
            end
            
            if #botsToTrain == 0 then
                LogStatus("No bots have trainable spells in cache.", 1, 0.6, 0.4)
                return
            end
            
            -- Start batch training with countdown
            isBatchTraining = true
            local totalBots = #botsToTrain
            local totalTime = totalBots * 1.5
            local remainingTime = totalTime
            local trainedCount = 0
            
            -- Update status with countdown
            local function UpdateCountdown()
                statusFs:SetText(string.format("|cff40ff40Batch training: %d/%d bots, ~%.1fs remaining|r",
                    trainedCount, totalBots, math.max(0, remainingTime)))
            end
            
            -- Initial countdown display
            UpdateCountdown()
            
            -- Schedule countdown updates (every 0.5s)
            local countdownUpdate
            countdownUpdate = function()
                if not isBatchTraining then return end
                remainingTime = remainingTime - 0.5
                if remainingTime > 0 then
                    UpdateCountdown()
                    After(0.5, countdownUpdate)
                end
            end
            After(0.5, countdownUpdate)
            
            -- Queue train commands with 1.5s spacing
            for i, bot in ipairs(botsToTrain) do
                local delay = (i - 1) * 1.5
                After(delay, function()
                    if not isBatchTraining then return end
                    PBAM.Bridge.TrainAllSpells(bot.name, bot.trainerEntry)
                    trainedCount = trainedCount + 1
                    UpdateCountdown()
                    LogStatus(string.format("Training %s... (%d/%d)", bot.name, trainedCount, totalBots), 0.75, 1, 0.75)
                    
                    -- Last bot: cleanup after delay
                    if i == totalBots then
                        After(1.5, function()
                            isBatchTraining = false
                            batchCheckbox:SetChecked(false)
                            batchModeEnabled = false
                            statusFs:SetText("|cff40ff40Batch training complete!|r")
                            LogStatus(string.format("Batch training complete. Trained %d bot(s).", totalBots), 0.6, 1, 0.6)
                            UpdateTrainAllButtonState()
                        end)
                    end
                end)
            end
            
        else
            -- Single mode: train current bot only
            local trainer = PBAM.Bridge.Trainer and PBAM.Bridge.Trainer[string.lower(PBAM.SelectedBot)]
            if not trainer or not trainer.spells or #trainer.spells == 0 then
                LogStatus("No trainable spells available for " .. (PBAM.SelectedBot or "selected bot"), 1, 0.6, 0.4)
                return
            end
            
            statusFs:SetText("|cff40ff40Learning all spells for " .. PBAM.SelectedBot .. "...|r")
            PBAM.Bridge.TrainAllSpells(PBAM.SelectedBot, trainer.trainerEntry)
        end
    end)
    
    -- Refresh button handler (batch-aware)
    refreshBtn:SetScript("OnClick", function()
        -- If in batch mode, refresh all bots' trainer data
        if batchModeEnabled then
            StartBatchScan()
        elseif PBAM.SelectedBot then
            -- Single mode: refresh current bot only
            panel.OnRefresh(PBAM.SelectedBot)
        end
    end)
end, { hideForPlayer = true })
