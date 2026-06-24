-- ============================================================
--  PBAM_Tab_Spells.lua  |  Spells tab — bridge spellbook + legacy cast MVP
-- ============================================================

PBAM = PBAM or {}

-- -----------------------------------------------------------------------------
-- Local spell filter lists
--
-- These lists are intentionally simple name-based deny-lists so they are easy to
-- maintain without touching bridge code.
--
-- How to use them:
--   1. Add spell names in lower-case.
--   2. Use the exact visible spell name when possible.
--   3. Keep entries grouped by theme so future contributors can find them quickly.
--
-- Examples:
--   SPELL_FILTERS.class["mage"]["teleport: stormwind"] = true
--   SPELL_FILTERS.race["draenei"]["gift of the naaru"] = true
--   SPELL_FILTERS.profession["general"]["smelting"] = true
--
-- Notes:
--   - "general" applies regardless of class/race/profession.
--   - If a spell is showing up in the wrong tab, add it here instead of hacking the
--     row builder.
--   - Profession/crafting/utility spells belong in Professions, not Spells.
-- -----------------------------------------------------------------------------
local SPELL_FILTERS = {
    race = {
        -- Example racial filters:
        -- draenei = { ["gift of the naaru"] = true },
        -- dwarf = { ["find treasure"] = true },
    },
    class = {
        -- Example class filters:
        -- mage = { ["teleport: stormwind"] = true, ["portal: stormwind"] = true },
        -- shaman = { ["ancestral spirit"] = true },
    },
    profession = {
        general = {
            ["alchemy"] = true,
            ["blacksmithing"] = true,
            ["cooking"] = true,
            ["disenchant"] = true,
            ["enchanting"] = true,
            ["engineering"] = true,
            ["find fish"] = true,
            ["find herbs"] = true,
            ["find minerals"] = true,
            ["first aid"] = true,
            ["fishing"] = true,
            ["herb gathering"] = true,
            ["herbalism"] = true,
            ["inscription"] = true,
            ["jewelcrafting"] = true,
            ["leatherworking"] = true,
            ["mining"] = true,
            ["skinning"] = true,
            ["smelting"] = true,
            ["tailoring"] = true,
        },
        patterns = {
            --"^enchant ",
            --"^mill ",
            --"^prospect ",
            --"^smelt ",
        },
    },
}

local function NormalizeSpellName(name)
    return string.lower(tostring(name or "")):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

local function ClassFilterKey(botName)
    local detail = PBAM.Bridge and PBAM.Bridge.Details and PBAM.Bridge.Details[string.lower(botName or "")]
    return string.lower(tostring(detail and detail.className or "")):gsub("%s+", "")
end

local function RaceFilterKey(botName)
    local detail = PBAM.Bridge and PBAM.Bridge.Details and PBAM.Bridge.Details[string.lower(botName or "")]
    return string.lower(tostring(detail and detail.race or "")):gsub("%s+", "")
end

local function IsFilteredSpell(botName, spell)
    local name = NormalizeSpellName(spell and spell.name)
    if name == "" then return false end

    local generalProf = SPELL_FILTERS.profession.general or {}
    if generalProf[name] then return true end
    for _, pattern in ipairs(SPELL_FILTERS.profession.patterns or {}) do
        if string.find(name, pattern) then return true end
    end

    local classList = SPELL_FILTERS.class[ClassFilterKey(botName)]
    if classList and classList[name] then return true end

    local raceList = SPELL_FILTERS.race[RaceFilterKey(botName)]
    if raceList and raceList[name] then return true end

    return false
end

local function GetSpellDisplayName(spell)
    local name = tostring(spell and spell.name or "")
    local rank = tostring(spell and spell.rank or "")
    if rank ~= "" and rank ~= "nil" then
        return name .. " (" .. rank .. ")"
    end
    return name ~= "" and name or ("Spell #" .. tostring(spell and spell.spellId or "?"))
end

local function IsRosterOnline(name)
    if not name or name == "" then return false end
    if not PBAM.Bridge.Roster then return true end
    for _, e in ipairs(PBAM.Bridge.Roster) do
        if string.lower(e.name) == string.lower(name) and e.alive then
            return true
        end
    end
    return false
end

local function GetSpellTargetOptions(botName, includeSelf)
    local values = {
        { value = "", label = "Bot target" },
    }
    if UnitName and UnitName("player") then
        table.insert(values, { value = UnitName("player"), label = "You (Player)" })
    end
    -- Local player and target are always valid (not in roster)
    if UnitExists and UnitExists("target") then
        local targetName = UnitName("target")
        if targetName and targetName ~= "" then
            table.insert(values, { value = targetName, label = "Target: " .. tostring(targetName) })
        end
    end
    -- Helper to check if a party/raid unit is online via roster
    local function IsOnline(name)
        return name and name ~= "" and IsRosterOnline(name)
    end
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists and UnitExists(unit) then
            local name = UnitName(unit)
            if name and IsOnline(name) then table.insert(values, { value = name, label = "Party: " .. name }) end
        end
    end
    for i = 1, 40 do
        local unit = "raid" .. i
        if UnitExists and UnitExists(unit) then
            local name = UnitName(unit)
            if name and IsOnline(name) then table.insert(values, { value = name, label = "Raid: " .. name }) end
        end
    end
    if includeSelf and botName and botName ~= "" then
        table.insert(values, { value = botName, label = "Bot self: " .. botName })
    end
    return values
end

PBAM.RegisterTab("Spells", "Spells", 5, function(panel)
    local MARGIN, ROW_H = 12, 46
    local rows = {}
    local searchText = ""
    local selectedTarget = ""
    local selfCast = false

    PBAM.Bridge.RegisterCallback("SpellbookUpdated", function(botName)
        if botName == PBAM.SelectedBot and PBAM.CurrentTab == "Spells" and panel.OnBotSelect then
            panel.OnBotSelect(botName)
        end
    end)
    PBAM.Bridge.RegisterCallback("CAST_SPELLResult", function(result)
        if PBAM.CurrentTab ~= "Spells" or not result or result.botName ~= PBAM.SelectedBot then return end
        PBAM.SetStatusText(panel.StatusText, "Cast " .. (result.result == "OK" and "ok" or ("failed: " .. tostring(result.reason or "unknown"))), result.result == "OK" and "success" or "error")
    end)

    local emptyFs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyFs:SetPoint("CENTER", panel, "CENTER", 0, 0)
    emptyFs:SetText("Select a bot to view spells")
    emptyFs:SetTextColor(0.55, 0.55, 0.55, 1)

    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", MARGIN, -MARGIN)
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -MARGIN, -MARGIN)
    header:SetHeight(116)
    PBAM.ApplyBackdrop(header, 0.55)
    PBAM.CreateSectionHeader(header, "Spells", -10, 13)

    local refreshBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    refreshBtn:SetSize(90, 22)
    refreshBtn:SetPoint("TOPRIGHT", header, "TOPRIGHT", -14, -26)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Refresh Spellbook", 1, 0.82, 0.22, true)
        GameTooltip:AddLine("Request fresh spellbook data from the selected bot.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    refreshBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local searchLabel = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", header, "TOPLEFT", 20, -30)
    searchLabel:SetText("Search:")

    PBAM._SpellsSearchBoxCounter = (PBAM._SpellsSearchBoxCounter or 0) + 1
    local searchBox = CreateFrame("EditBox", "PBAMSpellsSearchEditBox" .. tostring(PBAM._SpellsSearchBoxCounter), header, "InputBoxTemplate")
    searchBox:SetAutoFocus(false)
    searchBox:SetWidth(180)
    searchBox:SetHeight(22)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 6, 0)
    searchBox:SetScript("OnTextChanged", function(self)
        searchText = string.lower(self:GetText() or "")
        if panel.OnBotSelect and PBAM.SelectedBot then panel.OnBotSelect(PBAM.SelectedBot) end
    end)

    local selfCheck = CreateFrame("CheckButton", nil, header, "UICheckButtonTemplate")
    selfCheck:SetPoint("TOPLEFT", header, "TOPLEFT", 18, -56)
    selfCheck:SetScript("OnClick", function(self)
        selfCast = self:GetChecked() and true or false
        if panel.RefreshTargets then panel.RefreshTargets(PBAM.SelectedBot) end
    end)
    selfCheck.text = selfCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    selfCheck.text:SetPoint("LEFT", selfCheck, "RIGHT", 2, 0)
    selfCheck.text:SetText("Include bot self")

    local targetLabel = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    targetLabel:SetPoint("LEFT", selfCheck.text, "RIGHT", 30, 0)
    targetLabel:SetText("Target:")

    -- Custom scrollable dropdown for targets with position awareness
    local targetDropdownBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    targetDropdownBtn:SetSize(170, 22)
    targetDropdownBtn:SetPoint("LEFT", targetLabel, "RIGHT", 12, -2)
    targetDropdownBtn:SetText("Select Target")

    local targetMenu = CreateFrame("Frame", nil, UIParent)
    targetMenu:SetFrameStrata("FULLSCREEN")
    targetMenu:SetWidth(190)
    targetMenu:Hide()
    PBAM.ApplyBackdrop(targetMenu, 1.0)

    -- Custom scrollable container using a simple Frame + ScrollFrame
    local targetScroll = CreateFrame("ScrollFrame", nil, targetMenu)
    targetScroll:SetPoint("TOPLEFT", targetMenu, "TOPLEFT", 4, -4)
    targetScroll:SetPoint("BOTTOMRIGHT", targetMenu, "BOTTOMRIGHT", -4, 4)
    targetScroll:EnableMouseWheel(true)
    targetScroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), cur - delta * 20)))
    end)

    local targetScrollContent = CreateFrame("Frame", nil, targetScroll)
    targetScrollContent:SetWidth(178)
    targetScrollContent:SetHeight(4)
    targetScroll:SetScrollChild(targetScrollContent)

    local maxVisibleRows = 5
    local rowHeight = 22
    local menuMaxHeight = maxVisibleRows * rowHeight + 8

    local targetEntries = {}

    -- Background highlight texture for selected rows
    local selBg = targetScrollContent:CreateTexture(nil, "BACKGROUND")
    selBg:SetTexture(PBAM.textures.white)
    selBg:SetVertexColor(0.25, 0.35, 0.55, 1)
    selBg:Hide()

    -- Click-catchers (must be created before functions that reference them)
    local globalClickCatcher = CreateFrame("Button", nil, UIParent)
    globalClickCatcher:SetFrameStrata("FULLSCREEN")
    globalClickCatcher:EnableMouse(true)
    globalClickCatcher:SetMovable(true)
    globalClickCatcher:SetAllPoints(UIParent)
    globalClickCatcher:Hide()

    local menuClickCatcher = CreateFrame("Button", nil, UIParent)
    menuClickCatcher:SetFrameStrata("DIALOG")
    menuClickCatcher:EnableMouse(true)
    menuClickCatcher:Hide()

    -- HideTargetMenu must be defined before BuildTargetMenu so closures capture it
    HideTargetMenu = function()
        targetMenu:Hide()
        menuClickCatcher:Hide()
        globalClickCatcher:Hide()
    end

    local function BuildTargetMenu()
        -- Hide all existing entry buttons
        for _, btn in ipairs(targetEntries) do
            if btn and btn.Hide then btn:Hide() end
        end
        wipe(targetEntries)

        local values = GetSpellTargetOptions(PBAM.SelectedBot, selfCast)
        local count = 0
        for _, entry in ipairs(values) do
            local btn = CreateFrame("Button", nil, targetScrollContent, "UIPanelButtonTemplate")
            btn:SetSize(168, rowHeight - 2)
            btn:SetText(entry.label or tostring(entry.value))
            btn:SetPoint("TOPLEFT", targetScrollContent, "TOPLEFT", 6, -4 - count * rowHeight)
            btn:SetPoint("RIGHT", targetScrollContent, "RIGHT", -6, 0)
            btn:SetScript("OnClick", function()
                selectedTarget = entry.value
                targetDropdownBtn:SetText(entry.label or tostring(entry.value))
                if entry.onSelect then entry.onSelect(entry.value, entry) end
                HideTargetMenu()
            end)
            btn:SetEnabled(not (entry.disabled and entry.disabled()))
            table.insert(targetEntries, btn)
            count = count + 1
        end

        local contentH = math.max(count * rowHeight + 8, 32)
        targetScrollContent:SetHeight(contentH)
        targetMenu:SetHeight(math.min(count * rowHeight + 16, menuMaxHeight + 8))

        -- Position awareness: check if there's room below or need to open up
        local btnBottom = targetDropdownBtn:GetBottom() or 0
        local screenBottom = GetScreenHeight() * UIParent:GetScale()
        local spaceBelow = screenBottom - btnBottom
        local neededHeight = math.min(count, maxVisibleRows) * rowHeight + 16

        if spaceBelow < neededHeight and count > maxVisibleRows then
            targetMenu:SetPoint("BOTTOMLEFT", targetDropdownBtn, "TOPLEFT", 0, 2)
            targetScroll:SetVerticalScroll(0)
        else
            targetMenu:SetPoint("TOPLEFT", targetDropdownBtn, "BOTTOMLEFT", 0, -2)
            targetScroll:SetVerticalScroll(0)
        end

        if count > maxVisibleRows then
            targetScroll:EnableMouseWheel(true)
        else
            targetScroll:EnableMouseWheel(false)
        end
    end

    ShowTargetMenu = function()
        BuildTargetMenu()
        targetMenu:Show()
        -- Bring to top so it renders above everything else
        targetMenu:SetFrameStrata("FULLSCREEN")
        targetMenu:Raise()
        -- Position the menu click-catcher over the entire menu area to capture all clicks within it
        menuClickCatcher:ClearAllPoints()
        menuClickCatcher:SetPoint("TOPLEFT", targetMenu, "TOPLEFT", 0, 0)
        menuClickCatcher:SetPoint("BOTTOMRIGHT", targetMenu, "BOTTOMRIGHT", 0, 0)
        menuClickCatcher:SetFrameStrata("FULLSCREEN")
        menuClickCatcher:Raise()
        globalClickCatcher:Show()
    end

    globalClickCatcher:SetScript("OnClick", function()
        HideTargetMenu()
    end)

    targetDropdownBtn:SetScript("OnClick", function()
        if not PBAM.SelectedBot then return end
        if targetMenu:IsShown() then HideTargetMenu() else ShowTargetMenu() end
    end)
    targetDropdownBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Select Target", 1, 0.82, 0.22, true)
        GameTooltip:AddLine("Choose which bot/unit the caster should target.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    targetDropdownBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local statusFs = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusFs:SetPoint("TOPLEFT", header, "TOPLEFT", 20, -94)
    statusFs:SetPoint("RIGHT", header, "RIGHT", -18, 0)
    statusFs:SetJustifyH("LEFT")
    PBAM.WrapFontString(statusFs, 620)
    panel.StatusText = statusFs

    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -MARGIN, MARGIN)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), cur - delta * 28)))
    end)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(660)
    scroll:SetScrollChild(content)
    PBAM.ApplyBackdrop(content, 0.35)

    local tooltipCard = CreateFrame("Frame", nil, UIParent)
    tooltipCard:SetWidth(260)
    tooltipCard:SetHeight(54)
    tooltipCard:SetFrameStrata("TOOLTIP")
    tooltipCard:Hide()
    PBAM.ApplyBackdrop(tooltipCard, 0.96)
    local tooltipCardText = tooltipCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tooltipCardText:SetPoint("TOPLEFT", tooltipCard, "TOPLEFT", 10, -10)
    tooltipCardText:SetPoint("RIGHT", tooltipCard, "RIGHT", -10, 0)
    PBAM.WrapFontString(tooltipCardText, 240)
    tooltipCardText:SetTextColor(0.82, 0.82, 0.82, 1)

    local function HideSpellTooltipExtras()
        tooltipCard:Hide()
        GameTooltip:Hide()
    end

    local function HasVisibleGameTooltip()
        if GameTooltip.NumLines and GameTooltip:NumLines() and GameTooltip:NumLines() > 0 then
            local left1 = _G[GameTooltip:GetName() .. "TextLeft1"]
            local text = left1 and left1.GetText and left1:GetText() or nil
            return text ~= nil and text ~= ""
        end
        return false
    end

    local function TryShowGameSpellTooltip(spellId)
        if not spellId or spellId <= 0 then return false end

        if GameTooltip.SetSpellByID then
            local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, spellId)
            if ok and HasVisibleGameTooltip() then return true end
            GameTooltip:ClearLines()
        end

        if GameTooltip.SetHyperlink then
            local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "spell:" .. tostring(spellId))
            if ok and HasVisibleGameTooltip() then return true end
            GameTooltip:ClearLines()
        end

        local spellName = GetSpellInfo and GetSpellInfo(spellId)
        if spellName and GameTooltip.SetText then
            return false
        end

        return false
    end

    local function ShowSpellTooltipExtras(spellId, owner)
        if not spellId or spellId <= 0 then return end
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        if not TryShowGameSpellTooltip(spellId) then
            GameTooltip:Hide()
            return
        end
        GameTooltip:Show()

        local lines = { "Cast button uses native bridge RUN~CAST_SPELL when available." }
        if selectedTarget and selectedTarget ~= "" then
            table.insert(lines, "Planned target: " .. tostring(selectedTarget))
            table.insert(lines, "Explicit target syntax is not bridge-confirmed yet.")
        end
        tooltipCardText:SetText(table.concat(lines, "\n"))
        tooltipCard:ClearAllPoints()
        tooltipCard:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 0, -6)
        tooltipCard:Show()
    end

    local function ClearRows()
        for _, r in ipairs(rows) do r:Hide() end
        HideSpellTooltipExtras()
    end

    local function Row(i)
        if rows[i] then rows[i]:Show(); return rows[i] end
        local r = CreateFrame("Button", nil, content)
        r:SetHeight(ROW_H)
        r:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -8 - (i - 1) * ROW_H)
        r:SetPoint("RIGHT", content, "RIGHT", -8, 0)
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()
        r.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        r.bg:SetVertexColor(0.10, 0.10, 0.12, i % 2 == 0 and 0.32 or 0.18)
        r.icon = r:CreateTexture(nil, "OVERLAY")
        r.icon:SetSize(24, 24)
        r.icon:SetPoint("LEFT", r, "LEFT", 8, 0)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 7)
        r.name:SetPoint("RIGHT", r, "RIGHT", -90, 0)
        r.name:SetJustifyH("LEFT")
        r.meta = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.meta:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -5)
        r.meta:SetPoint("RIGHT", r, "RIGHT", -90, 0)
        r.meta:SetJustifyH("LEFT")
        r.cast = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        r.cast:SetSize(72, 22)
        r.cast:SetPoint("RIGHT", r, "RIGHT", -6, 0)
        r.cast:SetText("Cast")
        r:SetScript("OnEnter", function(self)
            ShowSpellTooltipExtras(self.spellId, self)
        end)
        r:SetScript("OnLeave", function() HideSpellTooltipExtras() end)
        rows[i] = r
        return r
    end

    function panel.RefreshTargets(botName)
        local values = GetSpellTargetOptions(botName, selfCast)
        for _, entry in ipairs(values) do
            entry.onSelect = function(value, entryData)
                selectedTarget = value or ""
                targetDropdownBtn:SetText(entryData.label or tostring(entryData.value))
                PBAM.SetStatusText(statusFs, selectedTarget ~= "" and ("Target selected: " .. tostring(selectedTarget) .. ".") or "Casting will send no target.", "info")
            end
        end
        -- Keep blank target blank: empty target means cast without explicit target.
    end

    panel.OnRefresh = function(botName)
        if not botName then return end
        local key = string.lower(botName)
        PBAM.Bridge.Spellbook[key] = nil
        PBAM.Bridge.RequestSpellbook(botName)
        PBAM.SetStatusText(statusFs, "Requesting spellbook...", "loading")
        if panel.OnBotSelect then panel.OnBotSelect(botName) end
    end

    refreshBtn:SetScript("OnClick", function()
        if PBAM.SelectedBot then panel.OnRefresh(PBAM.SelectedBot) end
    end)

    panel.OnBotSelect = function(botName)
        ClearRows()
        PBAM.SetButtonEnabled(refreshBtn, botName and botName ~= "", "Select a bot to refresh spells.")
        if not botName then emptyFs:Show(); header:Hide(); scroll:Hide(); return end
        emptyFs:Hide(); header:Show(); scroll:Show()
        panel.RefreshTargets(botName)

        local key = string.lower(botName)
        local sb = PBAM.Bridge.Spellbook and PBAM.Bridge.Spellbook[key]
        if not sb then
            PBAM.Bridge.RequestSpellbook(botName)
            PBAM.SetStatusText(statusFs, "Requesting spellbook...", "loading")
            local r = Row(1)
            r.icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
            r.name:SetText("Waiting for bridge spellbook data...")
            r.meta:SetText("Once loaded, this tab shows non-profession spells only.")
            r.cast:Hide()
            content:SetHeight(70)
            return
        end

        local filtered = {}
        for _, spell in ipairs(sb.spells or {}) do
            local displayName = string.lower(GetSpellDisplayName(spell))
            if not IsFilteredSpell(botName, spell) and (searchText == "" or displayName:find(searchText, 1, true)) then
                table.insert(filtered, spell)
            end
        end
        table.sort(filtered, function(a, b) return GetSpellDisplayName(a) < GetSpellDisplayName(b) end)

        if sb.loading then
            PBAM.SetStatusText(statusFs, "Loading spellbook...", "loading")
        else
            PBAM.SetStatusText(statusFs, tostring(#filtered) .. " spells shown. Tooltips use SpellByID when available. Cast uses native bridge endpoint.", "info")
        end

        if #filtered == 0 then
            local r = Row(1)
            r.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
            r.name:SetText(searchText ~= "" and "No spells match the current search." or "No non-profession spells returned.")
            r.meta:SetText("Use the local filter lists at the top of this file to hide unwanted class, race, or profession spells.")
            r.cast:Hide()
            content:SetHeight(70)
            return
        end

        for i, spell in ipairs(filtered) do
            local r = Row(i)
            local spellId = tonumber(spell.spellId) or 0
            local icon = nil
            if spellId > 0 and GetSpellInfo then
                local _, _, tex = GetSpellInfo(spellId)
                icon = tex
            end
            r.spellId = spellId
            r.spellName = spell.name
            r.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_Book_09")
            r.name:SetText(GetSpellDisplayName(spell))
            r.meta:SetText(string.format("Spell ID: %s%s%s", tostring(spell.spellId or "?"), spell.spellLevel and spell.spellLevel > 0 and ("  Level: " .. tostring(spell.spellLevel)) or "", spell.cooldown and spell.cooldown > 0 and ("  Cooldown: " .. tostring(spell.cooldown)) or ""))
            r.cast:Show()
            PBAM.SetButtonEnabled(r.cast, true, nil)
            r.cast:SetScript("OnClick", function()
                local spellText = spell.name or GetSpellDisplayName(spell) or tostring(spell.spellId)
                if PBAM.Bridge and PBAM.Bridge.CastSpell and spellId > 0 then
                    PBAM.Bridge.CastSpell(botName, spellId, selectedTarget or "")
                    PBAM.SetStatusText(statusFs, "Cast request sent for " .. GetSpellDisplayName(spell) .. (selectedTarget and selectedTarget ~= "" and (" on " .. tostring(selectedTarget)) or "") .. ".", "info")
                    return
                end
                local cmd = "cast " .. spellText
                if selectedTarget and selectedTarget ~= "" then cmd = cmd .. " on " .. selectedTarget end
                SendChatMessage(cmd, "WHISPER", nil, botName)
                PBAM.SetStatusText(statusFs, "Legacy cast command sent for " .. GetSpellDisplayName(spell) .. ".", "warn")
            end)
        end
        content:SetHeight(20 + #filtered * ROW_H)
    end
end, { hideForPlayer = true })
