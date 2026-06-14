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

PBAM.RegisterTab("Trainer", "Trainer", 6, function(panel)
    local MARGIN, ROW_H = 12, 56
    local rows = {}
    local statusFs

    PBAM.Bridge.RegisterCallback("TrainerUpdated", function(botName)
        if botName == PBAM.SelectedBot and PBAM.CurrentTab == "Trainer" and panel.OnBotSelect then panel.OnBotSelect(botName) end
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

    local emptyFs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyFs:SetPoint("CENTER", panel, "CENTER"); emptyFs:SetText("Select a bot to view trainer spells"); emptyFs:SetTextColor(0.55,0.55,0.55,1)

    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", MARGIN, -MARGIN); header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -MARGIN, -MARGIN); header:SetHeight(64)
    PBAM.ApplyBackdrop(header, 0.55); PBAM.CreateSectionHeader(header, "Trainer", -10, 13)
    statusFs = header:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); statusFs:SetPoint("TOPLEFT", header, "TOPLEFT", 18, -34); statusFs:SetPoint("RIGHT", header, "RIGHT", -112, 0); statusFs:SetJustifyH("LEFT"); statusFs:SetTextColor(0.7,0.7,0.7,1)
    local refreshBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate"); refreshBtn:SetSize(88,22); refreshBtn:SetPoint("RIGHT", header, "RIGHT", -12, -6); refreshBtn:SetText("Refresh")
    panel.StatusText = statusFs

    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8); scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -MARGIN, MARGIN)
    scroll:EnableMouseWheel(true); scroll:SetScript("OnMouseWheel", function(self, delta) self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 28))) end)
    local content = CreateFrame("Frame", nil, scroll); content:SetWidth(660); scroll:SetScrollChild(content); PBAM.ApplyBackdrop(content, 0.35)

    local function ClearRows() for _,r in ipairs(rows) do r:Hide() end end
    local function Row(i)
        if rows[i] then rows[i]:Show(); return rows[i] end
        local r=CreateFrame("Frame", nil, content); r:SetHeight(ROW_H); r:SetPoint("TOPLEFT", content,"TOPLEFT",8,-8-(i-1)*ROW_H); r:SetPoint("RIGHT", content,"RIGHT",-8,0)
        r.icon=r:CreateTexture(nil,"OVERLAY"); r.icon:SetSize(26,26); r.icon:SetPoint("LEFT",r,"LEFT",6,0); r.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
        r.name=r:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); r.name:SetPoint("TOPLEFT",r.icon,"TOPRIGHT",8,-1); r.name:SetPoint("RIGHT",r,"RIGHT",-76,0); r.name:SetJustifyH("LEFT")
        r.cost=r:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); r.cost:SetPoint("TOPLEFT",r.name,"BOTTOMLEFT",0,-6); r.cost:SetPoint("RIGHT",r,"RIGHT",-76,0); r.cost:SetJustifyH("LEFT")
        r.btn=CreateFrame("Button", nil, r, "UIPanelButtonTemplate"); r.btn:SetSize(62,22); r.btn:SetPoint("RIGHT",r,"RIGHT",-4,0); r.btn:SetText("Learn")
        rows[i]=r; return r
    end

    panel.OnRefresh = function(botName)
        if not botName then return end
        PBAM.Bridge.Trainer[string.lower(botName)] = nil
        PBAM.Bridge.RequestTrainer(botName)
        panel.OnBotSelect(botName)
    end

    refreshBtn:SetScript("OnClick", function() if PBAM.SelectedBot then panel.OnRefresh(PBAM.SelectedBot) end end)

    panel.OnBotSelect = function(botName)
        ClearRows()
        PBAM.SetButtonEnabled(refreshBtn, botName and botName ~= "", "Select a bot to refresh trainer data.")
        if not botName then emptyFs:Show(); header:Hide(); scroll:Hide(); return end
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
            r.btn:Show(); PBAM.SetButtonEnabled(r.btn, spell.canAfford, "This bot cannot afford that training right now."); r.btn:SetScript("OnClick", function() statusFs:SetText("Learning " .. tostring(spell.name or spell.spellId) .. "..."); PBAM.Bridge.LearnTrainerSpell(botName, spell.trainerEntry or trainer.trainerEntry, spell.spellId) end)
        end
        content:SetHeight(20 + #trainer.spells*ROW_H)
    end
end, { hideForPlayer = true })
