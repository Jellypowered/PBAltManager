-- ============================================================
--  PBAM_Theme.lua  |  Visual theme — dark with gold accents
--  Inspired by PlayerbotManager's elegant dark/gold palette
-- ============================================================

PBAM = PBAM or {}

-- ── Color Palette ─────────────────────────────────────────────

if not PBAM.Theme then
    PBAM.Theme = {
        -- Backgrounds
        bg_dark       = { r = 0.06, g = 0.06, b = 0.08, a = 0.95 },
        bg_medium     = { r = 0.10, g = 0.10, b = 0.12, a = 0.90 },
        bg_light      = { r = 0.14, g = 0.14, b = 0.16, a = 0.85 },
        bg_highlight  = { r = 0.18, g = 0.16, b = 0.10, a = 0.70 },

        -- Accents
        gold          = { r = 0.83, g = 0.69, b = 0.22, a = 1.0 },
        gold_light    = { r = 0.90, g = 0.80, b = 0.40, a = 1.0 },
        gold_dim      = { r = 0.55, g = 0.44, b = 0.14, a = 1.0 },

        -- Text
        text_white    = { r = 0.92, g = 0.92, b = 0.92, a = 1.0 },
        text_gray     = { r = 0.60, g = 0.60, b = 0.60, a = 1.0 },
        text_dim      = { r = 0.40, g = 0.40, b = 0.40, a = 1.0 },
        text_gold     = { r = 0.83, g = 0.69, b = 0.22, a = 1.0 },

        -- Status
        green         = { r = 0.27, g = 1.00, b = 0.53, a = 1.0 },
        red           = { r = 1.00, g = 0.22, b = 0.22, a = 1.0 },
        orange        = { r = 1.00, g = 0.55, b = 0.00, a = 1.0 },

        -- Border
        border        = { r = 0.35, g = 0.35, b = 0.35, a = 0.95 },

        -- Class colors (hex strings for WoW item links)
        class_colors = {
            ["Warrior"]      = "C79C6E",
            ["Paladin"]      = "F58CBA",
            ["Hunter"]       = "ABD473",
            ["Rogue"]        = "FFF569",
            ["Priest"]       = "FFFFFF",
            ["Death Knight"] = "C41F3B",
            ["Shaman"]       = "0070DE",
            ["Mage"]         = "69CCF0",
            ["Warlock"]      = "9482C9",
            ["Druid"]        = "FF7D0A",
        },
    }
end

-- ── Texture References ──────────────────────────────────────

PBAM.textures = {
    white = "Interface\\Buttons\\WHITE8x8",
    border = "Interface\\Tooltips\\UI-Tooltip-Border",
    chat_bg = "Interface\\ChatFrame\\ChatFrameBackground",
}

-- ── Shared Backdrop ──────────────────────────────────────────

local function ApplyBackdrop(frame, bgAlpha, borderColor)
    if not frame or not frame.SetBackdrop then return end
    frame:SetBackdrop({
        bgFile   = PBAM.textures.white,
        edgeFile = PBAM.textures.border,
        tile     = true, tileSize = 16, edgeSize = 14,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    if frame.SetBackdropColor then
        frame:SetBackdropColor(PBAM.Theme.bg_dark.r, PBAM.Theme.bg_dark.g, PBAM.Theme.bg_dark.b, bgAlpha or PBAM.Theme.bg_dark.a)
    end
    if frame.SetBackdropBorderColor then
        local bc = borderColor or PBAM.Theme.border
        frame:SetBackdropBorderColor(bc.r, bc.g, bc.b, bc.a)
    end
end

-- ── Font Strings ─────────────────────────────────────────────

local function CreateLabel(parent, text, fontSize, x, y, width, justifyH, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetText(text)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y or 0)
    if width then fs:SetWidth(width) end
    if justifyH then fs:SetJustifyH(justifyH) end
    if color then
        fs:SetTextColor(color.r or color[1] or 1, color.g or color[2] or 1, color.b or color[3] or 1, color.a or color[4] or 1)
    else
        local c = PBAM.Theme.text_white
        fs:SetTextColor(c.r, c.g, c.b, c.a)
    end
    return fs
end

local function CreateGoldLine(parent, y, width)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetHeight(1)
    local w = width or -20
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, y)
    t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", w, y)
    t:SetTexture(PBAM.textures.white)
    t:SetVertexColor(PBAM.Theme.gold.r, PBAM.Theme.gold.g, PBAM.Theme.gold.b, 0.55)
    return t
end

local function CreateSectionHeader(parent, text, y, fontSize)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, y or -10)
    fs:SetText(text)
    local fontStr, fontSz, fontFlags = fs:GetFont()
    fs:SetFont(fontStr, fontSize or 14, "OUTLINE")
    fs:SetTextColor(PBAM.Theme.gold.r, PBAM.Theme.gold.g, PBAM.Theme.gold.b)
    fs.goldLine = CreateGoldLine(parent, (y or -10) - 14)
    return fs
end

-- Store helpers on PBAM namespace
PBAM.ApplyBackdrop = ApplyBackdrop
PBAM.CreateLabel = CreateLabel
PBAM.CreateGoldLine = CreateGoldLine
PBAM.CreateSectionHeader = CreateSectionHeader
