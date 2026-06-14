-- ============================================================
--  PBAM_Bridge.lua  |  MBOT bridge communication layer
--  Based on MultiBot-Chatless protocol
-- ============================================================

PBAM = PBAM or {}
PBAM.Bridge = PBAM.Bridge or {}
local Bridge = PBAM.Bridge

-- Protocol (from MultiBot-Chatless)
Bridge.PREFIX   = "MBOT"
Bridge.VERSION  = "1"

-- State
Bridge.Roster        = {}
Bridge.Details       = {}
Bridge.States        = {}
Bridge.Stats         = {}
Bridge.PvpStats      = {}
Bridge.Professions   = {}  -- BOT_SKILLS (weapon, armor, class skills)
Bridge.Crafting      = {}  -- PROFESSION (crafting professions like leatherworking, fishing)
Bridge.Inventory     = {}
Bridge.Bank          = {}
Bridge.TalentSpecs   = {}
Bridge.ProfessionRecipes = {}
Bridge.Spellbook     = {}
Bridge.InventoryItemActions = {}
Bridge.ProfessionCraftActions = {}
Bridge.Trainer       = {}
Bridge.Glyphs        = {}
Bridge.Outfits       = {}
Bridge.Quests        = {}
Bridge.GameObjects   = {}
Bridge.Recipes       = Bridge.ProfessionRecipes -- legacy alias

Bridge.callbacks     = {}
Bridge.Connected     = false
Bridge.Server        = nil
Bridge.Protocol      = nil

-- Class ID lookup (WotLK)
Bridge.ClassById = {
    [1]="Warrior",[2]="Paladin",[3]="Hunter",[4]="Rogue",[5]="Priest",
    [6]="Death Knight",[7]="Shaman",[8]="Mage",[9]="Warlock",[11]="Druid",
}

-- Reverse lookup
Bridge.ClassByName = {}
for id, name in pairs(Bridge.ClassById) do
    Bridge.ClassByName[string.lower(name)] = id
end

-- ── Callback System ─────────────────────────────────────────
function Bridge.RegisterCallback(event, func)
    Bridge.callbacks[event] = Bridge.callbacks[event] or {}
    table.insert(Bridge.callbacks[event], func)
    Bridge.DebugPrint("RegisterCallback: registered handler for " .. event .. " (total: " .. #Bridge.callbacks[event] .. ")")
end

function Bridge.FireCallback(event, ...)
    local handlers = Bridge.callbacks[event]
    Bridge.DebugPrint("[FireCallback DEBUG] event=" .. tostring(event) .. " handlers=" .. tostring(handlers and #handlers or 0))
    if not handlers then Bridge.DebugPrint("[FireCallback DEBUG] NO HANDLERS FOR " .. event); return end
    for i, func in ipairs(handlers) do
        Bridge.DebugPrint("[FireCallback DEBUG] Calling handler " .. i .. " for " .. event)
        local ok, err = pcall(func, ...)
        if not ok and type(PBAM.LogError) == "function" then
            PBAM.LogError("CB:" .. tostring(err))
        end
    end
end

-- ── Debug ───────────────────────────────────────────────────
function Bridge.DebugPrint(...)
    local msg = "[PBAM] " .. table.concat({ ... }, " ")
    if type(PBAM) == "table" and type(PBAM.DebugPrint) == "function" then
        PBAM.DebugPrint(msg)
    elseif type(DEFAULT_CHAT_FRAME) == "table" then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF69CCF0" .. msg .. "|r")
    end
end

function Bridge.LogError(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444[PBAltManager]|r " .. tostring(msg or ""))
    end
end

-- ── Helper: splitOnce (from MultiBot-Chatless) ──────────────
local function splitOnce(s, sep)
    if not s or not sep then return "", "" end
    local idx = string.find(s, sep, 1, true)
    if not idx then return s, "" end
    return string.sub(s, 1, idx - 1), string.sub(s, idx + 1)
end

local function trim(value)
    if type(value) ~= "string" then return "" end
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function urlDecode(value)
    if type(value) ~= "string" or value == "" then return "" end
    return (value:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16) or 0)
    end))
end


local function urlEncode(value)
    value = tostring(value or "")
    return (value:gsub("([^%w%-%_%.%~ ])", function(c)
        return string.format("%%%02X", string.byte(c))
    end):gsub(" ", "%%20"))
end

local function makeToken(kind)
    Bridge._seq = (Bridge._seq or 0) + 1
    local now = GetTime and math.floor((GetTime() or 0) * 1000) or time()
    return tostring(now) .. "-" .. tostring(kind or "pbam") .. "-" .. tostring(Bridge._seq)
end

local function parseOpcodePayload(payload)
    local opcode, rest = splitOnce(payload or "", "~")
    local name, rest2 = splitOnce(rest or "", "~")
    local token, rest3 = splitOnce(rest2 or "", "~")
    return opcode, trim(urlDecode(name)), trim(token), rest3 or ""
end

local function parseItemLinkId(text)
    return tonumber(tostring(text or ""):match("item:(%d+)")) or 0
end

-- ── Send ────────────────────────────────────────────────────
function Bridge.Send(opcode, payload)
    local msg = opcode
    if payload and payload ~= "" then
        msg = msg .. "~" .. tostring(payload)
    end
    Bridge.DebugPrint("TX: " .. msg)
    local ch = "PARTY"
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then ch = "RAID" end
    SendAddonMessage(Bridge.PREFIX, msg, ch)
end

function Bridge.SendHello()           Bridge.Send("HELLO", Bridge.VERSION) end
function Bridge.SendPing()            Bridge.Send("PING", tostring(math.floor(GetTime() and GetTime()*1000 or 0))) end
function Bridge.RequestRoster()       Bridge.Send("GET", "ROSTER") end
function Bridge.RequestStates()       Bridge.Send("GET", "STATES") end
function Bridge.RequestBotDetail(bot) Bridge.Send("GET", "DETAIL~" .. bot) end
function Bridge.RequestBotDetails()   Bridge.Send("GET", "DETAILS") end
function Bridge.RequestStats(bot)     Bridge.Send("GET", "STATS" .. (bot and "~" .. bot or "")) end
function Bridge.RequestPvpStats(bot)  Bridge.Send("GET", "PVP_STATS" .. (bot and "~" .. bot or "")) end
function Bridge.RequestInventory(bot) local t=makeToken("inv"); Bridge.Send("GET", "INVENTORY~" .. urlEncode(bot) .. "~" .. t); return t end
function Bridge.RequestBank(bot)      local t=makeToken("bank"); Bridge.Send("GET", "BANK~" .. urlEncode(bot) .. "~" .. t); return t end
function Bridge.RequestGuildBank(bot) local t=makeToken("gbank"); Bridge.Send("GET", "GBANK~" .. urlEncode(bot) .. "~" .. t); return t end
function Bridge.RequestTalentSpecList(bot) local t=makeToken("talents"); Bridge.Send("GET", "TALENT_SPEC_LIST~" .. urlEncode(bot) .. "~" .. t); return t end
function Bridge.RequestSpellbook(bot) local t=makeToken("spellbook"); Bridge.Send("GET", "SPELLBOOK~" .. urlEncode(bot) .. "~" .. t); return t end
function Bridge.RequestBotSkills(bot) local t=makeToken("skills"); Bridge.Send("GET", "BOT_SKILLS~" .. urlEncode(bot) .. "~" .. t); return t end
function Bridge.RequestBotReputations(bot) local t=makeToken("rep"); Bridge.Send("GET", "BOT_REPUTATIONS~" .. urlEncode(bot) .. "~" .. t); return t end
function Bridge.RequestBotEmblems(bot)     local t=makeToken("emblem"); Bridge.Send("GET", "BOT_EMBLEMS~" .. urlEncode(bot) .. "~" .. t); return t end
function Bridge.RequestProfessionRecipes(bot, skillId)
    local t=makeToken("recipes"); Bridge.Send("GET", "PROFESSION_RECIPES~" .. urlEncode(bot) .. "~" .. (skillId or 0) .. "~" .. t); return t
end
function Bridge.RequestGlyphs(bot)    local t=makeToken("glyphs"); Bridge.Send("GET", "GLYPHS~" .. urlEncode(bot) .. "~" .. t); return t end
function Bridge.RequestOutfits(bot)   local t=makeToken("outfits"); Bridge.Send("GET", "OUTFITS~" .. urlEncode(bot) .. "~" .. t); return t end
function Bridge.EquipOutfit(bot, outfitName, action)
    local t=makeToken("outfitcmd"); Bridge.Send("RUN", "OUTFIT~" .. urlEncode(bot) .. "~" .. t .. "~" .. urlEncode((outfitName or "") .. " " .. (action or "EQUIP")) .. "~1"); return t
end
function Bridge.RequestTrainer(bot)   local t=makeToken("trainer"); Bridge.Send("GET", "TRAINER~" .. urlEncode(bot) .. "~" .. t); return t end
function Bridge.RequestQuests(mode, bot) mode = string.upper(mode or "ALL")
    local t=makeToken("quests"); Bridge.Send("GET", "QUESTS~" .. mode .. "~" .. urlEncode(bot or "") .. "~" .. t); return t
end
function Bridge.RequestGameObjects(bot) Bridge.Send("GET", "GAMEOBJECTS~" .. bot) end
function Bridge.CraftRecipe(bot, skillId, spellId, itemId)
    local t=makeToken("craft"); Bridge.ProfessionCraftActions[t] = { botName = bot, skillId = tonumber(skillId) or 0, spellId = tonumber(spellId) or 0, itemId = tonumber(itemId) or 0 }; Bridge.Send("RUN", "CRAFT_RECIPE~" .. urlEncode(bot) .. "~" .. t .. "~" .. (skillId or 0) .. "~" .. (spellId or 0) .. "~" .. (itemId or 0)); return t
end
function Bridge.RunInventoryItemAction(bot, action, itemId, count)
    local t=makeToken("item"); action = string.upper(trim(action or "")); Bridge.InventoryItemActions[t] = { botName = bot, action = action, itemId = tonumber(itemId) or 0, count = tonumber(count) or 0 }; Bridge.Send("RUN", "ITEM_ACTION~" .. urlEncode(bot) .. "~" .. t .. "~" .. action .. "~" .. (itemId or 0) .. "~" .. (count or 0)); return t
end
function Bridge.LearnTrainerSpell(bot, trainerEntry, spellId)
    local t=makeToken("learn"); Bridge.Send("RUN", "TRAINER_LEARN~" .. urlEncode(bot) .. "~" .. t .. "~" .. (trainerEntry or 0) .. "~" .. (spellId or 0)); return t
end
function Bridge.TrainAllSpells(bot, trainerEntry) Bridge.LearnTrainerSpell(bot, trainerEntry, "ALL") end

-- ── Receive Handler ─────────────────────────────────────────
function Bridge.OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= Bridge.PREFIX then return end
    Bridge.DebugPrint("RX: " .. message:sub(1, 120) .. " (from " .. tostring(sender) .. ")")
    Bridge.Server = sender

    -- Split opcode from payload using ~
    local opcode, payload = splitOnce(message, "~")

    if opcode == "HELLO_ACK" then
        local ver, modName = splitOnce(payload or "", "~")
        Bridge.Connected = true
        Bridge.Protocol = ver or "1"
        Bridge.ServerName = modName or "mod-multibot-bridge"
        Bridge.FireCallback("Connected")
    elseif opcode == "HELLO_NACK" then
        Bridge.Connected = false
        Bridge.FireCallback("Disconnected", "Protocol mismatch")
    elseif opcode == "PING" then
        -- Respond to ping
        Bridge.Send("PONG", payload or "")
    elseif opcode == "PONG" then
        -- Bridge.FireCallback("Pong", payload)  -- Disabled - not needed
        -- Bridge.FireCallback("Pong", payload)
    elseif opcode == "ROSTER" then
        Bridge.ApplyRosterPayload(payload)
    elseif opcode == "STATES" then
        Bridge.ApplyStatesPayload(payload)
    elseif opcode == "STATE" then
        Bridge.ApplyStatePayload(payload)
    elseif opcode == "DETAIL" then
        Bridge.ApplyBotDetailPayload(payload)
    elseif opcode == "DETAILS" then
        Bridge.ApplyBotDetailsPayload(payload)
    elseif opcode == "STATS" then
        Bridge.ApplyStatsPayload(payload)
    elseif opcode == "PVP_STATS" then
        Bridge.ApplyPvpStatsPayload(payload)
    elseif opcode == "INV_BEGIN" or opcode == "INV_SUMMARY" or opcode == "INV_ITEM" or opcode == "INV_END" then
        Bridge.DebugPrint("[ROUTER] Routing INV_* message: opcode=" .. opcode .. " payload=" .. tostring(payload))
        Bridge.ApplyInventoryPayload(opcode .. "~" .. payload)
    elseif opcode == "INVENTORY" then
        Bridge.ApplyInventoryPayload(payload)
    elseif opcode == "BANK" or opcode == "BANK_BEGIN" or opcode == "BANK_SUMMARY" or opcode == "BANK_ITEM" or opcode == "BANK_ERROR" or opcode == "BANK_END" then
        Bridge.ApplyBankPayload(opcode .. "~" .. payload)
    elseif opcode == "GBANK" or opcode == "GBANK_BEGIN" or opcode == "GBANK_SUMMARY" or opcode == "GBANK_ITEM" or opcode == "GBANK_ERROR" or opcode == "GBANK_END" then
        Bridge.ApplyGuildBankPayload(opcode .. "~" .. payload)
    elseif opcode == "TALENT_SPEC_BEGIN" or opcode == "TALENT_SPEC_ITEM" or opcode == "TALENT_SPEC_END" then
        Bridge.ApplyTalentSpecPayload(opcode .. "~" .. payload)
    elseif opcode == "SPELLBOOK" or opcode == "SPELLBOOK_BEGIN" or opcode == "SPELLBOOK_SPELL" or opcode == "SPELLBOOK_END" or opcode == "SB_BEGIN" or opcode == "SB_ITEM" or opcode == "SB_END" then
        Bridge.ApplySpellbookPayload(opcode .. "~" .. payload)
    elseif opcode == "PROFESSION" then
        Bridge.ApplyProfessionPayload(opcode .. "~" .. payload)
    elseif opcode == "BOT_SKILLS" or opcode == "BOT_SKILLS_BEGIN" or opcode == "BOT_SKILLS_ITEM" or opcode == "BOT_SKILLS_END" then
        Bridge.ApplyBotSkillsPayload(opcode .. "~" .. payload)
    elseif opcode == "BOT_REPUTATIONS" or opcode == "BOT_REPUTATIONS_BEGIN" or opcode == "BOT_REPUTATION_ITEM" or opcode == "BOT_REPUTATION" or opcode == "BOT_REPUTATIONS_END" then
        Bridge.ApplyBotReputationsPayload(opcode .. "~" .. payload)
    elseif opcode == "BOT_EMBLEMS" then
        Bridge.ApplyBotEmblemsPayload(payload)
    elseif opcode == "PROFESSION_RECIPES" or opcode == "PROFESSION_RECIPES_BEGIN" or opcode == "PROFESSION_RECIPES_ITEM" or opcode == "PROFESSION_RECIPES_END" then
        Bridge.ApplyProfessionRecipesPayload(opcode .. "~" .. payload)
    elseif opcode == "GLYPHS" then
        Bridge.ApplyGlyphsPayload(payload)
    elseif opcode == "OUTFITS" or opcode == "OUTFITS_BEGIN" or opcode == "OUTFITS_ITEM" or opcode == "OUTFITS_END" or opcode == "OUTFITS_CMD" then
        Bridge.ApplyOutfitsPayload(opcode .. "~" .. payload)
    elseif opcode == "TRAINER" or opcode == "TRAINER_BEGIN" or opcode == "TRAINER_ITEM" or opcode == "TRAINER_SPELL" or opcode == "TRAINER_ERROR" or opcode == "TRAINER_END" then
        Bridge.ApplyTrainerPayload(opcode .. "~" .. payload)
    elseif opcode == "QUESTS" or opcode == "QUESTS_BEGIN" or opcode == "QUESTS_ITEM" or opcode == "QUESTS_END" or opcode == "QUESTS_DONE" then
        Bridge.ApplyQuestsPayload(opcode .. "~" .. payload)
    elseif opcode == "GAMEOBJECTS" then
        Bridge.ApplyGameObjectsPayload(payload)
    elseif opcode == "PROFESSION_RECIPE_CRAFT" or opcode == "CRAFT_RECIPE" then
        Bridge.ApplyCraftRecipeResult(payload)
    elseif opcode == "INVENTORY_ITEM_ACTION" then
        Bridge.ApplyInventoryItemActionPayload(payload)
    elseif opcode == "TRAINER_LEARN" then
        Bridge.ApplyTrainerLearnResult(payload)
    end
end

-- ── Payload Parsers ─────────────────────────────────────────

function Bridge.ApplyRosterPayload(payload)
    local roster = {}
    if type(payload) == "string" and payload ~= "" then
        for entry in string.gmatch(payload, "([^;]+)") do
            local fields = {}
            for value in string.gmatch(entry, "([^,]+)") do
                fields[#fields + 1] = value
            end
            if fields[1] and fields[1] ~= "" then
                roster[#roster + 1] = {
                    name = trim(fields[1]),
                    classId = tonumber(fields[2]) or 0,
                    level = tonumber(fields[3]) or 0,
                    mapId = tonumber(fields[4]) or 0,
                    alive = fields[5] == "1",
                    hpPct = tonumber(fields[6]) or 0,
                    mpPct = tonumber(fields[7]) or 0,
                }
            end
        end
    end
    Bridge.Roster = roster
    Bridge.DebugPrint("ROSTER: " .. #roster .. " bots")
    Bridge.FireCallback("RosterUpdated", roster)
    -- Request details for all bots
    if Bridge.Connected then
        Bridge.RequestBotDetails()
    end
end

function Bridge.ApplyStatesPayload(payload)
    local applied = 0
    if type(payload) == "string" and payload ~= "" then
        for entry in string.gmatch(payload, "([^;]+)") do
            if Bridge.ApplyStatePayload(entry) then
                applied = applied + 1
            end
        end
    end
    Bridge.DebugPrint("STATES: " .. applied .. " entries")
    Bridge.FireCallback("StatesUpdated", applied)
end

function Bridge.ApplyStatePayload(payload)
    local name, rest = splitOnce(payload or "", "~")
    local combat, normal = splitOnce(rest or "", "~")

    name = trim(name)
    if name == "" then return nil end

    local entry = {
        name = name,
        combat = combat or "",
        normal = normal or "",
    }
    Bridge.States[string.lower(name)] = entry

    -- Add to roster if not present
    local found = false
    for _, e in ipairs(Bridge.Roster) do
        if e.name == name then found = true; break end
    end
    if not found then
        local detail = Bridge.Details[string.lower(name)]
        local classId = detail and detail.className and (Bridge.ClassByName[string.lower(detail.className)] or 0) or 0
        table.insert(Bridge.Roster, {
            name = name,
            classId = classId,
            level = detail and detail.level or 0,
            mapId = 0,
            alive = true,
            hpPct = 100,
            mpPct = 100,
        })
    end

    Bridge.FireCallback("StateUpdated", name, entry)
    return entry
end

function Bridge.ApplyBotDetailPayload(payload)
    local name, rest = splitOnce(payload or "", "~")
    local race, rest2 = splitOnce(rest or "", "~")
    local gender, rest3 = splitOnce(rest2 or "", "~")
    local className, rest4 = splitOnce(rest3 or "", "~")
    local level, rest5 = splitOnce(rest4 or "", "~")
    local talent1, rest6 = splitOnce(rest5 or "", "~")
    local talent2, rest7 = splitOnce(rest6 or "", "~")
    local talent3, score = splitOnce(rest7 or "", "~")

    name = trim(urlDecode(name))
    if name == "" then return nil end

    local detail = {
        name = name,
        race = trim(urlDecode(race)),
        gender = trim(urlDecode(gender)),
        className = trim(urlDecode(className)),
        level = tonumber(level) or 0,
        talent1 = tonumber(talent1) or 0,
        talent2 = tonumber(talent2) or 0,
        talent3 = tonumber(talent3) or 0,
        score = tonumber(score) or 0,
    }
    Bridge.Details[string.lower(name)] = detail

    -- Add to roster if not present
    local found = false
    for _, e in ipairs(Bridge.Roster) do
        if e.name == name then found = true; break end
    end
    if not found then
        local classId = detail.className and (Bridge.ClassByName[string.lower(detail.className)] or 0) or 0
        table.insert(Bridge.Roster, {
            name = name,
            classId = classId,
            level = detail.level,
            mapId = 0,
            alive = true,
            hpPct = 100,
            mpPct = 100,
        })
    end

    Bridge.FireCallback("BotDetailUpdated", detail)
    Bridge.FireCallback("RosterUpdated", Bridge.Roster)
    return detail
end

function Bridge.ApplyBotDetailsPayload(payload)
    local applied = 0
    if type(payload) == "string" and payload ~= "" then
        for entry in string.gmatch(payload, "([^;]+)") do
            if Bridge.ApplyBotDetailPayload(entry) then
                applied = applied + 1
            end
        end
    end
    Bridge.DebugPrint("DETAILS: " .. applied .. " entries")
    Bridge.FireCallback("BotDetailsUpdated", applied)
    return applied
end

function Bridge.ApplyStatsPayload(payload)
    local name, rest = splitOnce(payload or "", "~")
    local level, rest2 = splitOnce(rest or "", "~")
    local gold, rest3 = splitOnce(rest2 or "", "~")
    local silver, rest4 = splitOnce(rest3 or "", "~")
    local copper, rest5 = splitOnce(rest4 or "", "~")
    local bagUsed, rest6 = splitOnce(rest5 or "", "~")
    local bagTotal, rest7 = splitOnce(rest6 or "", "~")
    local durabilityPct, rest8 = splitOnce(rest7 or "", "~")
    local xpPct, manaPct = splitOnce(rest8 or "", "~")

    name = trim(urlDecode(name))
    if name == "" then return nil end

    local stats = {
        name = name,
        level = tonumber(level) or 0,
        gold = tonumber(gold) or 0,
        silver = tonumber(silver) or 0,
        copper = tonumber(copper) or 0,
        bagUsed = tonumber(bagUsed) or 0,
        bagTotal = tonumber(bagTotal) or 0,
        durabilityPct = tonumber(durabilityPct) or 0,
        xpPct = tonumber(xpPct) or 0,
        manaPct = tonumber(manaPct) or 0,
    }
    Bridge.Stats[string.lower(name)] = stats

    Bridge.FireCallback("StatsUpdated", stats)
    return stats
end

function Bridge.ApplyPvpStatsPayload(payload)
    local name, rest = splitOnce(payload or "", "~")
    local arenaPoints, rest2 = splitOnce(rest or "", "~")
    local honorPoints, rest3 = splitOnce(rest2 or "", "~")
    local team2v2, rest4 = splitOnce(rest3 or "", "~")
    local rating2v2, rest5 = splitOnce(rest4 or "", "~")
    local team3v3, rest6 = splitOnce(rest5 or "", "~")
    local rating3v3, rest7 = splitOnce(rest6 or "", "~")
    local team5v5, rating5v5 = splitOnce(rest7 or "", "~")

    name = trim(urlDecode(name))
    if name == "" then return nil end

    local stats = {
        name = name,
        arenaPoints = tonumber(arenaPoints) or 0,
        honorPoints = tonumber(honorPoints) or 0,
        teams = {
            ["2v2"] = { team = trim(urlDecode(team2v2)), rating = tonumber(rating2v2) or 0 },
            ["3v3"] = { team = trim(urlDecode(team3v3)), rating = tonumber(rating3v3) or 0 },
            ["5v5"] = { team = trim(urlDecode(team5v5)), rating = tonumber(rating5v5) or 0 },
        },
    }
    Bridge.PvpStats[string.lower(name)] = stats

    Bridge.FireCallback("PvpStatsUpdated", stats)
    return stats
end

function Bridge.ApplyInventoryPayload(payload)
    local opcode, name, token, rest = parseOpcodePayload(payload)
    if name == "" then return end
    local key = string.lower(name)

    if opcode == "INV_BEGIN" then
        Bridge.Inventory[key] = { name = name, token = token, items = {}, goldCopper = 0, bagUsed = 0, bagTotal = 0, loading = true }
    elseif opcode == "INV_SUMMARY" then
        local gold, rest2 = splitOnce(rest, "~")
        local silver, rest3 = splitOnce(rest2, "~")
        local copper, rest4 = splitOnce(rest3, "~")
        local bagUsed, bagTotal = splitOnce(rest4, "~")
        local inv = Bridge.Inventory[key] or { name = name, items = {} }
        inv.token = token
        inv.goldCopper = (tonumber(gold) or 0) * 10000 + (tonumber(silver) or 0) * 100 + (tonumber(copper) or 0)
        inv.bagUsed = tonumber(bagUsed) or 0
        inv.bagTotal = tonumber(bagTotal) or 0
        Bridge.Inventory[key] = inv
    elseif opcode == "INV_ITEM" then
        local itemText = trim(urlDecode(rest))
        local inv = Bridge.Inventory[key] or { name = name, items = {} }
        inv.items = inv.items or {}
        if itemText ~= "" then
            table.insert(inv.items, { text = itemText, itemId = parseItemLinkId(itemText) })
        end
        Bridge.Inventory[key] = inv
    elseif opcode == "INV_END" then
        local inv = Bridge.Inventory[key] or { name = name, items = {} }
        inv.loading = false
        Bridge.Inventory[key] = inv
        Bridge.FireCallback("InventoryUpdated", name, inv)
    end
end

function Bridge.ApplyBankPayload(payload)
    local opcode, name, token, rest = parseOpcodePayload(payload)
    if name == "" then return end
    local key = string.lower(name)
    if opcode == "BANK_BEGIN" or opcode == "BANK" then
        Bridge.Bank[key] = { name = name, token = token, items = {}, loading = true }
    elseif opcode == "BANK_SUMMARY" then
        local numSlots, goldCopper = splitOnce(rest, "~")
        local bank = Bridge.Bank[key] or { name = name, items = {} }
        bank.numSlots = tonumber(numSlots) or 0
        bank.goldCopper = tonumber(goldCopper) or 0
        Bridge.Bank[key] = bank
        local inv = Bridge.Inventory[key]
        if inv then inv.bankGoldCopper = bank.goldCopper end
    elseif opcode == "BANK_ITEM" then
        local bank = Bridge.Bank[key] or { name = name, items = {} }
        bank.items = bank.items or {}
        local itemText = trim(urlDecode(rest))
        if itemText ~= "" then table.insert(bank.items, { text = itemText, itemId = parseItemLinkId(itemText) }) end
        Bridge.Bank[key] = bank
    elseif opcode == "BANK_ERROR" then
        local bank = Bridge.Bank[key] or { name = name, items = {} }
        bank.error = trim(urlDecode(rest))
        Bridge.Bank[key] = bank
    elseif opcode == "BANK_END" then
        local bank = Bridge.Bank[key] or { name = name, items = {} }
        bank.loading = false
        Bridge.Bank[key] = bank
        Bridge.FireCallback("BankUpdated", name, bank)
    end
end

function Bridge.ApplyGuildBankPayload(payload)
    -- GBANK_BEGIN~BotName~SessionID
    -- GBANK_SUMMARY~BotName~SessionID~NumSlots
    -- GBANK_ITEM~BotName~SessionID~ItemText
    -- GBANK_END~BotName~SessionID

    local parts = {}
    for s in string.gmatch(payload or "", "[^~]+") do table.insert(parts, s) end

    if #parts < 2 then return end

    local name = trim(parts[1])
    if name == "" then return end

    local opcode = parts[2]
    if opcode == "GBANK_BEGIN" then
        local gbank = { name = name, items = {} }
        Bridge.Bank[string.lower(name .. "_gbank")] = gbank
    elseif opcode == "GBANK_SUMMARY" and #parts >= 3 then
        local gbank = Bridge.Bank[string.lower(name .. "_gbank")] or { name = name, items = {} }
        gbank.numSlots = tonumber(parts[3]) or 0
        Bridge.Bank[string.lower(name .. "_gbank")] = gbank
    elseif opcode == "GBANK_ITEM" and #parts >= 4 then
        local gbank = Bridge.Bank[string.lower(name .. "_gbank")] or { name = name, items = {} }
        table.insert(gbank.items, trim(parts[4]))
        Bridge.Bank[string.lower(name .. "_gbank")] = gbank
    elseif opcode == "GBANK_END" then
        Bridge.FireCallback("GuildBankUpdated", name, Bridge.Bank[string.lower(name .. "_gbank")])
    end
end

function Bridge.ApplyTalentSpecPayload(payload)
    -- TALENT_SPEC_BEGIN~BotName~Token
    -- TALENT_SPEC_ITEM~BotName~Token~Index~SpecName~Build
    -- TALENT_SPEC_END~BotName~Token
    local opcode, name, token, rest = parseOpcodePayload(payload)
    if name == "" then return end
    local key = string.lower(name)

    if opcode == "TALENT_SPEC_BEGIN" then
        Bridge.TalentSpecs[key] = { name = name, token = token, specs = {}, loading = true }
    elseif opcode == "TALENT_SPEC_ITEM" then
        local index, rest2 = splitOnce(rest, "~")
        local specName, build = splitOnce(rest2, "~")
        local specs = Bridge.TalentSpecs[key] or { name = name, token = token, specs = {} }
        table.insert(specs.specs, {
            index = tonumber(index) or 0,
            name = trim(urlDecode(specName)),
            build = trim(build),
        })
        Bridge.TalentSpecs[key] = specs
    elseif opcode == "TALENT_SPEC_END" then
        local specs = Bridge.TalentSpecs[key] or { name = name, token = token, specs = {} }
        specs.loading = false
        Bridge.TalentSpecs[key] = specs
        Bridge.FireCallback("TalentSpecsUpdated", name, specs.specs)
    end
end

function Bridge.ApplySpellbookPayload(payload)
    -- SB_BEGIN~BotName~Token / SB_ITEM~BotName~Token~SpellId / SB_END~BotName~Token
    -- Legacy: SPELLBOOK_BEGIN~BotName~SessionID / SPELLBOOK_SPELL~BotName~SessionID~SpellId~Name~Rank~Cooldown~SpellLevel / SPELLBOOK_END~BotName~SessionID
    local opcode, name, token, rest = parseOpcodePayload(payload)
    if name == "" then return end
    local key = string.lower(name)

    if opcode == "SB_BEGIN" or opcode == "SPELLBOOK_BEGIN" then
        Bridge.Spellbook[key] = { name = name, token = token, spells = {}, loading = true }
    elseif opcode == "SB_ITEM" then
        local sb = Bridge.Spellbook[key] or { name = name, token = token, spells = {} }
        local spellId = tonumber(rest) or 0
        table.insert(sb.spells, { spellId = spellId, name = GetSpellInfo and GetSpellInfo(spellId) or nil })
        Bridge.Spellbook[key] = sb
    elseif opcode == "SPELLBOOK_SPELL" then
        local spellId, rest2 = splitOnce(rest, "~")
        local spellName, rest3 = splitOnce(rest2, "~")
        local rank, rest4 = splitOnce(rest3, "~")
        local cooldown, spellLevel = splitOnce(rest4, "~")
        local sb = Bridge.Spellbook[key] or { name = name, token = token, spells = {} }
        table.insert(sb.spells, {
            spellId = tonumber(spellId) or 0,
            name = trim(urlDecode(spellName)),
            rank = trim(urlDecode(rank)),
            cooldown = tonumber(cooldown) or 0,
            spellLevel = tonumber(spellLevel) or 0,
        })
        Bridge.Spellbook[key] = sb
    elseif opcode == "SB_END" or opcode == "SPELLBOOK_END" then
        local sb = Bridge.Spellbook[key] or { name = name, token = token, spells = {} }
        sb.loading = false
        Bridge.Spellbook[key] = sb
        Bridge.FireCallback("SpellbookUpdated", name, sb)
    end
end

function Bridge.ApplyBotSkillsPayload(payload)
    local opcode, name, token, rest = parseOpcodePayload(payload)
    if name == "" then return end
    local key = string.lower(name)
    if opcode == "BOT_SKILLS_BEGIN" or opcode == "BOT_SKILLS" then
        Bridge.Professions[key] = { name = name, token = token, skills = {}, primary = {}, secondary = {}, other = {}, loading = true }
    elseif opcode == "BOT_SKILLS_ITEM" then
        local category, rest2 = splitOnce(rest, "~")
        local skillId, rest3 = splitOnce(rest2, "~")
        local skillKey, rest4 = splitOnce(rest3, "~")
        local skillName, rest5 = splitOnce(rest4, "~")
        local value, maxValue = splitOnce(rest5, "~")
        local displayName = trim(urlDecode(skillName))
        local internalKey = string.lower(trim(urlDecode(skillKey)))
        local entry = {
            category = trim(urlDecode(category)), type = trim(urlDecode(category)),
            id = tonumber(skillId) or 0, key = internalKey,
            name = internalKey, displayName = displayName ~= "" and displayName or internalKey,
            value = tonumber(value) or 0, max = tonumber(maxValue) or 0,
        }
        local skills = Bridge.Professions[key] or { name = name, skills = {}, primary = {}, secondary = {}, other = {} }
        skills.skills[entry.id ~= 0 and entry.id or entry.displayName] = entry
        local secondary = { cooking=true, fishing=true, firstaid=true, ["first aid"]=true }
        if string.lower(entry.category) == "profession" then
            if secondary[internalKey] or secondary[string.lower(entry.displayName)] then table.insert(skills.secondary, entry) else table.insert(skills.primary, entry) end
        else
            table.insert(skills.other, entry)
        end
        Bridge.Professions[key] = skills
    elseif opcode == "BOT_SKILLS_END" then
        local skills = Bridge.Professions[key] or { name = name, skills = {}, primary = {}, secondary = {}, other = {} }
        skills.loading = false
        Bridge.Professions[key] = skills
        Bridge.FireCallback("BotSkillsUpdated", name, skills)
    end
end

function Bridge.ApplyProfessionPayload(payload)
    -- PROFESSION~BotName~profession1:value/max;profession2:value/max;...
    -- Example: PROFESSION~Shifty~leatherworking:45/75;skinning:30/75
    -- Or: PROFESSION~BotName~professionPayload (when called from OnAddonMessage)
    
    local parts = {}
    for s in string.gmatch(payload or "", "[^~]+") do table.insert(parts, s) end
    
    if #parts < 2 then return end
    
    -- Check if parts[1] is an opcode
    local name, professionStr
    if parts[1] == "PROFESSION" then
        name = trim(urlDecode(parts[2]))
        professionStr = parts[3] or ""
    else
        name = trim(urlDecode(parts[1]))
        professionStr = parts[2] or ""
    end
    
    if name == "" then return end
    
    local crafting = { name = name, professions = {} }
    
    -- Parse semicolon-separated profession entries
    for entry in string.gmatch(professionStr, "([^;]+)") do
        entry = trim(urlDecode(entry))
        if entry ~= "" then
            -- Each entry is like "leatherworking:45/75"
            local profName, value = splitOnce(entry, ":")
            profName = trim(profName)
            profName = string.lower(profName)
            
            if profName ~= "" and value and value ~= "" then
                -- Value is in format "level/max" (e.g., "45/75")
                local levelStr, maxStr = splitOnce(value, "/")
                levelStr = trim(levelStr)
                maxStr = trim(maxStr)
                
                -- Safety check: ensure these are actually numeric
                local levelNum = 0
                local maxNum = 0
                if levelStr and levelStr ~= "" then
                    local testNum = tonumber(levelStr)
                    if testNum then levelNum = testNum end
                end
                if maxStr and maxStr ~= "" then
                    local testNum = tonumber(maxStr)
                    if testNum then maxNum = testNum end
                end
                
                crafting.professions[profName] = {
                    name = profName,
                    level = levelNum,
                    max = maxNum,
                }
            end
        end
    end
    
    Bridge.Crafting[string.lower(name)] = crafting
    Bridge.DebugPrint("PROFESSION: stored crafting for " .. name .. " with " .. #crafting.professions .. " professions")
    Bridge.DebugPrint("PROFESSION: firing CraftingUpdated callback for " .. name)
    Bridge.FireCallback("CraftingUpdated", name, crafting)
end

function Bridge.ApplyBotReputationsPayload(payload)
    -- BOT_REPUTATIONS_BEGIN~BotName~SessionID
    -- BOT_REPUTATION_ITEM~BotName~SessionID~FactionId~Faction~Standing~Value~Max
    -- BOT_REPUTATIONS_END~BotName~SessionID

    local parts = {}
    for s in string.gmatch(payload or "", "[^~]+") do table.insert(parts, s) end

    if #parts < 2 then return end

    local opcode, name
    if tostring(parts[1]):find("^BOT_REPUT") then
        opcode = parts[1]
        name = trim(urlDecode(parts[2]))
        table.remove(parts, 1)
    else
        name = trim(urlDecode(parts[1]))
        opcode = parts[2]
    end
    if name == "" then return end
    local fieldOffset = (parts[2] == opcode) and 1 or 0
    if opcode == "BOT_REPUTATIONS_BEGIN" then
        local reps = { name = name, reputations = {} }
        Bridge.BotReputations = Bridge.BotReputations or {}
        Bridge.BotReputations[string.lower(name)] = reps
    elseif (opcode == "BOT_REPUTATION" or opcode == "BOT_REPUTATION_ITEM") and #parts >= 6 then
        local reps = Bridge.BotReputations and Bridge.BotReputations[string.lower(name)] or { name = name, reputations = {} }
        if opcode == "BOT_REPUTATION_ITEM" then
            local factionId = tonumber(parts[3 + fieldOffset]) or 0
            local factionName = trim(urlDecode(parts[4 + fieldOffset]))
            reps.reputations[factionName ~= "" and factionName or tostring(factionId)] = {
                factionId = factionId,
                standing = tonumber(parts[5 + fieldOffset]) or 0,
                value = tonumber(parts[6 + fieldOffset]) or 0,
                max = tonumber(parts[7 + fieldOffset]) or 0,
            }
        else
            reps.reputations[trim(parts[2 + fieldOffset])] = {
                standing = tonumber(parts[3 + fieldOffset]) or 0,
                value = tonumber(parts[4 + fieldOffset]) or 0,
                max = tonumber(parts[5 + fieldOffset]) or 0,
            }
        end
        Bridge.BotReputations[string.lower(name)] = reps
    elseif opcode == "BOT_REPUTATIONS_END" then
        Bridge.FireCallback("BotReputationsUpdated", name, Bridge.BotReputations and Bridge.BotReputations[string.lower(name)])
    end
end

function Bridge.ApplyBotEmblemsPayload(payload)
    -- BOT_EMBLEMS_BEGIN~BotName~SessionID
    -- BOT_EMBLEM~BotName~SessionID~EmblemId~Count
    -- BOT_EMBLEMS_END~BotName~SessionID
    -- BOT_EMBLEMS_MONEY~BotName~SessionID~Copper

    local parts = {}
    for s in string.gmatch(payload or "", "[^~]+") do table.insert(parts, s) end

    if #parts < 2 then return end

    local name = trim(parts[1])
    if name == "" then return end

    local opcode = parts[2]
    if opcode == "BOT_EMBLEMS_BEGIN" then
        local emblems = { name = name, emblems = {}, money = 0 }
        Bridge.BotEmblems = Bridge.BotEmblems or {}
        Bridge.BotEmblems[string.lower(name)] = emblems
    elseif opcode == "BOT_EMBLEM" and #parts >= 5 then
        local emblems = Bridge.BotEmblems and Bridge.BotEmblems[string.lower(name)] or { name = name, emblems = {} }
        emblems.emblems[tonumber(parts[3]) or 0] = tonumber(parts[4]) or 0
        Bridge.BotEmblems[string.lower(name)] = emblems
    elseif opcode == "BOT_EMBLEMS_MONEY" and #parts >= 3 then
        local emblems = Bridge.BotEmblems and Bridge.BotEmblems[string.lower(name)] or { name = name, money = 0 }
        emblems.money = tonumber(parts[3]) or 0
        Bridge.BotEmblems[string.lower(name)] = emblems
    elseif opcode == "BOT_EMBLEMS_END" then
        Bridge.FireCallback("BotEmblemsUpdated", name, Bridge.BotEmblems and Bridge.BotEmblems[string.lower(name)])
    end
end

function Bridge.ApplyProfessionRecipesPayload(payload)
    -- PROFESSION_RECIPES_BEGIN~BotName~Token~SkillId
    -- PROFESSION_RECIPES_ITEM~BotName~Token~SkillId~SpellId~ItemId~Difficulty~Craftable~Materials
    -- PROFESSION_RECIPES_END~BotName~Token~SkillId
    local opcode, name, token, rest = parseOpcodePayload(payload)
    if name == "" then return end

    if opcode == "PROFESSION_RECIPES_BEGIN" then
        local skillId = tonumber(rest) or 0
        local key = string.lower(name) .. ":" .. tostring(skillId)
        Bridge.ProfessionRecipes[key] = { name = name, token = token, skillId = skillId, recipes = {}, loading = true }
    elseif opcode == "PROFESSION_RECIPES_ITEM" then
        local skillId, rest2 = splitOnce(rest, "~")
        local spellId, rest3 = splitOnce(rest2, "~")
        local itemId, rest4 = splitOnce(rest3, "~")
        local difficulty, rest5 = splitOnce(rest4, "~")
        local craftable, materials = splitOnce(rest5, "~")
        skillId = tonumber(skillId) or 0
        local key = string.lower(name) .. ":" .. tostring(skillId)
        local recipes = Bridge.ProfessionRecipes[key] or { name = name, token = token, skillId = skillId, recipes = {} }
        table.insert(recipes.recipes, {
            skillId = skillId,
            spellId = tonumber(spellId) or 0,
            itemId = tonumber(itemId) or 0,
            difficulty = trim(urlDecode(difficulty)),
            craftable = tonumber(craftable) or 0,
            materials = trim(urlDecode(materials)),
        })
        Bridge.ProfessionRecipes[key] = recipes
    elseif opcode == "PROFESSION_RECIPES_END" then
        local skillId = tonumber(rest) or 0
        local key = string.lower(name) .. ":" .. tostring(skillId)
        local recipes = Bridge.ProfessionRecipes[key] or { name = name, token = token, skillId = skillId, recipes = {} }
        recipes.loading = false
        Bridge.ProfessionRecipes[key] = recipes
        Bridge.FireCallback("ProfessionRecipesUpdated", name, skillId, recipes.recipes)
    end
end

function Bridge.ApplyGlyphsPayload(payload)
    -- GLYPHS_BEGIN~BotName~SessionID
    -- GLYPH~BotName~SessionID~SocketIndex~GlyphSpellId~GlyphTooltip
    -- GLYPHS_END~BotName~SessionID

    local parts = {}
    for s in string.gmatch(payload or "", "[^~]+") do table.insert(parts, s) end

    if #parts < 2 then return end

    local name = trim(parts[1])
    if name == "" then return end

    local opcode = parts[2]
    if opcode == "GLYPHS_BEGIN" then
        local glyphs = { name = name, glyphs = {} }
        Bridge.Glyphs[string.lower(name)] = glyphs
    elseif opcode == "GLYPH" and #parts >= 5 then
        local glyphs = Bridge.Glyphs[string.lower(name)] or { name = name, glyphs = {} }
        table.insert(glyphs.glyphs, {
            socketIndex = tonumber(parts[3]) or 0,
            spellId = tonumber(parts[4]) or 0,
            tooltip = trim(parts[5]),
        })
        Bridge.Glyphs[string.lower(name)] = glyphs
    elseif opcode == "GLYPHS_END" then
        Bridge.FireCallback("GlyphsUpdated", name, Bridge.Glyphs[string.lower(name)])
    end
end

function Bridge.ApplyOutfitsPayload(payload)
    local opcode, name, token, rest = parseOpcodePayload(payload)
    if name == "" then return end
    local key = string.lower(name)
    if opcode == "OUTFITS_BEGIN" or opcode == "OUTFITS" then
        Bridge.Outfits[key] = { name = name, token = token, outfits = {}, loading = true }
    elseif opcode == "OUTFITS_ITEM" then
        local rawLine = trim(urlDecode(rest))
        local setName, itemText = splitOnce(rawLine, ":")
        local outfits = Bridge.Outfits[key] or { name = name, outfits = {} }
        table.insert(outfits.outfits, { name = trim(setName), raw = rawLine, items = trim(itemText) })
        Bridge.Outfits[key] = outfits
    elseif opcode == "OUTFITS_CMD" then
        Bridge.FireCallback("OutfitCommandResult", name, trim(rest))
    elseif opcode == "OUTFITS_END" then
        local outfits = Bridge.Outfits[key] or { name = name, outfits = {} }
        outfits.loading = false
        Bridge.Outfits[key] = outfits
        Bridge.FireCallback("OutfitsUpdated", name, outfits)
    end
end

function Bridge.ApplyTrainerPayload(payload)
    local opcode, name, token, rest = parseOpcodePayload(payload)
    if name == "" then return end
    local key = string.lower(name)
    if opcode == "TRAINER_BEGIN" or opcode == "TRAINER" then
        local trainerEntry, trainerName = splitOnce(rest, "~")
        Bridge.Trainer[key] = { name = name, token = token, trainerEntry = tonumber(trainerEntry) or 0, trainerName = trim(urlDecode(trainerName)), spells = {}, loading = true }
    elseif opcode == "TRAINER_ITEM" or opcode == "TRAINER_SPELL" then
        local trainerEntry, rest2 = splitOnce(rest, "~")
        local spellId, rest3 = splitOnce(rest2, "~")
        local cost, canAfford = splitOnce(rest3, "~")
        local trainer = Bridge.Trainer[key] or { name = name, spells = {} }
        local sid = tonumber(spellId) or 0
        local spellName = GetSpellInfo and GetSpellInfo(sid) or nil
        table.insert(trainer.spells, { trainerEntry = tonumber(trainerEntry) or trainer.trainerEntry or 0, spellId = sid, name = spellName or ("Spell #" .. tostring(sid)), cost = tonumber(cost) or 0, canAfford = tostring(canAfford) == "1" })
        Bridge.Trainer[key] = trainer
    elseif opcode == "TRAINER_ERROR" then
        local trainerEntry, reason = splitOnce(rest, "~")
        local trainer = Bridge.Trainer[key] or { name = name, spells = {} }
        trainer.trainerEntry = tonumber(trainerEntry) or trainer.trainerEntry or 0
        trainer.error = trim(urlDecode(reason)) ~= "" and trim(urlDecode(reason)) or "UNKNOWN_ERROR"
        Bridge.Trainer[key] = trainer
    elseif opcode == "TRAINER_END" then
        local trainer = Bridge.Trainer[key] or { name = name, spells = {} }
        trainer.loading = false
        Bridge.Trainer[key] = trainer
        Bridge.FireCallback("TrainerUpdated", name, trainer)
    end
end

function Bridge.ApplyQuestsPayload(payload)
    -- QUESTS_BEGIN~BotName~SessionID~Mode
    -- QUESTS_ITEM~BotName~SessionID~Mode~Status~QuestId~QuestName
    -- QUESTS_END~BotName~SessionID

    local parts = {}
    for s in string.gmatch(payload or "", "[^~]+") do table.insert(parts, s) end

    if #parts < 2 then return end

    local opcode, name
    if tostring(parts[1]):find("^QUESTS") then
        opcode = parts[1]
        name = trim(urlDecode(parts[2]))
        table.remove(parts, 1)
    else
        name = trim(urlDecode(parts[1]))
        opcode = parts[2]
    end
    if name == "" then return end
    local fieldOffset = (parts[2] == opcode) and 1 or 0
    if opcode == "QUESTS_BEGIN" and #parts >= 3 then
        local quests = {
            name = name,
            mode = trim(parts[3 + fieldOffset]),
            quests = {},
        }
        Bridge.Quests[string.lower(name)] = quests
    elseif opcode == "QUESTS_ITEM" and #parts >= 6 then
        local quests = Bridge.Quests[string.lower(name)] or { name = name, quests = {} }
        table.insert(quests.quests, {
            mode = trim(parts[3 + fieldOffset]),
            status = trim(parts[4 + fieldOffset]),
            questId = tonumber(parts[5 + fieldOffset]) or 0,
            questName = trim(urlDecode(parts[6 + fieldOffset])) or "",
        })
        Bridge.Quests[string.lower(name)] = quests
    elseif opcode == "QUESTS_END" then
        Bridge.FireCallback("QuestsUpdated", name, Bridge.Quests[string.lower(name)])
    end
end

function Bridge.ApplyGameObjectsPayload(payload)
    -- GAMEOBJECTS_BEGIN~BotName~SessionID
    -- GAMEOBJECT~BotName~SessionID~GoId~Name~Position
    -- GAMEOBJECTS_END~BotName~SessionID

    local parts = {}
    for s in string.gmatch(payload or "", "[^~]+") do table.insert(parts, s) end

    if #parts < 2 then return end

    local name = trim(parts[1])
    if name == "" then return end

    local opcode = parts[2]
    if opcode == "GAMEOBJECTS_BEGIN" then
        local gobs = { name = name, gameobjects = {} }
        Bridge.GameObjects[string.lower(name)] = gobs
    elseif opcode == "GAMEOBJECT" and #parts >= 5 then
        local gobs = Bridge.GameObjects[string.lower(name)] or { name = name, gameobjects = {} }
        table.insert(gobs.gameobjects, {
            goId = tonumber(parts[3]) or 0,
            name = trim(parts[4]),
            position = trim(parts[5]),
        })
        Bridge.GameObjects[string.lower(name)] = gobs
    elseif opcode == "GAMEOBJECTS_END" then
        Bridge.FireCallback("GameObjectsUpdated", name, Bridge.GameObjects[string.lower(name)])
    end
end

function Bridge.ApplyCraftRecipeResult(payload)
    -- PROFESSION_RECIPE_CRAFT~BotName~Token~SkillId~SpellId~ItemId~OK|ERR~Reason
    local name, rest = splitOnce(payload or "", "~")
    local token, rest2 = splitOnce(rest or "", "~")
    local skillId, rest3 = splitOnce(rest2 or "", "~")
    local spellId, rest4 = splitOnce(rest3 or "", "~")
    local itemId, rest5 = splitOnce(rest4 or "", "~")
    local status, reason = splitOnce(rest5 or "", "~")

    token = trim(token)
    local command = Bridge.ProfessionCraftActions[token] or {}
    local result = {
        botName = trim(urlDecode(name)) ~= "" and trim(urlDecode(name)) or command.botName,
        token = token,
        skillId = tonumber(skillId) or command.skillId or 0,
        spellId = tonumber(spellId) or command.spellId or 0,
        itemId = tonumber(itemId) or command.itemId or 0,
        result = trim(status),
        reason = trim(urlDecode(reason)),
    }

    Bridge.ProfessionCraftActions[token] = nil
    Bridge.FireCallback("ProfessionCraftResult", result)
    Bridge.FireCallback("CraftRecipeResult", result) -- legacy callback alias
end

function Bridge.ApplyInventoryItemActionPayload(payload)
    -- INVENTORY_ITEM_ACTION~BotName~Token~Action~ItemId~OK|ERR~Reason~Moved
    local name, rest = splitOnce(payload or "", "~")
    local token, rest2 = splitOnce(rest or "", "~")
    local action, rest3 = splitOnce(rest2 or "", "~")
    local itemId, rest4 = splitOnce(rest3 or "", "~")
    local status, rest5 = splitOnce(rest4 or "", "~")
    local reason, moved = splitOnce(rest5 or "", "~")

    token = trim(token)
    local command = Bridge.InventoryItemActions[token] or {}
    local result = {
        botName = trim(urlDecode(name)) ~= "" and trim(urlDecode(name)) or command.botName,
        token = token,
        action = string.upper(trim(action ~= "" and action or command.action or "")),
        itemId = tonumber(itemId) or command.itemId or 0,
        result = trim(status),
        reason = trim(urlDecode(reason)),
        moved = tonumber(moved) or 0,
        count = command.count,
    }

    Bridge.InventoryItemActions[token] = nil
    Bridge.FireCallback("InventoryItemActionResult", result)
end

function Bridge.ApplyTrainerLearnResult(payload)
    -- TRAINER_LEARN~BotName~Token~TrainerEntry~SpellId~Result~Reason~LearnedCount~Spent

    local parts = {}
    for s in string.gmatch(payload or "", "[^~]+") do table.insert(parts, s) end

    if #parts < 8 then return end

    local result = {
        botName = trim(parts[1]),
        token = trim(parts[2]),
        trainerEntry = tonumber(parts[3]) or 0,
        spellId = trim(parts[4]),
        result = trim(parts[5]),
        reason = trim(parts[6]),
        learnedCount = tonumber(parts[7]) or 0,
        spent = tonumber(parts[8]) or 0,
    }

    Bridge.FireCallback("TrainerLearnResult", result)
end

-- Class name lookup (reverse of ClassById)
function Bridge.GetClassIdByName(className)
    if not className then return 0 end
    local lower = string.lower(className)
    for id, name in pairs(Bridge.ClassById) do
        if string.lower(name) == lower then
            return id
        end
    end
    return 0
end

-- ── Initialize on PLAYER_LOGIN ──────────────────────────────

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    Bridge.SendHello()
    Bridge.StartPingTimer()
end)

function Bridge.StartPingTimer()
    if Bridge.PingFrame then return end
    local frame = CreateFrame("Frame")
    Bridge.PingFrame = frame
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", function()
        Bridge.SendHello()
    end)
    frame:SetScript("OnUpdate", function(self, elapsed)
        local now = GetTime() or 0
        Bridge._pingTimerAccum = (Bridge._pingTimerAccum or 0) + elapsed
        if Bridge._pingTimerAccum >= 15 then
            Bridge._pingTimerAccum = 0
            if not Bridge.Connected then
                Bridge.SendHello()
            else
                Bridge.SendPing()
            end
        end
    end)
end

-- Expose for external access
_G.PBAMBridge = Bridge
