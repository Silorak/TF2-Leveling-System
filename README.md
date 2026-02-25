<div align="center">

# TF2 Leveling System

[![Version](https://img.shields.io/badge/version-1.0.0-blue?style=for-the-badge)](https://github.com/Silorak/TF2-Leveling-System/releases)
[![SourceMod](https://img.shields.io/badge/SourceMod-1.12-orange?style=for-the-badge)](https://www.sourcemod.net/)
[![License](https://img.shields.io/badge/license-GPL%20v3-green?style=for-the-badge)](LICENSE)

A modular XP and leveling system for TF2 servers with cosmetic rewards, chat tags, and VIP features.

[Installation](#installation) · [Configuration](#configuration) · [Commands](#commands) · [API](#developer-api)

</div>

---

## Architecture

A modular plugin suite built around a shared native API. Each plugin can be loaded or unloaded independently without affecting the others.

| Plugin | File | Purpose |
|--------|------|---------|
| **Core** | `leveling_core.smx` | Database, XP/level logic, admin commands, all natives |
| **Chat** | `leveling_chat.smx` | Chat tags with hex color support via Chat Processor |
| **Cosmetics** | `leveling_cosmetics.smx` | Trails, auras, player models, equip menu |
| **VIP** | `leveling_vip.smx` | Custom welcome messages and chat tags |
| **Visuals** | `leveling_visuals.smx` | HUD progress bar (below speed HUD, toggleable with `!xphud`), floating XP, level-up effects |

**Core is required.** The other four are optional — load whichever modules you need.

---

## Features

**Leveling** — 50 levels with configurable exponential XP scaling. XP from kills, revenge bonuses, and a configurable donor multiplier. Auto-save with transaction batching. MySQL and SQLite both supported.

**Chat Tags** — Level-based colored chat tags using `{#RRGGBB}` hex format. Tags are cached on level-up (not processed per-message). Players can equip any tag they've unlocked, or VIPs can set fully custom tags.

**Cosmetics** — Equip trails (sprite-based), auras (particle effects), and player models simultaneously. Models use TF2's `SetCustomModel` + `m_bUseClassAnimations` pipeline for correct animations. All cosmetics are config-driven.

**VIP** — Custom welcome messages with `{RAINBOW}` support and custom chat tags. Requires `ADMFLAG_RESERVATION`. Cooldown-protected, input-validated, persisted to database.

**Visuals** — HUD bar showing XP progress displayed just below the TFDB speed HUD (centered, green, single line). Can be toggled off per-player with `!xphud`. Floating "+XP" on kills, level-up effects (screen shake, gold flash, confetti particle).

---

## Installation

### Requirements

- **SourceMod 1.12+**
- **[Chat Processor](https://github.com/Drixevel/Chat-Processor)** — only if using `leveling_chat.smx`
- **[Color Variables](https://github.com/KissLick/ColorVariables)** — `colorvariables.inc` in your include path

### File Structure

```
addons/sourcemod/
├── plugins/
│   ├── leveling_core.smx          ← required
│   ├── leveling_chat.smx          ← optional
│   ├── leveling_cosmetics.smx     ← optional
│   ├── leveling_vip.smx           ← optional
│   └── leveling_visuals.smx       ← optional
├── configs/leveling/
│   ├── core.cfg                   ← auto-created if missing
│   ├── tags.cfg                   ← chat tags by level
│   └── cosmetics.cfg              ← trails, auras, models
├── translations/
│   └── leveling.phrases.txt
└── scripting/
    ├── include/leveling.inc       ← public API
    ├── leveling_core.sp
    ├── leveling_chat.sp
    ├── leveling_cosmetics.sp
    ├── leveling_vip.sp
    └── leveling_visuals.sp
```

### Compile Order

Compile `leveling_core.sp` first, then the other four in any order. All subplugins soft-depend on core via `SharedPlugin`.

### Database Setup

By default the plugin uses SQLite (`tf2_leveling.sq3`). For MySQL, add a `"leveling"` entry to `configs/databases.cfg`:

```
"leveling"
{
    "driver"    "mysql"
    "host"      "localhost"
    "database"  "tf2_server"
    "user"      "your_user"
    "pass"      "your_password"
    "port"      "3306"
}
```

The table `sm_leveling_users` is created automatically with schema versioning — no manual migration needed.

---

## Configuration

### Core Settings — `configs/leveling/core.cfg`

```
"LevelingCore"
{
    "base_xp"           "100"       // XP for level 1→2 (10 - 10000)
    "xp_multiplier"     "1.15"      // Exponential scaling (0.1 - 5.0)
    "kill_xp"           "10"        // XP per kill (1 - 1000)
    "revenge_xp"        "50"        // Bonus for revenge kills (0 - 500)
    "donor_multiplier"  "2"         // XP multiplier for donors (1 - 5)
    "levelup_sound"     "ui/item_acquired.wav"
}
```

**XP Formula:** `XP_needed = base_xp × (level ^ xp_multiplier)`

At defaults: Level 1→2 needs 100 XP (10 kills). Level 25→26 needs ~762 XP. Level 49→50 needs ~2,511 XP. The plugin validates the formula won't overflow at max level on config load.

### Chat Tags — `configs/leveling/tags.cfg`

```
"LevelingTags"
{
    "1"     "{#00FF00}[Newbie]"
    "5"     "{#00BFFF}[Regular]"
    "10"    "{#FFD700}[Veteran]"
    "50"    "{#FF00FF}[Legend]"
}
```

Players get the highest tag they've unlocked. Colors use `{#RRGGBB}` hex format.

### Cosmetics — `configs/leveling/cosmetics.cfg`

```
"LevelingCosmetics"
{
    "Trails"
    {
        "Red Laser"
        {
            "level"     "2"
            "material"  "materials/sprites/laser.vmt"
        }
    }
    "Auras"
    {
        "Fire"
        {
            "level"     "4"
            "effect"    "burningplayer_corpse"
        }
    }
    "Models"
    {
        "Robot Heavy"
        {
            "level"     "5"
            "model"     "models/bots/heavy/bot_heavy.mdl"
        }
    }
}
```

### ConVars

| ConVar | Default | Description |
|--------|---------|-------------|
| `sm_leveling_verbose` | `0` | Enable verbose logging (load/save/auto-save) |
| `sm_leveling_autosave` | `300` | Auto-save interval in seconds (min 60) |

---

## Commands

### Player

| Command | Description |
|---------|-------------|
| `!level` / `sm_level` | Show your level, XP, kills, and playtime |
| `!rank` / `sm_rank` | Top 10 leaderboard |
| `!cosmetics` / `sm_equip` | Open cosmetics equip menu |
| `!xphud` / `sm_xphud` | Toggle XP progress bar on/off |

### VIP (requires `ADMFLAG_RESERVATION`)

| Command | Description |
|---------|-------------|
| `!welcomemsg <message>` | Set custom join message (`{RAINBOW}` supported) |
| `!welcomemsg` | Clear custom welcome |
| `!customtag <tag>` | Set custom chat tag |
| `!customtag` | Clear custom tag, revert to level tag |

60-second cooldown between changes. Input is validated (alphanumeric + basic punctuation only).

### Admin

| Command | Permission | Description |
|---------|------------|-------------|
| `sm_givexp <player> <amount>` | SLAY | Give XP (1 - 10,000) |
| `sm_setlevel <player> <level>` | SLAY | Set level (1 - 50), resets XP to 0 |
| `sm_resetlevel <player>` | ROOT | Full reset (level, XP, kills, playtime, cosmetics) |

All admin commands are logged via `LogAction`.

---

## Developer API

Include `leveling.inc` in your plugin. Core registers 17 natives, 3 forwards, a `CosmeticType` enum, and a `LevelingPlayer` methodmap.

### Enum

```sourcepawn
enum CosmeticType
{
    Cosmetic_Trail = 0,
    Cosmetic_Aura,
    Cosmetic_Model,
    Cosmetic_Tag
}
```

### Natives

```sourcepawn
// Read
native int  Leveling_GetLevel(int client);
native int  Leveling_GetXP(int client);
native int  Leveling_GetTotalKills(int client);
native int  Leveling_GetPlaytime(int client);           // seconds, includes current session
native int  Leveling_GetXPForLevel(int level);           // -1 at max level
native bool Leveling_IsDataLoaded(int client);
native bool Leveling_HasLevel(int client, int required);

// Write
native void     Leveling_GiveXP(int client, int amount); // capped at 10,000 per call
native void     Leveling_SetLevel(int client, int level); // does NOT fire OnLevelUp
native void     Leveling_SavePlayer(int client);
native Database Leveling_GetDatabase();

// Cosmetic data (stored in core DB, typed with CosmeticType enum)
native void Leveling_GetEquipped(int client, CosmeticType type, char[] buffer, int maxlen);
native void Leveling_SetEquipped(int client, CosmeticType type, const char[] value);

// VIP data (stored in core DB)
native void Leveling_GetCustomWelcome(int client, char[] buffer, int maxlen);
native void Leveling_SetCustomWelcome(int client, const char[] message);
native void Leveling_GetCustomTag(int client, char[] buffer, int maxlen);
native void Leveling_SetCustomTag(int client, const char[] tag);
```

### Forwards

```sourcepawn
// Fired when player data is loaded from DB. Wait for this before accessing data.
forward void Leveling_OnDataLoaded(int client);

// Fired on level up (not on SetLevel).
forward void Leveling_OnLevelUp(int client, int newLevel);

// Fired on XP gain. totalXP = XP after gain for current level.
forward void Leveling_OnXPGain(int client, int amount, int totalXP);
```

### Methodmap

```sourcepawn
LevelingPlayer player = LevelingPlayer(client);

player.Level;           // get/set
player.XP;              // get
player.TotalKills;      // get
player.Playtime;        // get (seconds)
player.IsLoaded;        // get
player.GiveXP(100);
player.HasLevel(10);
```

### Example Plugin

```sourcepawn
#include <sourcemod>
#include <leveling>

public void Leveling_OnLevelUp(int client, int newLevel)
{
    if (newLevel == 50)
        PrintToChatAll("%N has reached max level!", client);
}

public void Leveling_OnDataLoaded(int client)
{
    // Safe to read player data now
    int level = Leveling_GetLevel(client);
    PrintToServer("%N loaded at level %d", client, level);

    // Check equipped cosmetic using enum
    char trail[64];
    Leveling_GetEquipped(client, Cosmetic_Trail, trail, sizeof(trail));
    if (trail[0] != '\0')
        PrintToServer("%N has trail: %s", client, trail);
}
```

---

## Translations

Supported: English, Spanish, Russian, German, French, Portuguese.

To add a language, edit `translations/leveling.phrases.txt` and add your language code under each phrase block.

---

## Troubleshooting

**Cosmetics not working** — Check that model/material paths exist on the server. Look for `"Model not precached"` errors in the server console. Auras and models only apply to alive players.

**Chat tags not showing** — Make sure `chat-processor.smx` is loaded and `leveling_chat.smx` is loaded after `leveling_core.smx`. Check that `tags.cfg` exists and is valid KeyValues.

**Database errors** — If MySQL fails, the plugin falls back to SQLite automatically. Check `logs/` for connection errors. Verify your `databases.cfg` entry uses the key name `"leveling"`.

**Players T-posing with models** — Make sure you are running `leveling_cosmetics.smx`. It uses the correct `SetCustomModel` + `m_bUseClassAnimations` pipeline.

---

## Credits

- **Author:** [Silorak](https://github.com/Silorak)
- **[Chat Processor](https://github.com/Drixevel/Chat-Processor)** by Drixevel
- **[Color Variables](https://github.com/KissLick/ColorVariables)** by KissLick / Drixevel

---

## License

GPL v3.0 — see [LICENSE](LICENSE).

<div align="center">

[Report Bug](https://github.com/Silorak/TF2-Leveling-System/issues) · [Request Feature](https://github.com/Silorak/TF2-Leveling-System/issues)

</div>
