# PBAltManager Historical Plan / Changelog

This document is now a historical reference for the implementation work that was completed.

Active user documentation should live in the wiki:

- `PBAltManager.wiki/Home.md`
- `PBAltManager.wiki/Getting-Started.md`
- tab pages under `PBAltManager.wiki/`

Active bridge follow-up proposals live in:

- `bridgeplan.md`

---

# Project Summary

PBAltManager was built as a compact World of Warcraft WotLK (3.3.5a) addon for managing playerbot alts through `mod-multibot-bridge`, while co-existing with tools like MultiBot-Chatless and CleanBot.

Major completed outcomes:

- unified roster with local-player support
- talents tab with bridge data + legacy apply fallback
- inventory and bank tab with equip/trade workflows
- professions tab with recipe browser and crafting support
- spells tab for non-profession spellbook browsing and legacy cast MVP
- trainer tab
- equipment/outfits tab
- dropdown tab navigation
- shared helper layer
- wiki + README cleanup

---

# Final Completed Work Order

1. Phase 1 — bridge coverage cleanup ✅
2. Phase 2 — talents apply MVP and follow-up talent builder polish ✅
3. Phase 3 — inventory equip/trade MVP with clear unsupported/legacy paths ✅
4. Phase 4 — professions crafting ✅
5. Phase 6 — polish / UX unification ✅
6. Phase 8 — dropdown tab navigation ✅
7. Phase 5 — spells tab list-only + controlled legacy cast MVP ✅
8. Phase 7 — bridge enhancement proposal documentation ✅
9. Phase 9 — code cleanup and contributor comments ✅
10. Phase 10 — wiki / documentation refresh ✅

---

# Phase Summary

## Phase 1 — Bridge cleanup

Completed:

- parser/callback support expanded and stabilized in `PBAM_Bridge.lua`
- bridge request/response handling organized around the implemented UI tabs
- roster/detail/state/stat loading established as the core data flow

## Phase 2 — Talents

Completed:

- Talents tab built
- bridge detail/spec list loading integrated
- custom talent planning supported
- premade spec selection supported
- controlled legacy talent apply flow used until a native bridge endpoint exists

Known lasting note:

- full structured bridge talent apply/reset remains a future bridge concern documented in `bridgeplan.md`

## Phase 3 — Inventory actions

Completed:

- inventory list and bank view
- Equip Mode
- Trade Mode
- target selection for trade workflows
- bridge-backed item actions where available
- controlled legacy fallback for equip/trade where bridge coverage is incomplete

## Phase 4 — Professions

Completed:

- profession summary view
- primary/secondary grouping
- recipe browser
- material display with icons/counts
- craft one / craft all behavior
- special handling for utility profession entries such as Basic Campfire

Known lasting note:

- item-target profession actions still belong in future bridge expansion work

## Phase 5 — Spells tab

Completed:

- new `PBAM_Tab_Spells.lua`
- bridge spellbook browsing
- local search/filter
- local deny-lists for race/class/profession cleanup
- real game tooltip usage when available
- legacy cast MVP

Known lasting note:

- structured bridge spell execution remains future work in `bridgeplan.md`

## Phase 6 — Polish / UX unification

Completed:

- `PBAM_Helpers.lua` added and wired into TOC
- shared helpers for wrapping, status text, dropdowns, selection state, and button disabling
- local-player behavior improved in Roster
- hidden bot-only tabs when the logged-in player is selected
- refresh behavior standardized through tab refresh hooks
- status/feedback polish applied across tabs
- final Phase 6 UX sweep completed

## Phase 7 — Bridge enhancement proposals

Completed as documentation/planning:

- `bridgeplan.md` updated to reflect the real post-implementation state
- proposed future bridge endpoints documented for:
  - talent apply/reset
  - inventory equip
  - inventory trade
  - generic spell cast
  - related structured result/error flows

## Phase 8 — Dropdown tab navigation

Completed:

- visible tab row replaced by dropdown navigation
- existing `PBAM.RegisterTab()` ordering preserved
- hidden-tab logic integrated cleanly with dropdown navigation
- current tab label updates through the dropdown control

## Phase 9 — Code cleanup and contributor comments

Completed:

- readability and structure pass performed
- bridge-vs-legacy execution boundaries clarified in comments
- key navigation/refresh/spell execution areas annotated for future contributors
- README reduced to a quick summary while deeper documentation moved to the wiki

## Phase 10 — Wiki / documentation refresh

Completed:

- wiki expanded into user-facing documentation
- tab pages added/refined, including Spells
- troubleshooting and limitations expanded
- credits page updated
- README updated with prominent wiki link and brief overview format

---

# Historical Notes

## README direction

The README is intentionally short now:

- quick summary
- requirements
- install steps
- slash commands
- prominent wiki link

Detailed usage/troubleshooting/reference material was moved to the wiki.

## Local-player support direction

The logged-in player is supported primarily through Roster.
Bot-only tabs may be hidden when the player is selected unless a local version of that feature exists.

## Legacy fallback philosophy

Where bridge support was missing, PBAltManager preferred controlled, clearly labeled fallback behavior instead of pretending a native bridge action existed.
This especially affected:

- talent apply
- inventory equip
- inventory trade
- spell cast

---

# Current Reference Files

- `README.md` — quick summary
- `bridgeplan.md` — future bridge endpoint proposals
- `PBAltManager.wiki/` — user-facing documentation

This file remains as a compact historical record of what was planned and completed.
