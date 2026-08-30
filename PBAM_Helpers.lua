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

local function NormalizeStatusMessage(msg)
    msg = tostring(msg or "")
    msg = msg:gsub("[\r\n]+", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if #msg > 170 then msg = msg:sub(1, 167) .. "..." end
    return msg
end

local function SetStatusText(fs, msg, kind)
    if not fs then return end
    local colors = {
        info = PBAM.Theme.gold_light,
        ready = PBAM.Theme.gold_light,
        loading = PBAM.Theme.gold_light,
        success = PBAM.Theme.green,
        error = PBAM.Theme.red,
        warn = PBAM.Theme.gold_light,
    }
    local c = colors[kind or "info"] or PBAM.Theme.text_gray
    fs:SetText(NormalizeStatusMessage(msg))
    fs:SetTextColor(c.r, c.g, c.b, c.a or 1)
end

local function AttachSharedStatusText(panel, defaultMsg, defaultKind)
    if not panel then return nil end
    panel._sharedStatusDefault = { msg = defaultMsg or "", kind = defaultKind or "info" }
    if PBAM.MainStatusText then
        panel.StatusText = PBAM.MainStatusText
        if defaultMsg ~= nil then SetStatusText(PBAM.MainStatusText, defaultMsg, defaultKind or "info") end
        return PBAM.MainStatusText
    end
    local fs = CreateStatusText(panel)
    panel.StatusText = fs
    if defaultMsg ~= nil then SetStatusText(fs, defaultMsg, defaultKind or "info") end
    return fs
end

local function SetFrameEnabled(frame, enabled)
    if not frame then return end
    if enabled then
        frame:Enable()
    else
        frame:Disable()
    end
end

local function SetButtonEnabled(button, enabled, disabledTooltip)
    if not button then return end
    SetFrameEnabled(button, enabled)
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
    -- SetHyperlink throws on plain names, numeric fields, or unsupported links.
    -- Only pass an actual item hyperlink to avoid tooltip libraries aborting the
    -- dropdown's OnEnter handler (notably LibExtraTip on WotLK clients).
    local itemLink = tostring(entry.tooltipItemLink or "")
    if itemLink:find("|Hitem:", 1, true) or itemLink:match("^item:%d+") then
        if GameTooltip.SetHyperlink then GameTooltip:SetHyperlink(itemLink) end
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

    local function EntryDisplayLabel(entry)
        return (entry and (entry.dropdownLabel or entry.label)) or ""
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
    end

    UIDropDownMenu_Initialize(dropdown, function(self)
        RebuildVisibleValues(self)
        for _, entry in ipairs(self.visibleValues) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = EntryDisplayLabel(entry)
            info.value = entry.value
            info.checked = (entry.value == self.selectedValue)
            info.icon = entry.icon
            info.tooltipTitle = entry.tooltipTitle or entry.label or tostring(entry.value)
            info.tooltipText = entry.tooltipText or entry.tooltip or nil
            info.func = function()
                self:SetValue(entry.value)
                if entry.onSelect then entry.onSelect(entry.value, entry) end
            end
            UIDropDownMenu_AddButton(info)
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

local activeScrollablePicker = nil
local scrollablePickerDismissFrame = CreateFrame("Button", nil, UIParent)
scrollablePickerDismissFrame:SetAllPoints(UIParent)
scrollablePickerDismissFrame:SetFrameStrata("DIALOG")
scrollablePickerDismissFrame:Hide()
scrollablePickerDismissFrame:SetScript("OnClick", function()
    if activeScrollablePicker and activeScrollablePicker.HidePopup then activeScrollablePicker:HidePopup() end
end)

local function CreateScrollableItemPicker(parent, width, popupHeight)
    local picker = CreateFrame("Frame", nil, parent)
    picker:SetSize(width or 220, 24)
    picker.values = {}
    picker.visibleValues = {}
    picker.selectedValue = nil

    picker.button = CreateFrame("Button", nil, picker)
    picker.button:SetAllPoints(picker)
    if PBAM and PBAM.ApplyBackdrop then PBAM.ApplyBackdrop(picker.button, 0.92) end
    picker.button:SetBackdropBorderColor(0.45, 0.34, 0.10, 0.95)
    picker.button:SetBackdropColor(0.12, 0.12, 0.14, 0.95)

    picker.button.icon = picker.button:CreateTexture(nil, "ARTWORK")
    picker.button.icon:SetSize(16, 16)
    picker.button.icon:SetPoint("LEFT", picker.button, "LEFT", 6, 0)
    picker.button.icon:Hide()

    picker.button.text = picker.button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    picker.button.text:SetPoint("LEFT", picker.button, "LEFT", 8, 0)
    picker.button.text:SetPoint("RIGHT", picker.button, "RIGHT", -22, 0)
    picker.button.text:SetJustifyH("LEFT")
    picker.button.text:SetText("Select...")

    picker.button.arrow = picker.button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    picker.button.arrow:SetPoint("RIGHT", picker.button, "RIGHT", -8, 0)
    picker.button.arrow:SetText("v")
    picker.button.arrow:SetTextColor(0.95, 0.80, 0.22, 1)

    picker.popup = CreateFrame("Frame", nil, UIParent)
    picker.popup:SetFrameStrata("FULLSCREEN_DIALOG")
    picker.popup:SetFrameLevel((scrollablePickerDismissFrame:GetFrameLevel() or 0) + 10)
    picker.popup:SetPoint("TOPLEFT", picker, "BOTTOMLEFT", 0, -2)
    picker.popup:SetSize(width or 220, popupHeight or 220)
    if PBAM and PBAM.ApplyBackdrop then PBAM.ApplyBackdrop(picker.popup, 0.96) end
    picker.popup:Hide()

    picker.scroll = CreateFrame("ScrollFrame", nil, picker.popup)
    picker.scroll:SetPoint("TOPLEFT", picker.popup, "TOPLEFT", 6, -6)
    picker.scroll:SetPoint("BOTTOMRIGHT", picker.popup, "BOTTOMRIGHT", -6, 6)
    picker.scroll:EnableMouseWheel(true)
    picker.scroll:SetScript("OnMouseWheel", function(self, delta)
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 20)))
    end)

    picker.content = CreateFrame("Frame", nil, picker.scroll)
    picker.content:SetWidth((width or 220) - 20)
    picker.scroll:SetScrollChild(picker.content)

    picker.rows = {}

    local function EntryDisplayLabel(entry)
        return (entry and (entry.dropdownLabel or entry.label)) or ""
    end

    local function RebuildVisibleValues(self)
        wipe(self.visibleValues)
        for _, entry in ipairs(self.values or {}) do
            if not IsHiddenDropdownValue(entry) then table.insert(self.visibleValues, entry) end
        end
        if self.selectedValue then
            local stillVisible = false
            for _, entry in ipairs(self.visibleValues) do
                if entry.value == self.selectedValue then stillVisible = true break end
            end
            if not stillVisible then
                self.selectedValue = self.visibleValues[1] and self.visibleValues[1].value or nil
            end
        elseif self.visibleValues[1] then
            self.selectedValue = self.visibleValues[1].value
        end
    end

    local function UpdateButton(self)
        local entry = self:GetSelectedEntry()
        local label = EntryDisplayLabel(entry)
        if label == "" then label = "Select..." end
        self.button.text:SetText(label)
        if entry and entry.icon then
            self.button.icon:SetTexture(entry.icon)
            self.button.icon:Show()
            self.button.text:ClearAllPoints()
            self.button.text:SetPoint("LEFT", self.button.icon, "RIGHT", 6, 0)
            self.button.text:SetPoint("RIGHT", self.button, "RIGHT", -22, 0)
        else
            self.button.icon:Hide()
            self.button.text:ClearAllPoints()
            self.button.text:SetPoint("LEFT", self.button, "LEFT", 8, 0)
            self.button.text:SetPoint("RIGHT", self.button, "RIGHT", -22, 0)
        end
    end

    local function AcquireRow(index)
        local row = picker.rows[index]
        if row then row:Show(); return row end
        row = CreateFrame("Button", nil, picker.content)
        row:SetHeight(20)
        row:SetPoint("TOPLEFT", picker.content, "TOPLEFT", 0, -((index - 1) * 20))
        row:SetPoint("RIGHT", picker.content, "RIGHT", 0, 0)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        row.bg:SetVertexColor(0.10, 0.10, 0.12, 0.65)
        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetTexture("Interface\\Buttons\\WHITE8x8")
        row.highlight:SetVertexColor(0.25, 0.22, 0.10, 0.35)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.text:SetJustifyH("LEFT")
        row:HookScript("OnEnter", SetDropdownButtonTooltip)
        row:HookScript("OnLeave", ClearDropdownButtonTooltip)
        picker.rows[index] = row
        return row
    end

    function picker:HidePopup()
        self.popup:Hide()
        scrollablePickerDismissFrame:Hide()
        if activeScrollablePicker == self then activeScrollablePicker = nil end
    end

    function picker:Refresh()
        RebuildVisibleValues(self)
        UpdateButton(self)
        for _, row in ipairs(self.rows) do row:Hide() end
        for i, entry in ipairs(self.visibleValues) do
            local row = AcquireRow(i)
            row._pbamDropdownEntry = entry
            if entry.icon then
                row.icon:SetTexture(entry.icon)
                row.icon:Show()
                row.text:ClearAllPoints()
                row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            else
                row.icon:Hide()
                row.text:ClearAllPoints()
                row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
                row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            end
            row.text:SetText(EntryDisplayLabel(entry))
            row:SetScript("OnClick", function()
                self:SetValue(entry.value)
                self:HidePopup()
                if entry.onSelect then entry.onSelect(entry.value, entry) end
            end)
        end
        self.content:SetHeight(math.max(1, #self.visibleValues * 20))
    end

    function picker:SetValues(newValues)
        self.values = newValues or {}
        self:Refresh()
    end

    function picker:GetSelectedEntry()
        for _, entry in ipairs(self.visibleValues or {}) do
            if entry.value == self.selectedValue then return entry end
        end
        return nil
    end

    function picker:SetValue(value)
        self.selectedValue = value
        self:Refresh()
    end

    picker.button:SetScript("OnClick", function()
        if picker.popup:IsShown() then
            picker:HidePopup()
            return
        end
        if activeScrollablePicker and activeScrollablePicker ~= picker and activeScrollablePicker.HidePopup then
            activeScrollablePicker:HidePopup()
        end
        activeScrollablePicker = picker
        picker:Refresh()
        scrollablePickerDismissFrame:Show()
        picker.popup:Show()
    end)

    picker.popup:SetScript("OnMouseDown", function() end)
    picker:SetScript("OnHide", function() picker:HidePopup() end)
    picker:Refresh()
    return picker
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
PBAM.AttachSharedStatusText = AttachSharedStatusText
PBAM.SetFrameEnabled = SetFrameEnabled
PBAM.SetButtonEnabled = SetButtonEnabled
PBAM.CreateSmallButton = CreateSmallButton
PBAM.CreateDropdown = CreateDropdown
PBAM.CreateScrollableItemPicker = CreateScrollableItemPicker
