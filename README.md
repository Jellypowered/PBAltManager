# PBAltManager Extended

PBAltManager is a dark-and-gold World of Warcraft WotLK (3.3.5a) addon for managing playerbot alts through `mod-multibot-bridge`.

It brings the most useful day-to-day bot management tools into one window with a compact roster, dropdown tab navigation, and bridge-first data loading.

> **Extended Branch**: This branch (`Extended`) contains the latest features, native bridge endpoints, and performance optimizations. For stable production use, see the `main` branch.

---

## 🌿 Branch Comparison

| Feature | main Branch | Extended Branch (this) |
|---------|-------------|------------------------|
| **Protocol** | `MBOT` prefix | `PBAM` prefix |
| **Native Bridge Endpoints** | ❌ None | ✅ 8 endpoints |
| **Inventory Bag Filtering** | ❌ No | ✅ With dropdown UI |
| **Targeted Crafting** | ❌ Manual only | ✅ Targeted craft modes |
| **Trade Mode** | ✅ Basic (legacy) | ✅ Enhanced (native bridge) |
| **Talent Reset** | Basic | ✅ Custom builds + 0-0-0 reset |
| **Quest Support** | ❌ None | ✅ Abandon/share via bridge |
| **Optimizations** | Standard | ✅ Throttling, debouncing, batching |

> **Important**: The Extended branch requires the [Extended fork of mod-multibot-bridge](https://github.com/Jellypowered/mod-multibot-bridge/tree/Extended).

**See the full [feature comparison](#feature-comparison) below for details.**

## 📘 Full Documentation Wiki

**Use the wiki for setup help, tab-by-tab guides, troubleshooting, limitations, and roadmap updates:**

**[Open the PBAltManager Wiki](https://github.com/Jellypowered/PBAltManager/wiki)**

## Features

- Roster overview for bots and the logged-in player (with roster sort options)
- Talents viewer/planner with native bridge talent apply (including custom builds and reset via 0-0-0)
- Inventory view with exact item locations, bag entries, and equipment tabs
- Bank view (when banker is nearby)
- Professions and recipe browser with targeted craft modes (normal, trade slot, bag item, equipped item)
- Spells tab with native bridge spell casting and detailed failure reason mapping
- Trainer spell view and learning
- Equipment tab with bridge data display and fallback to inspect
- Outfits view
- Search/filter tools and minimap launcher
- Options panel with Silent Mode, Debug Mode, Hide Minimap Button, Suppress Legacy Sending, Confirm Destructive Actions, Default Roster Sort, and Refresh Throttle

## Requirements

- **Client:** WoW WotLK 3.3.5a (12340)
- **Server:** AzerothCore with `mod-playerbots`
- **Bridge:** `mod-multibot-bridge`

## Installation

1. Put this folder in:
   ```text
   World of Warcraft/Interface/AddOns/PBAltManager/
   ```
2. Make sure `mod-multibot-bridge` is built and enabled on the server.
3. Enable the addon at character select.
4. Log in and use `/pbam`.

## Slash Commands

| Command | Description |
|---|---|
| `/pbam` | Toggle the main window |
| `/pbam show` | Show the window |
| `/pbam hide` | Hide the window |
| `/pbam refresh` | Refresh current data |
| `/pbam debug` | Toggle debug logging |
| `/pbam about` | Version info |

## Current Notes

- PBAltManager co-exists with Multibot-Chatless and CleanBot.
- All planned implementation phases are complete. See [Roadmap](https://github.com/Jellypowered/PBAltManager/wiki/Roadmap).
- The logged-in player is supported primarily through the Roster tab; bot-only tabs may hide when your own character is selected.
- The clear-selection button now performs a full PBAltManager UI reset to get back to a fresh-start style state without reloading the whole WoW UI, followed by a delayed full refresh after bridge data has time to return.
- Bot quests in the Roster tab are rendered as clickable quest links when bridge quest IDs are available.

---

## 🌟 Feature Comparison: main vs Extended

### Native Bridge Endpoints (Extended only)

| Action | Purpose |
|--------|---------|
| `CAST_SPELL` | Cast spells with detailed failure reason mapping |
| `QUEST_ABANDON` | Abandon quests directly via bridge |
| `QUEST_SHARE` | Share quests to other players via bridge |
| `ITEM_EQUIP` | Equip items with bag/slot support (not just slot hint) |
| `BAG_MOVE` | Move entire bags between slots |
| `ITEM_TRADE` | Trade items with bag/slot source specification |
| `TALENT_APPLY` | Apply talent builds including custom builds and reset via 0-0-0 |
| `CRAFT_RECIPE_TARGET` | Targeted crafting with modes: normal, trade slot, bag item, equipped item |

### Trade Mode Comparison

| Aspect | main Branch | Extended Branch |
|--------|-------------|-----------------|
| **Method** | Legacy chat command (`t <itemLink> 1`) | Native bridge endpoint (`ITEM_TRADE`) |
| **Targeting** | Manual target selection | Auto-targets player |
| **Source Spec** | Item only | Item + bag/slot source |
| **Reliability** | Depends on chat parsing | Direct bridge integration |
| **Requirements** | Works with stock bridge | Requires Extended mod-multibot-bridge fork |

### Inventory Tab Enhancements (Extended only)

- ✅ **Bag filtering UI** - Filter inventory by equipped bag slots with dropdown
- ✅ **Exact location tracking** - `INV_BAG` and `INV_ITEM_LOC` packets provide precise bag+slot locations
- ✅ **Equipped bag visualization** - Shows backpack + 4 equipped bag slots (slots 1-4)
- ✅ **Per-bag empty states** - Context-aware messages when specific bags are empty

### Professions Tab Enhancements (Extended only)

- ✅ **Target mode dropdown** - Select from: Normal, Trade Slot, Bag Item, Equipped Item
- ✅ **Target item dropdown** - Populate craft targets from inventory
- ✅ **Trade event integration** - Listens for `TRADE_SHOW`, `TRADE_CLOSED`, `TRADE_TARGET_ITEM_CHANGED`, etc.
- ✅ **Enhanced status messages** - Detailed feedback on cast results and trade state

### Performance Optimizations (Extended)

- ✅ **Roster refresh batching** - Reduces UI freezes during bulk operations
- ✅ **Duplicate request throttling** - Configurable 100-5000ms delay to prevent duplicate bridge requests
- ✅ **Callback debouncing** - Prevents callback cascades that cause token collisions
- ✅ **Better token handling** - Unique tokens for async responses to prevent data loss

---

## 📊 Version Stats

| Metric | Value |
|--------|-------|
| Commits ahead of main | 4 commits |
| Files changed | 11 files |
| Lines added | +1,794 |
| Lines removed | -338 |

---

## 🚀 Getting Started with Extended

> **⚠️ Requirement**: This branch requires the [Extended fork of mod-multibot-bridge](https://github.com/Jellypowered/mod-multibot-bridge).

To set up:

```bash
cd azerothcore-wotlk/modules
rm -rf mod-multibot-bridge  # Remove stock version if present
git clone https://github.com/Jellypowered/mod-multibot-bridge.git
cd mod-multibot-bridge
git switch Extended
# Rebuild your server
```

Once set up:

1. The `PBAM` protocol prefix is used automatically
2. Native endpoints are available on first load
3. New UI elements appear in the Inventory and Professions tabs
4. Check the [Inventory](https://github.com/Jellypowered/PBAltManager/wiki/Inventory) and [Professions](https://github.com/Jellypowered/PBAltManager/wiki/Professions) wiki pages for usage guides

## Documentation

For full usage information, troubleshooting, limitations, and roadmap details, use the wiki:

- [Wiki Home](https://github.com/Jellypowered/PBAltManager/wiki)
- [Getting Started](https://github.com/Jellypowered/PBAltManager/wiki/Getting-Started)
- [Roster](https://github.com/Jellypowered/PBAltManager/wiki/Roster)
- [Inventory](https://github.com/Jellypowered/PBAltManager/wiki/Inventory)
- [Professions](https://github.com/Jellypowered/PBAltManager/wiki/Professions)
- [Talents](https://github.com/Jellypowered/PBAltManager/wiki/Talents)
- [Trainer](https://github.com/Jellypowered/PBAltManager/wiki/Trainer)
- [Equipment](https://github.com/Jellypowered/PBAltManager/wiki/Equipment)
- [Troubleshooting](https://github.com/Jellypowered/PBAltManager/wiki/Troubleshooting)
- [Known Limitations](https://github.com/Jellypowered/PBAltManager/wiki/Known-Limitations)
- [Roadmap](https://github.com/Jellypowered/PBAltManager/wiki/Roadmap)
- [Contributing](https://github.com/Jellypowered/PBAltManager/wiki/Contributing)

## Related Projects

- [mod-quest-catchup](https://github.com/Jellypowered/mod-quest-catchup) — Quest progress syncing between players
- [mod-xpcatchup](https://github.com/Jellypowered/mod-xpcatchup) — Dynamic XP redistribution for groups

Developer planning details remain in:

- [`plan.md`](plan.md)
- [`bridgeplan.md`](bridgeplan.md)

## Credits

- [PlayerbotManager](https://github.com/Lichborne-AC/PlayerBotManager)
- [MultiBot-Chatless](https://github.com/Wishmaster117/MultiBot-Chatless)
- [mod-multibot-bridge](https://github.com/Wishmaster117/mod-multibot-bridge)
- [CleanBot](https://github.com/bennybroseph/CleanBot)
- AzerothCore / mod-playerbots ecosystem
