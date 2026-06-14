-- ============================================================
--  PBAM_Tab_Professions.lua  |  Professions tab
-- ============================================================

PBAM = PBAM or {}

local SECONDARY = { cooking=true, fishing=true, firstaid=true, ["first aid"]=true }
local ICONS = {
    alchemy="Interface\\Icons\\Trade_Alchemy", blacksmithing="Interface\\Icons\\Trade_BlackSmithing", enchanting="Interface\\Icons\\Trade_Engraving",
    engineering="Interface\\Icons\\Trade_Engineering", herbalism="Interface\\Icons\\Trade_Herbalism", inscription="Interface\\Icons\\INV_Inscription_Tradeskill01",
    jewelcrafting="Interface\\Icons\\INV_Misc_Gem_01", leatherworking="Interface\\Icons\\Trade_LeatherWorking", mining="Interface\\Icons\\Trade_Mining",
    skinning="Interface\\Icons\\INV_Misc_Pelt_Wolf_01", tailoring="Interface\\Icons\\Trade_Tailoring", cooking="Interface\\Icons\\INV_Misc_Food_15",
    fishing="Interface\\Icons\\Trade_Fishing", firstaid="Interface\\Icons\\Spell_Holy_SealOfSacrifice", ["first aid"]="Interface\\Icons\\Spell_Holy_SealOfSacrifice",
}

local SKILL_ID_FALLBACKS = { cooking=185, firstaid=129, ["first aid"]=129, fishing=356, mining=186 }

-- Empty-state message position when no bot is selected.
-- Adjust X to move left/right and Y to move up/down.
local EMPTY_MESSAGE_X_OFFSET = -215
local EMPTY_MESSAGE_Y_OFFSET = 0

local function NiceName(s)
    s = tostring(s or "")
    local key = string.lower(s):gsub("%s+", "")
    if key == "firstaid" then return "First Aid" end
    return (s:gsub("_", " "):gsub("^%l", string.upper))
end

local function RecipeName(recipe)
    local itemId = tonumber(recipe and recipe.itemId) or 0
    local spellId = tonumber(recipe and recipe.spellId) or 0
    local itemName, itemLink = nil, nil
    if itemId > 0 and GetItemInfo then itemName, itemLink = GetItemInfo(itemId) end
    local spellName = spellId > 0 and GetSpellInfo and GetSpellInfo(spellId) or nil
    return itemLink or itemName or spellName or ("Recipe #" .. tostring(spellId))
end

local function DifficultyColor(difficulty)
    difficulty = string.lower(tostring(difficulty or ""))
    if difficulty == "orange" then return "|cffff8040" end
    if difficulty == "yellow" then return "|cffffff00" end
    if difficulty == "green" then return "|cff40ff40" end
    if difficulty == "gray" or difficulty == "grey" then return "|cff808080" end
    return "|cffffffff"
end

local function CraftReason(reason)
    reason = tostring(reason or "")
    local map = {
        OK = "Craft started.", NO_MATERIALS = "Missing materials.", REQUIRES_SPELL_FOCUS = "Requires a nearby profession tool or focus.",
        MOVING = "Bot is moving.", UNKNOWN_RECIPE = "Bot does not know this recipe.", MISSING_PROFESSION = "Bot does not have that profession.",
        INVALID_BOT = "Bot is unavailable.", INVALID_RECIPE = "Invalid recipe.", SILENCED = "Bot cannot cast right now.", COOLDOWN = "Recipe is on cooldown.",
    }
    return map[reason] or (reason ~= "" and reason or "Unknown bridge result.")
end

-- Profession skill lines also include utility spells that are not recipes. Add newly discovered
-- unwanted entries here by lower-case spell name, or by a Lua pattern when exact rank/localization
-- varies. Keep this as a deny-list instead of requiring itemId because enchants do not create items.
local HIDDEN_RECIPE_SPELL_NAMES = {
    -- Main Skills to hide
    ["enchanting"] = true,
    ["tailoring"] = true,
    ["blacksmithing"] = true,
    ["herbalism"] = true,
    ["engineering"] = true,
    ["alchemy"] = true,
    ["leatherworking"] = true,
    ["skinning"] = true,
    ["jewelcrafting"] = true,
    ["inscription"] = true,
    ["mining"] = true,
    ["smelting"] = true,
    -- Secondary spell names to hide
    ["cooking"] = true,
    ["first aid"] = true,
    ["fishing"] = true,
    -- Not related to Crafting
    ["herb gathering"] = true,
    ["find minerals"] = true,
    ["find herbs"] = true,
    ["find fish"] = true,
    -- Specific things to hide until implemented functionality
    ["disenchant"] = true,
}

local HIDDEN_RECIPE_SPELL_PATTERNS = {
    -- Example: "^smelt ", -- uncomment/add if a non-craft utility family should be hidden later
    "^mill ",
    "^enchant ",
}

-- Special clickable profession spells that are useful in the recipe list but do not behave like
-- material-consuming recipes. Add future exceptions by spell id here.
-- fields:
--   alwaysCraftable = enables Craft even when bridge craftable count is 0
--   disableCraftAll = disables All because this is a utility/repeatable spell, not batch crafting
--   legacyCast = uses /w bot cast <spellId> instead of CRAFT_RECIPE when bridge validation requires materials
--   label = optional info suffix shown on the recipe row
--   forceWhiteName = keeps utility rows from looking disabled/gray due to profession difficulty color
local SPECIAL_RECIPE_SPELLS = {
    [818] = { alwaysCraftable=true, disableCraftAll=true, legacyCast=true, forceWhiteName=true, label="Utility: creates a campfire" }, -- Basic Campfire
}

local function IsHiddenRecipeSpell(recipe)
    local name = RecipeName(recipe):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    name = string.lower(tostring(name or ""))
    if HIDDEN_RECIPE_SPELL_NAMES[name] then return true end
    for _, pattern in ipairs(HIDDEN_RECIPE_SPELL_PATTERNS) do
        if string.find(name, pattern) then return true end
    end
    return false
end

local function SpecialRecipe(recipe)
    return SPECIAL_RECIPE_SPELLS[tonumber(recipe and recipe.spellId) or 0]
end

local function ParseMaterials(materials)
    local out = {}
    for entry in string.gmatch(tostring(materials or ""), "([^;]+)") do
        local itemId, required, available = string.match(entry, "^(%d+):(%d+):(%d+)$")
        if itemId then
            table.insert(out, { itemId=tonumber(itemId) or 0, required=tonumber(required) or 0, available=tonumber(available) or 0 })
        end
    end
    return out
end

local function SkillKey(e)
    return string.lower(tostring((e and (e.key or e.name or e.displayName)) or "")):gsub("%s+", "")
end

local function SkillId(e)
    local id = tonumber(e and e.id) or 0
    if id > 0 then return id end
    return SKILL_ID_FALLBACKS[SkillKey(e)] or 0
end

PBAM.RegisterTab("Professions", "Professions", 4, function(panel)
    local MARGIN, PROF_ROW_H, RECIPE_ROW_H = 12, 52, 72
    local profRows, recipeRows = {}, {}
    local selectedSkillId, selectedSkillName, statusText, lastBotName
    local craftQueue = { active=false, remaining=0, botName=nil, skillId=0, spellId=0, itemId=0, recipeName="", waiting=false }
    local queueTimer = CreateFrame("Frame", nil, panel)
    queueTimer:Hide()
    queueTimer:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed < 3.25 then return end
        self.elapsed = 0
        if not craftQueue.active or craftQueue.waiting or craftQueue.remaining <= 0 then self:Hide(); return end
        craftQueue.waiting = true
        statusText:SetText("Craft All: crafting " .. tostring(craftQueue.recipeName) .. " (" .. tostring(craftQueue.remaining) .. " left)...")
        PBAM.Bridge.CraftRecipe(craftQueue.botName, craftQueue.skillId, craftQueue.spellId, craftQueue.itemId)
    end)

    local function refresh(botName)
        if botName == PBAM.SelectedBot and PBAM.CurrentTab == "Professions" and panel.OnBotSelect then panel.OnBotSelect(botName) end
    end
    PBAM.Bridge.RegisterCallback("CraftingUpdated", refresh)
    PBAM.Bridge.RegisterCallback("BotSkillsUpdated", refresh)
    PBAM.Bridge.RegisterCallback("ProfessionRecipesUpdated", function(botName, skillId)
        if botName == PBAM.SelectedBot and tonumber(skillId) == tonumber(selectedSkillId) and panel.RefreshRecipes then panel.RefreshRecipes() end
    end)
    PBAM.Bridge.RegisterCallback("ProfessionCraftResult", function(result)
        if result and result.botName == PBAM.SelectedBot and statusText then
            local ok = result.result == "OK"
            if craftQueue.active and result.token and ok then
                craftQueue.remaining = math.max(0, (tonumber(craftQueue.remaining) or 0) - 1)
                craftQueue.waiting = false
                PBAM.Bridge.RequestProfessionRecipes(result.botName, result.skillId)
                if craftQueue.remaining > 0 then
                    statusText:SetText("|cff40ff40Craft queued. Waiting for cast to finish; " .. tostring(craftQueue.remaining) .. " left.|r")
                    queueTimer.elapsed = 0; queueTimer:Show()
                else
                    statusText:SetText("|cff40ff40Craft All complete. Refreshing recipe counts...|r")
                    craftQueue.active = false; queueTimer:Hide()
                end
            elseif craftQueue.active and not ok then
                craftQueue.active = false; craftQueue.waiting = false; queueTimer:Hide()
                statusText:SetText("|cffff6060Craft All stopped: " .. CraftReason(result.reason) .. "|r")
                PBAM.Bridge.RequestProfessionRecipes(result.botName, result.skillId)
            else
                statusText:SetText((ok and "|cff40ff40" or "|cffff6060") .. CraftReason(ok and "OK" or result.reason) .. "|r")
                if ok then PBAM.Bridge.RequestProfessionRecipes(result.botName, result.skillId) end
            end
        end
    end)

    local emptyFs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyFs:SetPoint("CENTER", panel, "CENTER", EMPTY_MESSAGE_X_OFFSET, EMPTY_MESSAGE_Y_OFFSET)
    emptyFs:SetText("Select a bot to view professions")
    emptyFs:SetTextColor(0.55, 0.55, 0.55, 1)

    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", MARGIN, -MARGIN)
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -MARGIN, -MARGIN)
    header:SetHeight(52)
    PBAM.ApplyBackdrop(header, 0.55)
    PBAM.CreateSectionHeader(header, "Professions", -10, 13)
    local refreshBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    refreshBtn:SetSize(86,22); refreshBtn:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -17, 6); refreshBtn:SetText("Refresh")

    local profScroll = CreateFrame("ScrollFrame", nil, panel)
    profScroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    profScroll:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", MARGIN, MARGIN)
    profScroll:SetWidth(260); profScroll:EnableMouseWheel(true)
    profScroll:SetScript("OnMouseWheel", function(self, delta) self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 28))) end)
    local profContent = CreateFrame("Frame", nil, profScroll)
    profContent:SetWidth(250); profScroll:SetScrollChild(profContent); PBAM.ApplyBackdrop(profContent, 0.35)

    local recipesPanel = CreateFrame("Frame", nil, panel)
    recipesPanel:SetPoint("TOPLEFT", profScroll, "TOPRIGHT", 8, 0)
    recipesPanel:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -MARGIN, MARGIN)
    PBAM.ApplyBackdrop(recipesPanel, 0.35)
    local recipeTitle = recipesPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    recipeTitle:SetPoint("TOPLEFT", recipesPanel, "TOPLEFT", 10, -10)
    recipeTitle:SetText("Recipes")
    statusText = recipesPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("TOPLEFT", recipeTitle, "BOTTOMLEFT", 0, -4)
    statusText:SetPoint("RIGHT", recipesPanel, "RIGHT", -10, 0)
    statusText:SetJustifyH("LEFT")
    panel.StatusText = statusText
    local recipeScroll = CreateFrame("ScrollFrame", nil, recipesPanel)
    recipeScroll:SetPoint("TOPLEFT", recipesPanel, "TOPLEFT", 8, -44)
    recipeScroll:SetPoint("BOTTOMRIGHT", recipesPanel, "BOTTOMRIGHT", -8, 8)
    recipeScroll:EnableMouseWheel(true)
    recipeScroll:SetScript("OnMouseWheel", function(self, delta) self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 28))) end)
    local recipeContent = CreateFrame("Frame", nil, recipeScroll)
    recipeContent:SetWidth(390); recipeScroll:SetScrollChild(recipeContent)

    local function Clear(rows) for _,r in ipairs(rows) do r:Hide() end end
    local function ProfRow(i)
        if profRows[i] then profRows[i]:Show(); return profRows[i] end
        local r = CreateFrame("Button", nil, profContent); r:SetHeight(PROF_ROW_H); r:SetPoint("TOPLEFT", profContent, "TOPLEFT", 8, -8-(i-1)*PROF_ROW_H); r:SetPoint("RIGHT", profContent, "RIGHT", -8, 0)
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r.icon = r:CreateTexture(nil, "OVERLAY"); r.icon:SetSize(26,26); r.icon:SetPoint("LEFT", r, "LEFT", 3, 0)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -2)
        r.skill = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.skill:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
        profRows[i]=r; return r
    end
    local function RecipeRow(i)
        if recipeRows[i] then recipeRows[i]:Show(); return recipeRows[i] end
        local r = CreateFrame("Frame", nil, recipeContent); r:SetHeight(RECIPE_ROW_H); r:SetPoint("TOPLEFT", recipeContent, "TOPLEFT", 2, -2-(i-1)*RECIPE_ROW_H); r:SetPoint("RIGHT", recipeContent, "RIGHT", -2, 0)
        r.output = CreateFrame("Button", nil, r)
        r.output:SetSize(24,24); r.output:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -2)
        r.output.icon = r.output:CreateTexture(nil, "ARTWORK"); r.output.icon:SetAllPoints(r.output)
        r.output:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.itemId and self.itemId > 0 then
                GameTooltip:SetHyperlink("item:" .. tostring(self.itemId))
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Craft output", 0.8, 0.8, 0.8)
            elseif self.spellId and self.spellId > 0 then
                if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(self.spellId) else GameTooltip:SetText(self.spellName or ("Spell #" .. tostring(self.spellId))) end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Recipe spell / output effect", 0.8, 0.8, 0.8)
            end
            GameTooltip:Show()
        end)
        r.output:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.name:SetPoint("TOPLEFT", r.output, "TOPRIGHT", 6, -1); r.name:SetPoint("RIGHT", r, "RIGHT", -136, 0); r.name:SetJustifyH("LEFT")
        r.info = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.info:SetPoint("TOPLEFT", r.output, "BOTTOMLEFT", 0, -3); r.info:SetPoint("RIGHT", r, "RIGHT", -136, 0); r.info:SetJustifyH("LEFT")
        r.matIcons = {}
        for n=1,8 do
            local b = CreateFrame("Button", nil, r)
            b:SetSize(22,22)
            if n == 1 then b:SetPoint("TOPLEFT", r.info, "BOTTOMLEFT", 0, -4) else b:SetPoint("LEFT", r.matIcons[n-1], "RIGHT", 5, 0) end
            b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints(b)
            b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall"); b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -1)
            b:SetScript("OnEnter", function(self)
                if self.itemId and self.itemId > 0 then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink("item:" .. tostring(self.itemId))
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Available: " .. tostring(self.available or 0) .. " / Required: " .. tostring(self.required or 0), 1, 1, 1)
                    GameTooltip:Show()
                end
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:Hide()
            r.matIcons[n] = b
        end
        r.more = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.more:SetPoint("LEFT", r.matIcons[8], "RIGHT", 5, 0)
        r.btn = CreateFrame("Button", nil, r, "UIPanelButtonTemplate"); r.btn:SetSize(56,22); r.btn:SetPoint("RIGHT", r, "RIGHT", -66, 8); r.btn:SetText("Craft")
        r.allBtn = CreateFrame("Button", nil, r, "UIPanelButtonTemplate"); r.allBtn:SetSize(58,22); r.allBtn:SetPoint("LEFT", r.btn, "RIGHT", 4, 0); r.allBtn:SetText("All")
        recipeRows[i]=r; return r
    end

    panel.RefreshRecipes = function()
        Clear(recipeRows)
        if not PBAM.SelectedBot then return end
        if not selectedSkillId or selectedSkillId == 0 then
            recipeTitle:SetText("Recipes")
            statusText:SetText("Select a profession. Recipe-capable entries appear after BOT_SKILLS loads from the bridge.")
            recipeContent:SetHeight(30); return
        end
        recipeTitle:SetText("Recipes - " .. tostring(selectedSkillName or selectedSkillId))
        local key = string.lower(PBAM.SelectedBot) .. ":" .. tostring(selectedSkillId)
        local data = PBAM.Bridge.ProfessionRecipes and PBAM.Bridge.ProfessionRecipes[key]
        if not data then
            statusText:SetText("Requesting recipes...")
            PBAM.Bridge.RequestProfessionRecipes(PBAM.SelectedBot, selectedSkillId)
            recipeContent:SetHeight(30); return
        end
        local recipes = {}
        for _,rec in ipairs(data.recipes or {}) do
            -- Deny-list only: enchants legitimately have itemId=0, so do not require created items.
            if not IsHiddenRecipeSpell(rec) then table.insert(recipes, rec) end
        end
        if data.loading then statusText:SetText("Loading recipes...") else statusText:SetText(#recipes .. " recipes shown (" .. tostring(#(data.recipes or {})) .. " bridge entries). Craft makes one item; All crafts one at a time.") end
        if #recipes == 0 then recipeContent:SetHeight(30); return end
        table.sort(recipes, function(a,b) return tostring(RecipeName(a)) < tostring(RecipeName(b)) end)
        for i, rec in ipairs(recipes) do
            local r = RecipeRow(i)
            local itemName, _, _, _, _, _, _, _, _, itemTex = nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
            if (tonumber(rec.itemId) or 0) > 0 and GetItemInfo then itemName, _, _, _, _, _, _, _, _, itemTex = GetItemInfo(rec.itemId) end
            local spellName, _, spellTex = nil, nil, nil
            if (tonumber(rec.spellId) or 0) > 0 and GetSpellInfo then spellName, _, spellTex = GetSpellInfo(rec.spellId) end
            r.output.itemId = tonumber(rec.itemId) or 0
            r.output.spellId = tonumber(rec.spellId) or 0
            r.output.spellName = spellName
            r.output.icon:SetTexture(itemTex or spellTex or "Interface\\Icons\\INV_Misc_QuestionMark")
            local craftable = tonumber(rec.craftable) or 0
            local special = SpecialRecipe(rec)
            local nameColor = (special and special.forceWhiteName) and "|cffffffff" or DifficultyColor(rec.difficulty)
            r.name:SetText(nameColor .. RecipeName(rec) .. "|r")
            local canCraft = craftable > 0 or (special and special.alwaysCraftable)
            r.info:SetText("|cff888888Can craft: " .. tostring(craftable) .. "  spell " .. tostring(rec.spellId) .. (special and special.label and ("  " .. special.label) or "") .. "|r")
            local mats = ParseMaterials(rec.materials)
            for n,b in ipairs(r.matIcons) do
                local mat = mats[n]
                if mat then
                    local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(mat.itemId)
                    b.itemId, b.required, b.available = mat.itemId, mat.required, mat.available
                    b.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
                    b.icon:SetVertexColor(mat.available >= mat.required and 1 or 0.8, mat.available >= mat.required and 1 or 0.25, mat.available >= mat.required and 1 or 0.25, 1)
                    b.count:SetText(tostring(mat.available) .. "/" .. tostring(mat.required))
                    b:Show()
                else
                    b.itemId = nil; b:Hide()
                end
            end
            r.more:SetText(#mats > #r.matIcons and ("+" .. tostring(#mats - #r.matIcons)) or "")
            r.btn:SetText("Craft")
            PBAM.SetButtonEnabled(r.btn, canCraft, "This recipe cannot be crafted right now.")
            r.btn:SetScript("OnClick", function()
                statusText:SetText("Crafting one " .. tostring(RecipeName(rec)) .. "...")
                if special and special.legacyCast and SendChatMessage then
                    -- Legacy fallback for utility craft spells the bridge rejects as NO_MATERIALS.
                    SendChatMessage("cast " .. tostring(rec.spellId), "WHISPER", nil, PBAM.SelectedBot)
                    statusText:SetText("Sent legacy cast for " .. tostring(RecipeName(rec)) .. ".")
                else
                    PBAM.Bridge.CraftRecipe(PBAM.SelectedBot, rec.skillId or selectedSkillId, rec.spellId, rec.itemId)
                end
            end)
            r.allBtn:SetText(craftable > 1 and ("All " .. tostring(craftable)) or "All")
            PBAM.SetButtonEnabled(r.allBtn, craftable > 0 and not (special and special.disableCraftAll), (special and special.disableCraftAll) and "Craft All is disabled for this recipe." or "No crafts are currently available.")
            r.allBtn:SetScript("OnClick", function()
                craftQueue.active = true
                craftQueue.remaining = craftable
                craftQueue.botName = PBAM.SelectedBot
                craftQueue.skillId = rec.skillId or selectedSkillId
                craftQueue.spellId = rec.spellId
                craftQueue.itemId = rec.itemId
                craftQueue.recipeName = RecipeName(rec)
                craftQueue.waiting = false
                statusText:SetText("Craft All queued for " .. tostring(craftable) .. "x " .. tostring(craftQueue.recipeName) .. ".")
                queueTimer.elapsed = 99; queueTimer:Show()
            end)
        end
        recipeContent:SetHeight(8 + #recipes * RECIPE_ROW_H)
    end

    local function UpdateButtons(botName)
        PBAM.SetButtonEnabled(refreshBtn, botName and botName ~= "", "Select a bot to refresh professions.")
    end

    panel.OnRefresh = function(botName)
        if not botName then return end
        local k=string.lower(botName); PBAM.Bridge.Crafting[k]=nil; PBAM.Bridge.Professions[k]=nil
        PBAM.Bridge.Send("GET", "PROFESSION~"..botName); PBAM.Bridge.RequestBotSkills(botName)
        if selectedSkillId then PBAM.Bridge.ProfessionRecipes[k .. ":" .. tostring(selectedSkillId)] = nil end
        panel.OnBotSelect(botName)
    end

    refreshBtn:SetScript("OnClick", function()
        if PBAM.SelectedBot then panel.OnRefresh(PBAM.SelectedBot) end
    end)

    panel.OnBotSelect = function(botName)
        Clear(profRows)
        if botName ~= lastBotName then selectedSkillId = nil; selectedSkillName = nil; lastBotName = botName end
        UpdateButtons(botName)
        if not botName then emptyFs:Show(); header:Hide(); profScroll:Hide(); recipesPanel:Hide(); return end
        emptyFs:Hide(); header:Show(); profScroll:Show(); recipesPanel:Show()
        local key = string.lower(botName)
        local crafting = PBAM.Bridge.Crafting and PBAM.Bridge.Crafting[key]
        local skills = PBAM.Bridge.Professions and PBAM.Bridge.Professions[key]
        if not skills then PBAM.Bridge.RequestBotSkills(botName) end
        if not crafting then PBAM.Bridge.Send("GET", "PROFESSION~"..botName) end
        if not crafting and not skills then
            local r=ProfRow(1); r.icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01"); r.name:SetText("Requesting data..."); r.skill:SetText(""); profContent:SetHeight(70); panel.RefreshRecipes(); return
        end

        local primary, secondary, seen = {}, {}, {}
        local function addEntry(bucket, e)
            local k = SkillKey(e)
            if k ~= "" then seen[k] = true end
            table.insert(bucket, e)
        end
        if skills then
            for _,e in ipairs(skills.primary or {}) do addEntry(primary, e) end
            for _,e in ipairs(skills.secondary or {}) do addEntry(secondary, e) end
        end
        if crafting and crafting.professions then
            for name,e in pairs(crafting.professions) do
                local k = string.lower(tostring(name or "")):gsub("%s+", "")
                if not seen[k] then
                    local row = { name=name, displayName=name, value=e.level, max=e.max, id=0 }
                    if SECONDARY[k] then addEntry(secondary, row) else addEntry(primary, row) end
                end
            end
        end
        table.sort(primary, function(a,b) return tostring(a.displayName or a.name) < tostring(b.displayName or b.name) end)
        table.sort(secondary, function(a,b) return tostring(a.displayName or a.name) < tostring(b.displayName or b.name) end)

        local list = { { header="Primary Professions", sub=(#primary == 0 and "None learned" or nil) } }
        for _,e in ipairs(primary) do table.insert(list, e) end
        table.insert(list, { header="Secondary Professions", sub=(#secondary == 0 and "None learned" or nil) })
        for _,e in ipairs(secondary) do table.insert(list, e) end

        for i,e in ipairs(list) do
            local r=ProfRow(i)
            if e.header then
                r.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_11")
                r.name:SetText("|cffffd100" .. e.header .. "|r")
                r.skill:SetText(e.sub or "")
                r:SetScript("OnClick", nil)
                r:EnableMouse(false)
            else
                r:EnableMouse(true)
                local keyName=SkillKey(e)
                r.icon:SetTexture(ICONS[keyName] or "Interface\\Icons\\INV_Misc_Book_11")
                r.name:SetText(NiceName(e.displayName or e.name))
                r.skill:SetText(string.format("Skill: %d / %d%s", e.value or e.level or 0, e.max or 0, SkillId(e) > 0 and "" or "  (waiting)"))
                r:SetScript("OnClick", function()
                    selectedSkillId = SkillId(e)
                    selectedSkillName = NiceName(e.displayName or e.name)
                    if selectedSkillId == 0 and not skills then PBAM.Bridge.RequestBotSkills(botName) end
                    panel.RefreshRecipes()
                end)
            end
        end
        profContent:SetHeight(18 + math.max(1,#list)*PROF_ROW_H)
        if not selectedSkillId or selectedSkillId == 0 then
            for _,e in ipairs(list) do
                if not e.header and SkillId(e) > 0 then selectedSkillId = SkillId(e); selectedSkillName = NiceName(e.displayName or e.name); break end
            end
        end
        panel.RefreshRecipes()
    end
end, { hideForPlayer = true })
