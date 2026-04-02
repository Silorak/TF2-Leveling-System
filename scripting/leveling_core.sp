#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <colorvariables>

// Define this BEFORE including leveling.inc so the SharedPlugin / 
// MarkNativeAsOptional block is skipped — core registers the natives,
// it doesn't depend on them.
#define LEVELING_CORE_PLUGIN
#include <leveling>

#define PLUGIN_NAME        "TF2 Leveling System"
#define PLUGIN_AUTHOR      "Silorak"
#define PLUGIN_DESCRIPTION "Core leveling system with XP, levels, and database"
#define PLUGIN_VERSION "1.5.0"
#define PLUGIN_URL         "https://github.com/Silorak/TF2-Leveling-System"

#define MAX_LEVEL          50
#define TABLE_NAME         "sm_leveling_users"
#define SCHEMA_VERSION     4
#define MAX_GIVEXP         10000
#define TF_DEATHFLAG_REVENGE     8
#if !defined TF_DEATHFLAG_DEADRINGER
#define TF_DEATHFLAG_DEADRINGER  32
#endif

public Plugin myinfo =
{
    name        = PLUGIN_NAME,
    author      = PLUGIN_AUTHOR,
    description = PLUGIN_DESCRIPTION,
    version     = PLUGIN_VERSION,
    url         = PLUGIN_URL
};

// ============================================================================
// PLAYER DATA
// ============================================================================

int    g_Level[MAXPLAYERS + 1];
int    g_XP[MAXPLAYERS + 1];
int    g_TotalKills[MAXPLAYERS + 1];
int    g_Playtime[MAXPLAYERS + 1];
int    g_ConnectTime[MAXPLAYERS + 1];
bool   g_DataLoaded[MAXPLAYERS + 1];

// Equipped cosmetics (stored in core, read by cosmetics subplugin)
char   g_Trail[MAXPLAYERS + 1][64];
char   g_Aura[MAXPLAYERS + 1][64];
char   g_Model[MAXPLAYERS + 1][64];
char   g_Tag[MAXPLAYERS + 1][16];
char   g_Sheen[MAXPLAYERS + 1][64];
char   g_Killstreaker[MAXPLAYERS + 1][64];
char   g_Death[MAXPLAYERS + 1][64];
char   g_Pet[MAXPLAYERS + 1][128];
char   g_Spawn[MAXPLAYERS + 1][64];

// VIP data (stored in core, read by VIP subplugin)
char   g_CustomWelcome[MAXPLAYERS + 1][128];
char   g_CustomTag[MAXPLAYERS + 1][32];

// ============================================================================
// GLOBALS
// ============================================================================

Database g_Database;

// Config values
int    g_BaseXP         = 100;
float  g_XPMultiplier   = 1.15;
int    g_KillXP         = 10;
int    g_RevengeXP      = 50;
int    g_DonorMultiplier = 2;
char   g_LevelUpSound[PLATFORM_MAX_PATH] = "ui/item_acquired.wav";

// ConVars
ConVar g_Verbose;
ConVar g_AutoSaveInterval;

// Forwards
GlobalForward g_OnDataLoaded;
GlobalForward g_OnLevelUp;
GlobalForward g_OnXPGain;

// ============================================================================
// PLUGIN LOAD
// ============================================================================

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    // Core natives
    CreateNative("Leveling_GetLevel",         Native_GetLevel);
    CreateNative("Leveling_GetXP",            Native_GetXP);
    CreateNative("Leveling_GetTotalKills",    Native_GetTotalKills);
    CreateNative("Leveling_GetPlaytime",      Native_GetPlaytime);
    CreateNative("Leveling_GetXPForLevel",    Native_GetXPForLevel);
    CreateNative("Leveling_IsDataLoaded",     Native_IsDataLoaded);
    CreateNative("Leveling_GiveXP",           Native_GiveXP);
    CreateNative("Leveling_SetLevel",         Native_SetLevel);
    CreateNative("Leveling_HasLevel",         Native_HasLevel);
    CreateNative("Leveling_SavePlayer",       Native_SavePlayer);
    CreateNative("Leveling_GetDatabase",      Native_GetDatabase);

    // Cosmetic data natives
    CreateNative("Leveling_GetEquipped",      Native_GetEquipped);
    CreateNative("Leveling_SetEquipped",      Native_SetEquipped);

    // VIP data natives
    CreateNative("Leveling_GetCustomWelcome", Native_GetCustomWelcome);
    CreateNative("Leveling_SetCustomWelcome", Native_SetCustomWelcome);
    CreateNative("Leveling_GetCustomTag",     Native_GetCustomTag);
    CreateNative("Leveling_SetCustomTag",     Native_SetCustomTag);

    // Forwards
    g_OnDataLoaded = new GlobalForward("Leveling_OnDataLoaded", ET_Ignore, Param_Cell);
    g_OnLevelUp    = new GlobalForward("Leveling_OnLevelUp",    ET_Ignore, Param_Cell, Param_Cell);
    g_OnXPGain     = new GlobalForward("Leveling_OnXPGain",     ET_Ignore, Param_Cell, Param_Cell, Param_Cell);

    RegPluginLibrary("leveling");
    return APLRes_Success;
}

public void OnPluginStart()
{
    LoadTranslations("leveling.phrases");
    LoadTranslations("common.phrases");

    // ConVars
    g_Verbose          = CreateConVar("sm_leveling_verbose", "0", "Enable verbose logging", _, true, 0.0, true, 1.0);
    g_AutoSaveInterval = CreateConVar("sm_leveling_autosave", "300.0", "Auto-save interval in seconds", _, true, 60.0);

    // Player commands
    RegConsoleCmd("sm_level", Command_Level, "Check your current level");
    RegConsoleCmd("sm_rank",  Command_Rank,  "View top 10 players");

    // Admin commands
    RegAdminCmd("sm_givexp",     Command_GiveXP,    ADMFLAG_SLAY, "Give XP to a player");
    RegAdminCmd("sm_setlevel",   Command_SetLevel,  ADMFLAG_SLAY, "Set a player's level");
    RegAdminCmd("sm_resetlevel", Command_ResetLevel, ADMFLAG_ROOT, "Reset a player's level");

    // Events
    HookEvent("player_death", Event_PlayerDeath);

    // Database
    DB_Connect();
}

public void OnMapStart()
{
    LoadConfig();
    PrecacheSound(g_LevelUpSound, true);
    CreateTimer(g_AutoSaveInterval.FloatValue, Timer_AutoSave, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

// ============================================================================
// CLIENT HOOKS
// ============================================================================

public void OnClientAuthorized(int client, const char[] auth)
{
    ResetPlayerData(client);
    g_ConnectTime[client] = GetTime();

    if (!IsFakeClient(client))
        DB_LoadUser(client);
}

public void OnClientDisconnect(int client)
{
    if (g_DataLoaded[client])
    {
        // Finalize session playtime
        g_Playtime[client] += GetTime() - g_ConnectTime[client];
        g_ConnectTime[client] = GetTime();
        DB_SaveUser(client);
    }
    ResetPlayerData(client);
}

void ResetPlayerData(int client)
{
    g_Level[client]       = 1;
    g_XP[client]          = 0;
    g_TotalKills[client]  = 0;
    g_Playtime[client]    = 0;
    g_ConnectTime[client] = GetTime();
    g_DataLoaded[client]  = false;
    g_Trail[client][0]    = '\0';
    g_Aura[client][0]     = '\0';
    g_Model[client][0]    = '\0';
    g_Tag[client][0]      = '\0';
    g_Sheen[client][0]      = '\0';
    g_Killstreaker[client][0] = '\0';
    g_Death[client][0]    = '\0';
    g_Pet[client][0]      = '\0';
    g_Spawn[client][0]    = '\0';
    g_CustomWelcome[client][0] = '\0';
    g_CustomTag[client][0]     = '\0';
}

// ============================================================================
// CONFIG
// ============================================================================

void LoadConfig()
{
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/leveling/core.cfg");

    if (!FileExists(path))
    {
        LogMessage("[Leveling] Config not found, creating default: %s", path);
        CreateDefaultConfig(path);
        return;
    }

    KeyValues kv = new KeyValues("LevelingCore");
    if (!kv.ImportFromFile(path))
    {
        LogError("[Leveling] Failed to parse config: %s", path);
        delete kv;
        return;
    }

    g_BaseXP         = ClampInt(kv.GetNum("base_xp", 100),       10, 10000);
    g_XPMultiplier   = ClampFloat(kv.GetFloat("xp_multiplier", 1.15), 0.1, 5.0);
    g_KillXP         = ClampInt(kv.GetNum("kill_xp", 10),        1, 1000);
    g_RevengeXP      = ClampInt(kv.GetNum("revenge_xp", 50),     0, 500);
    g_DonorMultiplier = ClampInt(kv.GetNum("donor_multiplier", 2), 1, 5);
    kv.GetString("levelup_sound", g_LevelUpSound, sizeof(g_LevelUpSound), "ui/item_acquired.wav");

    delete kv;

    // Validate XP formula won't overflow at max level
    float maxXP = float(g_BaseXP) * Pow(float(MAX_LEVEL), g_XPMultiplier);
    if (maxXP > 2000000000.0)
    {
        LogError("[Leveling] XP formula overflows at max level! Clamping multiplier.");
        g_XPMultiplier = 1.15;
    }
}

void CreateDefaultConfig(const char[] path)
{
    KeyValues kv = new KeyValues("LevelingCore");
    kv.SetNum("base_xp", 100);
    kv.SetFloat("xp_multiplier", 1.15);
    kv.SetNum("kill_xp", 10);
    kv.SetNum("revenge_xp", 50);
    kv.SetNum("donor_multiplier", 2);
    kv.SetString("levelup_sound", "ui/item_acquired.wav");
    kv.ExportToFile(path);
    delete kv;
}

// ============================================================================
// XP LOGIC
// ============================================================================

int GetXPForNextLevel(int level)
{
    if (level >= MAX_LEVEL) return -1;
    return RoundToFloor(float(g_BaseXP) * Pow(float(level), g_XPMultiplier));
}

void GiveXP(int client, int amount)
{
    if (!g_DataLoaded[client] || amount <= 0) return;

    g_XP[client] += amount;

    Call_StartForward(g_OnXPGain);
    Call_PushCell(client);
    Call_PushCell(amount);
    Call_PushCell(g_XP[client]);
    Call_Finish();

    CheckLevelUp(client);
}

void CheckLevelUp(int client)
{
    int needed = GetXPForNextLevel(g_Level[client]);

    while (needed != -1 && g_XP[client] >= needed)
    {
        g_XP[client] -= needed;
        g_Level[client]++;

        CPrintToChatAll("%t", "LevelUp", client, g_Level[client]);

        if (g_LevelUpSound[0] != '\0')
            EmitSoundToAll(g_LevelUpSound, client, SNDCHAN_AUTO, SNDLEVEL_NORMAL);

        Call_StartForward(g_OnLevelUp);
        Call_PushCell(client);
        Call_PushCell(g_Level[client]);
        Call_Finish();

        needed = GetXPForNextLevel(g_Level[client]);
    }
}

int GetCurrentPlaytime(int client)
{
    return g_Playtime[client] + (GetTime() - g_ConnectTime[client]);
}

// ============================================================================
// DATABASE
// ============================================================================

void DB_Connect()
{
    if (g_Database != null)
    {
        delete g_Database;
        g_Database = null;
    }

    if (SQL_CheckConfig("leveling"))
    {
        Database.Connect(DB_OnConnect, "leveling");
    }
    else
    {
        // No "leveling" section in databases.cfg — use a local SQLite file.
        char error[255];
        g_Database = SQLite_UseDatabase("tf2_leveling", error, sizeof(error));
        if (g_Database == null)
            SetFailState("[Leveling] SQLite connection failed: %s", error);

        LogMessage("[Leveling] Using local SQLite database (tf2_leveling).");
        DB_Init();
    }
}

public void DB_OnConnect(Database db, const char[] error, any data)
{
    if (db == null)
    {
        SetFailState("[Leveling] Database connection failed: %s", error);
        return;
    }

    g_Database = db;
    LogMessage("[Leveling] Connected to database successfully.");
    DB_Init();

    // Async connect may finish after players have already connected.
    // Retry loading any players whose load was skipped while DB was null.
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && !g_DataLoaded[i])
            DB_LoadUser(i);
    }
}

void DB_Init()
{
    // Create table with all columns (v3 schema).
    char query[1024];
    g_Database.Format(query, sizeof(query),
        "CREATE TABLE IF NOT EXISTS %s ("
    ... "steam_id VARCHAR(32) PRIMARY KEY, "
    ... "name VARCHAR(64), "
    ... "level INT DEFAULT 1, "
    ... "xp INT DEFAULT 0, "
    ... "total_kills INT DEFAULT 0, "
    ... "equipped_trail VARCHAR(64) DEFAULT '', "
    ... "equipped_aura VARCHAR(64) DEFAULT '', "
    ... "equipped_model VARCHAR(64) DEFAULT '', "
    ... "equipped_tag VARCHAR(16) DEFAULT '', "
    ... "equipped_sheen VARCHAR(64) DEFAULT '', "
    ... "equipped_killstreaker VARCHAR(64) DEFAULT '', "
    ... "equipped_death VARCHAR(64) DEFAULT '', "
    ... "equipped_pet VARCHAR(128) DEFAULT '', "
    ... "equipped_spawn VARCHAR(64) DEFAULT '', "
    ... "custom_welcome VARCHAR(128) DEFAULT '', "
    ... "custom_tag VARCHAR(32) DEFAULT '', "
    ... "playtime INT DEFAULT 0, "
    ... "schema_version INT DEFAULT %d, "
    ... "last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP);",
        TABLE_NAME, SCHEMA_VERSION);

    g_Database.Query(DB_OnGenericQuery, query, _, DBPrio_High);

    // Index for top-player queries.
    char driver[16];
    g_Database.Driver.GetIdentifier(driver, sizeof(driver));

    if (StrEqual(driver, "mysql", false))
    {
        g_Database.Format(query, sizeof(query),
            "CREATE INDEX idx_level_xp ON %s(level DESC, xp DESC);",
            TABLE_NAME);
    }
    else
    {
        g_Database.Format(query, sizeof(query),
            "CREATE INDEX IF NOT EXISTS idx_level_xp ON %s(level DESC, xp DESC);",
            TABLE_NAME);
    }
    g_Database.Query(DB_OnGenericQuery, query, _, DBPrio_Low);

    // Schema migration: add v3 columns if missing.
    // Query table_info first so we don't spam "duplicate column" errors
    // on every server start.
    g_Database.Format(query, sizeof(query),
        "PRAGMA table_info(%s);", TABLE_NAME);
    g_Database.Query(DB_OnSchemaCheck, query, _, DBPrio_Low);
}

public void DB_OnSchemaCheck(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        // Not SQLite or PRAGMA failed — try blind ALTER TABLE (MySQL path).
        RunMigrations();
        return;
    }

    // Scan column names returned by PRAGMA table_info.
    bool hasSheen, hasKillstreaker, hasDeath, hasPet, hasSpawn;
    while (results.FetchRow())
    {
        char colName[64];
        results.FetchString(1, colName, sizeof(colName)); // column 1 = name

        if (StrEqual(colName, "equipped_sheen"))   hasSheen = true;
        else if (StrEqual(colName, "equipped_killstreaker")) hasKillstreaker = true;
        else if (StrEqual(colName, "equipped_death")) hasDeath = true;
        else if (StrEqual(colName, "equipped_pet"))   hasPet = true;
        else if (StrEqual(colName, "equipped_spawn")) hasSpawn = true;
    }

    char migrate[256];
    if (!hasSheen)
    {
        g_Database.Format(migrate, sizeof(migrate),
            "ALTER TABLE %s ADD COLUMN equipped_sheen VARCHAR(64) DEFAULT ''", TABLE_NAME);
        g_Database.Query(DB_OnGenericQuery, migrate, _, DBPrio_Low);
    }
    if (!hasKillstreaker)
    {
        g_Database.Format(migrate, sizeof(migrate),
            "ALTER TABLE %s ADD COLUMN equipped_killstreaker VARCHAR(64) DEFAULT ''", TABLE_NAME);
        g_Database.Query(DB_OnGenericQuery, migrate, _, DBPrio_Low);
    }
    if (!hasDeath)
    {
        g_Database.Format(migrate, sizeof(migrate),
            "ALTER TABLE %s ADD COLUMN equipped_death VARCHAR(64) DEFAULT ''", TABLE_NAME);
        g_Database.Query(DB_OnGenericQuery, migrate, _, DBPrio_Low);
    }
    if (!hasPet)
    {
        g_Database.Format(migrate, sizeof(migrate),
            "ALTER TABLE %s ADD COLUMN equipped_pet VARCHAR(128) DEFAULT ''", TABLE_NAME);
        g_Database.Query(DB_OnGenericQuery, migrate, _, DBPrio_Low);
    }
    if (!hasSpawn)
    {
        g_Database.Format(migrate, sizeof(migrate),
            "ALTER TABLE %s ADD COLUMN equipped_spawn VARCHAR(64) DEFAULT ''", TABLE_NAME);
        g_Database.Query(DB_OnGenericQuery, migrate, _, DBPrio_Low);
    }
}

// MySQL fallback — PRAGMA doesn't exist, so just run ALTER and ignore errors.
void RunMigrations()
{
    char migrate[256];
    g_Database.Format(migrate, sizeof(migrate),
        "ALTER TABLE %s ADD COLUMN equipped_sheen VARCHAR(64) DEFAULT ''", TABLE_NAME);
    g_Database.Query(DB_OnMigrationQuery, migrate, _, DBPrio_Low);

    g_Database.Format(migrate, sizeof(migrate),
        "ALTER TABLE %s ADD COLUMN equipped_killstreaker VARCHAR(64) DEFAULT ''", TABLE_NAME);
    g_Database.Query(DB_OnMigrationQuery, migrate, _, DBPrio_Low);

    g_Database.Format(migrate, sizeof(migrate),
        "ALTER TABLE %s ADD COLUMN equipped_death VARCHAR(64) DEFAULT ''", TABLE_NAME);
    g_Database.Query(DB_OnMigrationQuery, migrate, _, DBPrio_Low);

    g_Database.Format(migrate, sizeof(migrate),
        "ALTER TABLE %s ADD COLUMN equipped_pet VARCHAR(128) DEFAULT ''", TABLE_NAME);
    g_Database.Query(DB_OnMigrationQuery, migrate, _, DBPrio_Low);

    g_Database.Format(migrate, sizeof(migrate),
        "ALTER TABLE %s ADD COLUMN equipped_spawn VARCHAR(64) DEFAULT ''", TABLE_NAME);
    g_Database.Query(DB_OnMigrationQuery, migrate, _, DBPrio_Low);
}

// Silently swallow "duplicate column" errors from MySQL migrations.
public void DB_OnMigrationQuery(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0' && StrContains(error, "duplicate") == -1
        && StrContains(error, "Duplicate") == -1)
    {
        LogError("[Leveling] Migration query failed: %s", error);
    }
}

void DB_LoadUser(int client)
{
    if (g_Database == null) return;

    char auth[32];
    if (!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth))) return;

    char escapedAuth[65];
    g_Database.Escape(auth, escapedAuth, sizeof(escapedAuth));

    char query[512];
    g_Database.Format(query, sizeof(query),
        "SELECT level, xp, total_kills, equipped_trail, equipped_aura, "
    ... "equipped_model, equipped_tag, playtime, custom_welcome, custom_tag, "
    ... "equipped_sheen, equipped_killstreaker, equipped_death, equipped_pet, equipped_spawn "
    ... "FROM %s WHERE steam_id = '%s'",
        TABLE_NAME, escapedAuth);

    g_Database.Query(DB_OnUserLoaded, query, GetClientUserId(client));
}

public void DB_OnUserLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client == 0) return;

    if (error[0] != '\0')
    {
        LogError("[Leveling] Failed to load user: %s", error);
        return;
    }

    if (results.FetchRow())
    {
        g_Level[client]      = results.FetchInt(0);
        g_XP[client]         = results.FetchInt(1);
        g_TotalKills[client] = results.FetchInt(2);
        results.FetchString(3, g_Trail[client], sizeof(g_Trail[]));
        results.FetchString(4, g_Aura[client],  sizeof(g_Aura[]));
        results.FetchString(5, g_Model[client], sizeof(g_Model[]));
        results.FetchString(6, g_Tag[client],   sizeof(g_Tag[]));
        g_Playtime[client]   = results.FetchInt(7);
        results.FetchString(8, g_CustomWelcome[client], sizeof(g_CustomWelcome[]));
        results.FetchString(9, g_CustomTag[client],     sizeof(g_CustomTag[]));
        results.FetchString(10, g_Sheen[client],        sizeof(g_Sheen[]));
        results.FetchString(11, g_Killstreaker[client], sizeof(g_Killstreaker[]));
        results.FetchString(12, g_Death[client],        sizeof(g_Death[]));
        results.FetchString(13, g_Pet[client],          sizeof(g_Pet[]));
        results.FetchString(14, g_Spawn[client],        sizeof(g_Spawn[]));
    }
    else
    {
        DB_CreateUser(client);
    }

    g_DataLoaded[client] = true;

    if (g_Verbose.BoolValue)
        LogMessage("[Leveling] Loaded %N - Level %d, %d XP", client, g_Level[client], g_XP[client]);

    Call_StartForward(g_OnDataLoaded);
    Call_PushCell(client);
    Call_Finish();
}

void DB_CreateUser(int client)
{
    if (g_Database == null) return;

    char auth[32], name[64];
    if (!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth))) return;
    GetClientName(client, name, sizeof(name));

    char escapedAuth[65], safeName[129];
    g_Database.Escape(auth, escapedAuth, sizeof(escapedAuth));
    g_Database.Escape(name, safeName, sizeof(safeName));

    char query[512];
    g_Database.Format(query, sizeof(query),
        "INSERT INTO %s (steam_id, name, level, xp, total_kills, schema_version) "
    ... "VALUES ('%s', '%s', 1, 0, 0, %d)",
        TABLE_NAME, escapedAuth, safeName, SCHEMA_VERSION);

    g_Database.Query(DB_OnGenericQuery, query);
}

void DB_SaveUser(int client)
{
    if (g_Database == null || !g_DataLoaded[client]) return;

    char auth[32], name[64];
    if (!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth))) return;
    GetClientName(client, name, sizeof(name));

    // Escape all user-controlled strings
    char ea[65], sn[129], st[129], sa[129], sm[129], stag[33], sw[257], sct[65];
    char se[129], sd[129], sp[257];
    g_Database.Escape(auth, ea, sizeof(ea));
    g_Database.Escape(name, sn, sizeof(sn));
    g_Database.Escape(g_Trail[client], st, sizeof(st));
    g_Database.Escape(g_Aura[client],  sa, sizeof(sa));
    g_Database.Escape(g_Model[client], sm, sizeof(sm));
    g_Database.Escape(g_Tag[client],   stag, sizeof(stag));
    g_Database.Escape(g_Sheen[client],   se, sizeof(se));
    char sk[129];
    g_Database.Escape(g_Killstreaker[client], sk, sizeof(sk));
    g_Database.Escape(g_Death[client], sd, sizeof(sd));
    g_Database.Escape(g_Pet[client],   sp, sizeof(sp));
    char ssw[129];
    g_Database.Escape(g_Spawn[client], ssw, sizeof(ssw));
    g_Database.Escape(g_CustomWelcome[client], sw, sizeof(sw));
    g_Database.Escape(g_CustomTag[client],     sct, sizeof(sct));

    char query[3072];
    g_Database.Format(query, sizeof(query),
        "UPDATE %s SET name='%s', level=%d, xp=%d, total_kills=%d, "
    ... "equipped_trail='%s', equipped_aura='%s', equipped_model='%s', equipped_tag='%s', "
    ... "equipped_sheen='%s', equipped_killstreaker='%s', equipped_death='%s', equipped_pet='%s', equipped_spawn='%s', "
    ... "custom_welcome='%s', custom_tag='%s', "
    ... "playtime=%d, last_seen=CURRENT_TIMESTAMP "
    ... "WHERE steam_id='%s'",
        TABLE_NAME, sn, g_Level[client], g_XP[client], g_TotalKills[client],
        st, sa, sm, stag, se, sk, sd, sp, ssw, sw, sct,
        GetCurrentPlaytime(client), ea);

    g_Database.Query(DB_OnGenericQuery, query);

    if (g_Verbose.BoolValue)
        LogMessage("[Leveling] Saved %N - Level %d", client, g_Level[client]);
}

public void DB_OnGenericQuery(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
        LogError("[Leveling] Query failed: %s", error);
}

// ============================================================================
// AUTO-SAVE (batched with transaction)
// ============================================================================

public Action Timer_AutoSave(Handle timer)
{
    if (g_Database == null) return Plugin_Continue;

    Transaction txn = new Transaction();
    int count = 0;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || IsFakeClient(client) || !g_DataLoaded[client])
            continue;

        char auth[32], name[64];
        if (!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth))) continue;
        GetClientName(client, name, sizeof(name));

        char ea[65], sn[129], st[129], sa[129], sm[129], stag[33], sw[257], sct[65];
        char se[129], sd[129], sp[257];
        g_Database.Escape(auth, ea, sizeof(ea));
        g_Database.Escape(name, sn, sizeof(sn));
        g_Database.Escape(g_Trail[client], st, sizeof(st));
        g_Database.Escape(g_Aura[client],  sa, sizeof(sa));
        g_Database.Escape(g_Model[client], sm, sizeof(sm));
        g_Database.Escape(g_Tag[client],   stag, sizeof(stag));
        g_Database.Escape(g_Sheen[client],   se, sizeof(se));
        char sk[129];
        g_Database.Escape(g_Killstreaker[client], sk, sizeof(sk));
        g_Database.Escape(g_Death[client], sd, sizeof(sd));
        g_Database.Escape(g_Pet[client],   sp, sizeof(sp));
        char ssw[129];
        g_Database.Escape(g_Spawn[client], ssw, sizeof(ssw));
        g_Database.Escape(g_CustomWelcome[client], sw, sizeof(sw));
        g_Database.Escape(g_CustomTag[client],     sct, sizeof(sct));

        char query[3072];
        g_Database.Format(query, sizeof(query),
            "UPDATE %s SET name='%s', level=%d, xp=%d, total_kills=%d, "
        ... "equipped_trail='%s', equipped_aura='%s', equipped_model='%s', equipped_tag='%s', "
        ... "equipped_sheen='%s', equipped_killstreaker='%s', equipped_death='%s', equipped_pet='%s', equipped_spawn='%s', "
        ... "custom_welcome='%s', custom_tag='%s', "
        ... "playtime=%d, last_seen=CURRENT_TIMESTAMP "
        ... "WHERE steam_id='%s'",
            TABLE_NAME, sn, g_Level[client], g_XP[client], g_TotalKills[client],
            st, sa, sm, stag, se, sk, sd, sp, ssw, sw, sct,
            GetCurrentPlaytime(client), ea);

        txn.AddQuery(query);
        count++;
    }

    if (count > 0)
    {
        g_Database.Execute(txn, _, DB_OnTxnFailure);
        if (g_Verbose.BoolValue)
            LogMessage("[Leveling] Auto-saved %d player(s) in transaction", count);
    }
    else
    {
        delete txn;
    }

    return Plugin_Continue;
}

public void DB_OnTxnFailure(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    LogError("[Leveling] Auto-save transaction failed at query %d: %s", failIndex, error);
}

// ============================================================================
// EVENTS
// ============================================================================

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int victim   = GetClientOfUserId(event.GetInt("userid"));

    if (attacker < 1 || attacker > MaxClients || attacker == victim) return Plugin_Continue;
    if (IsFakeClient(attacker) || !g_DataLoaded[attacker]) return Plugin_Continue;

    // No XP for killing bots
    if (victim >= 1 && victim <= MaxClients && IsFakeClient(victim))
        return Plugin_Continue;

    // Spy Dead Ringer feign death — don't award XP/kills for fake deaths
    if (event.GetInt("death_flags") & TF_DEATHFLAG_DEADRINGER)
        return Plugin_Continue;

    g_TotalKills[attacker]++;

    int xp = g_KillXP;

    if (event.GetInt("death_flags") & TF_DEATHFLAG_REVENGE)
    {
        xp += g_RevengeXP;
        CPrintToChat(attacker, "%t", "RevengeBonus");
    }

    if (CheckCommandAccess(attacker, "sm_donor_perk", ADMFLAG_RESERVATION, true))
        xp *= g_DonorMultiplier;

    GiveXP(attacker, xp);
    return Plugin_Continue;
}

// ============================================================================
// COMMANDS
// ============================================================================

public Action Command_Level(int client, int args)
{
    if (client == 0) return Plugin_Handled;
    if (!g_DataLoaded[client])
    {
        CPrintToChat(client, "%t", "DataNotLoaded");
        return Plugin_Handled;
    }

    int needed = GetXPForNextLevel(g_Level[client]);
    int hours = GetCurrentPlaytime(client) / 3600;
    int minutes = (GetCurrentPlaytime(client) % 3600) / 60;

    CPrintToChat(client, "%t", "LevelInfo", g_Level[client], g_XP[client],
                 needed == -1 ? 0 : needed, g_TotalKills[client], hours, minutes);
    return Plugin_Handled;
}

public Action Command_Rank(int client, int args)
{
    if (client == 0 || g_Database == null) return Plugin_Handled;

    char query[256];
    g_Database.Format(query, sizeof(query),
        "SELECT name, level, xp FROM %s ORDER BY level DESC, xp DESC LIMIT 10",
        TABLE_NAME);

    g_Database.Query(DB_OnTopQuery, query, GetClientUserId(client));
    return Plugin_Handled;
}

public void DB_OnTopQuery(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client == 0 || error[0] != '\0') return;

    Menu menu = new Menu(Handler_TopMenu);
    menu.SetTitle("Top 10 Players");

    int rank = 1;
    while (results.FetchRow())
    {
        char topName[64], display[128];
        results.FetchString(0, topName, sizeof(topName));
        int level = results.FetchInt(1);
        Format(display, sizeof(display), "#%d %s (Lvl %d)", rank++, topName, level);
        menu.AddItem("", display, ITEMDRAW_DISABLED);
    }

    if (rank == 1)
        menu.AddItem("", "No data", ITEMDRAW_DISABLED);

    menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_TopMenu(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End) delete menu;
    return 0;
}

public Action Command_GiveXP(int client, int args)
{
    if (args < 2)
    {
        ReplyToCommand(client, "%t", "GiveXP_Usage");
        return Plugin_Handled;
    }

    char targetName[64], amountStr[16];
    GetCmdArg(1, targetName, sizeof(targetName));
    GetCmdArg(2, amountStr, sizeof(amountStr));

    int amount = StringToInt(amountStr);
    if (amount <= 0 || amount > MAX_GIVEXP)
    {
        ReplyToCommand(client, "%t", "GiveXP_Invalid");
        return Plugin_Handled;
    }

    int target = FindTarget(client, targetName, true, false);
    if (target == -1) return Plugin_Handled;

    GiveXP(target, amount);
    LogAction(client, target, "\"%L\" gave %d XP to \"%L\"", client, amount, target);
    CPrintToChat(client, "%t", "GiveXP_Success", amount, target);

    return Plugin_Handled;
}

public Action Command_SetLevel(int client, int args)
{
    if (args < 2)
    {
        ReplyToCommand(client, "%t", "SetLevel_Usage");
        return Plugin_Handled;
    }

    char targetName[64], levelStr[16];
    GetCmdArg(1, targetName, sizeof(targetName));
    GetCmdArg(2, levelStr, sizeof(levelStr));

    int level = StringToInt(levelStr);
    if (level < 1 || level > MAX_LEVEL)
    {
        ReplyToCommand(client, "%t", "SetLevel_Invalid", MAX_LEVEL);
        return Plugin_Handled;
    }

    int target = FindTarget(client, targetName, true, false);
    if (target == -1) return Plugin_Handled;

    g_Level[target] = level;
    g_XP[target] = 0;
    DB_SaveUser(target);

    LogAction(client, target, "\"%L\" set level of \"%L\" to %d", client, target, level);
    CPrintToChat(client, "%t", "SetLevel_Success", target, level);
    CPrintToChat(target, "%t", "SetLevel_Notify", level);

    return Plugin_Handled;
}

public Action Command_ResetLevel(int client, int args)
{
    if (args < 1)
    {
        ReplyToCommand(client, "%t", "ResetLevel_Usage");
        return Plugin_Handled;
    }

    char targetName[64];
    GetCmdArg(1, targetName, sizeof(targetName));

    int target = FindTarget(client, targetName, true, false);
    if (target == -1) return Plugin_Handled;

    ResetPlayerData(target);
    g_DataLoaded[target] = true;
    g_ConnectTime[target] = GetTime();
    DB_SaveUser(target);

    LogAction(client, target, "\"%L\" reset level of \"%L\"", client, target);
    CPrintToChat(client, "%t", "ResetLevel_Success", target);
    CPrintToChat(target, "%t", "ResetLevel_Notify");

    return Plugin_Handled;
}

// ============================================================================
// NATIVES
// ============================================================================

public int Native_GetLevel(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    ValidateClient(client);
    return g_Level[client];
}

public int Native_GetXP(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    ValidateClient(client);
    return g_XP[client];
}

public int Native_GetTotalKills(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    ValidateClient(client);
    return g_TotalKills[client];
}

public int Native_GetPlaytime(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    ValidateClient(client);
    return GetCurrentPlaytime(client);
}

public int Native_GetXPForLevel(Handle plugin, int numParams)
{
    return GetXPForNextLevel(GetNativeCell(1));
}

public int Native_IsDataLoaded(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (client < 1 || client > MaxClients) return false;
    return g_DataLoaded[client];
}

public int Native_GiveXP(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int amount = GetNativeCell(2);
    ValidateClient(client);

    if (amount < 1 || amount > MAX_GIVEXP)
        return ThrowNativeError(SP_ERROR_NATIVE, "Amount must be 1-%d, got %d", MAX_GIVEXP, amount);

    GiveXP(client, amount);
    return 0;
}

public int Native_SetLevel(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int level  = GetNativeCell(2);
    ValidateClient(client);

    if (level < 1 || level > MAX_LEVEL)
        return ThrowNativeError(SP_ERROR_NATIVE, "Level must be 1-%d", MAX_LEVEL);

    g_Level[client] = level;
    g_XP[client] = 0;
    return 0;
}

public int Native_HasLevel(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    ValidateClient(client);
    return g_Level[client] >= GetNativeCell(2);
}

public int Native_SavePlayer(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    ValidateClient(client);
    DB_SaveUser(client);
    return 0;
}

public any Native_GetDatabase(Handle plugin, int numParams)
{
    return g_Database;
}

// Cosmetic data natives
public int Native_GetEquipped(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    ValidateClient(client);

    CosmeticType type = view_as<CosmeticType>(GetNativeCell(2));
    int maxlen = GetNativeCell(4);

    switch (type)
    {
        case Cosmetic_Trail: SetNativeString(3, g_Trail[client], maxlen);
        case Cosmetic_Aura:  SetNativeString(3, g_Aura[client], maxlen);
        case Cosmetic_Model: SetNativeString(3, g_Model[client], maxlen);
        case Cosmetic_Tag:   SetNativeString(3, g_Tag[client], maxlen);
        case Cosmetic_Sheen:        SetNativeString(3, g_Sheen[client], maxlen);
        case Cosmetic_Killstreaker: SetNativeString(3, g_Killstreaker[client], maxlen);
        case Cosmetic_Death: SetNativeString(3, g_Death[client], maxlen);
        case Cosmetic_Pet:   SetNativeString(3, g_Pet[client], maxlen);
        case Cosmetic_Spawn: SetNativeString(3, g_Spawn[client], maxlen);
        default: ThrowNativeError(SP_ERROR_NATIVE, "Invalid CosmeticType %d", type);
    }

    return 0;
}

public int Native_SetEquipped(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    ValidateClient(client);

    CosmeticType type = view_as<CosmeticType>(GetNativeCell(2));

    char value[128];
    GetNativeString(3, value, sizeof(value));

    switch (type)
    {
        case Cosmetic_Trail: strcopy(g_Trail[client], sizeof(g_Trail[]), value);
        case Cosmetic_Aura:  strcopy(g_Aura[client], sizeof(g_Aura[]), value);
        case Cosmetic_Model: strcopy(g_Model[client], sizeof(g_Model[]), value);
        case Cosmetic_Tag:   strcopy(g_Tag[client], sizeof(g_Tag[]), value);
        case Cosmetic_Sheen:        strcopy(g_Sheen[client], sizeof(g_Sheen[]), value);
        case Cosmetic_Killstreaker: strcopy(g_Killstreaker[client], sizeof(g_Killstreaker[]), value);
        case Cosmetic_Death: strcopy(g_Death[client], sizeof(g_Death[]), value);
        case Cosmetic_Pet:   strcopy(g_Pet[client], sizeof(g_Pet[]), value);
        case Cosmetic_Spawn: strcopy(g_Spawn[client], sizeof(g_Spawn[]), value);
        default: ThrowNativeError(SP_ERROR_NATIVE, "Invalid CosmeticType %d", type);
    }

    return 0;
}

// VIP data natives
public int Native_GetCustomWelcome(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    ValidateClient(client);
    SetNativeString(2, g_CustomWelcome[client], GetNativeCell(3));
    return 0;
}

public int Native_SetCustomWelcome(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    ValidateClient(client);
    GetNativeString(2, g_CustomWelcome[client], sizeof(g_CustomWelcome[]));
    return 0;
}

public int Native_GetCustomTag(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    ValidateClient(client);
    SetNativeString(2, g_CustomTag[client], GetNativeCell(3));
    return 0;
}

public int Native_SetCustomTag(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    ValidateClient(client);
    GetNativeString(2, g_CustomTag[client], sizeof(g_CustomTag[]));
    return 0;
}

// ============================================================================
// HELPERS
// ============================================================================

void ValidateClient(int client)
{
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
        ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);
}

int ClampInt(int value, int min, int max)
{
    if (value < min) return min;
    if (value > max) return max;
    return value;
}

float ClampFloat(float value, float min, float max)
{
    if (value < min) return min;
    if (value > max) return max;
    return value;
}

public void OnPluginEnd()
{
    // Save all connected players
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client) && !IsFakeClient(client) && g_DataLoaded[client])
        {
            g_Playtime[client] += GetTime() - g_ConnectTime[client];
            g_ConnectTime[client] = GetTime();
            DB_SaveUser(client);
        }
    }
}
