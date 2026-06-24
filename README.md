# PBAltManager

PBAltManager is a dark-and-gold World of Warcraft WotLK (3.3.5a) addon for managing playerbot alts through `mod-multibot-bridge`.

It brings the most useful day-to-day bot management tools into one window with a compact roster, dropdown tab navigation, and bridge-first data loading.

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
- Native bridge endpoints implemented: QUEST_ABANDON, QUEST_SHARE, ITEM_EQUIP (with bag support), ITEM_TRADE, CAST_SPELL (with detailed failure reasons), TALENT_APPLY (including custom builds and reset via 0-0-0), CRAFT_RECIPE_TARGET (targeted craft with bag/trade/equip modes), INVENTORY_BULK, BOT_SKILLS_BULK.
- Inventory packets INV_BAG, INV_ITEM_LOC, and INV_EQUIP_LOC provide exact bag/slot locations for items and equipment.
- Recent optimization work reduces client hangs by throttling duplicate bridge requests (configurable 100-5000ms), debouncing callbacks, and batching roster refreshes. Some roster/sidebar sort data may appear slightly slower during initial loading, but the client stays more responsive.

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
