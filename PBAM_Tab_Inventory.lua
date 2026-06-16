-- ============================================================
--  PBAM_Tab_Inventory.lua  |  Inventory tab
-- ============================================================

PBAM = PBAM or {}

-- Empty-state message position when no bot is selected.
-- Adjust X to move left/right and Y to move up/down.
local EMPTY_MESSAGE_X_OFFSET = -185
local EMPTY_MESSAGE_Y_OFFSET = 0

local function MoneyText(copper)
    copper = tonumber(copper or 0) or 0
    return string.format("%dg %ds %dc", math.floor(copper / 10000), math.floor((copper % 10000) / 100), copper % 100)
end

local function ItemText(item)
    if type(item) == "table" then return item.text or "" end
    return tostring(item or "")
end

local function ItemId(item)
    return type(item) == "table" and tonumber(item.itemId or 0) or tonumber(tostring(item or ""):match("item:(%d+)")) or 0
end

local function ItemLink(item)
    local text = ItemText(item)
    -- MultiBot-Chatless sends a real client hyperlink from GetItemInfo(itemId).
    -- Prefer that over the bridge text so SendChatMessage transmits a normal item link.
    local id = ItemId(item)
    if id and id > 0 and GetItemInfo then
        local _, link = GetItemInfo(id)
        if link and link ~= "" then return link end
    end
    -- mod-playerbots parses item ids from "Hitem:" links, so preserve links exactly.
    if tostring(text or ""):match("|Hitem:") then return text end
    -- Fallback for plain "[Item Name]xN" snapshots: use the item name only.
    local cleanName = tostring(text or ""):match("%[(.-)%]")
    if cleanName then return cleanName end
    return text
end

local function ItemName(item)
    local link = ItemLink(item)
    local name = tostring(link or ""):match("%[(.-)%]")
    if name and name ~= "" then return name end
    local text = ItemText(item)
    if text ~= "" then return text end
    return "item"
end

local function ItemIcon(item)
    local id = ItemId(item)
    if id and id > 0 and GetItemIcon then return GetItemIcon(id) end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local afterFrame, afterJobs
local function After(delay, func)
    if C_Timer and C_Timer.After then return C_Timer.After(delay, func) end
    if PBAM and PBAM.After then return PBAM.After(delay, func) end
    if not afterFrame then
        afterJobs = {}
        afterFrame = CreateFrame("Frame")
        afterFrame:SetScript("OnUpdate", function(_, elapsed)
            for i = #afterJobs, 1, -1 do
                local job = afterJobs[i]
                job.t = job.t - elapsed
                if job.t <= 0 then table.remove(afterJobs, i); job.f() end
            end
        end)
    end
    table.insert(afterJobs, { t = tonumber(delay) or 0, f = func })
end

local function LogStatus(fs, msg, r, g, b)
    if fs then
        fs:SetText(tostring(msg or ""))
        fs:SetTextColor(r or 0.8, g or 0.8, b or 0.8, 1)
    end
    if msg and msg ~= "" and PBAM and PBAM.LogInfo then PBAM.LogInfo(msg) end
end

local function UnitShortName(unit)
    if not UnitName then return nil end
    local name = UnitName(unit)
    if type(name) == "string" then return name end
    return nil
end

local function GetEligibleTradeTargets()
    local seen, targets = {}, {}
    local function add(name, label)
        if not name or name == "" then return end
        local key = string.lower(name)
        if seen[key] then return end
        seen[key] = true
        table.insert(targets, { name = name, label = label or name })
    end

    add(UnitShortName("player"), "You")
    local raidCount = GetNumRaidMembers and GetNumRaidMembers() or 0
    if raidCount and raidCount > 0 then
        for i = 1, raidCount do add(UnitShortName("raid" .. i)) end
    else
        local partyCount = GetNumPartyMembers and GetNumPartyMembers() or 0
        for i = 1, partyCount do add(UnitShortName("party" .. i)) end
    end
    if PBAM.Bridge and PBAM.Bridge.Roster then
        for _, bot in ipairs(PBAM.Bridge.Roster) do
            local name = type(bot) == "table" and (bot.name or bot.Name) or bot
            add(name, name and (name .. " (bot)") or nil)
        end
    end
    return targets
end

-- Check if current target is a valid vendor NPC (like MultiBot-Chatless)
-- Player must have selected the target (not the bot), and it should be a vendor NPC
local function GetCurrentMerchantTargetName()
    -- Target must exist and not be a player (playerbots check UNIT_NPC_FLAG_VENDOR)
    if not UnitExists("target") then
        return nil
    end
    if UnitIsPlayer("target") then
        return nil
    end
    
    local name = UnitName("target")
    if not name or name == "" or name == "Unknown Entity" then
        return nil
    end
    
    return name
end

local function AddBackdrop(frame, alpha)
    if PBAM and PBAM.ApplyBackdrop then PBAM.ApplyBackdrop(frame, alpha); return end
    if frame and frame.SetBackdrop then
        frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        frame:SetBackdropColor(0.05, 0.05, 0.07, alpha or 0.8)
    end
end

PBAM.RegisterTab("Inventory", "Inventory", 3, function(panel)
    local MARGIN, ROW_H = 12, 30
    local rows, targetRows = {}, {}
    local showingBank = false
    local equipMode = false
    local destroyMode = false
    local tradeMode = false
    local sellMode = false
    local sellBatch = false
    local selectedTradeItem = nil
    local tradeTarget = nil
    local tradeInitiatedAt = 0  -- timestamp when InitiateTrade was called

    -- Forward declarations for callback helpers/UI objects. Lua local scope starts
    -- at the declaration, so callbacks defined before these helpers need this.
    local titleFs, slotsFs, goldFs, content
    local ClearRows, HideTargetMenu, Row, UpdateRowHighlights

    -- InventoryUpdated / BankUpdated: only update the UI, do NOT re-trigger OnBotSelect.
    -- Re-triggering creates a cascade (callback → OnBotSelect → RequestInventoryRefresh)
    -- that overlaps with the initial request cycle, causing token collisions and lost data.
    -- Render inventory rows from bridge data (used by callbacks and OnBotSelect).
    local function RenderInventoryRows(inv, bank)
        if not inv then return false end
        goldFs:SetText("Gold: " .. MoneyText(inv.goldCopper) .. (bank and bank.goldCopper and ("   Bank: " .. MoneyText(bank.goldCopper)) or ""))
        slotsFs:SetText(string.format("Bags: %d / %d", inv.bagUsed or 0, inv.bagTotal or 0))
        if not inv.items or #inv.items == 0 then
            local r = Row(1); r.item=nil; r.itemText=nil; r.icon:SetTexture("Interface\\Icons\\INV_Box_01"); r.text:SetText("No inventory items returned."); content:SetHeight(60); return false
        end
        for i, item in ipairs(inv.items) do local r = Row(i); r.item=item; r.itemText=ItemText(item); r.icon:SetTexture(ItemIcon(item)); r.text:SetText(ItemText(item)) end
        UpdateRowHighlights(); content:SetHeight(20 + #inv.items * ROW_H)
        return true
    end
    -- Render bank rows from bridge data.
    local function RenderBankRows(bank)
        if not bank then return false end
        if bank.error and bank.error ~= "" then
            local r = Row(1); r.item=nil; r.itemText=nil; r.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02"); r.text:SetText("Bank unavailable: " .. bank.error)
            content:SetHeight(60); return false
        end
        if not bank.items or #bank.items == 0 then
            local r = Row(1); r.item=nil; r.itemText=nil; r.icon:SetTexture("Interface\\Icons\\INV_Box_02"); r.text:SetText("Nothing in this bot's bank.")
            content:SetHeight(60); return false
        end
        for i, item in ipairs(bank.items) do local r = Row(i); r.item=item; r.itemText=ItemText(item); r.icon:SetTexture(ItemIcon(item)); r.text:SetText(ItemText(item)) end
        UpdateRowHighlights(); content:SetHeight(20 + #bank.items * ROW_H)
        return true
    end
    -- InventoryUpdated / BankUpdated: only update the UI, do NOT re-trigger OnBotSelect.
    -- Re-triggering creates a cascade (callback → OnBotSelect → RequestInventoryRefresh)
    -- that overlaps with the initial request cycle, causing token collisions and lost data.
    PBAM.Bridge.RegisterCallback("InventoryUpdated", function(botName)
        if botName ~= PBAM.SelectedBot or PBAM.CurrentTab ~= "Inventory" then return end
        local key = string.lower(botName)
        local inv = PBAM.Bridge.Inventory and PBAM.Bridge.Inventory[key]
        local bank = PBAM.Bridge.Bank and PBAM.Bridge.Bank[key]
        ClearRows(); HideTargetMenu()
        if showingBank then
            titleFs:SetText("Bank")
            goldFs:SetText("Bank Gold: " .. MoneyText(bank and bank.goldCopper or 0))
            slotsFs:SetText(bank and bank.error and ("Banker: " .. bank.error) or "Click bank items to request bridge withdraw")
            if not RenderBankRows(bank) then
                if not bank then
                    local r = Row(1); r.item=nil; r.itemText=nil; r.icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01"); r.text:SetText("Requesting bank data...")
                    content:SetHeight(60)
                end
            end
        else
            titleFs:SetText("Inventory")
            if not RenderInventoryRows(inv, bank) then
                if not inv then
                    goldFs:SetText("Gold: loading..."); slotsFs:SetText("")
                    local r = Row(1); r.item=nil; r.itemText=nil; r.icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01"); r.text:SetText("Requesting inventory...")
                end
                content:SetHeight(math.max(content:GetHeight(), 60))
            end
        end
    end)
    PBAM.Bridge.RegisterCallback("BankUpdated", function(botName)
        if botName ~= PBAM.SelectedBot or PBAM.CurrentTab ~= "Inventory" then return end
        local key = string.lower(botName)
        local bank = PBAM.Bridge.Bank and PBAM.Bridge.Bank[key]
        ClearRows(); HideTargetMenu()
        titleFs:SetText("Bank")
        goldFs:SetText("Bank Gold: " .. MoneyText(bank and bank.goldCopper or 0))
        slotsFs:SetText(bank and bank.error and ("Banker: " .. bank.error) or "Click bank items to request bridge withdraw")
        if not RenderBankRows(bank) then
            if not bank then
                local r = Row(1); r.item=nil; r.itemText=nil; r.icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01"); r.text:SetText("Requesting bank data...")
                content:SetHeight(60)
            end
        end
    end)
    PBAM.Bridge.RegisterCallback("InventoryItemActionResult", function(result)
        if not result or result.botName ~= PBAM.SelectedBot or PBAM.CurrentTab ~= "Inventory" then return end
        local ok = result.result == "OK"
        LogStatus(panel.StatusText, string.format("%s %s for item %s%s", tostring(result.action or "Item action"), ok and "completed" or "failed", tostring(result.itemId or "?"), ok and "" or (": " .. tostring(result.reason or "unknown"))), ok and 0.35 or 1, ok and 0.9 or 0.35, ok and 0.45 or 0.25)
        if ok and PBAM.SelectedBot then
            After(0.55, function() PBAM.Bridge.RequestInventory(PBAM.SelectedBot) end)
            if showingBank then After(0.70, function() PBAM.Bridge.RequestBank(PBAM.SelectedBot) end) end
        end
    end)

    local emptyFs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyFs:SetPoint("CENTER", panel, "CENTER", EMPTY_MESSAGE_X_OFFSET, EMPTY_MESSAGE_Y_OFFSET)
    emptyFs:SetText("Select a bot to view inventory")
    emptyFs:SetTextColor(0.55, 0.55, 0.55, 1)

    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", MARGIN, -MARGIN)
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -MARGIN, -MARGIN)
    header:SetHeight(100)
    AddBackdrop(header, 0.55)

    titleFs = PBAM.CreateSectionHeader(header, "Inventory", -10, 13)
    local controlsFrame = CreateFrame("Frame", nil, header)
    controlsFrame:SetPoint("TOPRIGHT", titleFs.goldLine or titleFs, "BOTTOMRIGHT", 0, -4)
    controlsFrame:SetSize(292, 34)
    AddBackdrop(controlsFrame, 0.22)

    slotsFs = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    slotsFs:SetPoint("TOPLEFT", titleFs, "BOTTOMLEFT", 4, -10)
    slotsFs:SetPoint("RIGHT", header, "RIGHT", -320, 0)
    PBAM.WrapFontString(slotsFs, 220)
    slotsFs:SetTextColor(0.7, 0.7, 0.7, 1)

    goldFs = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    goldFs:SetPoint("TOPLEFT", slotsFs, "BOTTOMLEFT", 0, -6)
    goldFs:SetPoint("RIGHT", header, "RIGHT", -320, 0)
    PBAM.WrapFontString(goldFs, 220)
    goldFs:SetTextColor(0.95, 0.80, 0.22, 1)

    local function Button(text, x)
        local b = CreateFrame("Button", nil, controlsFrame, "UIPanelButtonTemplate")
        b:SetSize(88, 24); b:SetPoint("RIGHT", controlsFrame, "RIGHT", x, 0); b:SetText(text); return b
    end
    local refreshBtn = Button("Refresh", -14)
    local bankBtn = Button("Bank", -108)
    local invBtn = Button("Inventory", -202)

    local body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -MARGIN, MARGIN)

    local actionPanel = CreateFrame("Frame", nil, body)
    actionPanel:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
    actionPanel:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
    actionPanel:SetWidth(360)
    AddBackdrop(actionPanel, 0.48)
    PBAM.CreateSectionHeader(actionPanel, "Actions", -10, 13)

    local scroll = CreateFrame("ScrollFrame", nil, body)
    scroll:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", actionPanel, "BOTTOMLEFT", -10, 0)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta) self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 28))) end)

    content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(390)
    scroll:SetScrollChild(content)
    AddBackdrop(content, 0.35)

    local function CheckButtonLeft(name, y)
        local b = CreateFrame("CheckButton", nil, actionPanel, "UICheckButtonTemplate")
        b:SetPoint("TOPLEFT", actionPanel, "TOPLEFT", 16, y)
        b:SetSize(26, 26)
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        b.label:SetPoint("LEFT", b, "RIGHT", 4, 0)
        b.label:SetText(name)
        return b
    end

    local function CheckButtonRight(name, y)
        local b = CreateFrame("CheckButton", nil, actionPanel, "UICheckButtonTemplate")
        b:SetPoint("TOPRIGHT", actionPanel, "TOPRIGHT", -128, y)
        b:SetSize(26, 26)
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        b.label:SetPoint("LEFT", b, "RIGHT", 4, 0)
        b.label:SetText(name)
        return b
    end

    local equipCheck = CheckButtonLeft("Equip Mode", -24)
    local destroyCheck = CheckButtonRight("Destroy Mode", -24)
    local tradeCheck = CheckButtonLeft("Trade Mode", -48)
    local sellCheck = CheckButtonLeft("Sell Mode", -72)
    local sellBatch = CheckButtonRight("Batch Mode", -72)

    local tradeTargetLabel = actionPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tradeTargetLabel:SetPoint("TOPLEFT", actionPanel, "TOPLEFT", 18, -124)
    tradeTargetLabel:SetText("Trade Target")

    local targetButton = CreateFrame("Button", nil, actionPanel, "UIPanelButtonTemplate")
    targetButton:SetSize(180, 24)
    targetButton:SetPoint("TOPLEFT", tradeTargetLabel, "BOTTOMLEFT", 0, -6)
    targetButton:SetText("Choose")

    local function SellButton(text, y)
        local b = CreateFrame("Button", nil, actionPanel, "UIPanelButtonTemplate")
        b:SetSize(120, 24); b:SetPoint("TOPLEFT", actionPanel, "TOPLEFT", 18, y)
        b:SetText(text)
        return b
    end
    local sellGreysBtn = SellButton("Sell Greys", -190)
    local sellVendorBtn = SellButton("Sell Vendorable", -224)

    local targetMenu = CreateFrame("Frame", nil, panel)
    targetMenu:SetFrameStrata("DIALOG")
    targetMenu:SetSize(200, 220)
    AddBackdrop(targetMenu, 0.96)
    targetMenu:Hide()

    local targetScroll = CreateFrame("ScrollFrame", nil, targetMenu)
    targetScroll:SetPoint("TOPLEFT", targetMenu, "TOPLEFT", 6, -6)
    targetScroll:SetPoint("BOTTOMRIGHT", targetMenu, "BOTTOMRIGHT", -6, 6)
    targetScroll:EnableMouseWheel(true)
    targetScroll:SetScript("OnMouseWheel", function(self, delta) self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 20))) end)
    local targetContent = CreateFrame("Frame", nil, targetScroll)
    targetContent:SetWidth(180)
    targetScroll:SetScrollChild(targetContent)

    local statusFs = actionPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusFs:SetPoint("TOPLEFT", actionPanel, "TOPLEFT", 18, -330)
    statusFs:SetPoint("RIGHT", actionPanel, "RIGHT", -18, 0)
    statusFs:SetJustifyH("LEFT")
    PBAM.WrapFontString(statusFs, 324)
    statusFs:SetTextColor(0.7, 0.7, 0.7, 1)
    statusFs:SetText("Sell Mode uses your current target like Trainer. Target a vendor NPC first.")
    panel.StatusText = statusFs

    local hintFs = actionPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hintFs:SetPoint("BOTTOMLEFT", actionPanel, "BOTTOMLEFT", 18, 18)
    hintFs:SetPoint("RIGHT", actionPanel, "RIGHT", -18, 0)
    hintFs:SetJustifyH("LEFT")
    PBAM.WrapFontString(hintFs, 324)
    hintFs:SetTextColor(0.55, 0.55, 0.55, 1)
    hintFs:SetText("Shift-left-click links items to chat. Bank items withdraw via bridge when possible.")

    local function UpdateActionButtons(botName)
        local hasBot = botName and botName ~= ""
        PBAM.SetButtonEnabled(refreshBtn, hasBot, "Select a bot to refresh inventory.")
        PBAM.SetButtonEnabled(bankBtn, hasBot, "Select a bot to view bank data.")
        PBAM.SetButtonEnabled(invBtn, hasBot, "Select a bot to view inventory.")
        PBAM.SetButtonEnabled(targetButton, hasBot and tradeMode, tradeMode and "No trade target is available right now." or "Enable Trade Mode to choose a trade target.")
        equipCheck:SetEnabled(hasBot)
        tradeCheck:SetEnabled(hasBot)
        sellCheck:SetEnabled(hasBot)
        sellBatch:SetEnabled(hasBot)
        destroyCheck:SetEnabled(hasBot)
    end

    local function SetTargetText()
        targetButton:SetText(tradeTarget or "Choose")
    end

    HideTargetMenu = function()
        targetMenu:Hide()
    end

    local function ShowTargetMenu()
        local targets = GetEligibleTradeTargets()
        if (not tradeTarget or tradeTarget == "") and targets[1] then tradeTarget = targets[1].name end
        SetTargetText()
        for _, r in ipairs(targetRows) do r:Hide() end

        local rowH = 22
        local menuH = math.min(220, math.max(32, (#targets * rowH) + 12))
        targetMenu:SetHeight(menuH)
        targetContent:SetHeight(math.max(menuH - 12, #targets * rowH))

        for i, target in ipairs(targets) do
            local r = targetRows[i]
            if not r then
                r = CreateFrame("Button", nil, targetContent)
                r:SetHeight(rowH)
                r:SetPoint("LEFT", targetContent, "LEFT", 0, 0)
                r:SetPoint("RIGHT", targetContent, "RIGHT", 0, 0)
                r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
                r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.text:SetPoint("LEFT", r, "LEFT", 6, 0); r.text:SetPoint("RIGHT", r, "RIGHT", -6, 0); r.text:SetJustifyH("LEFT")
                r:SetScript("OnClick", function(self)
                    tradeTarget = self.value
                    SetTargetText()
                    HideTargetMenu()
                    LogStatus(statusFs, "Trade target set to " .. tostring(tradeTarget), 0.75, 0.75, 0.75)
                end)
                targetRows[i] = r
            end
            r:SetPoint("TOPLEFT", targetContent, "TOPLEFT", 0, -(i - 1) * rowH)
            r.value = target.name
            r.text:SetText(target.label or target.name)
            r.bg:SetVertexColor(0.12, 0.12, 0.14, target.name == tradeTarget and 0.75 or (i % 2 == 0 and 0.38 or 0.20))
            r:Show()
        end

        targetMenu:ClearAllPoints()
        local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
        local bottom = targetButton.GetBottom and targetButton:GetBottom() or 0
        local top = targetButton.GetTop and targetButton:GetTop() or 0
        if bottom and (bottom * scale) > (menuH + 20) then
            targetMenu:SetPoint("TOPLEFT", targetButton, "BOTTOMLEFT", 0, -2)
        else
            targetMenu:SetPoint("BOTTOMLEFT", targetButton, "TOPLEFT", 0, 2)
        end
        targetMenu:Show()
    end

    targetButton:SetScript("OnClick", function()
        if not PBAM.SelectedBot or not tradeMode then return end
        if targetMenu:IsShown() then HideTargetMenu() else ShowTargetMenu() end
    end)

    local function RefreshTargetDropdown()
        local targets = GetEligibleTradeTargets()
        if (not tradeTarget or tradeTarget == "") and targets[1] then tradeTarget = targets[1].name end
        SetTargetText()
        if targetMenu:IsShown() then ShowTargetMenu() end
    end

    local function SendLegacyInventoryCommand(command, botName, item, suffix)
        if not botName or botName == "" or not command or command == "" then return false end
        local link = item and ItemLink(item) or ""
        if item and (not link or link == "") then return false end
        local msg = item and (command .. " " .. link) or command
        if suffix and suffix ~= "" then msg = msg .. " " .. tostring(suffix) end
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("[PBAM] Sending: /w " .. botName .. " " .. string.sub(msg, 1, 100))
        end
        SendChatMessage(msg, "WHISPER", nil, botName)
        return true
    end

    -- Debounce: prevent rapid overlapping refresh cycles (e.g. callback → OnBotSelect → this).
    local lastRefreshTime = 0
    local function RequestInventoryRefresh()
        local now = GetTime() or 0
        if PBAM.SelectedBot and (now - lastRefreshTime) < 3 then return end
        lastRefreshTime = now
        if not PBAM.SelectedBot then return end
        local key = string.lower(PBAM.SelectedBot)
        local inv = PBAM.Bridge.Inventory and PBAM.Bridge.Inventory[key]
        if inv and inv.loading then return end
        After(1.50, function()
            local currentKey = PBAM.SelectedBot and string.lower(PBAM.SelectedBot)
            local currentInv = currentKey and PBAM.Bridge.Inventory and PBAM.Bridge.Inventory[currentKey]
            if PBAM.SelectedBot and not (currentInv and currentInv.loading) then PBAM.Bridge.RequestInventory(PBAM.SelectedBot) end
        end)
        After(2.25, function()
            local currentKey = PBAM.SelectedBot and string.lower(PBAM.SelectedBot)
            local currentInv = currentKey and PBAM.Bridge.Inventory and PBAM.Bridge.Inventory[currentKey]
            if PBAM.SelectedBot and not (currentInv and currentInv.loading) then PBAM.Bridge.RequestInventory(PBAM.SelectedBot) end
        end)
    end

    local function RequestEquipmentRefresh()
        if not PBAM.SelectedBot or not PBAM.RefreshEquipmentTab then return end
        After(0.75, function() if PBAM.SelectedBot and PBAM.RefreshEquipmentTab then PBAM.RefreshEquipmentTab(PBAM.SelectedBot, true) end end)
        After(1.75, function() if PBAM.SelectedBot and PBAM.RefreshEquipmentTab then PBAM.RefreshEquipmentTab(PBAM.SelectedBot, true) end end)
    end

    UpdateRowHighlights = function()
        local selectedText = selectedTradeItem and ItemText(selectedTradeItem) or nil
        for i, r in ipairs(rows) do
            if r.bg then
                local selected = selectedText and r.itemText == selectedText
                if selected then r.bg:SetVertexColor(0.95, 0.72, 0.18, 0.36) else r.bg:SetVertexColor(0.10,0.10,0.12, i % 2 == 0 and 0.32 or 0.18) end
            end
        end
    end

    local function HandleItemClick(row, button)
        local item = row and row.item
        if not item then return end
        HideTargetMenu()

        if IsShiftKeyDown and IsShiftKeyDown() and button == "LeftButton" then
            local link = ItemLink(item)
            if ChatEdit_InsertLink and link and link ~= "" and ChatEdit_InsertLink(link) then return end
            LogStatus(statusFs, "Item link: " .. tostring(link or ItemName(item)), 0.75, 0.75, 0.75)
            return
        end

        if not PBAM.SelectedBot then return end
        if showingBank then
            local id = ItemId(item)
            if id > 0 and PBAM.Bridge.RunInventoryItemAction then
                PBAM.Bridge.RunInventoryItemAction(PBAM.SelectedBot, "BANK_WITHDRAW", id, 1)
                LogStatus(statusFs, "Requesting bank withdrawal for " .. ItemName(item) .. " via bridge...", 0.95, 0.8, 0.25)
            else
                LogStatus(statusFs, "Cannot withdraw this bank item: no item id in bridge snapshot.", 1, 0.35, 0.25)
            end
            return
        end

        if equipMode then
            local hint = button == "LeftButton" and "main/normal" or "offhand/standard"
            -- Playerbot command: "e <itemlink>" triggers EquipAction
            if SendLegacyInventoryCommand("e", PBAM.SelectedBot, item) then
                LogStatus(statusFs, "Equip command sent (" .. hint .. ") for " .. ItemName(item) .. ". Bot will equip if item is valid.", 0.35, 0.9, 0.45)
                RequestInventoryRefresh()
                RequestEquipmentRefresh()
            else
                LogStatus(statusFs, "Could not equip: item link/name unavailable.", 1, 0.35, 0.25)
            end
            return
        end

        if tradeMode then
            selectedTradeItem = item
            UpdateRowHighlights()
            -- Playerbot needs time to establish the trade relationship after InitiateTrade.
            local now = GetTime and GetTime() or 0
            local elapsed = now - tradeInitiatedAt
            -- Wait for bot AI to process SMSG_TRADE_STATUS and be ready to receive items
            if elapsed < 1.0 then
                LogStatus(statusFs, "Please wait... Bot accepting trade. Try again in " .. string.format("%.1f", 2.5 - elapsed) .. "s.", 0.95, 0.8, 0.25)
                return
            end
            -- Use mod-playerbots' real trade trigger directly.
            -- "give <itemLink>" works only because item-link auto-trade parsing falls through to "t";
            -- sending "t <itemLink> 1" avoids the extra auto path and limits insertion to one trade slot/stack.
            local name = ItemName(item)
            if SendLegacyInventoryCommand("t", PBAM.SelectedBot, item, "1") then
                LogStatus(statusFs, "Sent trade command for " .. name .. " to " .. PBAM.SelectedBot .. ".", 0.35, 0.9, 0.45)
                -- Auto-refresh after successful trade (within 5s total)
                After(1.50, function() PBAM.Bridge.RequestInventory(PBAM.SelectedBot) end)
                After(2.25, function() PBAM.Bridge.RequestInventory(PBAM.SelectedBot) end)
            else
                LogStatus(statusFs, "Selected " .. name .. " for trade. Could not send command.", 0.95, 0.8, 0.25)
            end
            return
        end

        if sellMode then
            local link = ItemLink(item)
            local name = ItemName(item)
            if not link or link == "" then
                LogStatus(statusFs, "Cannot sell: item link unavailable.", 1, 0.35, 0.25)
                return
            end
            local currentTarget = GetCurrentMerchantTargetName()
            if not currentTarget or currentTarget == "" then
                LogStatus(statusFs, "Select a vendor first!", 1, 0.35, 0.25)
                return
            end
            -- Send 's <itemLink>' command to sell the item
            if DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("[PBAM] Sending: /w " .. PBAM.SelectedBot .. " s " .. string.sub(link, 1, 100))
            end
            SendChatMessage("s " .. link, "WHISPER", nil, PBAM.SelectedBot)
            LogStatus(statusFs, "Sent sell command for " .. name .. (sellBatch:GetChecked() and " (batch mode: whole stack)" or "") .. ". Refreshing in 1.25s...", 0.35, 0.9, 0.45)
            After(1.25, function() PBAM.Bridge.RequestInventory(PBAM.SelectedBot) end)
            return
        end

        if destroyCheck then
            local link = ItemLink(item)
            local name = ItemName(item)
            if not link or link == "" then
                LogStatus(statusFs, "Cannot destroy: item link unavailable.", 1, 0.35, 0.25)
                return
            end
            
            -- Send 'destroy <itemLink>' command to destroy the item
            if DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("[PBAM] Sending: /w " .. PBAM.SelectedBot .. " destroy " .. string.sub(link, 1, 100))
            end
            SendChatMessage("destroy " .. link, "WHISPER", nil, PBAM.SelectedBot)
            LogStatus(statusFs, "Sent destroy command for " .. name .. ". Refreshing in 1.25s...", 0.35, 0.9, 0.45)
            After(1.25, function() PBAM.Bridge.RequestInventory(PBAM.SelectedBot) end)
            return
        end

        LogStatus(statusFs, "No action mode enabled. Enable Equip Mode, Trade Mode, Destroy Mode, or Sell Mode first.", 0.95, 0.8, 0.25)
    end

    ClearRows = function()
        for _, r in ipairs(rows) do r:Hide() end
    end

    Row = function(i)
        if rows[i] then rows[i]:Show(); return rows[i] end
        local r = CreateFrame("Frame", nil, content)
        r:SetHeight(ROW_H); r:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -8 - (i - 1) * ROW_H); r:SetPoint("RIGHT", content, "RIGHT", -8, 0)
        local bg = r:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetTexture("Interface\\Buttons\\WHITE8x8"); bg:SetVertexColor(0.10,0.10,0.12, i % 2 == 0 and 0.32 or 0.18)
        r.bg = bg
        r:EnableMouse(true)
        r.icon = r:CreateTexture(nil, "OVERLAY"); r.icon:SetSize(22,22); r.icon:SetPoint("LEFT", r, "LEFT", 6, 0)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0); r.text:SetPoint("RIGHT", r, "RIGHT", -8, 0); r.text:SetJustifyH("LEFT")
        r:SetScript("OnMouseUp", HandleItemClick)
        r:SetScript("OnEnter", function(self)
            if not self.itemText or self.itemText == "" then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local link = ItemLink(self.item or self.itemText)
            if link and tostring(link):match("|Hitem:") then GameTooltip:SetHyperlink(link) else GameTooltip:AddLine(self.itemText, 1, 1, 1) end
            if equipMode then GameTooltip:AddLine("Equip Mode: left=normal/main hand, right=offhand/standard (playerbot 'e' command)", 0.35, 0.9, 0.45, true) end
            if tradeMode then GameTooltip:AddLine("Trade Mode: click to insert item into open trade ('t' + 'give' commands)", 0.95, 0.8, 0.25, true) end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[i] = r; return r
    end

    equipCheck:SetScript("OnClick", function(self)
        equipMode = self:GetChecked() and true or false
        if equipMode then
            destroyCheck:SetChecked(false)
            sellCheck:SetChecked(false)
            sellBatch:SetChecked(false)
            tradeMode = false; tradeCheck:SetChecked(false); HideTargetMenu()
            if CancelTrade then CancelTrade() end
            LogStatus(statusFs, "Equip Mode enabled. Left-click normal/main hand; right-click offhand/standard legacy equip.", 0.35, 0.9, 0.45)
        else
            LogStatus(statusFs, "Equip Mode disabled.", 0.75, 0.75, 0.75)
        end
        UpdateActionButtons(PBAM.SelectedBot)
    end)

    tradeCheck:SetScript("OnClick", function(self)
        tradeMode = self:GetChecked() and true or false
        if tradeMode then
            destroyCheck:SetChecked(false)
            sellCheck:SetChecked(false)
            sellBatch:SetChecked(false)
            equipMode = false; equipCheck:SetChecked(false); RefreshTargetDropdown()
            tradeInitiatedAt = GetTime and GetTime() or 0
            if PBAM.SelectedBot then
                -- Match MultiBot-Chatless: open the trade from the client, then insert only clicked items.
                if InitiateTrade then InitiateTrade(PBAM.SelectedBot) end
            end
            LogStatus(statusFs, "Trade Mode enabled for " .. tostring(PBAM.SelectedBot or "selected bot") .. ". Wait ~1s before inserting items.", 0.35, 0.9, 0.45)
        else
            selectedTradeItem = nil; UpdateRowHighlights(); HideTargetMenu()
            tradeInitiatedAt = 0
            if CancelTrade then CancelTrade() end
            LogStatus(statusFs, "Trade Mode disabled and trade canceled.", 0.75, 0.75, 0.75)
        end
        UpdateActionButtons(PBAM.SelectedBot)
    end)

    sellCheck:SetScript("OnClick", function(self)
        sellMode = self:GetChecked() and true or false
        if sellMode then
            equipCheck:SetChecked(false)
            tradeCheck:SetChecked(false)
            destroyCheck:SetChecked(false)

            LogStatus(statusFs, "Sell Mode enabled. Target a vendor NPC first.", 0.35, 0.9, 0.45)
        else
            LogStatus(statusFs, "Sell Mode disabled.", 0.75, 0.75, 0.75)
        end
        UpdateActionButtons(PBAM.SelectedBot)
    end)

    sellGreysBtn:SetScript("OnClick", function()
        if not PBAM.SelectedBot or not sellMode then return end
        local currentTarget = GetCurrentMerchantTargetName()
        if not currentTarget or currentTarget == "" then
            LogStatus(statusFs, "Select a vendor first!", 1, 0.35, 0.25)
            return
        end
        -- Send 's *' command to sell all grey items
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("[PBAM] Sending: /w " .. PBAM.SelectedBot .. " s *")
        end
        SendChatMessage("s *", "WHISPER", nil, PBAM.SelectedBot)
        After(1.25, function() PBAM.Bridge.RequestInventory(PBAM.SelectedBot) end)
    end)

    sellVendorBtn:SetScript("OnClick", function()
        if not PBAM.SelectedBot or not sellMode then return end
        local currentTarget = GetCurrentMerchantTargetName()
        if not currentTarget or currentTarget == "" then
            LogStatus(statusFs, "Select a vendor first!", 1, 0.35, 0.25)
            return
        end
        -- Send 's vendor' command to sell all vendorable items
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("[PBAM] Sending: /w " .. PBAM.SelectedBot .. " s vendor")
        end
        SendChatMessage("s vendor", "WHISPER", nil, PBAM.SelectedBot)
        After(1.25, function() PBAM.Bridge.RequestInventory(PBAM.SelectedBot) end)
    end)

    sellBatch:SetScript("OnClick", function(self)
        if self:GetChecked() and not sellMode then
            self:SetChecked(false)
            LogStatus(statusFs, "Batch Mode requires Sell Mode to be enabled.", 1, 0.7, 0.25)
        elseif self:GetChecked() then
            LogStatus(statusFs, "Batch Mode enabled. Currently sells whole stack on item click (same as single mode).", 0.95, 0.8, 0.25)
        else
            LogStatus(statusFs, "Batch Mode disabled.", 0.75, 0.75, 0.75)
        end
    end)

    destroyCheck:SetScript("OnClick", function(self)
        if self:GetChecked() then
            -- Disable all other mode checkboxes when Destroy Mode is enabled
            equipCheck:SetChecked(false)
            tradeCheck:SetChecked(false)
            sellCheck:SetChecked(false)
            sellBatch:SetChecked(false)
            LogStatus(statusFs, "Destroy Mode enabled. Use with caution.", 0.95, 0.8, 0.25)
        else
            LogStatus(statusFs, "Destroy Mode disabled.", 0.75, 0.75, 0.75)
        end
    end)

    refreshBtn:SetScript("OnClick", function()
        if PBAM.SelectedBot then
            showingBank = false
            PBAM.Bridge.Inventory[string.lower(PBAM.SelectedBot)] = nil
            PBAM.Bridge.RequestInventory(PBAM.SelectedBot)
            panel.OnBotSelect(PBAM.SelectedBot)
        end
    end)
    bankBtn:SetScript("OnClick", function()
        if PBAM.SelectedBot then
            showingBank = true
            PBAM.Bridge.Bank[string.lower(PBAM.SelectedBot)] = nil
            PBAM.Bridge.RequestBank(PBAM.SelectedBot)
            panel.OnBotSelect(PBAM.SelectedBot)
        end
    end)
    invBtn:SetScript("OnClick", function()
        if PBAM.SelectedBot then showingBank = false; panel.OnBotSelect(PBAM.SelectedBot) end
    end)

    panel.OnRefresh = function(botName)
        if not botName then return end
        if showingBank then
            PBAM.Bridge.Bank[string.lower(botName)] = nil
            PBAM.Bridge.RequestBank(botName)
        else
            PBAM.Bridge.Inventory[string.lower(botName)] = nil
            PBAM.Bridge.RequestInventory(botName)
        end
        panel.OnBotSelect(botName)
    end

    panel.OnBotSelect = function(botName)
        ClearRows()
        HideTargetMenu()
        UpdateActionButtons(botName)
        if not botName then emptyFs:Show(); header:Hide(); body:Hide(); return end
        emptyFs:Hide(); header:Show(); body:Show()
        local key = string.lower(botName)
        local inv = PBAM.Bridge.Inventory and PBAM.Bridge.Inventory[key]
        local bank = PBAM.Bridge.Bank and PBAM.Bridge.Bank[key]
        if showingBank then
            titleFs:SetText("Bank")
            goldFs:SetText("Bank Gold: " .. MoneyText(bank and bank.goldCopper or 0))
            slotsFs:SetText(bank and bank.error and ("Banker: " .. bank.error) or "Click bank items to request bridge withdraw")
            if not bank then
                local r = Row(1); r.item=nil; r.itemText=nil; r.icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01"); r.text:SetText("Requesting bank data... Stand near and interact with a banker if this fails.")
                content:SetHeight(60); return
            end
            if bank.error and bank.error ~= "" then
                local r = Row(1); r.item=nil; r.itemText=nil; r.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02"); r.text:SetText("Bank unavailable: " .. bank.error .. " — stand near/interact with a banker and try again.")
                content:SetHeight(60); return
            end
            if not bank.items or #bank.items == 0 then
                local r = Row(1); r.item=nil; r.itemText=nil; r.icon:SetTexture("Interface\\Icons\\INV_Box_02"); r.text:SetText("Nothing in this bot's bank, or the bridge returned an empty bank snapshot.")
                content:SetHeight(60); return
            end
            for i, item in ipairs(bank.items) do local r = Row(i); r.item=item; r.itemText=ItemText(item); r.icon:SetTexture(ItemIcon(item)); r.text:SetText(ItemText(item)) end
            UpdateRowHighlights(); content:SetHeight(20 + #bank.items * ROW_H); return
        end

        titleFs:SetText("Inventory")
        if not inv then
            PBAM.Bridge.Inventory[key] = { name = botName, items = {}, goldCopper = 0, bagUsed = 0, bagTotal = 0, loading = true }
            PBAM.Bridge.RequestInventory(botName)
            local r = Row(1); r.item=nil; r.itemText=nil; r.icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01"); r.text:SetText("Requesting inventory...")
            goldFs:SetText("Gold: loading..."); slotsFs:SetText(""); content:SetHeight(60); return
        end
        if inv.loading then
            local r = Row(1); r.item=nil; r.itemText=nil; r.icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01"); r.text:SetText("Requesting inventory...")
            goldFs:SetText("Gold: loading..."); slotsFs:SetText(""); content:SetHeight(60); return
        end
        goldFs:SetText("Gold: " .. MoneyText(inv.goldCopper) .. (bank and bank.goldCopper and ("   Bank: " .. MoneyText(bank.goldCopper)) or ""))
        slotsFs:SetText(string.format("Bags: %d / %d", inv.bagUsed or 0, inv.bagTotal or 0))
        if not inv.items or #inv.items == 0 then
            local r = Row(1); r.item=nil; r.itemText=nil; r.icon:SetTexture("Interface\\Icons\\INV_Box_01"); r.text:SetText("No inventory items returned."); content:SetHeight(60); return
        end
        for i, item in ipairs(inv.items) do local r = Row(i); r.item=item; r.itemText=ItemText(item); r.icon:SetTexture(ItemIcon(item)); r.text:SetText(ItemText(item)) end
        UpdateRowHighlights(); content:SetHeight(20 + #inv.items * ROW_H)
    end
end, { hideForPlayer = true })
