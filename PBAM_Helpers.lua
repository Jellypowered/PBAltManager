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

local function CreateDropdown(parent, values)
    PBAM._DropdownCounter = (PBAM._DropdownCounter or 0) + 1
    local dropdownName = "PBAMDropdown" .. tostring(PBAM._DropdownCounter)
    local dropdown = CreateFrame("Frame", dropdownName, parent, "UIDropDownMenuTemplate")
    dropdown.values = values or {}
    dropdown.selectedValue = nil
    dropdown.visibleValues = {}

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
            info.text = entry.label or tostring(entry.value)
            info.value = entry.value
            info.checked = (entry.value == self.selectedValue)
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
        UIDropDownMenu_SetText(self, (self:GetSelectedEntry() and self:GetSelectedEntry().label) or "")
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
        UIDropDownMenu_SetText(self, (self:GetSelectedEntry() and self:GetSelectedEntry().label) or "")
    end

    function dropdown:Refresh()
        RebuildVisibleValues(self)
        UIDropDownMenu_SetSelectedValue(self, self.selectedValue)
        UIDropDownMenu_SetText(self, (self:GetSelectedEntry() and self:GetSelectedEntry().label) or "")
    end

    RebuildVisibleValues(dropdown)
    UIDropDownMenu_SetWidth(dropdown, 140)
    UIDropDownMenu_SetButtonWidth(dropdown, 160)
    UIDropDownMenu_SetSelectedValue(dropdown, dropdown.selectedValue)
    UIDropDownMenu_SetText(dropdown, (dropdown:GetSelectedEntry() and dropdown:GetSelectedEntry().label) or "")

    return dropdown
end

PBAM.NormalizeName = NormalizeName
PBAM.WrapFontString = WrapFontString
PBAM.GetSelectedName = GetSelectedName
PBAM.GetSelectedKey = GetSelectedKey
PBAM.IsSelectedPlayer = IsSelectedPlayer
PBAM.GetReputationStandingName = GetReputationStandingName
PBAM.CreateActionRow = CreateActionRow
PBAM.CreateIconLabel = CreateIconLabel
PBAM.CreateStatusText = CreateStatusText
PBAM.SetStatusText = SetStatusText
PBAM.SetButtonEnabled = SetButtonEnabled
PBAM.CreateSmallButton = CreateSmallButton
PBAM.CreateDropdown = CreateDropdown
