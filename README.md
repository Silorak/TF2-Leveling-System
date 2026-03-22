<div align="center">

# TF2 Leveling System

[![Version](https://img.shields.io/badge/version-1.5.0-blue?style=for-the-badge)](https://github.com/Silorak/TF2-Leveling-System/releases)
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
| **Cosmetics** | `leveling_cosmetics.smx` | Trails, auras, models, sheens, killstreakers, death effects, pets, spawn particles |
| **VIP** | `leveling_vip.smx` | Custom welcome messages and chat tags |
| **Visuals** | `leveling_visuals.smx` | HUD progress bar, floating XP, level-up effects |

**Core is required.** The other four are optional — load whichever modules you need.

---

## Features

**Leveling** — 50 levels with configurable exponential XP scaling. XP from kills, revenge bonuses, and a configurable donor multiplier. Auto-save with transaction batching. MySQL and SQLite both supported.

**Chat Tags** — Level-based colored chat tags using `{#RRGGBB}` hex format with multi-color support (e.g. `{#FF0000}[{#00FF00}Tag{#FF0000}]`). Uses Chat Processor's native tag API (`ChatProcessor_AddClientTag`) for reliable rendering. Optional per-tag `name_color` for coloring the player's name in chat. Players automatically get their highest unlocked tag, or can manually select any unlocked tag via `!tags`. VIPs can set a custom tag via `!customtag` which appears by default — it also shows in the `!tags` menu as `★ VIP: YourTag` so players can freely switch between their custom tag and any level tag.

**Cosmetics** — 9 cosmetic types, all config-driven with optional admin flag restrictions:

- **Trails** — Sprite-based beams that follow the player.
- **Auras** — Unusual particle effects (Holy Grail, Hellish Inferno, Scorching Sensation, etc.) visible to everyone.
- **Models** — Player model overrides using TF2's `SetCustomModel` + `m_bUseClassAnimations` for correct animations with automatic wearable hiding.
- **Sheens** — Weapon sheens (Team Shine, Deadly Daffodil, etc.) applied via TF2Attributes.
- **Killstreakers** — Weapon killstreak effects (Fire Horns, Cerebral Discharge, etc.) applied via TF2Attributes.
- **Death Effects** — Ragdoll effects (gold/ice/ash/electro) or custom particles on death.
- **Pets** — Animated companion NPCs that follow the player. Powered by `base_boss` entity + VScript for smooth NPC-quality movement on any map. Pets walk, idle, jump when you jump, and have random mood particles (happy sparkles, angry flies, sad stormcloud). Up to 10 idle sounds per pet with configurable pitch and volume, plus jump and walk sounds. Color tinting via `!petcolor` (10 presets or custom RGB, saved to cookie). Supports ground pets and hover pets (configurable height offset), per-pet skins, bodygroups, and model scale. 20 built-in pets from levels 3-50.
- **Spawn Particles** — One-shot particle effects that play when you respawn.

**VIP** — Custom welcome messages with `{RAINBOW}` support and custom chat tags. Requires `ADMFLAG_RESERVATION`. Cooldown-protected, input-validated, persisted to database.

**Visuals** — HUD bar showing XP progress displayed below the TFDB speed HUD. Can be toggled off per-player with `!xphud`. Floating "+XP" on kills, level-up effects (screen shake, gold flash, confetti particle).

---

## Installation

### Requirements

- **SourceMod 1.12+**
- **[Chat Processor](https://github.com/Drixevel/Chat-Processor)** — only if using `leveling_chat.smx`
- **[Color Variables](https://github.com/KissLick/ColorVariables)** — `colorvariables.inc` in your include path
- **[TF2Attributes](https://github.com/FlaminSarge/tf2attributes)** — optional, only needed for sheens and killstreakers
- **clientprefs** — built into SourceMod, used for pet color persistence

### File Structure

This repo has two different install destinations. Most files go into `addons/sourcemod/`, but the `vscripts/` folder goes into `tf/scripts/`:

```
From this repo          →  Install to server
─────────────────────────────────────────────────────
configs/                →  addons/sourcemod/configs/
gamedata/               →  addons/sourcemod/gamedata/
plugins/                →  addons/sourcemod/plugins/
scripting/              →  addons/sourcemod/scripting/
translations/           →  addons/sourcemod/translations/
vscripts/               →  tf/scripts/vscripts/          ← DIFFERENT PATH!
```

Full server layout after install:

```
tf/
├── scripts/vscripts/
│   └── leveling/
│       └── pet_follower.nut           ← pet AI (required for pets)
└── addons/sourcemod/
    ├── plugins/
    │   ├── leveling_core.smx          ← required
    │   ├── leveling_chat.smx          ← optional
    │   ├── leveling_cosmetics.smx     ← optional
    │   ├── leveling_vip.smx           ← optional
    │   └── leveling_visuals.smx       ← optional
    ├── configs/leveling/
    │   ├── core.cfg                   ← auto-created if missing
    │   ├── tags.cfg                   ← chat tags by level
    │   └── cosmetics.cfg              ← all cosmetic definitions
    ├── configs/
    │   └── chat_processor.cfg         ← required for chat tags
    ├── gamedata/
    │   └── tf2.attributes.txt         ← required for sheens/killstreakers
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

> **⚠️ Important:** The `vscripts/` folder must go into `tf/scripts/vscripts/`, NOT into `addons/sourcemod/`. Pets will not work without this file in the correct location.

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
    "10"
    {
        "tag"          "{#FFD700}[{#FFFFFF}VIP Gold{#FFD700}]"
        "name_color"   "{#FFD700}"
        "flag"         "a"
    }
}
```

Tags support two formats: simple (`"level" "tag"`) for everyone, or subsection with optional `"name_color"` and `"flag"` for colored names and admin-restricted tags. Multi-color tags are supported (e.g. `{#FF0000}[{#00FF00}Tag{#FF0000}]`). Players see restricted tags as `(VIP Only)` in the `!tags` menu.

### Cosmetics — `configs/leveling/cosmetics.cfg`

```
"LevelingCosmetics"
{
    "Trails"
    {
        "Red Laser"
        {
            "level"      "2"
            "material"   "materials/sprites/laser.vmt"
            "color"      "255 0 0"
            "startwidth" "15.0"
            "endwidth"   "1.0"
            "lifetime"   "2.0"
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
    "Sheens"
    {
        "Team Shine"
        {
            "level"     "8"
            "sheen"     "1"         // 1-7: Team Shine through Hot Rod
        }
    }
    "Killstreakers"
    {
        "Fire Horns"
        {
            "level"     "12"
            "effect"    "2002"      // 2002-2008
        }
    }
    "Deaths"
    {
        "Gold Ragdoll"
        {
            "level"     "6"
            "type"      "gold"      // gold, ice, ash, electro
        }
    }
    "Pets"
    {
        "Hugcrab"
        {
            "level"             "3"
            "model"             "models/headcrabclassic.mdl"
            "desc"              "A friendly headcrab companion"
            "anim_idle"         "Idle01"
            "anim_walk"         "Run1"
            "anim_jump"         "jumpattack_broadcast"
            "height_type"       "ground"
            "modelscale"        "1.0"
            "can_be_colored"    "1"
            "sound_idle0"       "npc/headcrab_poison/ph_idle1.wav"
            "sound_idle1"       "npc/headcrab_poison/ph_idle2.wav"
            "sound_idle2"       "npc/headcrab_poison/ph_idle3.wav"
            "sound_jump"        "npc/headcrab_poison/ph_jump1.wav"
            "pitch"             "120"
            "volume"            "0.5"
        }
        "Crow"
        {
            "level"             "7"
            "model"             "models/crow.mdl"
            "anim_idle"         "idle"
            "anim_walk"         "walk"
            "anim_jump"         "jump"
            "height_type"       "hover"
            "height_custom"     "80"    // units above ground
            "modelscale"        "1.0"
            "skin"              "0"
            "skins"             "1"
        }
    }
    "Spawns"
    {
        "Confetti Burst"
        {
            "level"     "4"
            "effect"    "bday_confetti"
            "duration"  "3.0"
        }
    }
}
```

Items with `"flag"` are shown as `(VIP Only)` in the menu for players who don't have the required admin flag. Flag values: `"a"` = reservation (VIP/donor), `"b"` = generic, `"d"` = slay, `"z"` = root.

### ConVars

| ConVar | Default | Description |
|--------|---------|-------------|
| `sm_leveling_verbose` | `0` | Enable verbose logging (load/save/auto-save) |
| `sm_leveling_autosave` | `300` | Auto-save interval in seconds (min 60) |
| `sm_leveling_pet_debug` | `0` | Dump pet model sequences and sound paths to console on spawn |

---

## Commands

### Player

| Command | Description |
|---------|-------------|
| `!level` / `sm_level` | Show your level, XP, kills, and playtime |
| `!rank` / `sm_rank` | Top 10 leaderboard |
| `!cosmetics` / `sm_equip` | Open cosmetics equip menu |
| `!tags` / `sm_tags` | Select an unlocked chat tag |
| `!petcolor` / `sm_petcolor` | Pet color menu (10 presets), or `!petcolor R G B` for custom |
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
    Cosmetic_Tag,
    Cosmetic_Sheen,
    Cosmetic_Killstreaker,
    Cosmetic_Death,
    Cosmetic_Pet,
    Cosmetic_Spawn
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

**Pets not moving** — Make sure `pet_follower.nut` is installed at `tf/scripts/vscripts/leveling/pet_follower.nut` (NOT in `addons/sourcemod/`). This is a VScript file and must be in TF2's scripts directory.

**Pet sounds not playing** — TF2 does not ship all HL2 NPC sounds. Check server console for missing sound warnings. Set `sm_leveling_pet_debug 1` in console to dump all sound paths on pet spawn. Common fix: `npc/headcrab/` sounds don't exist in TF2 — use `npc/headcrab_poison/` instead.

**Pet too loud** — Adjust the `"volume"` key in `cosmetics.cfg` (0.0-1.0). Walk sounds automatically play at half the configured volume. Pre-tuned loud pets: Manhack (0.3), Fast Zombie (0.3), Strider (0.3).

**Cosmetics not working** — Check that model/material paths exist on the server. Look for `"Model not precached"` errors in the server console. Auras and models only apply to alive players.

**Sheens/Killstreakers not showing** — Make sure `tf2attributes.smx` is loaded and `gamedata/tf2.attributes.txt` is installed. These cosmetics require the TF2Attributes extension.

**Chat tags not showing** — Make sure `chat-processor.smx` is loaded and `configs/chat_processor.cfg` exists on the server (this file defines TF2's message format strings — without it, Chat Processor skips all chat processing silently). Check that `leveling_chat.smx` is loaded after `leveling_core.smx` and that `tags.cfg` exists and is valid KeyValues.

**Database errors** — If MySQL fails (wrong socket, bad credentials, server down), the plugin automatically falls back to SQLite. You will see `[Leveling] Falling back to local SQLite database.` in logs — this is normal and the plugin keeps working. If you see errors from `admin-sql-threaded.smx` about MySQL sockets, that's SourceMod's built-in admin plugin, not the leveling system — check your `databases.cfg` `"default"` section. No database setup is required to use this plugin — it works out of the box with SQLite.

**Players T-posing with models** — Make sure you are running `leveling_cosmetics.smx`. It uses the correct `SetCustomModel` + `m_bUseClassAnimations` pipeline.

---

## Credits

- **Author:** [Silorak](https://github.com/Silorak)
- **[Chat Processor](https://github.com/Drixevel/Chat-Processor)** by Drixevel
- **[Color Variables](https://github.com/KissLick/ColorVariables)** by KissLick / Drixevel
- **[TF2Attributes](https://github.com/FlaminSarge/tf2attributes)** by FlaminSarge

---

## License

GPL v3.0 — see [LICENSE](LICENSE).

<div align="center">

[Report Bug](https://github.com/Silorak/TF2-Leveling-System/issues) · [Request Feature](https://github.com/Silorak/TF2-Leveling-System/issues)

</div>