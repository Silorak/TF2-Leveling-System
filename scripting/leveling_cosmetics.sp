#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>
#include <colorvariables>
#include <leveling>

#define PLUGIN_NAME    "[Leveling] Cosmetics"
#define PLUGIN_VERSION "1.1.0"

public Plugin myinfo =
{
    name        = PLUGIN_NAME,
    author      = "Silorak",
    description = "Trails, auras, models, and equip menu",
    version     = PLUGIN_VERSION,
    url         = "https://github.com/Silorak/TF2-Leveling-System"
};

enum struct CosmeticItem
{
    char name[64];
    char value[128];
    int level;
    int flag; // Admin flag required (0 = none, available to all)
    
    // Optional properties for trails
    char color[32];
    float startwidth;
    float endwidth;
    float lifetime;
}

ArrayList g_TrailList;
ArrayList g_AuraList;
ArrayList g_ModelList;

int  g_iTrailEntity[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... };
int  g_iAuraEntity[MAXPLAYERS + 1]  = { INVALID_ENT_REFERENCE, ... };
bool g_bHasCustomModel[MAXPLAYERS + 1];

public void OnPluginStart()
{
    g_TrailList = new ArrayList(sizeof(CosmeticItem));
    g_AuraList  = new ArrayList(sizeof(CosmeticItem));
    g_ModelList = new ArrayList(sizeof(CosmeticItem));

    LoadTranslations("leveling.phrases");

    RegConsoleCmd("sm_cosmetics", Command_Cosmetics, "Open cosmetics menu");
    RegConsoleCmd("sm_equip",     Command_Cosmetics, "Open cosmetics menu");

    HookEvent("player_spawn", Event_PlayerSpawn);
}

public void OnMapStart()
{
    LoadCosmetics();
    PrecacheCosmetics();
}

public void OnClientDisconnect(int client)
{
    RemoveAllCosmetics(client);
    g_bHasCustomModel[client] = false;
}

public void Leveling_OnDataLoaded(int client)
{
    if (IsPlayerAlive(client))
        ApplyCosmetics(client);
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0 && IsPlayerAlive(client) && Leveling_IsDataLoaded(client))
        ApplyCosmetics(client);
    return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (StrEqual(classname, "tf_wearable") || StrEqual(classname, "tf_powerup_bottle"))
    {
        SDKHook(entity, SDKHook_SetTransmit, Hook_WearableTransmit);
    }
}

public Action Hook_WearableTransmit(int entity, int client)
{
    int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
    
    // Only hide wearables for players using a custom model
    if (owner > 0 && owner <= MaxClients && g_bHasCustomModel[owner])
        return Plugin_Handled;
    
    return Plugin_Continue;
}

// ============================================================================
// COSMETIC APPLICATION
// ============================================================================

void ApplyCosmetics(int client)
{
    if (!IsPlayerAlive(client)) return;

    char buffer[128];

    // Trail
    Leveling_GetEquipped(client, Cosmetic_Trail, buffer, sizeof(buffer));
    if (buffer[0] != '\0')
        CreateTrail(client, buffer);

    // Aura
    Leveling_GetEquipped(client, Cosmetic_Aura, buffer, sizeof(buffer));
    if (buffer[0] != '\0')
        CreateAura(client, buffer);

    // Model
    Leveling_GetEquipped(client, Cosmetic_Model, buffer, sizeof(buffer));
    if (buffer[0] != '\0')
        SetPlayerModel(client, buffer);

    // Spawn particle for level 3+
    if (Leveling_GetLevel(client) >= 3)
        CreateSpawnParticle(client);
}

void RemoveAllCosmetics(int client)
{
    RemoveTrail(client);
    RemoveAura(client);
    RestoreModel(client);
}

// ============================================================================
// TRAIL
// ============================================================================

void CreateTrail(int client, const char[] material)
{
    RemoveTrail(client);

    int trail = CreateEntityByName("env_spritetrail");
    if (trail == -1) return;

    DispatchKeyValue(trail, "spritename", material);
    
    // Default values if we can't find the trail in our config
    char color[32] = "255 255 255";
    float startwidth = 20.0;
    float endwidth = 1.0;
    float lifetime = 2.0;

    // Look up the trail properties
    for (int i = 0; i < g_TrailList.Length; i++)
    {
        CosmeticItem item;
        g_TrailList.GetArray(i, item);
        if (StrEqual(item.value, material))
        {
            strcopy(color, sizeof(color), item.color);
            startwidth = item.startwidth;
            endwidth = item.endwidth;
            lifetime = item.lifetime;
            break;
        }
    }
    
    char buffer[16];
    FloatToString(startwidth, buffer, sizeof(buffer));
    DispatchKeyValue(trail, "startwidth", buffer);
    
    FloatToString(endwidth, buffer, sizeof(buffer));
    DispatchKeyValue(trail, "endwidth", buffer);
    
    FloatToString(lifetime, buffer, sizeof(buffer));
    DispatchKeyValue(trail, "lifetime", buffer);
    
    DispatchKeyValue(trail, "rendercolor", color);
    DispatchKeyValue(trail, "rendermode", "5");
    DispatchSpawn(trail);

    float pos[3];
    GetClientAbsOrigin(client, pos);
    pos[2] += 10.0;
    TeleportEntity(trail, pos, NULL_VECTOR, NULL_VECTOR);

    SetVariantString("!activator");
    AcceptEntityInput(trail, "SetParent", client);

    g_iTrailEntity[client] = EntIndexToEntRef(trail);
}

void RemoveTrail(int client)
{
    if (g_iTrailEntity[client] != INVALID_ENT_REFERENCE)
    {
        int entity = EntRefToEntIndex(g_iTrailEntity[client]);
        if (entity != INVALID_ENT_REFERENCE)
            AcceptEntityInput(entity, "Kill");
    }
    g_iTrailEntity[client] = INVALID_ENT_REFERENCE;
}

// ============================================================================
// AURA
// ============================================================================

void CreateAura(int client, const char[] particleName)
{
    RemoveAura(client);

    int particle = CreateEntityByName("info_particle_system");
    if (particle == -1) return;

    DispatchKeyValue(particle, "effect_name", particleName);
    DispatchSpawn(particle);
    ActivateEntity(particle);
    AcceptEntityInput(particle, "Start");

    SetVariantString("!activator");
    AcceptEntityInput(particle, "SetParent", client);

    g_iAuraEntity[client] = EntIndexToEntRef(particle);
    SDKHook(particle, SDKHook_SetTransmit, Hook_AuraTransmit);
}

public Action Hook_AuraTransmit(int entity, int client)
{
    int owner = GetEntPropEnt(entity, Prop_Data, "m_pParent");
    return (owner == client) ? Plugin_Handled : Plugin_Continue;
}

void RemoveAura(int client)
{
    if (g_iAuraEntity[client] != INVALID_ENT_REFERENCE)
    {
        int entity = EntRefToEntIndex(g_iAuraEntity[client]);
        if (entity != INVALID_ENT_REFERENCE)
            AcceptEntityInput(entity, "Kill");
    }
    g_iAuraEntity[client] = INVALID_ENT_REFERENCE;
}

// ============================================================================
// MODEL (using TF2's SetCustomModel)
// ============================================================================

void SetPlayerModel(int client, const char[] modelPath)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client)) return;

    if (!IsModelPrecached(modelPath))
    {
        LogError("[Leveling] Model not precached: %s", modelPath);
        return;
    }

    SetVariantString(modelPath);
    AcceptEntityInput(client, "SetCustomModel");
    SetEntProp(client, Prop_Send, "m_bUseClassAnimations", 1);
    g_bHasCustomModel[client] = true;
}

void RestoreModel(int client)
{
    if (g_bHasCustomModel[client])
    {
        if (IsClientInGame(client) && IsPlayerAlive(client))
        {
            SetVariantString("");
            AcceptEntityInput(client, "SetCustomModel");
        }
        g_bHasCustomModel[client] = false;
    }
}

// ============================================================================
// SPAWN PARTICLE
// ============================================================================

void CreateSpawnParticle(int client)
{
    int particle = CreateEntityByName("info_particle_system");
    if (particle == -1) return;

    DispatchKeyValue(particle, "effect_name", "achieved");
    DispatchSpawn(particle);

    float pos[3];
    GetClientAbsOrigin(client, pos);
    TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);

    ActivateEntity(particle);
    AcceptEntityInput(particle, "Start");

    CreateTimer(2.0, Timer_KillEntity, EntIndexToEntRef(particle), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_KillEntity(Handle timer, int ref)
{
    int entity = EntRefToEntIndex(ref);
    if (entity != INVALID_ENT_REFERENCE && IsValidEntity(entity))
        AcceptEntityInput(entity, "Kill");
    return Plugin_Stop;
}

// ============================================================================
// MENUS
// ============================================================================

public Action Command_Cosmetics(int client, int args)
{
    if (client == 0) return Plugin_Handled;
    if (!Leveling_IsDataLoaded(client))
    {
        CPrintToChat(client, "%t", "DataNotLoaded");
        return Plugin_Handled;
    }
    OpenEquipMenu(client);
    return Plugin_Handled;
}

void OpenEquipMenu(int client)
{
    Menu menu = new Menu(Handler_EquipMenu);
    menu.SetTitle("Cosmetics (Level %d)", Leveling_GetLevel(client));

    char info[8];
    IntToString(view_as<int>(Cosmetic_Trail), info, sizeof(info));
    menu.AddItem(info, "Trails");
    IntToString(view_as<int>(Cosmetic_Aura), info, sizeof(info));
    menu.AddItem(info, "Auras");
    IntToString(view_as<int>(Cosmetic_Model), info, sizeof(info));
    menu.AddItem(info, "Models");
    menu.AddItem("unequip", "Unequip All");
    menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_EquipMenu(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));

        if (StrEqual(info, "unequip"))
        {
            Leveling_SetEquipped(param1, Cosmetic_Trail, "");
            Leveling_SetEquipped(param1, Cosmetic_Aura, "");
            Leveling_SetEquipped(param1, Cosmetic_Model, "");
            RemoveAllCosmetics(param1);
            CPrintToChat(param1, "%t", "Cosmetics_UnequipAll");
            OpenEquipMenu(param1);
        }
        else
        {
            CosmeticType type = view_as<CosmeticType>(StringToInt(info));
            OpenCosmeticList(param1, type);
        }
    }
    else if (action == MenuAction_End) delete menu;
    return 0;
}

void OpenCosmeticList(int client, CosmeticType type)
{
    int playerLevel = Leveling_GetLevel(client);

    char title[32];
    switch (type)
    {
        case Cosmetic_Trail: strcopy(title, sizeof(title), "Trails");
        case Cosmetic_Aura:  strcopy(title, sizeof(title), "Auras");
        case Cosmetic_Model: strcopy(title, sizeof(title), "Models");
    }

    Menu menu = new Menu(Handler_CosmeticList);
    menu.SetTitle("Select %s", title);

    ArrayList list = null;
    switch (type)
    {
        case Cosmetic_Trail: list = g_TrailList;
        case Cosmetic_Aura:  list = g_AuraList;
        case Cosmetic_Model: list = g_ModelList;
    }

    if (list != null)
    {
        for (int i = 0; i < list.Length; i++)
        {
            CosmeticItem item;
            list.GetArray(i, item);

            // Encode "typeInt|value" in info
            char info[256];
            Format(info, sizeof(info), "%d|%s", view_as<int>(type), item.value);

            bool hasLevel = (item.level <= playerLevel);
            bool hasFlag  = (item.flag == 0 || CheckCommandAccess(client, "sm_cosmetic_flag", item.flag, true));

            if (hasLevel && hasFlag)
            {
                menu.AddItem(info, item.name);
            }
            else
            {
                char display[128];
                if (!hasFlag)
                    Format(display, sizeof(display), "%s (VIP Only)", item.name);
                else
                    Format(display, sizeof(display), "%s (Locked - Lvl %d)", item.name, item.level);
                menu.AddItem("", display, ITEMDRAW_DISABLED);
            }
        }
    }

    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_CosmeticList(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        char info[256], display[64];
        menu.GetItem(param2, info, sizeof(info), _, display, sizeof(display));

        int sep = StrContains(info, "|");
        if (sep == -1) return 0;

        // Parse type from int before separator
        char typeStr[8];
        strcopy(typeStr, sizeof(typeStr), info);
        typeStr[sep] = '\0';
        CosmeticType type = view_as<CosmeticType>(StringToInt(typeStr));

        // Value is everything after separator
        char value[256];
        strcopy(value, sizeof(value), info[sep + 1]);

        Leveling_SetEquipped(param1, type, value);

        // Remove the old entity of this specific type before applying new one
        switch (type)
        {
            case Cosmetic_Trail:
            {
                RemoveTrail(param1);
                CreateTrail(param1, value);
                CPrintToChat(param1, "%t", "Trail_Equipped", display);
            }
            case Cosmetic_Aura:
            {
                RemoveAura(param1);
                CreateAura(param1, value);
                CPrintToChat(param1, "%t", "Aura_Equipped", display);
            }
            case Cosmetic_Model:
            {
                RestoreModel(param1);
                SetPlayerModel(param1, value);
                CPrintToChat(param1, "%t", "Model_Equipped", display);
            }
        }

        OpenEquipMenu(param1);
    }
    else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        OpenEquipMenu(param1);
    }
    else if (action == MenuAction_End) delete menu;
    return 0;
}

// ============================================================================
// CONFIG LOADING
// ============================================================================

void LoadCosmetics()
{
    g_TrailList.Clear();
    g_AuraList.Clear();
    g_ModelList.Clear();

    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/leveling/cosmetics.cfg");

    if (!FileExists(path)) return;

    KeyValues kv = new KeyValues("LevelingCosmetics");
    if (!kv.ImportFromFile(path))
    {
        delete kv;
        return;
    }

    ParseSection(kv, "Trails", g_TrailList, "material");
    ParseSection(kv, "Auras",  g_AuraList,  "effect");
    ParseSection(kv, "Models", g_ModelList,  "model");

    delete kv;
}

void ParseSection(KeyValues kv, const char[] section, ArrayList list, const char[] valueKey)
{
    if (!kv.JumpToKey(section)) return;

    if (kv.GotoFirstSubKey())
    {
        do
        {
            CosmeticItem item;
            kv.GetSectionName(item.name, sizeof(item.name));
            item.level = kv.GetNum("level");
            kv.GetString(valueKey, item.value, sizeof(item.value));
            
            // Optional admin flag (e.g. "a" for reservation, "b" for generic, etc.)
            char flagStr[16];
            kv.GetString("flag", flagStr, sizeof(flagStr), "");
            item.flag = (flagStr[0] != '\0') ? ReadFlagString(flagStr) : 0;
            
            // Optional Trail parameters (with defaults)
            if (StrEqual(section, "Trails"))
            {
                kv.GetString("color", item.color, sizeof(item.color), "255 255 255");
                item.startwidth = kv.GetFloat("startwidth", 20.0);
                item.endwidth = kv.GetFloat("endwidth", 1.0);
                item.lifetime = kv.GetFloat("lifetime", 2.0);
            }
            
            list.PushArray(item);
        }
        while (kv.GotoNextKey());
        kv.GoBack(); // back to section level
    }
    kv.GoBack(); // back to root
}

void PrecacheCosmetics()
{
    for (int i = 0; i < g_TrailList.Length; i++)
    {
        CosmeticItem item;
        g_TrailList.GetArray(i, item);
        if (item.value[0] != '\0') PrecacheModel(item.value, true);
    }

    for (int i = 0; i < g_ModelList.Length; i++)
    {
        CosmeticItem item;
        g_ModelList.GetArray(i, item);
        if (item.value[0] != '\0') PrecacheModel(item.value, true);
    }
}

public void OnPluginEnd()
{
    // Clean up all client cosmetics
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client))
            RemoveAllCosmetics(client);
    }
    delete g_TrailList;
    delete g_AuraList;
    delete g_ModelList;
}
