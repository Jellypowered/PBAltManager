-- ============================================================
--  PBAM_Tab_Equipment.lua  |  Equipment paperdoll / Outfits
--  Paperdoll approach based on MultiBot-Chatless InspectUI.
-- ============================================================

PBAM = PBAM or {}

local SLOT_NAMES = {
    [1]="Head", [2]="Neck", [3]="Shoulder", [4]="Shirt", [5]="Chest", [6]="Waist", [7]="Legs", [8]="Feet", [9]="Wrist", [10]="Hands",
    [11]="Finger 1", [12]="Finger 2", [13]="Trinket 1", [14]="Trinket 2", [15]="Back", [16]="Main Hand", [17]="Off Hand", [18]="Ranged", [19]="Tabard",
}
local LEFT_SLOTS  = {1,2,3,15,5,4,19,9}
local RIGHT_SLOTS = {10,6,7,8,11,12,13,14}
local BOTTOM_SLOTS = {16,17,18}
-- Empty-state message position when no bot is selected.
-- Adjust X to move left/right and Y to move up/down.
local EMPTY_MESSAGE_X_OFFSET = -125
local EMPTY_MESSAGE_Y_OFFSET = 0
  

local function itemIcon(link)
    if link and GetItemIcon then
        local icon = GetItemIcon(link)
        if icon then return icon end
    end
    return "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"
end

local function sameUnitName(unit, botName)
    if not unit or not UnitExists(unit) or not botName then return false end
    local name = UnitName(unit)
    name = name and tostring(name):match("^[^-]+") or ""
    return string.lower(name) == string.lower(tostring(botName):match("^[^-]+") or botName)
end

local function findBotUnit(botName)
    if not botName or botName == "" then return nil end
    if sameUnitName("target", botName) then return "target" end
    if InspectFrame and InspectFrame.unit and sameUnitName(InspectFrame.unit, botName) then return InspectFrame.unit end
    for i=1,4 do local u="party"..i; if sameUnitName(u, botName) then return u end end
    for i=1,40 do local u="raid"..i; if sameUnitName(u, botName) then return u end end
    return nil
end

PBAM.RegisterTab("Equipment", "Equipment", 7, function(panel)
    local MARGIN = 12
    local slotButtons, outfitRows = {}, {}

    PBAM.Bridge.RegisterCallback("OutfitsUpdated", function(botName)
        if botName == PBAM.SelectedBot and PBAM.CurrentTab == "Equipment" and panel.OnBotSelect then panel.OnBotSelect(botName) end
    end)
    local inspectFrame = CreateFrame("Frame")
    inspectFrame:RegisterEvent("INSPECT_READY")
    inspectFrame:SetScript("OnEvent", function()
        if PBAM.SelectedBot and PBAM.CurrentTab == "Equipment" and panel.OnBotSelect then panel.OnBotSelect(PBAM.SelectedBot) end
    end)

    local emptyFs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyFs:SetPoint("CENTER", panel, "CENTER", EMPTY_MESSAGE_X_OFFSET, EMPTY_MESSAGE_Y_OFFSET)
    emptyFs:SetText("Select a bot to view equipment");
    emptyFs:SetTextColor(0.55,0.55,0.55,1)

    local header=CreateFrame("Frame", nil, panel); header:SetPoint("TOPLEFT",panel,"TOPLEFT",MARGIN,-MARGIN); header:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-MARGIN,-MARGIN); header:SetHeight(58)
    PBAM.ApplyBackdrop(header,0.55); PBAM.CreateSectionHeader(header,"Equipment",-10,13)
    local hint=header:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); hint:SetPoint("LEFT",header,"LEFT",18,-40); hint:SetTextColor(0.72,0.72,0.72,1)
    local refreshBtn=CreateFrame("Button", nil, header, "UIPanelButtonTemplate"); refreshBtn:SetSize(88,22); refreshBtn:SetPoint("RIGHT",header,"RIGHT",-12,-6); refreshBtn:SetText("Refresh")
    panel.StatusText = hint

    -- This tab used to put the paperdoll inside a ScrollFrame. WotLK's
    -- DressUpModel is not clipped/laid out like a normal child frame, and the
    -- ScrollFrame child transform can make the model appear to drift, skew, or
    -- shrink while the parent window is moved. The content fits the fixed PBAM
    -- window, so keep it in a plain frame anchored directly to the tab panel.
    local body=CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT",header,"BOTTOMLEFT",0,-8)
    body:SetPoint("BOTTOMRIGHT",panel,"BOTTOMRIGHT",-MARGIN,MARGIN)
    PBAM.ApplyBackdrop(body,0.35)

    local doll=CreateFrame("Frame", nil, body); doll:SetPoint("TOPLEFT",body,"TOPLEFT",12,-12); doll:SetSize(410,430); PBAM.ApplyBackdrop(doll,0.25)
    local dollTitle=doll:CreateFontString(nil,"OVERLAY","GameFontNormal"); dollTitle:SetPoint("TOP",doll,"TOP",0,-10); dollTitle:SetText("Equipment")

    -- Live 3D model capability adapted from CleanBot's DressUpModel panel.
    -- V8: uses the CleanBot-style DressUpModel rotation path more literally.
    -- Important: camera/position calls are disabled by default because on some
    -- 3.3.5 clients they fight SetRotation and snap the model back while dragging.
    local MODEL_WIDTH, MODEL_HEIGHT = 300, 430

    -- Centering knobs. Now that the model is no longer inside a ScrollFrame,
    -- keep its viewport centered in the paperdoll/equipment-slot frame.
    local MODEL_OFFSET_X, MODEL_OFFSET_Y = 0, 0

    -- View knobs. For size, try MODEL_SCALE first. If that does nothing on your client,
    -- adjust MODEL_WIDTH/MODEL_HEIGHT proportionally, then re-center with offsets above.
    -- Leave this false unless you absolutely need the camera API. On your client,
    -- these camera/position calls are the likely source of rotation snap-back.
    local MODEL_USE_CAMERA_TUNING = false
    local MODEL_FULL_BODY_CAMERA = 1
    local MODEL_CAMERA_DISTANCE = 0
    local MODEL_CAM_DISTANCE_SCALE = 0
    local MODEL_SCALE = 0.75
    local MODEL_POS_X, MODEL_POS_Y, MODEL_POS_Z = 0.00, 0, 0.12

    -- CleanBot-style rotation. Right-click drag only, matching the working addon.
    local MODEL_ROTATION_START = 0
    local MODEL_ROTATE_SPEED = 0.013

    local function safeModelCall(m, method, ...)
        if m and m[method] then
            local ok = pcall(m[method], m, ...)
            return ok
        end
        return false
    end

    -- Anchor the 3D model directly to the equipment doll, not to an intermediate
    -- frame/scroll child. DressUpModel is sensitive to parent chains while moving
    -- frames on WotLK; CleanBot's stable path parents/anchors the model directly.
    local model = CreateFrame("DressUpModel", nil, doll)
    model:SetSize(MODEL_WIDTH, MODEL_HEIGHT)
    model:SetPoint("CENTER", doll, "CENTER", MODEL_OFFSET_X, MODEL_OFFSET_Y)
    model:EnableMouse(true)
    model:SetFrameLevel(doll:GetFrameLevel() + 1)

    local modelRotation = MODEL_ROTATION_START
    local dragLastX = 0
    local lastModelUnitKey, lastModelBot = nil, nil
    local isRotating = false

    local function normalizeModelRotation()
        local twoPi = math.pi * 2
        while modelRotation > twoPi do modelRotation = modelRotation - twoPi end
        while modelRotation < -twoPi do modelRotation = modelRotation + twoPi end
    end

    local function applyModelRotation(m)
        if not m then return end
        normalizeModelRotation()
        -- Match the working CleanBot implementation: DressUpModel + SetRotation.
        -- Do not call SetFacing here; on this panel it causes/encourages snap-back.
        if m.SetRotation then
            m:SetRotation(modelRotation)
        end
    end

    -- Local version of CleanBot's shared mouse-capture idea. While dragging, this
    -- invisible full-screen frame catches mouse-up even if the cursor leaves the model.
    local rotationCapture = CreateFrame("Frame", nil, UIParent)
    rotationCapture:Hide()
    rotationCapture:SetAllPoints(UIParent)
    rotationCapture:EnableMouse(true)
    if rotationCapture.SetFrameStrata then rotationCapture:SetFrameStrata("FULLSCREEN_DIALOG") end
    if rotationCapture.SetFrameLevel then rotationCapture:SetFrameLevel(9999) end
    rotationCapture.updateFunc = nil
    rotationCapture.mouseUpFunc = nil
    rotationCapture:SetScript("OnUpdate", function(self)
        if self.updateFunc then self.updateFunc() end
    end)
    rotationCapture:SetScript("OnMouseUp", function(self, button)
        if self.mouseUpFunc then self.mouseUpFunc(button) end
    end)
    rotationCapture:SetScript("OnHide", function(self)
        self.updateFunc = nil
        self.mouseUpFunc = nil
    end)

    local function beginRotationCapture(onUpdate, onMouseUp)
        rotationCapture.updateFunc = onUpdate
        rotationCapture.mouseUpFunc = onMouseUp
        rotationCapture:Show()
    end

    local function endRotationCapture()
        rotationCapture:Hide()
    end

    local function stopDrag()
        if not isRotating then return end
        isRotating = false
        endRotationCapture()
        applyModelRotation(model)
        if SetCursor then SetCursor(nil) end
    end

    local function rotateOnUpdate()
        local x = select(1, GetCursorPosition())
        local delta = x - dragLastX
        dragLastX = x
        if delta ~= 0 then
            modelRotation = modelRotation + delta * MODEL_ROTATE_SPEED
            applyModelRotation(model)
        end
    end

    local function restoreModelViewport()
        model:ClearAllPoints()
        model:SetSize(MODEL_WIDTH, MODEL_HEIGHT)
        model:SetPoint("CENTER", doll, "CENTER", MODEL_OFFSET_X, MODEL_OFFSET_Y)
    end

    local function applyModelView(m)
        if not m then return end
        restoreModelViewport()

        -- Camera/position APIs are intentionally optional. They can make the model
        -- look nice, but on some WotLK clients they also keep forcing the model
        -- back to its default rotation. Frame size/offset should do the scaling now.
        if MODEL_USE_CAMERA_TUNING then
            safeModelCall(m, "SetCamera", MODEL_FULL_BODY_CAMERA)
            safeModelCall(m, "SetPortraitZoom", 0)
            safeModelCall(m, "SetCameraDistance", MODEL_CAMERA_DISTANCE)
            safeModelCall(m, "SetCamDistanceScale", MODEL_CAM_DISTANCE_SCALE)
            safeModelCall(m, "SetModelScale", MODEL_SCALE)
            safeModelCall(m, "SetPosition", MODEL_POS_X, MODEL_POS_Y, MODEL_POS_Z)
        end

        applyModelRotation(m)
    end

    model:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            dragLastX = select(1, GetCursorPosition())
            isRotating = true
            if SetCursor then SetCursor("none") end
            beginRotationCapture(rotateOnUpdate, function(btn)
                if btn == "RightButton" then
                    stopDrag()
                end
            end)
        end
    end)
    model:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then stopDrag() end
    end)
    model:SetScript("OnHide", stopDrag)

    -- Main-window movement should not alter the model. Re-assert its direct
    -- doll-relative anchor after movement; no hiding/reparenting while dragging.
    PBAM.OnWindowDragStart = nil
    PBAM.OnWindowDragStop = function()
        restoreModelViewport()
        applyModelRotation(model)
    end

    model:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Live 3D model", 1, 0.82, 0)
        GameTooltip:AddLine("Right-click drag to rotate", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    model:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function makeSlot(slot, point, rel, x, y)
        local b=CreateFrame("Button", nil, doll)
        b:SetSize(42,42); b:SetPoint(point, rel or doll, point, x, y)
        b:SetFrameLevel(doll:GetFrameLevel() + 8)
        b.slot=slot
        b.bg=b:CreateTexture(nil,"BACKGROUND"); b.bg:SetAllPoints(); b.bg:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        b.icon=b:CreateTexture(nil,"ARTWORK"); b.icon:SetSize(34,34); b.icon:SetPoint("CENTER",b,"CENTER")
        -- No visible item-name labels: standard paperdoll viewers use icons + hover tooltips.
        b.label=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        b.label:Hide()
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
            if self.link then GameTooltip:SetHyperlink(self.link) else GameTooltip:AddLine(SLOT_NAMES[self.slot] or "Slot"); GameTooltip:AddLine("Empty / unavailable",0.7,0.7,0.7) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        slotButtons[slot]=b
    end
    for i,slot in ipairs(LEFT_SLOTS) do makeSlot(slot,"TOPLEFT",doll,18,-42-(i-1)*44) end
    for i,slot in ipairs(RIGHT_SLOTS) do makeSlot(slot,"TOPRIGHT",doll,-18,-42-(i-1)*44) end
    for i,slot in ipairs(BOTTOM_SLOTS) do makeSlot(slot,"BOTTOM",doll,(i-2)*62,26) end

    local outfitPanel=CreateFrame("Frame", nil, body); outfitPanel:SetPoint("TOPLEFT",doll,"TOPRIGHT",12,0); outfitPanel:SetPoint("BOTTOMRIGHT",body,"BOTTOMRIGHT",-12,12); PBAM.ApplyBackdrop(outfitPanel,0.25)
    PBAM.CreateSectionHeader(outfitPanel,"Outfits",-10,13)

    local function outfitRow(i)
        if outfitRows[i] then outfitRows[i]:Show(); return outfitRows[i] end
        local r=CreateFrame("Frame",nil,outfitPanel); r:SetHeight(30); r:SetPoint("TOPLEFT",outfitPanel,"TOPLEFT",12,-44-(i-1)*32); r:SetPoint("RIGHT",outfitPanel,"RIGHT",-12,0)
        r.icon=r:CreateTexture(nil,"OVERLAY"); r.icon:SetSize(22,22); r.icon:SetPoint("LEFT",r,"LEFT",0,0); r.icon:SetTexture("Interface\\Icons\\INV_Shirt_GuildTabard_01")
        r.text=r:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); r.text:SetPoint("LEFT",r.icon,"RIGHT",8,0); r.text:SetPoint("RIGHT",r,"RIGHT",-70,0); r.text:SetJustifyH("LEFT")
        r.btn=CreateFrame("Button",nil,r,"UIPanelButtonTemplate"); r.btn:SetSize(62,20); r.btn:SetPoint("RIGHT",r,"RIGHT",0,0); r.btn:SetText("Equip")
        outfitRows[i]=r; return r
    end
    local function clearOutfits() for _,r in ipairs(outfitRows) do r:Hide() end end

    panel.OnRefresh = function(botName)
        lastModelUnitKey, lastModelBot = nil, nil
        if model and model.ClearModel then model:ClearModel() end
        if not botName then return end
        PBAM.Bridge.Outfits[string.lower(botName)] = nil
        PBAM.Bridge.RequestOutfits(botName)
        panel.OnBotSelect(botName)
    end

    refreshBtn:SetScript("OnClick", function()
        if PBAM.SelectedBot then panel.OnRefresh(PBAM.SelectedBot) end
    end)

    panel.OnBotSelect=function(botName)
        PBAM.SetButtonEnabled(refreshBtn, botName and botName ~= "", "Select a bot to refresh equipment.")
        if not botName then emptyFs:Show(); header:Hide(); body:Hide(); return end
        emptyFs:Hide(); header:Show(); body:Show(); clearOutfits()
        dollTitle:SetText(botName)
        local unit=findBotUnit(botName)
        if unit then
            model:Show()
            local unitKey = (UnitGUID and UnitGUID(unit)) or unit
            -- Do not reload/reapply camera while the user is dragging. That was the snap-back.
            -- Also do not re-run the camera setup for the same unit on every outfit/inspect
            -- refresh; camera calls can reset rotation on some clients.
            if not isRotating then
                if panel.ForceModelRefresh or lastModelUnitKey ~= unitKey or lastModelBot ~= botName then
                    panel.ForceModelRefresh = nil
                    if model.ClearModel then model:ClearModel() end
                    safeModelCall(model, "SetUnit", unit)
                    lastModelUnitKey, lastModelBot = unitKey, botName
                    applyModelView(model)
                else
                    -- Same unit: leave the model completely alone. Outfit/inspect
                    -- refreshes should not fight user-controlled rotation.
                end
            end
        else
            lastModelUnitKey, lastModelBot = nil, nil
            model:Hide()
        end
        local foundLinks = 0
        for slot,b in pairs(slotButtons) do
            local link = unit and GetInventoryItemLink(unit, slot) or nil
            if link then foundLinks = foundLinks + 1 end
            b.link = link
            b.icon:SetTexture(link and itemIcon(link) or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
            b.icon:SetVertexColor(link and 1 or 0.45, link and 1 or 0.45, link and 1 or 0.45, 1)
            b.label:SetText("")
        end
        if unit and foundLinks > 0 then
            hint:SetText("")
        elseif unit then
            if NotifyInspect and (not CheckInteractDistance or CheckInteractDistance(unit, 1)) then NotifyInspect(unit) end
            hint:SetText("")
        else
            hint:SetText("")
        end
        local key=string.lower(botName); local outfits=PBAM.Bridge.Outfits and PBAM.Bridge.Outfits[key]
        if not outfits then PBAM.Bridge.RequestOutfits(botName) end
        if outfits and outfits.outfits and #outfits.outfits > 0 then
            for i,o in ipairs(outfits.outfits) do
                local r=outfitRow(i); r.text:SetText(o.name and o.name ~= "" and o.name or o.raw or "Outfit"); r.btn:Show(); r.btn:SetScript("OnClick", function() PBAM.Bridge.EquipOutfit(botName, o.name or o.raw, "EQUIP") end)
            end
        else
            local r=outfitRow(1); r.text:SetText(outfits and "No saved outfits returned." or "Requesting outfits..."); r.btn:Hide()
        end
    end

    PBAM.RefreshEquipmentTab = function(botName, forceModel)
        botName = botName or PBAM.SelectedBot
        if not botName or not panel.OnBotSelect then return end
        if forceModel then
            panel.ForceModelRefresh = true
            lastModelUnitKey, lastModelBot = nil, nil
        end
        panel.OnBotSelect(botName)
    end
end, { hideForPlayer = true })
