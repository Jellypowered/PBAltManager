# PBAltManager Bridge Enhancement Plan

Status: **Active planning** — last reviewed 2026-06-14.

PBAltManager currently uses a hybrid approach: bridge-first data loading with controlled legacy whisper fallbacks for write actions. This document outlines the missing/ desired server-side bridge endpoints that would replace those remaining legacy paths.

Each section describes:
- **Current behavior** — how PBAltManager handles it today
- **Proposed endpoint** — the future bridge pattern
- **Required behavior** — what the server module needs to support

---

## 1. Spell Cast

### Current behavior

The Spells tab uses bridge data for spellbook listing, but casting still relies on a legacy whisper fallback:

```text
/w <bot> cast <spell> [on <target>]
```

This works but provides no structured success/failure response. Multi-word spell names are handled by parsing the last ` on ` as the target separator.

### Proposed endpoint

```
REQUEST:  RUN~CAST_SPELL~bot~token~spellId~targetName
RESPONSE: CAST_SPELL~bot~token~OK|ERR~reason
```

### Required behavior

- Cast by spell ID from bridge spellbook data
- Optional `targetName` for buffs/heals (empty string = self/current target)
- Return structured reasons: `MISSING_SPELL`, `INVALID_TARGET`, `OUT_OF_RANGE`, `NO_MANA`, `COOLDOWN`, `REAGENTS`

---

## 2. Quest Actions (Abandon / Share)

### Current behavior

Roster displays bridge quest data via `GET~QUESTS`. Abandon and Share use legacy playerbot commands:

- **Abandon:** `drop <questId>` — works, then refreshes after a delay
- **Share:** disabled for bots — playerbot does not support bot-to-bot quest sharing; manual workaround is `/w <botname> q <questId>`

### Proposed endpoints

```
REQUEST:  RUN~QUEST_ABANDON~bot~token~questId
RESPONSE: QUEST_ABANDON~bot~token~OK|ERR~reason

REQUEST:  RUN~QUEST_SHARE~bot~token~questId~targetName
RESPONSE: QUEST_SHARE~bot~token~OK|ERR~reason
```

### Required behavior

- Validate the bot has the quest before abandoning
- For share, validate the target can receive the quest
- Return structured reasons: `MISSING_QUEST`, `NOT_SHAREABLE`, `INVALID_TARGET`, `QUEST_LOG_FULL`, `OUT_OF_RANGE`
- Trigger a quest data refresh after successful actions

---

## 3. Inventory Equip

### Current behavior

Equip Mode uses legacy whisper fallback:

```text
/w <bot> e <itemLink>
```

This works client-side but provides no structured success/failure response.

### Proposed endpoint

```
REQUEST:  RUN~ITEM_EQUIP~bot~token~itemId~slotHint
RESPONSE: ITEM_EQUIP~bot~token~OK|ERR~reason
```

**`slotHint` values:** `AUTO`, `MAIN_HAND`, `OFF_HAND`

### Required behavior

- Equip by item ID from the selected bot's inventory
- Respect main-hand/off-hand hints where applicable
- Return structured reasons: `NOT_EQUIPPABLE`, `MISSING_ITEM`, `WRONG_CLASS`, `WRONG_LEVEL`, `SLOT_BLOCKED`
- Refresh/effect observable via existing inventory/equipment requests

---

## 4. Inventory Trade

### Current behavior

Trade Mode calls `InitiateTrade(botName)` to open the trade window, then item clicks send:

```text
/w <bot> t <itemLink> 1
```

PBAM must preserve/rebuild a real `|Hitem:` link (preferably via `GetItemInfo(itemId)`). The trailing `1` maps to mod-playerbots `TradeAction` count parsing and limits insertion to one trade slot/stack.

### Proposed endpoint

```
REQUEST:  RUN~ITEM_TRADE~bot~token~itemId~targetName~count
RESPONSE: ITEM_TRADE~bot~token~OK|ERR~reason~moved
```

### Required behavior

- Validate target is a player/party/raid/allowed bot target
- Move exactly the requested item count/stack when possible
- Return structured reasons: `INVALID_TARGET`, `OUT_OF_RANGE`, `MISSING_ITEM`, `TRADE_BUSY`, `COUNT_UNAVAILABLE`
- Include `moved` count in the response

---

## 5. Profession Target-Item Craft / Enhancement

### Current issue

`RUN~CRAFT_RECIPE` handles simple material-consuming crafts, but PBAM cannot reliably complete profession actions that must apply to a **selected item**, such as:

- Enchanting enchants
- Armor kits, sharpening/weight stones
- Inscriptions
- Engineering item modifications
- Similar item-enhancement workflows

### Proposed endpoint

```
REQUEST:  RUN~CRAFT_RECIPE_TARGET~bot~token~skillId~spellId~targetItemId~targetBag~targetSlot
RESPONSE: CRAFT_RECIPE_TARGET~bot~token~OK|ERR~reason
```

**Alternative if bag/slot is not feasible:**

```
REQUEST:  RUN~CRAFT_RECIPE_TARGET~bot~token~skillId~spellId~targetItemGuidOrLink
RESPONSE: CRAFT_RECIPE_TARGET~bot~token~OK|ERR~reason
```

### Required behavior

- Validate bot knows the recipe and has the matching profession skill
- Validate required materials/tools/focus
- Validate the target item is in the bot's inventory/equipment/bank scope allowed by the endpoint
- Apply the spell to the **exact selected target item**, not just the first matching name/id
- Return structured reasons: `MISSING_TARGET_ITEM`, `INVALID_TARGET_ITEM`, `NO_MATERIALS`, `MISSING_TOOLS`, `REQUIRES_SPELL_FOCUS`, `SKILL_MISMATCH`, `UNKNOWN_RECIPE`, `CAST_FAILED_*`

---

## 6. Talent Apply / Reset

### Current behavior

- Refresh/read talent details through existing bridge data ✅
- Apply non-empty custom talent builds and named premade specs via legacy whisper fallback
- Cannot reset talents to `0, 0, 0` — the playerbot command rejects all-zero apply strings with `Invalid link`

### Proposed endpoint

```
REQUEST:  RUN~TALENT_APPLY~bot~token~buildString~dryRunFlag
RESPONSE: TALENT_APPLY~bot~token~OK|ERR~reason~summary
```

### Required behavior

- Accept full rank-by-rank build strings
- Support an explicit reset/empty build mode or a separate reset endpoint
- Return structured error reasons for invalid dependency/tier/rank states
- Dry-run flag for previewing a build without committing

---

## Priority Order (Suggested)

| Priority | Endpoint | Why |
|----------|----------|-----|
| 1 | Spell Cast | High-frequency action, currently fully legacy |
| 2 | Quest Abandon/Share | Already works via legacy; structured responses would improve UX |
| 3 | Inventory Equip | Simple one-to-one replacement of `e <itemLink>` |
| 4 | Inventory Trade | More complex (trade window state), but valuable for workflow |
| 5 | Profession Target-Item | Needed for full profession tab parity |
| 6 | Talent Apply/Reset | Lower frequency; reset is a known edge case |

---

## Implementation Notes

- All endpoints follow the existing bridge token pattern: `RUN~<ACTION>~bot~token~params` → `<ACTION>~bot~token~OK|ERR~details`
- Response format is consistent: `OK` or `ERR` followed by a reason string and optional additional data
- Bridge requests should trigger appropriate client-side refreshes (inventory, spells, quests) automatically where relevant
- The bridge module (`mod-multibot-bridge`) should validate all inputs before forwarding to mod-playerbots commands
