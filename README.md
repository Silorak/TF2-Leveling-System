<div align="center">

# TF2 Leveling System

[![Version](https://img.shields.io/badge/version-1.4.0-blue?style=for-the-badge)](https://github.com/Silorak/TF2-Leveling-System/releases)
[![SourceMod](https://img.shields.io/badge/SourceMod-1.12-orange?style=for-the-badge)](https://www.sourcemod.net/)
[![License](https://img.shields.io/badge/license-GPL%20v3-green?style=for-the-badge)](LICENSE)

A modular XP and leveling system for TF2 servers with cosmetic rewards, chat tags, and VIP features.

[Installation](#installation) · [Configuration](#configuration) · [Commands](#commands) · [API](#developer-api)

</div>

---

## Architecture

| Plugin | File | Purpose |
|--------|------|---------|
| **Core** | `leveling_core.smx` | Database, XP/level logic, admin commands, all natives |
| **Chat** | `leveling_chat.smx` | Chat tags with hex color support via Chat Processor |
| **Cosmetics** | `leveling_cosmetics.smx` | Trails, auras, models, sheens, killstreakers, death effects, pets, spawn particles |
| **VIP** | `leveling_vip.smx` | Custom welcome messages and chat tags |
| **Visuals** | `leveling_visuals.smx` | HUD progress bar, floating XP, level-up effects |

**Core is required.** The other four are optional.

---

## Features

**Leveling** — 50 levels with configurable exponential XP scaling. XP from kills (bots excluded), revenge bonuses, and a donor multiplier. Auto-save with transaction batching. MySQL and SQLite supported. Dead Ringer feign deaths filtered.

**Chat Tags** — Level-based colored tags using `{#RRGGBB}` hex format. Bots excluded. VIPs can set custom tags via `!customtag`.

**Cosmetics** — Nine cosmetic types, all config-driven with per-item level gates and optional admin flag restrictions:

| Type | Description |
|------|-------------|
| **Trails** | Sprite-based with configurable color, width, lifetime |
| **Auras** | Taunt unusual particles (utaunt_*) at player feet |
| **Models** | Player model overrides with automatic wearable hiding |
| **Sheens** | Weapon sheen colors via TF2Attributes (7 colors) |
| **Killstreakers** | Professional Killstreak eye effects via TF2Attributes (7 effects) |
| **Death Effects** | Gold/ice/ash/electro ragdoll flags or custom particles |
| **Pets** | Free-moving animated companions with idle/walk/jump states, configurable scale and height |
| **Spawn Particles** | One-shot particle burst on each respawn |

All cosmetics clean up on death (auras/trails fade to avoid decals), reapply on respawn. Per-type unequip in every submenu. Equipped items marked with ★.

**VIP** — Custom welcome messages with `{RAINBOW}` support. Cooldown-protected, input-validated, persisted to database.

**Visuals** — XP progress bar (toggleable with `!xphud`), floating "+XP" on kills, level-up effects (screen shake, gold flash, confetti).

---

## Installation

### Requirements

- **SourceMod 1.12+**
- **[Chat Processor](https://github.com/Drixevel/Chat-Processor)** — for `leveling_chat.smx`
- **[Color Variables](https://github.com/KissLick/ColorVariables)** — `colorvariables.inc`
- **[TF2Attributes](https://github.com/FlaminSarge/tf2attributes)** — for Sheens/Killstreakers (soft dependency — plugin works without it)

### File Structure

```
addons/sourcemod/
├── plugins/
│   ├── leveling_core.smx          ← required
│   ├── leveling_chat.smx          ← optional
│   ├── leveling_cosmetics.smx     ← optional
│   ├── leveling_vip.smx           ← optional
│   ├── leveling_visuals.smx       ← optional
│   └── tf2attributes.smx          ← optional
├── gamedata/
│   └── tf2.attributes.txt         ← for tf2attributes
├── configs/leveling/
│   ├── core.cfg                   ← auto-created if missing
│   ├── tags.cfg                   ← chat tags
│   └── cosmetics.cfg              ← all cosmetic items
└── translations/
    └── leveling.phrases.txt
```

### Compile Order

Compile `leveling_core.sp` first, then the rest. **All plugins must be compiled together** with the same `leveling.inc`.

### Database

Works out of the box with SQLite (no setup needed). For MySQL, add `"leveling"` to `databases.cfg`. Schema migrations are automatic.

---

## Configuration

### Cosmetics — `configs/leveling/cosmetics.cfg`

| Section | Value Key | Format |
|---------|-----------|--------|
| Trails | `material` | VMT path + optional `color`, `startwidth`, `endwidth`, `lifetime` |
| Auras | `effect` | TF2 particle name |
| Models | `model` | MDL path |
| Sheens | `sheen` | 1-7 |
| Killstreakers | `effect` | 2002-2008 |
| Deaths | `effect` | `gold`, `ice`, `ash`, `electro`, or particle name |
| Pets | `model` | MDL path + optional `anim_idle`, `anim_walk`, `anim_jump`, `height_type`, `height_custom`, `modelscale` |
| Spawns | `effect` | TF2 particle name |

All items support optional `"flag"` for admin restrictions (`"a"` = VIP, `"b"` = generic, `"z"` = root).

---

## Commands

| Command | Description |
|---------|-------------|
| `!level` | Show your level, XP, kills, playtime |
| `!rank` | Top 10 leaderboard |
| `!cosmetics` / `!equip` | Open cosmetics menu |
| `!tags` / `!tag` | Select a chat tag |
| `!xphud` | Toggle XP bar |
| `!welcomemsg` | Set/clear VIP welcome message |
| `!customtag` | Set/clear VIP chat tag |
| `sm_givexp` | Give XP (admin) |
| `sm_setlevel` | Set level (admin) |
| `sm_resetlevel` | Full reset (admin) |

---

## Developer API

```sourcepawn
#include <leveling>

enum CosmeticType {
    Cosmetic_Trail, Cosmetic_Aura, Cosmetic_Model, Cosmetic_Tag,
    Cosmetic_Sheen, Cosmetic_Killstreaker, Cosmetic_Death,
    Cosmetic_Pet, Cosmetic_Spawn
}

forward void Leveling_OnDataLoaded(int client);
forward void Leveling_OnLevelUp(int client, int newLevel);
forward void Leveling_OnXPGain(int client, int amount, int totalXP);

LevelingPlayer player = LevelingPlayer(client);
player.Level;   player.XP;   player.GiveXP(100);   player.HasLevel(10);
```

17 natives, 3 forwards, methodmap. See `leveling.inc` for full documentation.

---

## Credits

- **Author:** [Silorak](https://github.com/Silorak)
- **[Chat Processor](https://github.com/Drixevel/Chat-Processor)** by Drixevel
- **[Color Variables](https://github.com/KissLick/ColorVariables)** by KissLick
- **[TF2Attributes](https://github.com/FlaminSarge/tf2attributes)** by FlaminSarge

## License

GPL v3.0 — see [LICENSE](LICENSE).