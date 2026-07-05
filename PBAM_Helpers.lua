-- ============================================================
--  PBAM_Helpers.lua  |  Shared UI/state/data helpers
-- ============================================================

PBAM = PBAM or {}
PBAM._DropdownCounter = PBAM._DropdownCounter or 0

local function NormalizeName(name)
    return name and string.lower(tostring(name)) or nil
end

local function WrapFontString(fs, width)
    if not fs then return end
    if width then fs:SetWidth(width) end
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
end

local function GetSelectedName()
    return PBAM.SelectedBot
end

local function GetSelectedKey()
    return NormalizeName(PBAM.SelectedBot)
end

local function IsSelectedPlayer()
    local selected = GetSelectedKey()
    local playerName = UnitName and UnitName("player") or nil
    return selected ~= nil and selected == NormalizeName(playerName)
end

local function GetReputationStandingName(standingId)
    local standings = {
        [1] = { name = "Hated", color = "cc2222" },
        [2] = { name = "Hostile", color = "ff4444" },
        [3] = { name = "Unfriendly", color = "ee6622" },
        [4] = { name = "Neutral", color = "ffd100" },
        [5] = { name = "Friendly", color = "40c040" },
        [6] = { name = "Honored", color = "1eff66" },
        [7] = { name = "Revered", color = "33ccff" },
        [8] = { name = "Exalted", color = "a335ee" },
    }
    local entry = standings[tonumber(standingId)]
    if not entry then return tostring(standingId or "?") end
    return "|cff" .. entry.color .. entry.name .. "|r"
end

local function CreateActionRow(parent, height)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(height or 22)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetTexture(PBAM.textures and PBAM.textures.white or "Interface\\Buttons\\WHITE8x8")
    row.bg:SetVertexColor(0.08, 0.08, 0.10, 0.65)
    return row
end

local function CreateIconLabel(parent, icon, text)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(18)
    holder.icon = holder:CreateTexture(nil, "OVERLAY")
    holder.icon:SetSize(16, 16)
    holder.icon:SetPoint("LEFT", holder, "LEFT", 0, 0)
    holder.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    holder.text = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    holder.text:SetPoint("LEFT", holder.icon, "RIGHT", 6, 0)
    holder.text:SetText(text or "")
    return holder.text, holder.icon, holder
end

local function CreateStatusText(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetTextColor(PBAM.Theme.text_gray.r, PBAM.Theme.text_gray.g, PBAM.Theme.text_gray.b, PBAM.Theme.text_gray.a)
    return fs
end

local function SetStatusText(fs, msg, kind)
    if not fs then return end
    local colors = {
        info = PBAM.Theme.text_gray,
        ready = PBAM.Theme.text_gray,
        loading = PBAM.Theme.gold_light,
        success = PBAM.Theme.green,
        error = PBAM.Theme.red,
        warn = PBAM.Theme.orange,
    }
    local c = colors[kind or "info"] or PBAM.Theme.text_gray
    fs:SetText(tostring(msg or ""))
    fs:SetTextColor(c.r, c.g, c.b, c.a or 1)
end

local function SetButtonEnabled(button, enabled, disabledTooltip)
    if not button then return end
    button:SetEnabled(enabled and true or false)
    button._disabledTooltip = disabledTooltip
    if button._pbamTooltipHooked then return end
    button._pbamTooltipHooked = true
    button:HookScript("OnEnter", function(self)
        if self:IsEnabled() or not self._disabledTooltip or self._disabledTooltip == "" then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self._disabledTooltip, 1, 0.82, 0.22, true)
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", function()
        if GameTooltip and GameTooltip:IsOwned(button) then GameTooltip:Hide() end
    end)
end

local function CreateSmallButton(parent, label)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetHeight(20)
    btn:SetWidth(24)
    btn:SetText(label or "")
    return btn
end

local function IsHiddenDropdownValue(entry)
    if not entry then return true end
    if type(entry.hidden) == "function" then
        return not not entry.hidden()
    end
    return not not entry.hidden
end

local function GetItemQualityColor(quality)
    quality = tonumber(quality)
    if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
        return ITEM_QUALITY_COLORS[quality].hex or "|cffffffff"
    end
    return "|cffffffff"
end

local function BuildColoredItemLabel(label, itemLink, itemId, quality)
    label = tostring(label or "")
    if label == "" then return label end
    if not quality and GetItemInfo then
        local _, _, itemQuality = GetItemInfo(itemLink or itemId or 0)
        quality = itemQuality
    end
    return GetItemQualityColor(quality) .. label .. "|r"
end

local function SetDropdownButtonTooltip(button)
    if not button or not button._pbamDropdownEntry then return end
    local entry = button._pbamDropdownEntry
    if not GameTooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if entry.tooltipItemLink and GameTooltip.SetHyperlink then
        GameTooltip:SetHyperlink(entry.tooltipItemLink)
    elseif entry.tooltipItemId and tonumber(entry.tooltipItemId or 0) > 0 and GameTooltip.SetHyperlink then
        GameTooltip:SetHyperlink("item:" .. tostring(entry.tooltipItemId))
    elseif entry.tooltipTitle or entry.tooltipText or entry.tooltip then
        GameTooltip:SetText(entry.tooltipTitle or entry.label or tostring(entry.value), 1, 0.82, 0.22, true)
        if entry.tooltipText or entry.tooltip then
            GameTooltip:AddLine(entry.tooltipText or entry.tooltip, 0.8, 0.8, 0.8, true)
        end
    else
        GameTooltip:Hide()
        return
    end
    GameTooltip:Show()
end

local function ClearDropdownButtonTooltip(button)
    if GameTooltip and GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end

local function CreateDropdown(parent, values)
    PBAM._DropdownCounter = (PBAM._DropdownCounter or 0) + 1
    local dropdownName = "PBAMDropdown" .. tostring(PBAM._DropdownCounter)
    local dropdown = CreateFrame("Frame", dropdownName, parent, "UIDropDownMenuTemplate")
    dropdown.values = values or {}
    dropdown.selectedValue = nil
    dropdown.visibleValues = {}
    dropdown.scrollOffset = 0
    dropdown.maxVisibleItems = 18

    local function EntryDisplayLabel(entry)
        return (entry and (entry.dropdownLabel or entry.label)) or ""
    end

    local function ClampScrollOffset(self)
        local maxOffset = math.max(0, #(self.visibleValues or {}) - (tonumber(self.maxVisibleItems) or 18))
        self.scrollOffset = math.max(0, math.min(tonumber(self.scrollOffset) or 0, maxOffset))
    end

    local function RefreshOpenDropdown(self)
        if UIDropDownMenu_Refresh then
            UIDropDownMenu_Refresh(self, nil, 1)
            return
        end
        if CloseDropDownMenus then CloseDropDownMenus() end
        if ToggleDropDownMenu then ToggleDropDownMenu(1, nil, self, self, 0, 0) end
    end

    local function HandleDropdownMouseWheel(owner, delta)
        if not owner or #(owner.visibleValues or {}) <= (tonumber(owner.maxVisibleItems) or 18) then return end
        local previous = owner.scrollOffset or 0
        owner.scrollOffset = previous - delta
        ClampScrollOffset(owner)
        if owner.scrollOffset ~= previous then
            RefreshOpenDropdown(owner)
        end
    end

    local function ApplyEntryToButton(button, entry)
        if not button then return end
        button._pbamDropdownEntry = entry
        button._pbamDropdownOwner = button._pbamDropdownOwner or (button:GetParent() and button:GetParent()._pbamOwner) or nil
        if button._pbamHasPBAMTooltipHooks then return end
        button:HookScript("OnEnter", SetDropdownButtonTooltip)
        button:HookScript("OnLeave", ClearDropdownButtonTooltip)
        button:EnableMouseWheel(true)
        button:HookScript("OnMouseWheel", function(self, delta)
            HandleDropdownMouseWheel(self._pbamDropdownOwner or (self:GetParent() and self:GetParent()._pbamOwner), delta)
        end)
        button._pbamHasPBAMTooltipHooks = true
    end

    local function AttachMenuScrolling(self, level)
        local listFrame = _G["DropDownList" .. tostring(level or 1)]
        if not listFrame then return end
        listFrame._pbamOwner = self
        if listFrame._pbamHasMouseWheel then return end
        listFrame:EnableMouseWheel(true)
        listFrame:HookScript("OnMouseWheel", function(frame, delta)
            HandleDropdownMouseWheel(frame._pbamOwner, delta)
        end)
        listFrame._pbamHasMouseWheel = true
    end

    local function RebuildVisibleValues(self)
        wipe(self.visibleValues)
        for _, entry in ipairs(self.values or {}) do
            if not IsHiddenDropdownValue(entry) then
                table.insert(self.visibleValues, entry)
            end
        end
        if self.selectedValue then
            local stillVisible = false
            for _, entry in ipairs(self.visibleValues) do
                if entry.value == self.selectedValue then
                    stillVisible = true
                    break
                end
            end
            if not stillVisible then
                self.selectedValue = self.visibleValues[1] and self.visibleValues[1].value or nil
            end
        elseif self.visibleValues[1] then
            self.selectedValue = self.visibleValues[1].value
        end
        ClampScrollOffset(self)
    end

    UIDropDownMenu_Initialize(dropdown, function(self, level)
        RebuildVisibleValues(self)
        level = level or 1
        AttachMenuScrolling(self, level)
        local buttonIndex = 0
        local startIndex = (self.scrollOffset or 0) + 1
        local endIndex = math.min(#self.visibleValues, startIndex + (tonumber(self.maxVisibleItems) or 18) - 1)
        for entryIndex = startIndex, endIndex do
            local entry = self.visibleValues[entryIndex]
            local info = UIDropDownMenu_CreateInfo()
            buttonIndex = buttonIndex + 1
            info.text = EntryDisplayLabel(entry)
            info.value = entry.value
            info.checked = (entry.value == self.selectedValue)
            info.icon = entry.icon
            info.tooltipTitle = entry.tooltipTitle or entry.label or tostring(entry.value)
            info.tooltipText = (entry.tooltipItemLink or entry.tooltipItemId) and nil or (entry.tooltipText or entry.tooltip or nil)
            info.func = function()
                self:SetValue(entry.value)
                if entry.onSelect then entry.onSelect(entry.value, entry) end
            end
            UIDropDownMenu_AddButton(info, level)
            ApplyEntryToButton(_G["DropDownList" .. tostring(level) .. "Button" .. tostring(buttonIndex)], entry)
        end
    end)

    function dropdown:SetValues(newValues)
        self.values = newValues or {}
        RebuildVisibleValues(self)
        UIDropDownMenu_SetText(self, EntryDisplayLabel(self:GetSelectedEntry()))
    end

    function dropdown:GetSelectedEntry()
        for _, entry in ipairs(self.visibleValues or {}) do
            if entry.value == self.selectedValue then return entry end
        end
        return nil
    end

    function dropdown:SetValue(value)
        self.selectedValue = value
        RebuildVisibleValues(self)
        UIDropDownMenu_SetSelectedValue(self, self.selectedValue)
        UIDropDownMenu_SetText(self, EntryDisplayLabel(self:GetSelectedEntry()))
    end

    function dropdown:Refresh()
        RebuildVisibleValues(self)
        UIDropDownMenu_SetSelectedValue(self, self.selectedValue)
        UIDropDownMenu_SetText(self, EntryDisplayLabel(self:GetSelectedEntry()))
    end

    RebuildVisibleValues(dropdown)
    UIDropDownMenu_SetWidth(dropdown, 140)
    UIDropDownMenu_SetButtonWidth(dropdown, 160)
    UIDropDownMenu_SetSelectedValue(dropdown, dropdown.selectedValue)
    UIDropDownMenu_SetText(dropdown, EntryDisplayLabel(dropdown:GetSelectedEntry()))

    return dropdown
end

PBAM.NormalizeName = NormalizeName
PBAM.WrapFontString = WrapFontString
PBAM.GetSelectedName = GetSelectedName
PBAM.GetSelectedKey = GetSelectedKey
PBAM.IsSelectedPlayer = IsSelectedPlayer
PBAM.GetReputationStandingName = GetReputationStandingName
PBAM.GetItemQualityColor = GetItemQualityColor
PBAM.BuildColoredItemLabel = BuildColoredItemLabel
PBAM.CreateActionRow = CreateActionRow
PBAM.CreateIconLabel = CreateIconLabel
PBAM.CreateStatusText = CreateStatusText
PBAM.SetStatusText = SetStatusText
PBAM.SetButtonEnabled = SetButtonEnabled
PBAM.CreateSmallButton = CreateSmallButton
PBAM.CreateDropdown = CreateDropdown
