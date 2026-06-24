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

local function IsEquippableBagItem(item)
    local id = ItemId(item)
    if id and id > 0 and GetItemInfo then
        local _, _, _, _, _, itemType, itemSubType, _, itemEquipLoc = GetItemInfo(id)
        itemType = tostring(itemType or ""):lower()
        itemSubType = tostring(itemSubType or ""):lower()
        itemEquipLoc = tostring(itemEquipLoc or "")
        if itemEquipLoc == "INVTYPE_BAG" or itemEquipLoc == "INVTYPE_QUIVER" then return true end
        if itemType == "container" or itemSubType:find("quiver", 1, true) or itemSubType:find("ammo", 1, true) then return true end
    end
    local name = string.lower(ItemName(item) or "")
    return name:find("quiver", 1, true) or name:find("ammo pouch", 1, true) or name:find("shot pouch", 1, true)
end

local function After(delay, func)
    return PBAM.After(delay, func)
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
    local buyMode = false
    local equipMode = false
    local destroyMode = false
    local tradeMode = false
    local sellMode = false
    local sellBatch = false
    local selectedTradeItem = nil
    local tradeTarget = nil
    local tradeInitiatedAt = 0  -- timestamp when InitiateTrade was called
    local lastTabOpenInventoryRequest = 0


    -- Forward declarations for callback helpers/UI objects. Lua local scope starts
    -- at the declaration, so callbacks defined before these helpers need this.
    local titleFs, slotsFs, goldFs, content
    local ClearRows, HideTargetMenu, Row, UpdateRowHighlights
    local RenderMerchantRows
    local RefreshMerchantView

    -- InventoryUpdated / BankUpdated: only update the UI, do NOT re-trigger OnBotSelect.
    -- Re-triggering creates a cascade (callback → OnBotSelect → RequestInventoryRefresh)
    -- that overlaps with the initial request cycle, causing token collisions and lost data.
    -- Render inventory rows from bridge data (used by callbacks and OnBotSelect).
    local function RenderInventoryRows(inv, bank)
        if not inv then return false end
        goldFs:SetText("Gold: " .. MoneyText(inv.goldCopper) .. (bank and bank.goldCopper and ("   Bank: " .. MoneyText(bank.goldCopper)) or ""))
        slotsFs:SetText(string.format("Bags: %d / %d", inv.bagUsed or 0, inv.bagTotal or 0))
        if not inv.items or #inv.items == 0 then
            local r = Row(1); r.item=nil; r.itemText=nil; r.merchantItem=nil; r.icon:SetTexture("Interface\\Icons\\INV_Box_01"); r.text:SetText("No inventory items returned."); content:SetHeight(60); return false
        end
        for i, item in ipairs(inv.items) do local r = Row(i); r.item=item; r.itemText=ItemText(item); r.merchantItem=nil; r.icon:SetTexture(ItemIcon(item)); r.text:SetText(ItemText(item)) end
        UpdateRowHighlights(); content:SetHeight(20 + #inv.items * ROW_H)
        return true
    end
    local function BuildMerchantItems()
        local items = {}
        local count = GetMerchantNumItems and GetMerchantNumItems() or 0
        for i = 1, count do
            local name, texture, price, quantity, numAvailable, isUsable, extendedCost = GetMerchantItemInfo(i)
            local link = GetMerchantItemLink and GetMerchantItemLink(i) or nil
            local itemId = link and tonumber(tostring(link):match("item:(%d+)")) or 0
            local _, _, quality, level, minLevel, itemType, subType, stackCount, equipLoc = GetItemInfo(itemId)
            table.insert(items, {
                index = i, itemId = itemId, name = name or ("Merchant Item #" .. tostring(i)), icon = texture,
                price = tonumber(price) or 0, quantity = tonumber(quantity) or 1, available = tonumber(numAvailable) or -1,
                usable = isUsable, extendedCost = extendedCost, link = link, level = tonumber(level) or 0,
                minLevel = tonumber(minLevel) or 0, itemType = itemType, subType = subType, stackCount = tonumber(stackCount) or tonumber(quantity) or 1,
                equipLoc = equipLoc,
            })
        end
        return items
    end

    local function IsMerchantOpen()
        return (MerchantFrame and MerchantFrame:IsShown()) or ((GetMerchantNumItems and GetMerchantNumItems() or 0) > 0)
    end

    local function BuyReason(reason)
        local map = {
            OK = "Purchase completed.", INVALID_ITEM = "That vendor item is not valid.", NOT_VENDOR = "No vendor is selected.",
            TOO_EXPENSIVE = "Bot cannot afford that purchase.", OUT_OF_STOCK = "That item is sold out.",
            EXTENDED_COST = "That item needs alternate currency or tokens.",
        }
        reason = tostring(reason or "")
        return map[reason] or (reason ~= "" and reason or "Purchase failed.")
    end

    -- Render bank rows from bridge data.
    local function RenderBankRows(bank)
        if not bank then return false end
        if bank.error and bank.error ~= "" then
            local r = Row(1); r.item=nil; r.itemText=nil; r.merchantItem=nil; r.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02"); r.text:SetText("Bank unavailable: " .. bank.error)
            content:SetHeight(60); return false
        end
        if not bank.items or #bank.items == 0 then
            local r = Row(1); r.item=nil; r.itemText=nil; r.merchantItem=nil; r.icon:SetTexture("Interface\\Icons\\INV_Box_02"); r.text:SetText("Nothing in this bot's bank.")
            content:SetHeight(60); return false
        end
        for i, item in ipairs(bank.items) do local r = Row(i); r.item=item; r.itemText=ItemText(item); r.merchantItem=nil; r.icon:SetTexture(ItemIcon(item)); r.text:SetText(ItemText(item)) end
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
        if not result or PBAM.CurrentTab ~= "Inventory" then return end
        if result.action == "BUY_ITEM" then
            local ok = result.result == "OK"
            LogStatus(panel.StatusText, (ok and BuyReason("OK") or BuyReason(result.reason)) .. " [" .. tostring(result.botName or "bot") .. "]", ok and 0.35 or 1, ok and 0.9 or 0.35, ok and 0.45 or 0.25)
            if buyMode and RefreshMerchantView then After(0.20, RefreshMerchantView) end
            if result.botName and result.botName == PBAM.SelectedBot and not buyMode then
                After(0.55, function() PBAM.Bridge.RequestInventory(result.botName) end)
            end
            return
        end
        if result.botName ~= PBAM.SelectedBot then return end
        local ok = result.result == "OK"
        LogStatus(panel.StatusText, string.format("%s %s for item %s%s", tostring(result.action or "Item action"), ok and "completed" or "failed", tostring(result.itemId or "?"), ok and "" or (": " .. tostring(result.reason or "unknown"))), ok and 0.35 or 1, ok and 0.9 or 0.35, ok and 0.45 or 0.25)
        if ok and PBAM.SelectedBot then
            After(0.55, function() PBAM.Bridge.RequestInventory(PBAM.SelectedBot) end)
            if showingBank then After(0.70, function() PBAM.Bridge.RequestBank(PBAM.SelectedBot) end) end
        end
    end)
    PBAM.Bridge.RegisterCallback("NativeActionResult", function(result)
        if not result or PBAM.CurrentTab ~= "Inventory" then return end
        if result.type ~= "ITEM_EQUIP" and result.type ~= "ITEM_TRADE" then return end
        if result.botName ~= PBAM.SelectedBot then return end
        local ok = result.result == "OK"
        local label = result.type == "ITEM_TRADE" and "Trade" or "Equip"
        local extra = result.type == "ITEM_TRADE" and (" moved=" .. tostring(result.moved or 0)) or ""
        LogStatus(panel.StatusText, label .. (ok and " complete" or " failed") .. extra .. (ok and "" or (": " .. tostring(result.reason or "unknown"))), ok and 0.35 or 1, ok and 0.9 or 0.35, ok and 0.45 or 0.25)
        if ok and PBAM.SelectedBot then
            After(0.75, function() PBAM.Bridge.RequestInventory(PBAM.SelectedBot) end)
            if result.type == "ITEM_EQUIP" and PBAM.RefreshEquipmentTab then After(0.75, function() PBAM.RefreshEquipmentTab(PBAM.SelectedBot, true) end) end
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
    refreshBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Refresh Inventory", 1, 0.82, 0.22, true)
        GameTooltip:AddLine("Request fresh inventory data from the selected bot.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    refreshBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local bankBtn = Button("Bank", -108)
    bankBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("View Bank", 1, 0.82, 0.22, true)
        GameTooltip:AddLine("Switch to bank view to see the bot's bank contents.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Click bank items to request withdrawal via bridge.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    bankBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local invBtn = Button("Inventory", -202)
    invBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("View Inventory", 1, 0.82, 0.22, true)
        GameTooltip:AddLine("Switch to inventory view to see the bot's bag contents.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    invBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
    local buyCheck = CheckButtonRight("Buy Mode", -48)
    local sellCheck = CheckButtonLeft("Sell Mode", -72)
    local sellBatch = CheckButtonRight("Batch Mode", -72)

    local tradeTargetLabel = actionPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tradeTargetLabel:SetPoint("TOPLEFT", actionPanel, "TOPLEFT", 18, -124)
    tradeTargetLabel:SetText("Trade Target")
    tradeTargetLabel:Hide()

    local targetButton = CreateFrame("Button", nil, actionPanel, "UIPanelButtonTemplate")
    targetButton:SetSize(180, 24)
    targetButton:SetPoint("TOPLEFT", tradeTargetLabel, "BOTTOMLEFT", 0, -6)
    targetButton:SetText("Player")
    targetButton:Hide()

    local function SellButton(text, y)
        local b = CreateFrame("Button", nil, actionPanel, "UIPanelButtonTemplate")
        b:SetSize(120, 24); b:SetPoint("TOPLEFT", actionPanel, "TOPLEFT", 18, y)
        b:SetText(text)
        return b
    end
    local function RightActionButton(text, y)
        local b = CreateFrame("Button", nil, actionPanel, "UIPanelButtonTemplate")
        b:SetSize(120, 24); b:SetPoint("TOPRIGHT", actionPanel, "TOPRIGHT", -32, y)
        b:SetText(text)
        return b
    end
    local sellGreysBtn = SellButton("Sell Greys", -190)
    sellGreysBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Sell Grey Items", 1, 0.82, 0.22, true)
        GameTooltip:AddLine("Sell all grey-quality items from the bot's inventory", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    sellGreysBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local sellVendorBtn = SellButton("Sell Vendorable", -224)
    sellVendorBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Sell Vendorable Items", 1, 0.82, 0.22, true)
        GameTooltip:AddLine("Sell all items that can be sold to vendors", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    sellVendorBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local repairAllBtn = RightActionButton("Repair All", -190)
    repairAllBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Repair All Items", 1, 0.82, 0.22, true)
        GameTooltip:AddLine("Repair all equipped items for the selected bot", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    repairAllBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local buyAmmoBtn = SellButton("Buy Ammo", -258)
    buyAmmoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Buy Ammo", 1, 0.82, 0.22, true)
        GameTooltip:AddLine("Buy arrows/bullets for hunter bots from the merchant", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    buyAmmoBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
    local isBatchSelling = false

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
        PBAM.SetButtonEnabled(targetButton, false, "Trade Mode always targets your player character.")
        equipCheck:SetEnabled(hasBot)
        equipCheck:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Equip Mode", 1, 0.82, 0.22, true)
            GameTooltip:AddLine("Left-click: Equip item in main/off hand", 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Right-click: Equip item in off/main hand", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        equipCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)

        tradeCheck:SetEnabled(hasBot)
        tradeCheck:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Trade Mode", 1, 0.82, 0.22, true)
            GameTooltip:AddLine("Enable trading with the selected bot", 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Trade target is always your player character.", 0.6, 0.6, 0.6, true)
            GameTooltip:AddLine("Click items to place them into the bot's trade window.", 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end)
        tradeCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)

        buyCheck:SetEnabled(hasBot)
        buyCheck:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Buy Mode", 1, 0.82, 0.22, true)
            GameTooltip:AddLine("Left-click: Buy 1 item from merchant", 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Right-click: Buy full stack from merchant", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        buyCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)

        sellCheck:SetEnabled(hasBot)
        sellCheck:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Sell Mode", 1, 0.82, 0.22, true)
            GameTooltip:AddLine("Click items to sell them to the current vendor target", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        sellCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)

        sellBatch:SetEnabled(hasBot)
        sellBatch:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Batch Mode", 1, 0.82, 0.22, true)
            GameTooltip:AddLine("Sell entire stacks instead of single items", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        sellBatch:SetScript("OnLeave", function() GameTooltip:Hide() end)

        destroyCheck:SetEnabled(hasBot)
        destroyCheck:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Destroy Mode", 1, 0.82, 0.22, true)
            GameTooltip:AddLine("Click items to destroy them permanently", 1, 0.3, 0.3, true)
            GameTooltip:AddLine("WARNING: This cannot be undone!", 1, 0, 0, true)
            GameTooltip:Show()
        end)
        destroyCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    local function SetTargetText()
        tradeTarget = UnitShortName("player") or UnitName("player")
        targetButton:SetText(tradeTarget or "Player")
    end

    HideTargetMenu = function()
        targetMenu:Hide()
    end

    local function ShowTargetMenu()
        tradeTarget = UnitShortName("player") or UnitName("player")
        SetTargetText()
        HideTargetMenu()
    end

    targetButton:SetScript("OnClick", function()
        if not PBAM.SelectedBot or not tradeMode then return end
        if targetMenu:IsShown() then HideTargetMenu() else ShowTargetMenu() end
    end)

    local function RefreshTargetDropdown()
        tradeTarget = UnitShortName("player") or UnitName("player")
        SetTargetText()
        HideTargetMenu()
    end

    local function BotClassName(botName)
        local lower = string.lower(tostring(botName or ""))
        local detail = PBAM.Bridge.Details and PBAM.Bridge.Details[lower]
        if detail and detail.className and detail.className ~= "" then return detail.className end
        local roster = PBAM.GetRosterEntry and PBAM.GetRosterEntry(botName)
        return roster and roster.className or ""
    end

    local function BotLevel(botName)
        local lower = string.lower(tostring(botName or ""))
        return (PBAM.Bridge.Stats and PBAM.Bridge.Stats[lower] and PBAM.Bridge.Stats[lower].level)
            or (PBAM.Bridge.Details and PBAM.Bridge.Details[lower] and PBAM.Bridge.Details[lower].level)
            or (PBAM.GetRosterEntry and PBAM.GetRosterEntry(botName) and PBAM.GetRosterEntry(botName).level)
            or 0
    end

    local function BestVendorAmmo(kind, botLevel)
        local best = nil
        for _, item in ipairs(BuildMerchantItems()) do
            local subType = string.lower(tostring(item.subType or ""))
            local matches = (kind == "arrow" and subType == "arrow") or (kind == "bullet" and (subType == "bullet" or subType == "bullets"))
            if matches and not item.extendedCost and item.itemId and item.itemId > 0 then
                local minLevel = tonumber(item.minLevel) or 0
                if minLevel <= (tonumber(botLevel) or 0) then
                    if not best or minLevel > (tonumber(best.minLevel) or 0) or ((minLevel == (tonumber(best.minLevel) or 0)) and (tonumber(item.itemId) > tonumber(best.itemId))) then
                        best = item
                    end
                end
            end
        end
        return best
    end

    local function CountInventoryItem(botName, itemId)
        local inv = PBAM.Bridge.Inventory and PBAM.Bridge.Inventory[string.lower(tostring(botName or ""))]
        local total = 0
        for _, item in ipairs((inv and inv.itemLocations) or {}) do
            if tonumber(item.itemId) == tonumber(itemId) then total = total + (tonumber(item.count) or 0) end
        end
        return total
    end

    local function BridgeRangedItem(botName)
        local inv = PBAM.Bridge.Inventory and PBAM.Bridge.Inventory[string.lower(tostring(botName or ""))]
        for _, item in ipairs((inv and inv.equipmentLocations) or {}) do
            if tonumber(item.equipSlot) == 17 then return item end
        end
        return nil
    end

    local function BuildAmmoAction(item, botName)
        if not item then return nil end
        local stack = math.max(1, tonumber(item.stackCount) or tonumber(item.quantity) or 1)
        local targetCount = stack * 4
        local owned = CountInventoryItem(botName, item.itemId)
        local buyCount = math.max(0, targetCount - owned)
        if buyCount <= 0 then return nil, "Already has at least " .. tostring(targetCount) .. "x " .. tostring(item.name or item.itemId) .. "." end
        return {
            kind = "buyammo",
            itemId = item.itemId,
            count = buyCount,
            itemName = item.name,
            itemLink = item.link or item.name,
            owned = owned,
        }
    end

    local function DetermineAmmoPurchase(botName)
        if not IsMerchantOpen() then return nil, "Open a vendor window first." end
        local botLevel = BotLevel(botName)
        local unit = PBAM.FindBotUnit and PBAM.FindBotUnit(botName) or nil
        local rangedLink = unit and GetInventoryItemLink and GetInventoryItemLink(unit, 18) or nil
        local bridgeRanged = BridgeRangedItem(botName)
        local ammoKind = nil
        local function inferAmmoKind(itemRef)
            if itemRef and GetItemInfo then
                local _, _, _, _, _, _, rangedSubType = GetItemInfo(itemRef)
                local sub = string.lower(tostring(rangedSubType or ""))
                if sub:find("bow", 1, true) or sub:find("crossbow", 1, true) then return "arrow" end
                if sub:find("gun", 1, true) then return "bullet" end
            end
            return nil
        end
        ammoKind = inferAmmoKind(rangedLink) or inferAmmoKind(bridgeRanged and bridgeRanged.itemId and ("item:" .. tostring(bridgeRanged.itemId)))

        if ammoKind then
            local best = BestVendorAmmo(ammoKind, botLevel)
            if not best then return nil, "No level-appropriate ammo found." end
            return BuildAmmoAction(best, botName)
        end

        -- Fallback when the bot's ranged weapon cannot be inspected. This happens
        -- often for roster/batch actions because not every bot has an inspectable unit.
        local className = string.lower(tostring(BotClassName(botName) or "")):gsub("%s+", "")
        if className ~= "hunter" then return nil, "Could not inspect ranged weapon." end

        local arrow = BestVendorAmmo("arrow", botLevel)
        local bullet = BestVendorAmmo("bullet", botLevel)
        if arrow and not bullet then return BuildAmmoAction(arrow, botName) end
        if bullet and not arrow then return BuildAmmoAction(bullet, botName) end
        if arrow and bullet then
            local arrowAction = BuildAmmoAction(arrow, botName)
            local bulletAction = BuildAmmoAction(bullet, botName)
            local actions = {}
            if arrowAction then table.insert(actions, arrowAction) end
            if bulletAction then table.insert(actions, bulletAction) end
            if #actions > 0 then return { kind = "buyammo_multi", actions = actions, itemName = "arrows and bullets" } end
            return nil, "Already has enough arrows and bullets."
        end
        return nil, "No level-appropriate ammo found."
    end

    local function StartBatchAction(label, buildAction, validator)
        if isBatchSelling then return end
        if validator then
            local ok, msg = validator()
            if not ok then LogStatus(statusFs, msg or "Cannot start batch action.", 1, 0.35, 0.25); return end
        end
        local botsToProcess = {}
        for _, bot in ipairs(PBAM.Bridge.Roster or {}) do
            if bot and bot.name and bot.name ~= "" then
                local action, reason = buildAction(bot.name)
                if action then table.insert(botsToProcess, { name = bot.name, action = action }) end
            end
        end
        if #botsToProcess == 0 then
            LogStatus(statusFs, "No eligible bots in roster for " .. label .. ".", 1, 0.6, 0.4)
            return
        end
        table.sort(botsToProcess, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
        isBatchSelling = true
        local totalBots = #botsToProcess
        local remainingTime = totalBots * 1.5
        local processed = 0
        local function UpdateCountdown()
            statusFs:SetText(string.format("|cff40ff40%s: %d/%d bots, ~%.1fs remaining|r", label, processed, totalBots, math.max(0, remainingTime)))
        end
        UpdateCountdown()
        local countdownUpdate
        countdownUpdate = function()
            if not isBatchSelling then return end
            remainingTime = remainingTime - 0.5
            if remainingTime > 0 then UpdateCountdown(); After(0.5, countdownUpdate) end
        end
        After(0.5, countdownUpdate)
        for i, entry in ipairs(botsToProcess) do
            local delay = (i - 1) * 1.5
            After(delay, function()
                if not isBatchSelling then return end
                local action = entry.action
                if action.kind == "whisper" then
                    PBAM.LegacySendingMessage("[PBAM] Sending: /w " .. entry.name .. " " .. action.command)
                    SendChatMessage(action.command, "WHISPER", nil, entry.name)
                    if action.refreshInventory and PBAM.Bridge and PBAM.Bridge.RequestInventory then
                        After(1.25, function()
                            local key = string.lower(entry.name)
                            local inv = PBAM.Bridge.Inventory and PBAM.Bridge.Inventory[key]
                            if not (inv and inv.loading) then PBAM.Bridge.RequestInventory(entry.name) end
                        end)
                    end
                elseif action.kind == "buyammo" then
                    if PBAM.Bridge.RunInventoryItemAction then
                        PBAM.Bridge.RunInventoryItemAction(entry.name, "BUY_ITEM", action.itemId, action.count)
                        if action.itemLink then
                            After(1.50, function() SendLegacyInventoryCommand("e", entry.name, action.itemLink) end)
                        end
                    end
                elseif action.kind == "buyammo_multi" then
                    if PBAM.Bridge.RunInventoryItemAction then
                        for j, subAction in ipairs(action.actions or {}) do
                            local extraDelay = (j - 1) * 0.75
                            After(extraDelay, function()
                                PBAM.Bridge.RunInventoryItemAction(entry.name, "BUY_ITEM", subAction.itemId, subAction.count)
                                if subAction.itemLink then
                                    After(1.50, function() SendLegacyInventoryCommand("e", entry.name, subAction.itemLink) end)
                                end
                            end)
                        end
                    end
                end
                processed = processed + 1
                UpdateCountdown()
                if i == totalBots then
                    After(1.5, function()
                        isBatchSelling = false
                        sellBatch:SetChecked(false)
                        statusFs:SetText("|cff40ff40" .. label .. " complete!|r")
                        LogStatus(statusFs, string.format("%s complete. Processed %d bot(s).", label, totalBots), 0.6, 1, 0.6)
                    end)
                end
            end)
        end
    end

    local function GetBatchHunterLevelLimit()
        local count, minLevel = 0, nil
        for _, bot in ipairs(PBAM.Bridge.Roster or {}) do
            if bot and bot.name and bot.name ~= "" then
                local className = string.lower(tostring(BotClassName(bot.name) or "")):gsub("%s+", "")
                if className == "hunter" then
                    count = count + 1
                    local level = tonumber(BotLevel(bot.name)) or 0
                    if not minLevel or level < minLevel then minLevel = level end
                end
            end
        end
        return count, minLevel or 0
    end

    local function StartBatchBuyAmmo()
        if not buyMode then
            LogStatus(statusFs, "Enable Buy Mode first.", 1, 0.7, 0.25)
            return
        end
        if not IsMerchantOpen() then
            LogStatus(statusFs, "Open a vendor window first.", 1, 0.35, 0.25)
            return
        end
        local hunterCount, levelLimit = GetBatchHunterLevelLimit()
        if hunterCount <= 0 then
            LogStatus(statusFs, "No hunter bots in roster for Buy Ammo.", 1, 0.6, 0.4)
            return
        end
        local candidates = {}
        local arrow = BestVendorAmmo("arrow", levelLimit)
        local bullet = BestVendorAmmo("bullet", levelLimit)
        if arrow then table.insert(candidates, arrow) end
        if bullet then table.insert(candidates, bullet) end
        if #candidates == 0 then
            LogStatus(statusFs, "No level-appropriate ammo found for hunter roster.", 1, 0.6, 0.4)
            return
        end
        local channel = (GetNumRaidMembers and GetNumRaidMembers() > 0) and "RAID" or "PARTY"
        for i, item in ipairs(candidates) do
            local link = item.link or item.name
            if link and link ~= "" then
                local msg = "@hunter b " .. tostring(link)
                After((i - 1) * 0.75, function()
                    PBAM.LegacySendingMessage("[PBAM] Sending: /" .. string.lower(channel) .. " " .. msg)
                    SendChatMessage(msg, channel)
                end)
            end
        end
        sellBatch:SetChecked(false)
        LogStatus(statusFs, "Sent Buy Ammo command(s) to @hunter for " .. tostring(hunterCount) .. " hunter bot(s).", 0.35, 0.9, 0.45)
    end

    local function StartBatchSell(command, label)
        if not sellMode then
            LogStatus(statusFs, "Enable Sell Mode first.", 1, 0.7, 0.25)
            return
        end
        local currentTarget = GetCurrentMerchantTargetName()
        if not currentTarget or currentTarget == "" then
            LogStatus(statusFs, "Select a vendor first!", 1, 0.35, 0.25)
            return
        end
        local channel = (GetNumRaidMembers and GetNumRaidMembers() > 0) and "RAID" or "PARTY"
        if DEFAULT_CHAT_FRAME then
            PBAM.LegacySendingMessage("[PBAM] Sending: /" .. string.lower(channel) .. " " .. command)
        end
        SendChatMessage(command, channel)
        sellBatch:SetChecked(false)
        LogStatus(statusFs, "Sent batch command '" .. command .. "' to " .. channel .. ".", 0.35, 0.9, 0.45)
    end

    local function SendLegacyInventoryCommand(command, botName, item, suffix)
        if not botName or botName == "" or not command or command == "" then return false end
        local link = item and ItemLink(item) or ""
        if item and (not link or link == "") then return false end
        local msg = item and (command .. " " .. link) or command
        if suffix and suffix ~= "" then msg = msg .. " " .. tostring(suffix) end
        if DEFAULT_CHAT_FRAME then
            PBAM.LegacySendingMessage("[PBAM] Sending: /w " .. botName .. " " .. string.sub(msg, 1, 100))
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

    RenderMerchantRows = function()
        ClearRows()
        HideTargetMenu()
        titleFs:SetText("Merchant")
        goldFs:SetText("Vendor inventory")
        slotsFs:SetText(PBAM.SelectedBot and ("Buying for: " .. tostring(PBAM.SelectedBot)) or "Select a bot to buy items.")
        if not IsMerchantOpen() then
            local r = Row(1); r.item=nil; r.itemText=nil; r.merchantItem=nil; r.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01"); r.text:SetText("Open a merchant window to browse items.")
            content:SetHeight(60)
            return false
        end
        local merchantItems = BuildMerchantItems()
        if #merchantItems == 0 then
            local r = Row(1); r.item=nil; r.itemText=nil; r.merchantItem=nil; r.icon:SetTexture("Interface\\Icons\\INV_Box_01"); r.text:SetText("This merchant has no items.")
            content:SetHeight(60)
            return false
        end
        for i, item in ipairs(merchantItems) do
            local r = Row(i)
            r.item = item.link or item.name; r.itemText = item.link or item.name; r.merchantItem = item
            r.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            local priceText = (GetCoinTextureString and GetCoinTextureString(item.price or 0)) or MoneyText(item.price or 0)
            local stackText = (item.quantity and item.quantity > 1) and ("  Stack: " .. tostring(item.quantity)) or ""
            local availText = (item.available and item.available > -1) and ("  Avail: " .. tostring(item.available)) or ""
            local extraText = item.extendedCost and "  |cffff6060(extended cost)|r" or ""
            r.text:SetText(string.format("%s\n%s%s%s%s", tostring(item.name or ("Merchant Item #" .. tostring(i))), tostring(priceText or ""), stackText, availText, extraText))
        end
        content:SetHeight(20 + #merchantItems * ROW_H)
        return true
    end

    RefreshMerchantView = function()
        if PBAM.CurrentTab ~= "Inventory" or not buyMode then return end
        emptyFs:Hide(); header:Show(); body:Show()
        RenderMerchantRows()
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
        if not row or (not item and not (buyMode and row.merchantItem)) then return end
        HideTargetMenu()

        if item and IsShiftKeyDown and IsShiftKeyDown() and button == "LeftButton" then
            local link = ItemLink(item)
            if ChatEdit_InsertLink and link and link ~= "" and ChatEdit_InsertLink(link) then return end
            LogStatus(statusFs, "Item link: " .. tostring(link or ItemName(item)), 0.75, 0.75, 0.75)
            return
        end

        if buyMode then
            local merchantItem = row and row.merchantItem
            if not merchantItem then return end
            if not PBAM.SelectedBot then
                LogStatus(statusFs, "Select a bot first.", 1, 0.35, 0.25)
                return
            end
            if merchantItem.extendedCost then
                LogStatus(statusFs, "Extended-cost vendor items are not supported yet.", 1, 0.35, 0.25)
                return
            end
            if not merchantItem.itemId or merchantItem.itemId <= 0 then
                LogStatus(statusFs, "Cannot buy this merchant item: no item id.", 1, 0.35, 0.25)
                return
            end
            local count = button == "RightButton" and math.max(1, tonumber(merchantItem.quantity) or 1) or 1
            if PBAM.Bridge.RunInventoryItemAction and PBAM.Bridge.RunInventoryItemAction(PBAM.SelectedBot, "BUY_ITEM", merchantItem.itemId, count) then
                LogStatus(statusFs, "Buying " .. tostring(merchantItem.name or merchantItem.itemId) .. " x" .. tostring(count) .. " for " .. tostring(PBAM.SelectedBot) .. "...", 0.95, 0.8, 0.25)
            else
                local link = merchantItem.link or merchantItem.name
                if link and SendLegacyInventoryCommand("b", PBAM.SelectedBot, link, tostring(count)) then
                    LogStatus(statusFs, "Buy command sent for " .. tostring(merchantItem.name or merchantItem.itemId) .. ".", 0.35, 0.9, 0.45)
                else
                    LogStatus(statusFs, "Could not send buy command.", 1, 0.35, 0.25)
                end
            end
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
            local slotHint = IsEquippableBagItem(item) and "BAG" or (button == "RightButton" and "OFF_HAND" or "AUTO")
            if PBAM.Bridge and PBAM.Bridge.ItemEquip and PBAM.Bridge.ItemEquip(PBAM.SelectedBot, ItemId(item), slotHint, item.bag, item.slot) then
                LogStatus(statusFs, "Equip request sent (" .. slotHint .. ") for " .. ItemName(item) .. ".", 0.35, 0.9, 0.45)
                RequestInventoryRefresh()
                RequestEquipmentRefresh()
            elseif SendLegacyInventoryCommand("e", PBAM.SelectedBot, item) then
                LogStatus(statusFs, "Legacy equip command sent for " .. ItemName(item) .. ".", 0.35, 0.9, 0.45)
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
            local name = ItemName(item)
            local targetName = UnitShortName("player") or UnitName("player")
            if PBAM.Bridge and PBAM.Bridge.ItemTrade and PBAM.Bridge.ItemTrade(PBAM.SelectedBot, ItemId(item), targetName, 0, item.bag, item.slot) then
                LogStatus(statusFs, "Bridge trade request sent for " .. name .. " to " .. tostring(targetName) .. ".", 0.35, 0.9, 0.45)
                After(1.50, function() PBAM.Bridge.RequestInventory(PBAM.SelectedBot) end)
                After(2.25, function() PBAM.Bridge.RequestInventory(PBAM.SelectedBot) end)
            elseif SendLegacyInventoryCommand("t", PBAM.SelectedBot, item, "1") then
                LogStatus(statusFs, "Legacy trade command sent for " .. name .. ".", 0.35, 0.9, 0.45)
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
                PBAM.LegacySendingMessage("[PBAM] Sending: /w " .. PBAM.SelectedBot .. " s " .. string.sub(link, 1, 100))
            end
            SendChatMessage("s " .. link, "WHISPER", nil, PBAM.SelectedBot)
            LogStatus(statusFs, "Sent sell command for " .. name .. (sellBatch:GetChecked() and " (batch mode: whole stack)" or "") .. ". Refreshing in 1.25s...", 0.35, 0.9, 0.45)
            After(1.25, function() PBAM.Bridge.RequestInventory(PBAM.SelectedBot) end)
            return
        end

        if destroyMode then
            local link = ItemLink(item)
            local name = ItemName(item)
            if not link or link == "" then
                LogStatus(statusFs, "Cannot destroy: item link unavailable.", 1, 0.35, 0.25)
                return
            end

            PBAM.ConfirmDestructive("Destroy " .. tostring(name or link) .. " on " .. tostring(PBAM.SelectedBot) .. "?", function()
                -- Send 'destroy <itemLink>' command to destroy the item
                PBAM.LegacySendingMessage("[PBAM] Sending: /w " .. PBAM.SelectedBot .. " destroy " .. string.sub(link, 1, 100))
                SendChatMessage("destroy " .. link, "WHISPER", nil, PBAM.SelectedBot)
                LogStatus(statusFs, "Sent destroy command for " .. name .. ". Refreshing in 1.25s...", 0.35, 0.9, 0.45)
                After(1.25, function() PBAM.Bridge.RequestInventory(PBAM.SelectedBot) end)
            end)
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
            if buyMode and self.merchantItem and SetMerchantItem then
                GameTooltip:ClearLines()
                GameTooltip:SetMerchantItem(self.merchantItem.index)
            else
                if equipMode then GameTooltip:AddLine("Equip Mode: left=normal/main hand, right=offhand/standard legacy equip.", 0.35, 0.9, 0.45, true) end
                if tradeMode then GameTooltip:AddLine("Trade Mode: click to insert item into open trade ('t' + 'give' commands)", 0.95, 0.8, 0.25, true) end
                if buyMode and self.merchantItem then GameTooltip:AddLine("Buy Mode: left-click buys 1, right-click buys one merchant stack.", 0.35, 0.9, 0.45, true) end
            end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[i] = r; return r
    end

    equipCheck:SetScript("OnClick", function(self)
        equipMode = self:GetChecked() and true or false
        if equipMode then
            buyMode = false; buyCheck:SetChecked(false)
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
            buyMode = false; buyCheck:SetChecked(false)
            destroyCheck:SetChecked(false)
            sellCheck:SetChecked(false)
            sellBatch:SetChecked(false)
            equipMode = false; equipCheck:SetChecked(false); RefreshTargetDropdown()
            tradeInitiatedAt = GetTime and GetTime() or 0
            if PBAM.SelectedBot then
                -- Match MultiBot-Chatless: open the trade from the client, then insert only clicked items.
                if InitiateTrade then InitiateTrade(PBAM.SelectedBot) end
            end
            LogStatus(statusFs, "Trade Mode enabled for " .. tostring(PBAM.SelectedBot or "selected bot") .. ". Target is your player; wait ~1s before inserting items.", 0.35, 0.9, 0.45)
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
            buyMode = false; buyCheck:SetChecked(false)
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
        if sellBatch:GetChecked() then
            StartBatchSell("s *", "Sell Greys")
            return
        end
        if not PBAM.SelectedBot or not sellMode then return end
        local currentTarget = GetCurrentMerchantTargetName()
        if not currentTarget or currentTarget == "" then
            LogStatus(statusFs, "Select a vendor first!", 1, 0.35, 0.25)
            return
        end
        if DEFAULT_CHAT_FRAME then
            PBAM.LegacySendingMessage("[PBAM] Sending: /w " .. PBAM.SelectedBot .. " s *")
        end
        SendChatMessage("s *", "WHISPER", nil, PBAM.SelectedBot)
        After(1.25, function() PBAM.Bridge.RequestInventory(PBAM.SelectedBot) end)
    end)

    sellVendorBtn:SetScript("OnClick", function()
        if sellBatch:GetChecked() then
            StartBatchSell("s vendor", "Sell Vendorable")
            return
        end
        if not PBAM.SelectedBot or not sellMode then return end
        local currentTarget = GetCurrentMerchantTargetName()
        if not currentTarget or currentTarget == "" then
            LogStatus(statusFs, "Select a vendor first!", 1, 0.35, 0.25)
            return
        end
        if DEFAULT_CHAT_FRAME then
            PBAM.LegacySendingMessage("[PBAM] Sending: /w " .. PBAM.SelectedBot .. " s vendor")
        end
        SendChatMessage("s vendor", "WHISPER", nil, PBAM.SelectedBot)
        After(1.25, function() PBAM.Bridge.RequestInventory(PBAM.SelectedBot) end)
    end)

    repairAllBtn:SetScript("OnClick", function()
        local currentTarget = GetCurrentMerchantTargetName()
        if not currentTarget or currentTarget == "" then
            LogStatus(statusFs, "Select a repair vendor first!", 1, 0.35, 0.25)
            return
        end
        if sellBatch:GetChecked() then
            local channel = (GetNumRaidMembers and GetNumRaidMembers() > 0) and "RAID" or "PARTY"
            if DEFAULT_CHAT_FRAME then
                PBAM.LegacySendingMessage("[PBAM] Sending: /" .. string.lower(channel) .. " repair all")
            end
            SendChatMessage("repair all", channel)
            sellBatch:SetChecked(false)
            LogStatus(statusFs, "Sent batch repair command to " .. channel .. ".", 0.35, 0.9, 0.45)
            return
        end
        if not PBAM.SelectedBot then return end
        if DEFAULT_CHAT_FRAME then
            PBAM.LegacySendingMessage("[PBAM] Sending: /w " .. PBAM.SelectedBot .. " repair all")
        end
        SendChatMessage("repair all", "WHISPER", nil, PBAM.SelectedBot)
        LogStatus(statusFs, "Sent repair command for " .. tostring(PBAM.SelectedBot) .. ".", 0.35, 0.9, 0.45)
    end)

    buyAmmoBtn:SetScript("OnClick", function()
        if sellBatch:GetChecked() then
            StartBatchBuyAmmo()
            return
        end
        if not buyMode then
            LogStatus(statusFs, "Enable Buy Mode first.", 1, 0.7, 0.25)
            return
        end
        if not PBAM.SelectedBot then
            LogStatus(statusFs, "Select a bot first.", 1, 0.35, 0.25)
            return
        end
        local action, reason = DetermineAmmoPurchase(PBAM.SelectedBot)
        if not action then
            LogStatus(statusFs, reason or ("Could not determine ammo for " .. tostring(PBAM.SelectedBot) .. "."), 1, 0.35, 0.25)
            return
        end
        if action.kind == "buyammo_multi" then
            if not PBAM.Bridge.RunInventoryItemAction then
                LogStatus(statusFs, "Could not send Buy Ammo request.", 1, 0.35, 0.25)
                return
            end
            LogStatus(statusFs, "Buying ammo/shot for " .. tostring(PBAM.SelectedBot) .. "...", 0.35, 0.9, 0.45)
            for i, subAction in ipairs(action.actions or {}) do
                local delay = (i - 1) * 0.75
                After(delay, function()
                    PBAM.Bridge.RunInventoryItemAction(PBAM.SelectedBot, "BUY_ITEM", subAction.itemId, subAction.count)
                    if subAction.itemLink then
                        After(1.50, function()
                            if PBAM.SelectedBot and subAction.itemLink then
                                SendLegacyInventoryCommand("e", PBAM.SelectedBot, subAction.itemLink)
                            end
                        end)
                    end
                end)
            end
        elseif PBAM.Bridge.RunInventoryItemAction and PBAM.Bridge.RunInventoryItemAction(PBAM.SelectedBot, "BUY_ITEM", action.itemId, action.count) then
            LogStatus(statusFs, "Buying ammo for " .. tostring(PBAM.SelectedBot) .. ": " .. tostring(action.itemName) .. " x" .. tostring(action.count) .. "...", 0.35, 0.9, 0.45)
            if action.itemLink then
                After(1.50, function()
                    if PBAM.SelectedBot and action.itemLink then
                        SendLegacyInventoryCommand("e", PBAM.SelectedBot, action.itemLink)
                    end
                end)
            end
        else
            LogStatus(statusFs, "Could not send Buy Ammo request.", 1, 0.35, 0.25)
        end
    end)

    sellBatch:SetScript("OnClick", function(self)
        if self:GetChecked() and not (sellMode or buyMode) then
            self:SetChecked(false)
            LogStatus(statusFs, "Batch Mode requires Sell Mode or Buy Mode to be enabled.", 1, 0.7, 0.25)
        elseif self:GetChecked() then
            LogStatus(statusFs, "Batch Mode enabled. Sell buttons, Buy Ammo, and Repair All will process the whole roster.", 0.95, 0.8, 0.25)
        else
            LogStatus(statusFs, "Batch Mode disabled.", 0.75, 0.75, 0.75)
        end
    end)
    buyCheck:SetScript("OnClick", function(self)
        buyMode = self:GetChecked() and true or false
        if buyMode then
            equipMode = false; equipCheck:SetChecked(false)
            tradeMode = false; tradeCheck:SetChecked(false)
            sellMode = false; sellCheck:SetChecked(false)
            destroyMode = false; destroyCheck:SetChecked(false)
            sellBatch:SetChecked(false)
            showingBank = false
            LogStatus(statusFs, "Buy Mode enabled. Open a vendor window to browse merchant items.", 0.35, 0.9, 0.45)
            RefreshMerchantView()
        else
            showingBank = false
            if PBAM.SelectedBot then
                local key = string.lower(PBAM.SelectedBot)
                local token = PBAM.Bridge.RequestInventory and PBAM.Bridge.RequestInventory(PBAM.SelectedBot) or nil
                if token then
                    PBAM.Bridge.Inventory[key] = { name = PBAM.SelectedBot, token = token, items = {}, goldCopper = 0, bagUsed = 0, bagTotal = 0, loading = true }
                    LogStatus(statusFs, "Buy Mode disabled. Refreshing inventory...", 0.95, 0.8, 0.25)
                else
                    LogStatus(statusFs, "Buy Mode disabled. Inventory refresh already pending.", 0.75, 0.75, 0.75)
                end
                panel.OnBotSelect(PBAM.SelectedBot)
            else
                LogStatus(statusFs, "Buy Mode disabled.", 0.75, 0.75, 0.75)
            end
        end
        UpdateActionButtons(PBAM.SelectedBot)
    end)

    destroyCheck:SetScript("OnClick", function(self)
        destroyMode = self:GetChecked() and true or false
        if self:GetChecked() then
            -- Disable all other mode checkboxes when Destroy Mode is enabled
            buyMode = false; buyCheck:SetChecked(false)
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
        if buyMode then
            RefreshMerchantView()
        elseif PBAM.SelectedBot then
            showingBank = false
            local key = string.lower(PBAM.SelectedBot)
            PBAM.Bridge.Inventory[key] = { name = PBAM.SelectedBot, items = {}, goldCopper = 0, bagUsed = 0, bagTotal = 0, loading = true }
            PBAM.Bridge.RequestInventory(PBAM.SelectedBot)
            panel.OnBotSelect(PBAM.SelectedBot)
        end
    end)

    local merchantFrame = CreateFrame("Frame")
    merchantFrame:RegisterEvent("MERCHANT_SHOW")
    merchantFrame:RegisterEvent("MERCHANT_UPDATE")
    merchantFrame:RegisterEvent("MERCHANT_CLOSED")
    merchantFrame:SetScript("OnEvent", function(_, event)
        if PBAM.CurrentTab ~= "Inventory" or not buyMode then return end
        if event == "MERCHANT_CLOSED" then
            buyMode = false
            if buyCheck then buyCheck:SetChecked(false) end
            LogStatus(statusFs, "Merchant window closed. Buy Mode disabled.", 0.75, 0.75, 0.75)
            if PBAM.SelectedBot and panel.OnBotSelect then panel.OnBotSelect(PBAM.SelectedBot) end
            return
        end
        RefreshMerchantView()
    end)
    bankBtn:SetScript("OnClick", function()
        if buyMode then buyMode = false; buyCheck:SetChecked(false) end
        if PBAM.SelectedBot then
            showingBank = true
            PBAM.Bridge.Bank[string.lower(PBAM.SelectedBot)] = nil
            PBAM.Bridge.RequestBank(PBAM.SelectedBot)
            panel.OnBotSelect(PBAM.SelectedBot)
        end
    end)
    invBtn:SetScript("OnClick", function()
        if buyMode then buyMode = false; buyCheck:SetChecked(false) end
        if PBAM.SelectedBot then showingBank = false; panel.OnBotSelect(PBAM.SelectedBot) end
    end)

    panel.OnRefresh = function(botName)
        if buyMode then RefreshMerchantView(); return end
        if not botName then return end
        if showingBank then
            PBAM.Bridge.Bank[string.lower(botName)] = nil
            PBAM.Bridge.RequestBank(botName)
        else
            local key = string.lower(botName)
            local now = GetTime and GetTime() or 0
            local inv = PBAM.Bridge.Inventory and PBAM.Bridge.Inventory[key]
            if inv and inv.loading and (now - lastTabOpenInventoryRequest) < 1.0 then
                panel.OnBotSelect(botName)
                return
            end
            lastTabOpenInventoryRequest = now
            PBAM.Bridge.Inventory[key] = { name = botName, items = {}, goldCopper = 0, bagUsed = 0, bagTotal = 0, loading = true }
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
        if buyMode then
            RefreshMerchantView()
            return
        end
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
                local r = Row(1); r.item=nil; r.itemText=nil; r.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02"); r.text:SetText("Bank unavailable: " .. bank.error .. " - stand near/interact with a banker and try again.")
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
        local displayItems = (inv.itemLocations and #inv.itemLocations > 0) and inv.itemLocations or inv.items
        if not displayItems or #displayItems == 0 then
            local r = Row(1); r.item=nil; r.itemText=nil; r.icon:SetTexture("Interface\\Icons\\INV_Box_01"); r.text:SetText("No inventory items returned."); content:SetHeight(60); return
        end
        for i, item in ipairs(displayItems) do local r = Row(i); r.item=item; r.itemText=ItemText(item); r.icon:SetTexture(ItemIcon(item)); r.text:SetText(ItemText(item)) end
        UpdateRowHighlights(); content:SetHeight(20 + #displayItems * ROW_H)
    end
end, { hideForPlayer = true })
