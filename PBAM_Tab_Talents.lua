-- ============================================================
--  PBAM_Tab_Talents.lua  |  Bridge talent summary/apply tab
--  Uses PlayerbotManager talent textures imported into Textures/
-- ============================================================

PBAM = PBAM or {}

local ADDON_TEX = "Interface\\AddOns\\PBAltManager\\Textures\\"
local CLASS_KEYS = {
    ["Death Knight"] = "DeathKnight", ["Warrior"] = "Warrior", ["Paladin"] = "Paladin",
    ["Hunter"] = "Hunter", ["Rogue"] = "Rogue", ["Priest"] = "Priest", ["Shaman"] = "Shaman",
    ["Mage"] = "Mage", ["Warlock"] = "Warlock", ["Druid"] = "Druid",
}
local FALLBACK_NAMES = {
    Warrior={"Arms","Fury","Protection"}, Paladin={"Holy","Protection","Retribution"}, Hunter={"Beast Mastery","Marksmanship","Survival"},
    Rogue={"Assassination","Combat","Subtlety"}, Priest={"Discipline","Holy","Shadow"}, DeathKnight={"Blood","Frost","Unholy"},
    Shaman={"Elemental","Enhancement","Restoration"}, Mage={"Arcane","Fire","Frost"}, Warlock={"Affliction","Demonology","Destruction"},
    Druid={"Balance","Feral Combat","Restoration"},
}

local function classKey(className)
    return CLASS_KEYS[className or ""] or tostring(className or ""):gsub("%s+", "")
end

local function setTextSafe(fontString, text)
    if fontString then fontString:SetText(text or "") end
end

local function splitCsv(text)
    local out = {}
    for part in string.gmatch(tostring(text or ""), "([^,]+)") do
        table.insert(out, (part:gsub("^%s+", ""):gsub("%s+$", "")))
    end
    return out
end

local function parsePointSummary(summary)
    local a, b, c = tostring(summary or ""):match("^(%d+)%-(%d+)%-(%d+)$")
    if not a then return nil end
    return { tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0 }
end

local function after(delay, func)
    local f = CreateFrame("Frame")
    local elapsedTotal = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        elapsedTotal = elapsedTotal + (elapsed or 0)
        if elapsedTotal >= delay then
            self:SetScript("OnUpdate", nil)
            func()
        end
    end)
end

local function collectLiveTalentRanks(botName)
    local unit = PBAM.FindBotUnit and PBAM.FindBotUnit(botName) or nil
    if not unit or not GetTalentInfo then return nil end
    if InspectUnit and unit ~= "player" then InspectUnit(unit) end
    local ranks = {}
    local hasAny = false
    for tree=1,3 do
        ranks[tree] = {}
        for index=1,40 do
            local name, _, _, _, rank = GetTalentInfo(tree, index, true)
            if not name then break end
            ranks[tree][index] = tonumber(rank) or 0
            if (tonumber(rank) or 0) > 0 then hasAny = true end
        end
    end
    return hasAny and ranks or nil
end

local function makeTalentPlan(classToken, liveRanks)
    local talentData = PBAM.data and PBAM.data.talent and PBAM.data.talent.talents
    local classData = talentData and talentData[classToken]
    if not classData then return nil end
    local plan = {}
    for tree=1,3 do
        plan[tree] = {}
        for index=1,#(classData[tree] or {}) do
            plan[tree][index] = liveRanks and liveRanks[tree] and tonumber(liveRanks[tree][index]) or 0
        end
    end
    return plan
end

local function countTreePoints(plan, tree)
    local total = 0
    for _, rank in ipairs((plan and plan[tree]) or {}) do total = total + (tonumber(rank) or 0) end
    return total
end

local function countAllPoints(plan)
    return countTreePoints(plan, 1) + countTreePoints(plan, 2) + countTreePoints(plan, 3)
end

local function buildTalentApplyString(plan)
    if not plan then return nil end
    local trees = {}
    for tree=1,3 do
        local ranks = {}
        for index, rank in ipairs(plan[tree] or {}) do ranks[index] = tostring(tonumber(rank) or 0) end
        trees[tree] = table.concat(ranks, "")
    end
    return table.concat(trees, "-")
end

-- Legacy MVP talent application.
-- TODO bridge-talents: when the server adds something like
--   RUN~TALENT_APPLY~<bot>~<token>~<buildString>~<dryRunFlag>
-- replace this helper with PBAM.Bridge.ApplyTalentBuild(...), and keep the UI flow below unchanged.
local function sendTalentApplyWhisper(botName, spec)
    if not botName or not spec then return false end
    local specName = tostring(spec.name or "")

    -- IMPORTANT: the current bridge "build" field is only a point summary such as "54-12-5",
    -- not the full PBM/playerbot talent-rank string needed by "talents apply". Sending that
    -- summary to "talents apply" only partially applies talents. Until the bridge exposes the
    -- real build string (or RUN~TALENT_APPLY), use the named premade spec command instead.
    if specName ~= "" then
        -- Match PBM/MultiBot behavior: stop casts, ensure primary talent group, then apply the
        -- named premade after a short delay. Sending only "talents spec <name>" can leave the
        -- bot in a conversational "Picking ..." state without applying.
        SendChatMessage("stopcasting", "WHISPER", nil, botName)
        SendChatMessage("talents switch 1", "WHISPER", nil, botName)
        after(0.45, function()
            SendChatMessage("talents spec " .. specName, "WHISPER", nil, botName)
        end)
    else
        return false
    end
    return true
end

local function refreshAfterTalentApply(botName)
    if not botName then return end
    PBAM.Bridge.RequestBotDetail(botName)
    PBAM.Bridge.RequestTalentSpecList(botName)

    -- Give the bot/server a moment to apply the legacy whisper command, then refresh again.
    after(1.6, function()
        PBAM.Bridge.RequestBotDetail(botName)
        PBAM.Bridge.RequestTalentSpecList(botName)
    end)
end

StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["PBAM_CONFIRM_TALENT_APPLY"] = {
    text = "Apply talent build to %s?\n\n%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data)
        if data and data.panel and data.panel.ApplySelectedTalent then
            data.panel:ApplySelectedTalent(true)
        end
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

-- Current mod-playerbots talent commands do not expose a real "reset all talents" action.
-- Do not fake it with talents apply 000...: playerbot rejects that as "Invalid link".
-- TODO bridge-talents: replace ResetTalents with a native bridge/server endpoint when available.

PBAM.RegisterTab("Talents", "Talents", 2, function(panel)
    local MARGIN = 12
    local cards = {}
    local specRows = {}

    panel.SelectedTalentBuild = nil
    panel.DryRun = true

    local emptyFs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyFs:SetPoint("CENTER", panel, "CENTER")
    emptyFs:SetText("Select a bot to view talents")
    emptyFs:SetTextColor(0.55, 0.55, 0.55, 1)

    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", MARGIN, -MARGIN)
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -MARGIN, -MARGIN)
    header:SetHeight(96)
    PBAM.ApplyBackdrop(header, 0.55)
    PBAM.CreateSectionHeader(header, "Talents", -10, 13)

    local summary = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", header, "TOPLEFT", 20, -30)
    summary:SetPoint("RIGHT", header, "RIGHT", -360, 0)
    summary:SetJustifyH("LEFT")
    summary:SetTextColor(0.75, 0.75, 0.75, 1)

    local status = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -6)
    status:SetPoint("RIGHT", summary, "RIGHT", 0, 0)
    status:SetJustifyH("LEFT")
    status:SetTextColor(0.9, 0.78, 0.35, 1)
    panel.StatusText = status

    local dryRun = CreateFrame("CheckButton", nil, header, "UICheckButtonTemplate")
    dryRun:SetPoint("TOPRIGHT", header, "TOPRIGHT", -18, -55)
    dryRun:SetChecked(true)
    dryRun:SetScript("OnClick", function(self) panel.DryRun = self:GetChecked() and true or false end)
    dryRun.text = dryRun:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dryRun.text:SetPoint("RIGHT", dryRun, "LEFT", 2, 1)
    dryRun.text:SetText("Dry Run")
    dryRun.text:SetTextColor(0.9, 0.8, 0.45, 1)

    local applyBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    applyBtn:SetSize(68, 22)
    applyBtn:SetPoint("TOPRIGHT", header, "TOPRIGHT", -18, -27)
    applyBtn:SetText("Apply")

    local resetTalentsBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    resetTalentsBtn:SetSize(104, 22)
    resetTalentsBtn:SetPoint("RIGHT", applyBtn, "LEFT", -6, 0)
    resetTalentsBtn:SetText("Reset N/A")

    local resetBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    resetBtn:SetSize(54, 22)
    resetBtn:SetPoint("RIGHT", resetTalentsBtn, "LEFT", -6, 0)
    resetBtn:SetText("Clear")

    local refreshBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    refreshBtn:SetSize(64, 22)
    refreshBtn:SetPoint("RIGHT", resetBtn, "LEFT", -6, 0)
    refreshBtn:SetText("Refresh")

    local treeSelector = CreateFrame("Frame", nil, panel)
    treeSelector:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    treeSelector:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -8)
    treeSelector:SetHeight(42)
    PBAM.ApplyBackdrop(treeSelector, 0.35)

    local treeButtons = {}
    local dropdownBtn, selectedBuildText
    local updateApplyState
    local function updateTreeButtons()
        for i, btn in ipairs(treeButtons) do
            if i == panel.ActiveTalentTree then
                btn:LockHighlight()
            else
                btn:UnlockHighlight()
            end
        end
    end

    local body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT", treeSelector, "BOTTOMLEFT", 0, -8)
    body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -MARGIN, MARGIN)
    PBAM.ApplyBackdrop(body, 0.35)

    local scroll = CreateFrame("ScrollFrame", nil, body)
    scroll:SetPoint("TOPLEFT", body, "TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -8, 8)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, cur - delta * 30)))
    end)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(670, 720)
    scroll:SetScrollChild(content)

    local function makeCard(i)
        local card = CreateFrame("Frame", nil, content)
        card:SetSize(430, 650)
        card:SetPoint("TOP", content, "TOP", 0, -8)
        PBAM.ApplyBackdrop(card, 0.3)
        card.bg = card:CreateTexture(nil, "BORDER")
        card.bg:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -12) 
        card.bg:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -12, 24) -- was 58
        card.bg:SetTexCoord(0, 1, 0, 1)
        card.bg:SetVertexColor(1, 1, 1, 0.82)
        card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        card.title:SetPoint("TOP", card, "TOP", 0, -9)
        card.points = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        card.points:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -10)
        card.points:SetTextColor(1, 0.82, 0.1, 1)
        card.icons = {}
        card.arrows = {}
        card.note = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        card.note:SetPoint("TOP", card.bg, "BOTTOM", 0, -6)
        card.note:SetTextColor(0.8, 0.8, 0.8, 1)
        cards[i] = card
    end
    for i=1,3 do makeCard(i) end
    panel.ActiveTalentTree = 1

    local function showActiveTalentTree(treeIndex)
        panel.ActiveTalentTree = treeIndex or panel.ActiveTalentTree or 1
        for i, card in ipairs(cards) do
            if i == panel.ActiveTalentTree then card:Show() else card:Hide() end
        end
        updateTreeButtons()
    end

    for i=1,3 do
        local btn = CreateFrame("Button", nil, treeSelector, "UIPanelButtonTemplate")
        btn:SetSize(170, 24)
        btn:SetPoint("CENTER", treeSelector, "CENTER", (i - 2) * 180, -1)
        btn:SetText("Tree " .. i)
        btn:SetScript("OnClick", function() showActiveTalentTree(i) end)
        treeButtons[i] = btn
    end
    showActiveTalentTree(1)

    local renderTalentGrid

    local function clearTalentIcons(card)
        for _, icon in ipairs(card.icons or {}) do icon:Hide() end
        for _, arrow in ipairs(card.arrows or {}) do arrow:Hide() end
    end

    local function refreshRenderedTrees()
        if not panel.CurrentTalentClassKey then return end
        -- When editing (dirty), use TalentPlan; otherwise use LiveTalentRanks for viewing
        local sourceRanks = panel.TalentPlanDirty and panel.TalentPlan or (panel.TalentPlanHasLive and panel.LiveTalentRanks or panel.TalentPlan)
        for tree=1,3 do
            local c = cards[tree]
            local pts = sourceRanks and sourceRanks[tree] and countTreePoints(sourceRanks, tree) or 0
            c.points:SetText(tostring(pts) .. " pts")
            c.note:SetText(panel.TalentPlanDirty and "Custom build pending" or (pts == 0 and "No points in this tree" or (tostring(pts) .. " points in tree")))
            renderTalentGrid(c, panel.CurrentTalentClassKey, tree, pts)
        end
        updateApplyState()
    end

    local function canIncreaseTalent(treeIndex, talentIndex, maxRank, needIndex, tier)
        -- Use TalentPlan when editing, otherwise use LiveTalentRanks for viewing bot talents
        local plan = panel.TalentPlanDirty and panel.TalentPlan or (panel.TalentPlanHasLive and panel.LiveTalentRanks or panel.TalentPlan)
        if not plan or not plan[treeIndex] then return false, "No talent plan loaded" end
        local current = tonumber(plan[treeIndex][talentIndex]) or 0
        if current >= maxRank then return false, "Talent is already at max rank" end
        if needIndex > 0 and ((tonumber(plan[treeIndex][needIndex]) or 0) <= 0) then return false, "Requires linked prerequisite talent" end
        local requiredTreePoints = math.max(0, (tonumber(tier) or 1) - 1) * 5
        if countTreePoints(plan, treeIndex) < requiredTreePoints then return false, "Requires " .. tostring(requiredTreePoints) .. " points in this tree" end
        return true
    end

    local function canDecreaseTalent(treeIndex, talentIndex)
        -- Use TalentPlan when editing, otherwise use LiveTalentRanks for viewing bot talents
        local plan = panel.TalentPlanDirty and panel.TalentPlan or (panel.TalentPlanHasLive and panel.LiveTalentRanks or panel.TalentPlan)
        if not plan or not plan[treeIndex] or (tonumber(plan[treeIndex][talentIndex]) or 0) <= 0 then return false, "Talent has no points" end
        local talentData = PBAM.data and PBAM.data.talent and PBAM.data.talent.talents
        local treeData = talentData and talentData[panel.CurrentTalentClassKey] and talentData[panel.CurrentTalentClassKey][treeIndex]
        for idx, raw in ipairs(treeData or {}) do
            local data = splitCsv(raw)
            local need = tonumber(data[1]) or 0
            if need == talentIndex and (tonumber(plan[treeIndex][idx]) or 0) > 0 then
                return false, "Remove dependent talents first"
            end
        end
        return true
    end

    local function changeTalentRank(treeIndex, talentIndex, delta, maxRank, needIndex, tier)
        if delta > 0 then
            local ok, reason = canIncreaseTalent(treeIndex, talentIndex, maxRank, needIndex, tier)
            if not ok then setTextSafe(status, reason); return end
            panel.TalentPlan[treeIndex][talentIndex] = (tonumber(panel.TalentPlan[treeIndex][talentIndex]) or 0) + 1
        elseif delta < 0 then
            local ok, reason = canDecreaseTalent(treeIndex, talentIndex)
            if not ok then setTextSafe(status, reason); return end
            panel.TalentPlan[treeIndex][talentIndex] = math.max(0, (tonumber(panel.TalentPlan[treeIndex][talentIndex]) or 0) - 1)
        end
        panel.TalentPlanDirty = true
        panel.SelectedTalentBuild = nil
        dropdownBtn:SetText("Custom build")
        selectedBuildText:SetText("Custom rank link pending: " .. tostring(countAllPoints(panel.TalentPlan)) .. " point(s)")
        setTextSafe(status, "Custom talent build edited. Click Apply to send full rank link.")
        refreshRenderedTrees()
    end

    function renderTalentGrid(card, key, treeIndex, treePoints)
        clearTalentIcons(card)
        local talentInfo = PBAM.data and PBAM.data.talent
        local talentData = talentInfo and talentInfo.talents
        local arrowData = talentInfo and talentInfo.arrows
        local treeData = talentData and talentData[key] and talentData[key][treeIndex]
        if not treeData then return end

        local iconSize = 65 --was 44 Bigger is bigger icons
        local colGap = 54 -- was 78 Spacing between cols.
        local rowGap = 56 -- was 46 Spacing between rows. 
        local startX = 112 --was 48 Increase to move buttons to the right. 
        local startY = -12 --was 62

        -- When editing (dirty), use TalentPlan for live updates; otherwise use LiveTalentRanks for viewing
        local sourceRanks = panel.TalentPlanDirty and panel.TalentPlan and panel.TalentPlan[treeIndex]
                              or (panel.TalentPlanHasLive and panel.LiveTalentRanks and panel.LiveTalentRanks[treeIndex])
                              or (panel.TalentPlan and panel.TalentPlan[treeIndex])

        local arrows = arrowData and arrowData[key] and arrowData[key][treeIndex]
        for j, raw in ipairs(arrows or {}) do
            local data = splitCsv(raw)
            local needIndex = tonumber(data[1]) or 0
            local col = tonumber(data[2]) or 1
            local tier = tonumber(data[3]) or 1
            local tex = data[4] or "Down_Arrow"
            local arrow = card.arrows[j]
            if not arrow then
                arrow = card:CreateTexture(nil, "BORDER")
                arrow:SetSize(72, 72) -- was 54, 54
                card.arrows[j] = arrow
            end
            arrow:ClearAllPoints()
            -- Arrow direction offsets for proper alignment
            local xOffset, yOffset = -5, 5
            arrow:SetPoint("TOPLEFT", card, "TOPLEFT", startX + ((col - 1) * colGap) + xOffset, startY - ((tier - 1) * rowGap) + yOffset)

            -- Match PlayerbotManager behavior: silver means the dependency path exists,
            -- gold means the prerequisite talent currently has at least one rank.
            -- When viewing live bot talents, use LiveTalentRanks; when editing a custom build,
            -- use TalentPlan.
            local exactRank = sourceRanks and sourceRanks[needIndex]
            local active = (tonumber(exactRank) or 0) > 0

            arrow:SetTexture(ADDON_TEX .. "Talent_" .. (active and "Gold_" or "Silver_") .. tex .. ".blp")
            arrow:SetVertexColor(1, 1, 1, 1)
            arrow:Show()
        end
        for j, raw in ipairs(treeData) do
            local data = splitCsv(raw)
            local col = tonumber(data[2]) or 1
            local tier = tonumber(data[3]) or 1
            local texture = data[4] or "INV_Misc_QuestionMark"
            local maxRank = math.max(1, #data - 4)
            local icon = card.icons[j]
            if not icon then
                icon = CreateFrame("Button", nil, card)
                icon:SetSize(iconSize, iconSize)
                icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                icon.tex = icon:CreateTexture(nil, "ARTWORK")
                icon.tex:SetPoint("TOPLEFT", icon, "TOPLEFT", 14, -14) -- was 6, -6 --makes frame bigger
                icon.tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -14, 14) -- was -6, 6 --makes frame bigger
                icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                icon.border = icon:CreateTexture(nil, "OVERLAY")
                icon.border:SetAllPoints(icon)
                icon.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
                icon.rank = icon:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                icon.rank:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -3, 8) --Stock was 3, -2
                icon:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:ClearLines()
                    if self.spellId and self.spellId > 0 and GameTooltip.SetHyperlink then
                        GameTooltip:SetHyperlink("spell:" .. tostring(self.spellId))
                    else
                        GameTooltip:AddLine(self.talentName or "Talent", 1, 0.82, 0)
                    end
                    GameTooltip:AddLine("Max rank: " .. tostring(self.maxRank or 1), 0.75, 0.75, 0.75)
                    GameTooltip:AddLine("Left-click: add rank  |  Right-click: remove rank", 0.6, 0.8, 1, true)
                    GameTooltip:Show()
                end)
                icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
                icon:SetScript("OnClick", function(self, button)
                    changeTalentRank(self.treeIndex, self.talentIndex, button == "RightButton" and -1 or 1, self.maxRank or 1, self.needIndex or 0, self.tier or 1)
                end)
                card.icons[j] = icon
            end
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", card, "TOPLEFT", startX + ((col - 1) * colGap), startY - ((tier - 1) * rowGap))
            icon.treeIndex = treeIndex
            icon.talentIndex = j
            icon.needIndex = tonumber(data[1]) or 0
            icon.tier = tier
            icon.spellId = tonumber(data[5]) or 0
            icon.maxRank = maxRank
            icon.talentName = icon.spellId > 0 and GetSpellInfo and GetSpellInfo(icon.spellId) or "Talent"
            -- When editing (dirty), use TalentPlan for live updates; otherwise use LiveTalentRanks for viewing
            local sourceRanks = panel.TalentPlanDirty and panel.TalentPlan and panel.TalentPlan[treeIndex]
                                  or (panel.TalentPlanHasLive and panel.LiveTalentRanks and panel.LiveTalentRanks[treeIndex])
                                  or (panel.TalentPlan and panel.TalentPlan[treeIndex])
            local displayRank = sourceRanks and sourceRanks[j]
            icon.tex:SetTexture("Interface\\Icons\\" .. texture)
            -- Desaturate only if this specific talent has 0 points
            icon.tex:SetDesaturated(tonumber(displayRank or 0) == 0)
            icon.rank:SetText((displayRank ~= nil and tostring(displayRank) or "-") .. "/" .. tostring(maxRank))
            icon:Show()
        end
    end

    local specPanel = CreateFrame("Frame", nil, content)
    specPanel:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -670)
    specPanel:SetSize(648, 52)
    PBAM.ApplyBackdrop(specPanel, 0.25)

    local specTitle = specPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    specTitle:SetPoint("LEFT", specPanel, "LEFT", 12, 8)
    specTitle:SetText("Available Build")
    specTitle:SetTextColor(0.9, 0.78, 0.35, 1)

    dropdownBtn = CreateFrame("Button", nil, specPanel, "UIPanelButtonTemplate")
    dropdownBtn:SetSize(230, 24)
    dropdownBtn:SetPoint("LEFT", specTitle, "RIGHT", 12, 0)
    dropdownBtn:SetText("Select build...")

    selectedBuildText = specPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    selectedBuildText:SetPoint("LEFT", dropdownBtn, "RIGHT", 12, 0)
    selectedBuildText:SetPoint("RIGHT", specPanel, "RIGHT", -12, 0)
    selectedBuildText:SetJustifyH("LEFT")
    selectedBuildText:SetTextColor(0.65, 0.65, 0.65, 1)
    selectedBuildText:SetText("Bridge premade specs load here.")

    local dropdownMenu = CreateFrame("Frame", nil, specPanel)
    dropdownMenu:SetPoint("BOTTOMLEFT", dropdownBtn, "TOPLEFT", 0, 4)
    dropdownMenu:SetSize(360, 150)
    dropdownMenu:SetFrameLevel(specPanel:GetFrameLevel() + 10)
    PBAM.ApplyBackdrop(dropdownMenu, 0.95)
    dropdownMenu:Hide()

    function updateApplyState()
        if PBAM.SelectedBot and (panel.SelectedTalentBuild or panel.TalentPlanDirty) then
            applyBtn:Enable()
        else
            applyBtn:Disable()
        end
    end

    local function selectSpec(spec)
        panel.SelectedTalentBuild = spec
        panel.TalentPlanDirty = false
        dropdownMenu:Hide()
        dropdownBtn:SetText(spec and ("#" .. tostring(spec.index or "?") .. " " .. tostring(spec.name or "Unnamed")) or "Select build...")
        selectedBuildText:SetText(spec and ((spec.build and spec.build ~= "" and ("Point summary: " .. spec.build .. "  •  applies by premade spec name") or "Applies by premade spec name")) or "Bridge premade specs load here.")
        if spec then
            setTextSafe(status, "Selected: " .. tostring(spec.name or "Unnamed") .. " (will apply by premade spec name)")
            local previewVals = parsePointSummary(spec.build)
            if previewVals and panel.CurrentTalentClassKey then
                local best = 1
                if (previewVals[2] or 0) > (previewVals[best] or 0) then best = 2 end
                if (previewVals[3] or 0) > (previewVals[best] or 0) then best = 3 end
                for tree=1,3 do
                    local c = cards[tree]
                    c.points:SetText(tostring(previewVals[tree] or 0) .. " pts")
                    c.note:SetText("Selected build preview")
                    renderTalentGrid(c, panel.CurrentTalentClassKey, tree, previewVals[tree] or 0)
                end
                showActiveTalentTree(best)
            end
        end
        updateApplyState()
    end

    local function paintSpecRows()
        local botName = PBAM.SelectedBot
        local specs = {}
        if botName and PBAM.Bridge.TalentSpecs then
            local cache = PBAM.Bridge.TalentSpecs[string.lower(botName)]
            specs = (cache and cache.specs) or {}
        end

        for _, row in ipairs(specRows) do row:Hide() end
        if #specs == 0 then
            dropdownBtn:SetText("No builds loaded")
            selectedBuildText:SetText("Use Refresh or verify TALENT_SPEC_LIST support.")
            dropdownMenu:Hide()
        elseif not panel.SelectedTalentBuild then
            dropdownBtn:SetText("Select build...")
            selectedBuildText:SetText(tostring(#specs) .. " bridge premade build(s) available.")
        end

        dropdownMenu:SetHeight(math.max(28, math.min(#specs, 8) * 24 + 8))
        for i, spec in ipairs(specs) do
            local row = specRows[i]
            if not row then
                row = CreateFrame("Button", nil, dropdownMenu)
                row:SetHeight(22)
                row:SetPoint("TOPLEFT", dropdownMenu, "TOPLEFT", 6, -4 - ((i - 1) * 24))
                row:SetPoint("RIGHT", dropdownMenu, "RIGHT", -6, 0)
                row.bg = row:CreateTexture(nil, "BACKGROUND")
                row.bg:SetAllPoints()
                row.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
                row.index = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.index:SetPoint("LEFT", row, "LEFT", 8, 0)
                row.index:SetWidth(34)
                row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.name:SetPoint("LEFT", row.index, "RIGHT", 4, 0)
                row.name:SetWidth(130)
                row.name:SetJustifyH("LEFT")
                row.build = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.build:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
                row.build:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                row.build:SetJustifyH("LEFT")
                row.build:SetTextColor(0.68, 0.68, 0.68, 1)
                specRows[i] = row
            end
            row.spec = spec
            row.index:SetText("#" .. tostring(spec.index or i))
            row.name:SetText(spec.name or "Unnamed")
            row.build:SetText(spec.build and spec.build ~= "" and ("summary " .. spec.build) or "named spec")
            row.bg:SetVertexColor(panel.SelectedTalentBuild == spec and 0.45 or 0.1, panel.SelectedTalentBuild == spec and 0.34 or 0.1, panel.SelectedTalentBuild == spec and 0.08 or 0.1, 0.92)
            row:SetScript("OnClick", function(self) selectSpec(self.spec); paintSpecRows() end)
            if i <= 8 then row:Show() else row:Hide() end
        end
        updateApplyState()
    end

    dropdownBtn:SetScript("OnClick", function()
        if dropdownMenu:IsShown() then dropdownMenu:Hide() else paintSpecRows(); dropdownMenu:Show() end
    end)

    function panel:RefreshTalents()
        local botName = PBAM.SelectedBot
        if not botName then return end
        setTextSafe(status, "Refreshing talents...")
        PBAM.Bridge.RequestBotDetail(botName)
        PBAM.Bridge.RequestTalentSpecList(botName)
        local unit = PBAM.FindBotUnit and PBAM.FindBotUnit(botName) or nil
        if unit and InspectUnit then InspectUnit(unit) end
        after(0.35, function()
            panel.LiveTalentRanks = collectLiveTalentRanks(botName)
            panel.TalentPlanHasLive = panel.LiveTalentRanks ~= nil
            if panel.CurrentTalentClassKey then panel.TalentPlan = makeTalentPlan(panel.CurrentTalentClassKey, panel.LiveTalentRanks) end
            panel.TalentPlanDirty = false
            if panel.OnBotSelect then panel.OnBotSelect(botName) end
        end)
    end

    function panel:ResetTalents()
        setTextSafe(status, "Reset talents is not supported by current playerbot commands; bridge/server endpoint needed.")
    end

    function panel:ApplySelectedTalent(fromConfirmation)
        local botName = PBAM.SelectedBot
        local spec = self.SelectedTalentBuild
        if not botName or (not spec and not self.TalentPlanDirty) then
            setTextSafe(status, "Select a premade build or edit individual talents first.")
            return
        end

        if self.DryRun and not fromConfirmation then
            local desc
            if self.TalentPlanDirty then
                desc = "Custom talent build\nPoints: " .. tostring(countAllPoints(self.TalentPlan))
            else
                desc = tostring(spec.name or "Unnamed")
                if spec.build and spec.build ~= "" then desc = desc .. "\nPoint summary: " .. tostring(spec.build) end
            end
            StaticPopup_Show("PBAM_CONFIRM_TALENT_APPLY", botName, desc, { panel = self })
            return
        end

        -- Legacy fallback by design for now. The surrounding selection/confirmation flow is kept
        -- separate so a future RUN~TALENT_APPLY bridge endpoint can replace only this execution path.
        -- TODO bridge-talents: swap these legacy whisper calls to PBAM.Bridge.ApplyTalentBuild(...)
        -- when a native RUN~TALENT_APPLY endpoint exists.
        if self.TalentPlanDirty then
            local link = buildTalentApplyString(self.TalentPlan)
            if not link or link == "--" then
                setTextSafe(status, "Could not apply: custom talent plan is empty.")
                return
            end
            SendChatMessage("stopcasting", "WHISPER", nil, botName)
            SendChatMessage("talents switch 1", "WHISPER", nil, botName)
            after(0.45, function() SendChatMessage("talents apply " .. link, "WHISPER", nil, botName) end)
            setTextSafe(status, "Applied custom rank link via legacy whisper.")
            self.TalentPlanDirty = false
            refreshAfterTalentApply(botName)
            after(2.0, function() if panel.RefreshTalents then panel:RefreshTalents() end end)
        elseif sendTalentApplyWhisper(botName, spec) then
            setTextSafe(status, "Applied named premade via legacy whisper: " .. tostring(spec.name or "selected build"))
            refreshAfterTalentApply(botName)
            after(2.0, function() if panel.RefreshTalents then panel:RefreshTalents() end end)
        else
            setTextSafe(status, "Could not apply: selected build has no name or build string.")
        end
    end

    panel.OnRefresh = function(botName)
        if not botName then return end
        PBAM.SelectedBot = botName
        panel:RefreshTalents()
    end

    refreshBtn:SetScript("OnClick", function() panel:RefreshTalents() end)
    applyBtn:SetScript("OnClick", function() panel:ApplySelectedTalent(false) end)
    resetTalentsBtn:SetScript("OnClick", function() panel:ResetTalents() end)
    resetTalentsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Reset talents unavailable", 1, 0.82, 0)
        GameTooltip:AddLine("Current playerbot commands reject all-zero talent links.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Needs a future bridge/server reset endpoint.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    resetTalentsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    resetBtn:SetScript("OnClick", function()
        panel.SelectedTalentBuild = nil
        panel.TalentPlanDirty = false
        if panel.CurrentTalentClassKey then panel.TalentPlan = makeTalentPlan(panel.CurrentTalentClassKey, panel.LiveTalentRanks) end
        dropdownMenu:Hide()
        dropdownBtn:SetText("Select build...")
        selectedBuildText:SetText("Selection cleared.")
        setTextSafe(status, "Selection cleared.")
        refreshRenderedTrees()
        paintSpecRows()
    end)
    updateApplyState()

    if not panel._talentCallbacksRegistered then
        PBAM.Bridge.RegisterCallback("TalentSpecsUpdated", function(botName)
            if botName == PBAM.SelectedBot and PBAM.CurrentTab == "Talents" then
                paintSpecRows()
                setTextSafe(status, "Talent builds loaded from bridge.")
            end
        end)
        PBAM.Bridge.RegisterCallback("BotDetailUpdated", function(detail)
            if detail and detail.name == PBAM.SelectedBot and PBAM.CurrentTab == "Talents" and panel.OnBotSelect then
                panel.OnBotSelect(detail.name)
            end
        end)
        panel._talentCallbacksRegistered = true
    end

    panel.OnBotSelect = function(botName)
        local switchingBot = panel.LastTalentBotName ~= botName
        panel.LastTalentBotName = botName
        panel.SelectedTalentBuild = nil
        if switchingBot then panel.TalentPlanDirty = false; panel.TalentPlan = nil; panel.LiveTalentRanks = nil; panel.TalentPlanHasLive = false end
        dropdownMenu:Hide()
        dropdownBtn:SetText("Select build...")
        selectedBuildText:SetText("Bridge premade specs load here.")
        PBAM.SetButtonEnabled(refreshBtn, botName and botName ~= "", "Select a bot to refresh talents.")
        PBAM.SetButtonEnabled(applyBtn, botName and botName ~= "", "Select a bot before applying talents.")
        PBAM.SetButtonEnabled(resetBtn, botName and botName ~= "", "Select a bot before clearing talent selections.")
        PBAM.SetButtonEnabled(resetTalentsBtn, botName and botName ~= "", "Select a bot to inspect reset talent options.")
        if not botName then emptyFs:Show(); header:Hide(); body:Hide(); return end
        emptyFs:Hide(); header:Show(); body:Show()
        setTextSafe(status, "Requesting talent builds from bridge...")
        PBAM.Bridge.RequestTalentSpecList(botName)

        local detail = PBAM.Bridge.Details and PBAM.Bridge.Details[string.lower(botName)]
        if not detail then
            PBAM.Bridge.RequestBotDetail(botName)
            summary:SetText("Requesting talent details...")
            paintSpecRows()
            return
        end
        local key = classKey(detail.className)
        panel.CurrentTalentClassKey = key
        -- Always refresh live ranks when bot detail updates (e.g., after applying talents)
        -- but keep existing ranks if collection fails to avoid flickering
        local freshRanks = collectLiveTalentRanks(botName)
        if freshRanks then panel.LiveTalentRanks = freshRanks end
        panel.TalentPlanHasLive = panel.LiveTalentRanks ~= nil
        if not panel.TalentPlan or not panel.TalentPlanDirty then panel.TalentPlan = makeTalentPlan(key, panel.LiveTalentRanks) end
        local names = FALLBACK_NAMES[key] or {"Tree 1", "Tree 2", "Tree 3"}
        local vals = { tonumber(detail.talent1) or 0, tonumber(detail.talent2) or 0, tonumber(detail.talent3) or 0 }
        local total = vals[1] + vals[2] + vals[3]
        local main = 1; if vals[2] > vals[main] then main = 2 end; if vals[3] > vals[main] then main = 3 end
        for i=1,3 do
            if treeButtons[i] then treeButtons[i]:SetText((names[i] or ("Tree " .. i)) .. "  " .. tostring(vals[i]) .. " pts") end
        end
        showActiveTalentTree(panel.ActiveTalentTree or main)
        summary:SetText(string.format("%s — %s points: %d / %d / %d \nMain tree: %s", botName, detail.className or "Unknown", vals[1], vals[2], vals[3], names[main] or "Tree"))
        for i=1,3 do
            local c = cards[i]
            c.bg:SetTexture(ADDON_TEX .. "Talent_" .. key .. i .. ".blp")
            c.title:SetText(names[i] or ("Tree " .. i))
            c.points:SetText(tostring(vals[i]) .. " pts")
            c.note:SetText(vals[i] == 0 and "No points in this tree" or (tostring(vals[i]) .. " points in tree"))
            renderTalentGrid(c, key, i, vals[i])
            c:SetAlpha(total == 0 and 0.72 or (i == main and 1 or 0.88))
        end
        paintSpecRows()
    end
end, { hideForPlayer = true })
