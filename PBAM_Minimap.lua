-- ============================================================
--  PBAM_Minimap.lua  |  Minimap button via LibDBIcon-1.0
-- ============================================================

PBAM = PBAM or {}

-- Initialize config tables (these are saved by WoW as SavedVariables)
PBAMConfig = PBAMConfig or {}
PBAMConfig.Minimap = PBAMConfig.Minimap or {
    hide = false,
    minimapPos = 225,
}

PBAMMinimapDB = PBAMMinimapDB or { hide = false, minimapPos = 225 }
PBAMMinimapDB.hide = PBAMMinimapDB.hide or PBAMConfig.Minimap.hide or false
PBAMMinimapDB.minimapPos = tonumber(PBAMMinimapDB.minimapPos or PBAMConfig.Minimap.minimapPos) or 225
PBAMConfig.Minimap.hide = PBAMMinimapDB.hide
PBAMConfig.Minimap.minimapPos = PBAMMinimapDB.minimapPos

local dbicon = LibStub("LibDBIcon-1.0", true)
if not dbicon then
    print("[PBAM] ERROR: LibDBIcon-1.0 not available!")
    return
end

local miniButton = LibStub("LibDataBroker-1.1"):NewDataObject("PBAltManager", {
    type = "launcher",
    text = "PBAltManager",
    icon = "Interface\\Icons\\INV_Misc_Book_11",
    OnClick = function(self, btn)
        if btn == "LeftButton" then
            if PBAM and PBAM.OpenWindow then
                PBAM.OpenWindow()
            end
        end
    end,
    OnTooltipShow = function(tooltip)
        if not tooltip or not tooltip.AddLine then return end
        tooltip:AddLine("|cffC69B3APBAltManager|r")
        tooltip:AddLine("Left-Click to Toggle", 1, 1, 1)
        tooltip:AddLine("Drag to Reposition", 0.7, 0.7, 0.7)
    end,
})

-- Register minimap button and mirror position to both SavedVariables tables.
if dbicon then
    dbicon:Register("PBAltManager", miniButton, PBAMMinimapDB)
end

local syncFrame = CreateFrame("Frame")
syncFrame:RegisterEvent("PLAYER_LOGIN")
syncFrame:RegisterEvent("PLAYER_LOGOUT")
syncFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        PBAMMinimapDB.hide = PBAMConfig.Minimap.hide or PBAMMinimapDB.hide or false
        PBAMMinimapDB.minimapPos = tonumber(PBAMConfig.Minimap.minimapPos or PBAMMinimapDB.minimapPos) or 225
        if dbicon and dbicon.Refresh then
            dbicon:Refresh("PBAltManager", PBAMMinimapDB)
        end
    elseif event == "PLAYER_LOGOUT" then
        PBAMConfig.Minimap.hide = PBAMMinimapDB.hide or false
        PBAMConfig.Minimap.minimapPos = tonumber(PBAMMinimapDB.minimapPos) or 225
    end
end)

local syncTicker = CreateFrame("Frame")
syncTicker:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + elapsed
    if self.t < 0.5 then return end
    self.t = 0
    if PBAMMinimapDB then
        PBAMConfig.Minimap.hide = PBAMMinimapDB.hide or false
        PBAMConfig.Minimap.minimapPos = tonumber(PBAMMinimapDB.minimapPos) or PBAMConfig.Minimap.minimapPos or 225
    end
end)
