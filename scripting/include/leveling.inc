/**
 * TF2 Leveling System - Public API
 * Include this in any plugin that needs to interact with the leveling system.
 *
 * Example:
 *   #include <leveling>
 *
 *   public void Leveling_OnLevelUp(int client, int newLevel) {
 *       PrintToChat(client, "Congratulations on level %d!", newLevel);
 *   }
 */

#if defined _leveling_included
 #endinput
#endif
#define _leveling_included

#define LEVELING_MAX_LEVEL    50
#define LEVELING_VERSION      "1.1.0"

// ============================================================================
// ENUMS
// ============================================================================

enum CosmeticType
{
    Cosmetic_Trail = 0,
    Cosmetic_Aura,
    Cosmetic_Model,
    Cosmetic_Tag
}

// ============================================================================
// NATIVES - Core Level/XP Access
// ============================================================================

/**
 * Gets a player's current level.
 *
 * @param client    Valid client index (1 to MaxClients).
 * @return          Current level (1 to LEVELING_MAX_LEVEL).
 * @error           Invalid client index or client not in game.
 */
native int Leveling_GetLevel(int client);

/**
 * Gets a player's current XP towards next level.
 *
 * @param client    Valid client index.
 * @return          Current XP (0 to XP required for next level).
 * @error           Invalid client index or client not in game.
 */
native int Leveling_GetXP(int client);

/**
 * Gets a player's total kills across all sessions.
 *
 * @param client    Valid client index.
 * @return          Lifetime kill count.
 * @error           Invalid client index or client not in game.
 */
native int Leveling_GetTotalKills(int client);

/**
 * Gets a player's total playtime in seconds (includes current session).
 *
 * @param client    Valid client index.
 * @return          Total playtime in seconds.
 * @error           Invalid client index or client not in game.
 */
native int Leveling_GetPlaytime(int client);

/**
 * Gets the XP required for a given level to level up.
 *
 * @param level     Level to query (1 to LEVELING_MAX_LEVEL-1).
 * @return          XP required, or -1 if at max level.
 */
native int Leveling_GetXPForLevel(int level);

/**
 * Checks if a player's data has been loaded from the database.
 *
 * @param client    Valid client index.
 * @return          True if data is loaded and ready.
 */
native bool Leveling_IsDataLoaded(int client);

// ============================================================================
// NATIVES - Level/XP Modification
// ============================================================================

/**
 * Gives XP to a player, triggering level ups as appropriate.
 * Capped at 10000 XP per call to prevent abuse.
 *
 * @param client    Valid client index.
 * @param amount    Amount of XP to give (1 to 10000).
 * @error           Invalid client index or amount out of range.
 */
native void Leveling_GiveXP(int client, int amount);

/**
 * Sets a player's level directly. Resets XP to 0.
 * Does NOT trigger Leveling_OnLevelUp forward.
 *
 * @param client    Valid client index.
 * @param level     New level (1 to LEVELING_MAX_LEVEL).
 * @error           Invalid client or level out of range.
 */
native void Leveling_SetLevel(int client, int level);

/**
 * Checks if a player has reached a specific level.
 *
 * @param client        Valid client index.
 * @param requiredLevel Minimum level required.
 * @return              True if player.Level >= requiredLevel.
 * @error               Invalid client index.
 */
native bool Leveling_HasLevel(int client, int requiredLevel);

/**
 * Forces a save of a player's data to the database.
 *
 * @param client    Valid client index.
 */
native void Leveling_SavePlayer(int client);

/**
 * Gets the database handle for advanced queries by subplugins.
 *
 * @return          Database handle, or null if not connected.
 */
native Database Leveling_GetDatabase();

// ============================================================================
// NATIVES - Cosmetic Data (stored in core DB, used by cosmetics subplugin)
// ============================================================================

/**
 * Gets a player's equipped cosmetic value.
 *
 * @param client    Valid client index.
 * @param type      Cosmetic type (Cosmetic_Trail, Cosmetic_Aura, Cosmetic_Model, Cosmetic_Tag).
 * @param buffer    Buffer to store the value.
 * @param maxlen    Maximum buffer length.
 */
native void Leveling_GetEquipped(int client, CosmeticType type, char[] buffer, int maxlen);

/**
 * Sets a player's equipped cosmetic value.
 *
 * @param client    Valid client index.
 * @param type      Cosmetic type (Cosmetic_Trail, Cosmetic_Aura, Cosmetic_Model, Cosmetic_Tag).
 * @param value     Value to set (empty string to clear).
 */
native void Leveling_SetEquipped(int client, CosmeticType type, const char[] value);

// ============================================================================
// NATIVES - VIP Data (stored in core DB, used by VIP subplugin)
// ============================================================================

/**
 * Gets a player's custom welcome message.
 *
 * @param client    Valid client index.
 * @param buffer    Buffer to store the message.
 * @param maxlen    Maximum buffer length.
 */
native void Leveling_GetCustomWelcome(int client, char[] buffer, int maxlen);

/**
 * Sets a player's custom welcome message.
 *
 * @param client    Valid client index.
 * @param message   Message to set (empty to clear).
 */
native void Leveling_SetCustomWelcome(int client, const char[] message);

/**
 * Gets a player's custom VIP tag.
 *
 * @param client    Valid client index.
 * @param buffer    Buffer to store the tag.
 * @param maxlen    Maximum buffer length.
 */
native void Leveling_GetCustomTag(int client, char[] buffer, int maxlen);

/**
 * Sets a player's custom VIP tag.
 *
 * @param client    Valid client index.
 * @param tag       Tag to set (empty to clear).
 */
native void Leveling_SetCustomTag(int client, const char[] tag);

// ============================================================================
// FORWARDS
// ============================================================================

/**
 * Called when a player's data has been loaded from the database.
 * Subplugins should wait for this before accessing player data.
 *
 * @param client    Client index whose data was loaded.
 */
forward void Leveling_OnDataLoaded(int client);

/**
 * Called when a player levels up.
 *
 * @param client    Client index who leveled up.
 * @param newLevel  Their new level.
 */
forward void Leveling_OnLevelUp(int client, int newLevel);

/**
 * Called when a player gains XP.
 *
 * @param client    Client index who gained XP.
 * @param amount    Amount of XP gained.
 * @param totalXP   Their total XP after gain (for current level).
 */
forward void Leveling_OnXPGain(int client, int amount, int totalXP);

// ============================================================================
// METHODMAP
// ============================================================================

methodmap LevelingPlayer
{
    public LevelingPlayer(int client)
    {
        return view_as<LevelingPlayer>(client);
    }

    property int Level
    {
        public get() { return Leveling_GetLevel(view_as<int>(this)); }
        public set(int value) { Leveling_SetLevel(view_as<int>(this), value); }
    }

    property int XP
    {
        public get() { return Leveling_GetXP(view_as<int>(this)); }
    }

    property int TotalKills
    {
        public get() { return Leveling_GetTotalKills(view_as<int>(this)); }
    }

    property int Playtime
    {
        public get() { return Leveling_GetPlaytime(view_as<int>(this)); }
    }

    property bool IsLoaded
    {
        public get() { return Leveling_IsDataLoaded(view_as<int>(this)); }
    }

    public void GiveXP(int amount)
    {
        Leveling_GiveXP(view_as<int>(this), amount);
    }

    public bool HasLevel(int requiredLevel)
    {
        return Leveling_HasLevel(view_as<int>(this), requiredLevel);
    }
}

// ============================================================================
// SHARED PLUGIN
// Skip this block when leveling_core.sp includes this file, since core
// is the plugin that registers these natives (it doesn't depend on itself).
// ============================================================================

#if !defined LEVELING_CORE_PLUGIN

public SharedPlugin __pl_leveling =
{
    name = "leveling",
    file = "leveling_core.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_leveling_SetNTVOptional()
{
    MarkNativeAsOptional("Leveling_GetLevel");
    MarkNativeAsOptional("Leveling_GetXP");
    MarkNativeAsOptional("Leveling_GetTotalKills");
    MarkNativeAsOptional("Leveling_GetPlaytime");
    MarkNativeAsOptional("Leveling_GetXPForLevel");
    MarkNativeAsOptional("Leveling_IsDataLoaded");
    MarkNativeAsOptional("Leveling_GiveXP");
    MarkNativeAsOptional("Leveling_SetLevel");
    MarkNativeAsOptional("Leveling_HasLevel");
    MarkNativeAsOptional("Leveling_SavePlayer");
    MarkNativeAsOptional("Leveling_GetDatabase");
    MarkNativeAsOptional("Leveling_GetEquipped");
    MarkNativeAsOptional("Leveling_SetEquipped");
    MarkNativeAsOptional("Leveling_GetCustomWelcome");
    MarkNativeAsOptional("Leveling_SetCustomWelcome");
    MarkNativeAsOptional("Leveling_GetCustomTag");
    MarkNativeAsOptional("Leveling_SetCustomTag");
}
#endif

#endif // !LEVELING_CORE_PLUGIN
