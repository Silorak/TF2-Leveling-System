#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>
#include <colorvariables>
#include <leveling>

#undef REQUIRE_PLUGIN
#include <tf2attributes>
#define REQUIRE_PLUGIN

#define PLUGIN_NAME    "[Leveling] Cosmetics"
#define PLUGIN_VERSION "1.4.0"

public Plugin myinfo =
{
    name        = PLUGIN_NAME,
    author      = "Silorak",
    description = "Trails, auras, models, eyes, death effects, and pets",
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

    // Optional properties for pets (from SourcePets approach)
    char animIdle[64];
    char animWalk[64];
    char animJump[64];
    int heightType;       // 1=ground, 2=hover
    int heightCustom;     // offset when hover
    float modelScale;
}

ArrayList g_TrailList;
ArrayList g_AuraList;
ArrayList g_ModelList;
ArrayList g_SheenList;
ArrayList g_KillstreakerList;
ArrayList g_DeathList;
ArrayList g_PetList;
ArrayList g_SpawnList;

int  g_TrailEntity[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... };
int  g_AuraEntity[MAXPLAYERS + 1]  = { INVALID_ENT_REFERENCE, ... };
int  g_PetEntity[MAXPLAYERS + 1]   = { INVALID_ENT_REFERENCE, ... };
int  g_PetState[MAXPLAYERS + 1];    // 0=none, 1=idle, 2=walking, 3=jumping
int  g_PetType[MAXPLAYERS + 1] = { -1, ... }; // index into g_PetList
bool g_HasCustomModel[MAXPLAYERS + 1];
bool g_HasKillstreak[MAXPLAYERS + 1];
bool g_TF2AttribAvailable;

#define PET_STATE_NONE    0
#define PET_STATE_IDLE    1
#define PET_STATE_WALKING 2
#define PET_STATE_JUMPING 3

public void OnPluginStart()
{
    g_TrailList = new ArrayList(sizeof(CosmeticItem));
    g_AuraList  = new ArrayList(sizeof(CosmeticItem));
    g_ModelList = new ArrayList(sizeof(CosmeticItem));
    g_SheenList        = new ArrayList(sizeof(CosmeticItem));
    g_KillstreakerList = new ArrayList(sizeof(CosmeticItem));
    g_DeathList = new ArrayList(sizeof(CosmeticItem));
    g_PetList   = new ArrayList(sizeof(CosmeticItem));
    g_SpawnList = new ArrayList(sizeof(CosmeticItem));

    LoadTranslations("leveling.phrases");

    RegConsoleCmd("sm_cosmetics", Command_Cosmetics, "Open cosmetics menu");
    RegConsoleCmd("sm_equip",     Command_Cosmetics, "Open cosmetics menu");

    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("post_inventory_application", Event_Inventory);
}

// Fires when TF2 gives a player their loadout (spawn, resupply locker, loadout change).
// Weapon entities get recreated, so our killstreak attributes are lost — reapply them.
public Action Event_Inventory(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client < 1 || !IsClientInGame(client) || IsFakeClient(client))
        return Plugin_Continue;

    if (!Leveling_IsDataLoaded(client))
        return Plugin_Continue;

    // Delay slightly so TF2 finishes setting up weapon entities
    CreateTimer(0.3, Timer_ReapplyKillstreak, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Continue;
}

public Action Timer_ReapplyKillstreak(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (client < 1 || !IsClientInGame(client) || !IsPlayerAlive(client))
        return Plugin_Stop;

    CreateEyeEffects(client);

    return Plugin_Stop;
}

public void OnAllPluginsLoaded()
{
    g_TF2AttribAvailable = LibraryExists("tf2attributes");
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "tf2attributes"))
        g_TF2AttribAvailable = true;
}

public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, "tf2attributes"))
        g_TF2AttribAvailable = false;
}

public void OnMapStart()
{
    LoadCosmetics();
    PrecacheCosmetics();
}

public void OnClientDisconnect(int client)
{
    RemoveAllCosmetics(client);
    g_HasCustomModel[client] = false;
    g_HasKillstreak[client] = false;
    g_PetState[client] = PET_STATE_NONE;
    g_PetType[client] = -1;
}

void RemoveAllCosmetics(int client)
{
    RemoveTrail(client);
    RemoveAura(client);
    RemoveEyeEffects(client);
    RemovePet(client);
    RestoreModel(client);
}

public void Leveling_OnDataLoaded(int client)
{
    if (!IsClientInGame(client))
        return;

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
    if (owner > 0 && owner <= MaxClients && g_HasCustomModel[owner])
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

    // Killstreak (Sheen + Eye Effect) — applied together
    CreateEyeEffects(client);

    // Pet
    Leveling_GetEquipped(client, Cosmetic_Pet, buffer, sizeof(buffer));
    if (buffer[0] != '\0')
        CreatePet(client, buffer);

    // Spawn particle (one-shot effect on each respawn)
    Leveling_GetEquipped(client, Cosmetic_Spawn, buffer, sizeof(buffer));
    if (buffer[0] != '\0')
        CreateSpawnParticle(client, buffer);
}

// (RemoveAllCosmetics is defined above near OnClientDisconnect)

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
            if (item.color[0] != '\0')
                strcopy(color, sizeof(color), item.color);
            if (item.startwidth > 0.0)
                startwidth = item.startwidth;
            if (item.endwidth > 0.0)
                endwidth = item.endwidth;
            if (item.lifetime > 0.0)
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

    g_TrailEntity[client] = EntIndexToEntRef(trail);
}

void RemoveTrail(int client)
{
    if (g_TrailEntity[client] != INVALID_ENT_REFERENCE)
    {
        int entity = EntRefToEntIndex(g_TrailEntity[client]);
        if (entity != INVALID_ENT_REFERENCE)
            AcceptEntityInput(entity, "Kill");
    }
    g_TrailEntity[client] = INVALID_ENT_REFERENCE;
}

// ============================================================================
// AURA
// ============================================================================

void CreateAura(int client, const char[] particleName)
{
    RemoveAura(client);

    int particle = CreateEntityByName("info_particle_system");
    if (!IsValidEntity(particle)) return;

    float pos[3];
    GetClientAbsOrigin(client, pos);

    // Reuse or assign a targetname on the player (same approach as guardian plugin).
    char targetName[64];
    GetEntPropString(client, Prop_Data, "m_iName", targetName, sizeof(targetName));
    if (targetName[0] == '\0')
    {
        Format(targetName, sizeof(targetName), "lvlplayer%d", client);
        DispatchKeyValue(client, "targetname", targetName);
    }

    DispatchKeyValue(particle, "effect_name", particleName);
    DispatchKeyValueVector(particle, "origin", pos);

    DispatchSpawn(particle);
    ActivateEntity(particle);
    AcceptEntityInput(particle, "Start");

    // Parent to player using their targetname.
    SetVariantString(targetName);
    AcceptEntityInput(particle, "SetParent", client, particle, 0);

    // Most utaunt_*_parent particles are ground-ring/feet effects designed to
    // emit from entity origin.  Do NOT attach them to a bone — that displaces
    // and flips the effect.  Only attach non-parent utaunt particles (rare)
    // to "flag" if they're meant to float around the body.
    if (StrContains(particleName, "_parent", false) == -1
        && StrContains(particleName, "utaunt_", false) == -1)
    {
        SetVariantString("flag");
        AcceptEntityInput(particle, "SetParentAttachment", client, particle, 0);
    }

    g_AuraEntity[client] = EntIndexToEntRef(particle);
}

void RemoveAura(int client)
{
    KillEntRef(g_AuraEntity[client]);
    g_AuraEntity[client] = INVALID_ENT_REFERENCE;
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
    g_HasCustomModel[client] = true;
}

void RestoreModel(int client)
{
    if (g_HasCustomModel[client])
    {
        if (IsClientInGame(client) && IsPlayerAlive(client))
        {
            SetVariantString("");
            AcceptEntityInput(client, "SetCustomModel");
        }
        g_HasCustomModel[client] = false;
    }
}

// ============================================================================
// SPAWN PARTICLE
// ============================================================================

void CreateSpawnParticle(int client, const char[] particleName = "achieved")
{
    int particle = CreateEntityByName("info_particle_system");
    if (!IsValidEntity(particle)) return;

    DispatchKeyValue(particle, "effect_name", particleName);

    float pos[3];
    GetClientAbsOrigin(client, pos);

    DispatchKeyValueVector(particle, "origin", pos);
    DispatchSpawn(particle);
    ActivateEntity(particle);
    AcceptEntityInput(particle, "Start");

    CreateTimer(3.0, Timer_KillEntity, EntIndexToEntRef(particle), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_KillEntity(Handle timer, int ref)
{
    int entity = EntRefToEntIndex(ref);
    if (entity != INVALID_ENT_REFERENCE && IsValidEntity(entity))
        AcceptEntityInput(entity, "Kill");
    return Plugin_Stop;
}

// ============================================================================
// EYE EFFECTS (Professional Killstreak via TF2Attributes)
// ============================================================================
// Config "effect" value format: "effectID;sheenID"
// effectID: 2002=Fire Horns, 2003=Cerebral Discharge, 2004=Tornado,
//           2005=Flames, 2006=Singularity, 2007=Incinerator, 2008=Hypno-Beam
// sheenID:  1=Team Shine, 2=Deadly Daffodil, 3=Manndarin, 4=Mean Green,
//           5=Agonizing Emerald, 6=Villainous Violet, 7=Hot Rod

void CreateEyeEffects(int client)
{
    RemoveEyeEffects(client);

    if (!g_TF2AttribAvailable) return;
    if (!IsClientInGame(client) || !IsPlayerAlive(client)) return;

    // Read both equipped values
    char sheenStr[64], killstreakerStr[64];
    Leveling_GetEquipped(client, Cosmetic_Sheen, sheenStr, sizeof(sheenStr));
    Leveling_GetEquipped(client, Cosmetic_Killstreaker, killstreakerStr, sizeof(killstreakerStr));

    // Nothing equipped at all
    if (sheenStr[0] == '\0' && killstreakerStr[0] == '\0') return;

    int sheenId = StringToInt(sheenStr);           // 1-7 or 0
    int effectId = StringToInt(killstreakerStr);   // 2002-2008 or 0

    g_HasKillstreak[client] = true;

    for (int slot = 0; slot < 6; slot++)
    {
        int weapon = GetPlayerWeaponSlot(client, slot);
        if (!IsValidEntity(weapon)) continue;

        // Always enable killstreak counter
        TF2Attrib_SetByDefIndex(weapon, 2025, 1.0);

        // Sheen (colored weapon glow)
        if (sheenId >= 1 && sheenId <= 7)
            TF2Attrib_SetByDefIndex(weapon, 2014, float(sheenId));

        // Killstreaker (eye particle effect) — needs 5+ streak to show
        if (effectId >= 2002 && effectId <= 2008)
            TF2Attrib_SetByDefIndex(weapon, 2013, float(effectId));
    }

    // Eye effects only render at 5+ kill streak.
    // Since dodgeball doesn't have normal kill-based streaks,
    // we fake a 10-kill streak so the effect is always visible.
    if (effectId >= 2002 && effectId <= 2008)
        SetEntProp(client, Prop_Send, "m_nStreaks", 10, _, 0);
}

void RemoveEyeEffects(int client)
{
    if (!g_HasKillstreak[client]) return;
    g_HasKillstreak[client] = false;

    if (!g_TF2AttribAvailable) return;
    if (!IsClientInGame(client)) return;

    for (int slot = 0; slot < 6; slot++)
    {
        int weapon = GetPlayerWeaponSlot(client, slot);
        if (!IsValidEntity(weapon)) continue;

        TF2Attrib_RemoveByDefIndex(weapon, 2025);
        TF2Attrib_RemoveByDefIndex(weapon, 2013);
        TF2Attrib_RemoveByDefIndex(weapon, 2014);
    }

    if (IsPlayerAlive(client))
        SetEntProp(client, Prop_Send, "m_nStreaks", 0, _, 0);
}

// ============================================================================
// DEATH EFFECTS (ragdoll flags or particles on death)
// ============================================================================

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    if (victim < 1 || !Leveling_IsDataLoaded(victim)) return Plugin_Continue;

    // Spy Dead Ringer feign death — don't apply death effects or remove cosmetics
    if (event.GetInt("death_flags") & 32) // TF_DEATHFLAG_DEADRINGER
        return Plugin_Continue;

    // Clean up all visual entities on real death so they don't follow
    // the player into spectate mode.
    // Aura and trail use fade-kill (Stop now, Kill after 0.5s) so particles
    // have time to finish their emission cycle without leaving decals.
    FadeKillEntRef(g_TrailEntity[victim]);
    g_TrailEntity[victim] = INVALID_ENT_REFERENCE;
    FadeKillEntRef(g_AuraEntity[victim]);
    g_AuraEntity[victim] = INVALID_ENT_REFERENCE;
    RemoveEyeEffects(victim);
    RemovePet(victim);
    RestoreModel(victim);

    char deathEffect[64];
    Leveling_GetEquipped(victim, Cosmetic_Death, deathEffect, sizeof(deathEffect));
    if (deathEffect[0] == '\0') return Plugin_Continue;

    // Check if it's a ragdoll flag or a particle name
    if (StrEqual(deathEffect, "gold", false))
        ApplyRagdollFlag(victim, "m_bGoldRagdoll");
    else if (StrEqual(deathEffect, "ice", false))
        ApplyRagdollFlag(victim, "m_bIceRagdoll");
    else if (StrEqual(deathEffect, "ash", false))
        ApplyRagdollFlag(victim, "m_bBecomeAsh");
    else if (StrEqual(deathEffect, "electro", false))
        ApplyRagdollFlag(victim, "m_bElectrocuted");
    else
    {
        // It's a custom particle name — spawn at death position
        float pos[3];
        GetClientAbsOrigin(victim, pos);
        SpawnTempParticle(pos, deathEffect, 3.0);
    }

    return Plugin_Continue;
}

void ApplyRagdollFlag(int client, const char[] prop)
{
    // Delay one frame so TF2 has time to create the ragdoll entity
    DataPack dp = new DataPack();
    dp.WriteCell(GetClientUserId(client));
    dp.WriteString(prop);
    RequestFrame(Frame_ApplyRagdollFlag, dp);
}

void Frame_ApplyRagdollFlag(DataPack dp)
{
    dp.Reset();
    int client = GetClientOfUserId(dp.ReadCell());
    char prop[32];
    dp.ReadString(prop, sizeof(prop));
    delete dp;

    if (client == 0 || !IsClientInGame(client)) return;

    int ragdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
    if (ragdoll > 0 && IsValidEntity(ragdoll))
        SetEntProp(ragdoll, Prop_Send, prop, 1);
}

void SpawnTempParticle(float pos[3], const char[] particleName, float duration)
{
    int particle = CreateEntityByName("info_particle_system");
    if (particle == -1) return;

    DispatchKeyValue(particle, "effect_name", particleName);
    DispatchSpawn(particle);
    TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);
    ActivateEntity(particle);
    AcceptEntityInput(particle, "Start");

    CreateTimer(duration, Timer_KillEntity, EntIndexToEntRef(particle), TIMER_FLAG_NO_MAPCHANGE);
}

// ============================================================================
// PET (free-moving prop_dynamic with PreThink AI — SourcePets approach)
// ============================================================================

void CreatePet(int client, const char[] modelPath)
{
    RemovePet(client);

    if (!IsModelPrecached(modelPath))
    {
        LogError("[Leveling] Pet model not precached: %s", modelPath);
        return;
    }

    // Find the pet config entry so we can use its animations/height/scale
    int petIndex = -1;
    for (int i = 0; i < g_PetList.Length; i++)
    {
        CosmeticItem item;
        g_PetList.GetArray(i, item);
        if (StrEqual(item.value, modelPath))
        {
            petIndex = i;
            break;
        }
    }

    int pet = CreateEntityByName("prop_dynamic_override");
    if (!IsValidEntity(pet)) return;

    DispatchKeyValue(pet, "targetname", "leveling_pet");
    SetEntityModel(pet, modelPath);
    DispatchKeyValue(pet, "solid", "0");
    DispatchSpawn(pet);
    ActivateEntity(pet);

    // Position near owner with random offset
    float pos[3];
    GetClientAbsOrigin(client, pos);
    pos[0] += GetRandomFloat(-64.0, 64.0);
    pos[1] += GetRandomFloat(-64.0, 64.0);
    TeleportEntity(pet, pos, NULL_VECTOR, NULL_VECTOR);

    // Apply model scale from config (default 0.5)
    float scale = 0.5;
    if (petIndex >= 0)
    {
        CosmeticItem item;
        g_PetList.GetArray(petIndex, item);
        if (item.modelScale > 0.0)
            scale = item.modelScale;
    }
    SetEntPropFloat(pet, Prop_Send, "m_flModelScale", scale);

    // Start idle animation
    if (petIndex >= 0)
    {
        CosmeticItem item;
        g_PetList.GetArray(petIndex, item);
        if (item.animIdle[0] != '\0')
        {
            SetVariantString(item.animIdle);
            AcceptEntityInput(pet, "SetAnimation");
        }
    }

    g_PetEntity[client] = EntIndexToEntRef(pet);
    g_PetType[client] = petIndex;
    g_PetState[client] = PET_STATE_IDLE;

    // Hook PreThink to drive pet movement every tick
    SDKHook(client, SDKHook_PreThink, Hook_PetThink);
}

void RemovePet(int client)
{
    if (g_PetEntity[client] != INVALID_ENT_REFERENCE)
    {
        int entity = EntRefToEntIndex(g_PetEntity[client]);
        if (entity != -1 && IsValidEntity(entity))
            AcceptEntityInput(entity, "Kill");
    }
    g_PetEntity[client] = INVALID_ENT_REFERENCE;
    g_PetState[client] = PET_STATE_NONE;
    g_PetType[client] = -1;
    SDKUnhook(client, SDKHook_PreThink, Hook_PetThink);
}

void SetPetAnimation(int client, const char[] anim)
{
    int entity = EntRefToEntIndex(g_PetEntity[client]);
    if (entity == -1 || !IsValidEntity(entity)) return;
    SetVariantString(anim);
    AcceptEntityInput(entity, "SetAnimation");
}

void SetPetState(int client, int state)
{
    if (g_PetState[client] == state) return;
    g_PetState[client] = state;

    if (g_PetType[client] < 0) return;

    CosmeticItem item;
    g_PetList.GetArray(g_PetType[client], item);

    switch (state)
    {
        case PET_STATE_IDLE:
        {
            if (item.animIdle[0] != '\0')
                SetPetAnimation(client, item.animIdle);
        }
        case PET_STATE_WALKING:
        {
            if (item.animWalk[0] != '\0')
                SetPetAnimation(client, item.animWalk);
        }
        case PET_STATE_JUMPING:
        {
            if (item.animJump[0] != '\0')
                SetPetAnimation(client, item.animJump);
        }
    }
}

public void Hook_PetThink(int client)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
    {
        RemovePet(client);
        return;
    }

    int petEnt = EntRefToEntIndex(g_PetEntity[client]);
    if (petEnt == -1 || !IsValidEntity(petEnt))
    {
        SDKUnhook(client, SDKHook_PreThink, Hook_PetThink);
        g_PetEntity[client] = INVALID_ENT_REFERENCE;
        g_PetState[client] = PET_STATE_NONE;
        g_PetType[client] = -1;
        return;
    }

    // Hide pet while player is cloaked or disguised
    if (TF2_IsPlayerInCondition(client, TFCond_Cloaked) || TF2_IsPlayerInCondition(client, TFCond_Disguised))
        return;

    float petPos[3], petAng[3], clientPos[3];
    GetEntPropVector(petEnt, Prop_Data, "m_vecOrigin", petPos);
    GetEntPropVector(petEnt, Prop_Data, "m_angRotation", petAng);
    GetClientAbsOrigin(client, clientPos);

    // Target height
    float targetZ = clientPos[2];
    if (g_PetType[client] >= 0)
    {
        CosmeticItem item;
        g_PetList.GetArray(g_PetType[client], item);
        if (item.heightType == 2 && item.heightCustom > 0)
            targetZ = clientPos[2] + float(item.heightCustom);
    }

    float dist = GetVectorDistance(clientPos, petPos);

    // Emergency teleport if too far
    if (dist > 1024.0)
    {
        float newPos[3];
        newPos[0] = clientPos[0] + GetRandomFloat(-64.0, 64.0);
        newPos[1] = clientPos[1] + GetRandomFloat(-64.0, 64.0);
        newPos[2] = targetZ;
        TeleportEntity(petEnt, newPos, NULL_VECTOR, NULL_VECTOR);
        return;
    }

    // Smooth exponential lerp toward owner position.
    // Position-based teleport — proven SourcePets approach.
    float deadzone = 40.0;
    float speed = (dist - deadzone) / 54.0;
    if (speed < -4.0) speed = -4.0;
    if (speed > 4.0) speed = 4.0;
    if (FloatAbs(speed) < 0.3)
        speed *= 0.1;

    if (dist > deadzone)
    {
        if (petPos[0] < clientPos[0]) petPos[0] += speed;
        if (petPos[0] > clientPos[0]) petPos[0] -= speed;
        if (petPos[1] < clientPos[1]) petPos[1] += speed;
        if (petPos[1] > clientPos[1]) petPos[1] -= speed;
    }

    // Z lerp — smooth toward target height
    petPos[2] += (targetZ - petPos[2]) * 0.08;

    // Animation states
    if (!(GetEntityFlags(client) & FL_ONGROUND))
        SetPetState(client, PET_STATE_JUMPING);
    else if (FloatAbs(speed) > 0.2)
        SetPetState(client, PET_STATE_WALKING);
    else
        SetPetState(client, PET_STATE_IDLE);

    // Smooth yaw toward owner
    if (dist > 32.0)
    {
        float distX = clientPos[0] - petPos[0];
        float distY = clientPos[1] - petPos[1];
        float targetYaw = (ArcTangent2(distY, distX) * 180.0) / 3.14159;
        float currentYaw = petAng[1];

        float diff = targetYaw - currentYaw;
        while (diff > 180.0) diff -= 360.0;
        while (diff < -180.0) diff += 360.0;

        petAng[1] = currentYaw + diff * 0.1;
    }

    TeleportEntity(petEnt, petPos, petAng, NULL_VECTOR);
}

// ============================================================================
// SHARED ENTITY HELPER
// ============================================================================

void KillEntRef(int ref)
{
    if (ref == INVALID_ENT_REFERENCE) return;

    int entity = EntRefToEntIndex(ref);
    if (entity != -1 && IsValidEntity(entity))
    {
        AcceptEntityInput(entity, "Stop");
        AcceptEntityInput(entity, "Kill");
    }
}

// Stop the particle immediately (no new emissions) but delay the Kill
// so existing particles have time to fade out instead of leaving decals.
void FadeKillEntRef(int ref)
{
    if (ref == INVALID_ENT_REFERENCE) return;

    int entity = EntRefToEntIndex(ref);
    if (entity != -1 && IsValidEntity(entity))
    {
        AcceptEntityInput(entity, "Stop");
        CreateTimer(0.5, Timer_KillEntity, EntIndexToEntRef(entity), TIMER_FLAG_NO_MAPCHANGE);
    }
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
    IntToString(view_as<int>(Cosmetic_Sheen), info, sizeof(info));
    menu.AddItem(info, "Sheens");
    IntToString(view_as<int>(Cosmetic_Killstreaker), info, sizeof(info));
    menu.AddItem(info, "Killstreakers");
    IntToString(view_as<int>(Cosmetic_Death), info, sizeof(info));
    menu.AddItem(info, "Death Effects");
    IntToString(view_as<int>(Cosmetic_Pet), info, sizeof(info));
    menu.AddItem(info, "Pets");
    IntToString(view_as<int>(Cosmetic_Spawn), info, sizeof(info));
    menu.AddItem(info, "Spawn Particles");
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
            Leveling_SetEquipped(param1, Cosmetic_Sheen, "");
            Leveling_SetEquipped(param1, Cosmetic_Killstreaker, "");
            Leveling_SetEquipped(param1, Cosmetic_Death, "");
            Leveling_SetEquipped(param1, Cosmetic_Pet, "");
            Leveling_SetEquipped(param1, Cosmetic_Spawn, "");
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
        case Cosmetic_Sheen:        strcopy(title, sizeof(title), "Sheens");
        case Cosmetic_Killstreaker: strcopy(title, sizeof(title), "Killstreakers");
        case Cosmetic_Death: strcopy(title, sizeof(title), "Death Effects");
        case Cosmetic_Pet:   strcopy(title, sizeof(title), "Pets");
        case Cosmetic_Spawn: strcopy(title, sizeof(title), "Spawn Particles");
    }

    Menu menu = new Menu(Handler_CosmeticList);
    menu.SetTitle("Select %s", title);

    // Per-type unequip option
    char unequipInfo[16];
    Format(unequipInfo, sizeof(unequipInfo), "%d|", view_as<int>(type));
    menu.AddItem(unequipInfo, "-- Unequip --");

    ArrayList list = null;
    switch (type)
    {
        case Cosmetic_Trail: list = g_TrailList;
        case Cosmetic_Aura:  list = g_AuraList;
        case Cosmetic_Model: list = g_ModelList;
        case Cosmetic_Sheen:        list = g_SheenList;
        case Cosmetic_Killstreaker: list = g_KillstreakerList;
        case Cosmetic_Death: list = g_DeathList;
        case Cosmetic_Pet:   list = g_PetList;
        case Cosmetic_Spawn: list = g_SpawnList;
    }

    // Get currently equipped value for this type to mark it
    char currentEquipped[128];
    Leveling_GetEquipped(client, type, currentEquipped, sizeof(currentEquipped));

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
            bool isEquipped = StrEqual(item.value, currentEquipped);

            if (hasLevel && hasFlag)
            {
                char display[128];
                if (isEquipped)
                    Format(display, sizeof(display), "★ %s", item.name);
                else
                    strcopy(display, sizeof(display), item.name);
                menu.AddItem(info, display);
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

        // Empty value = unequip. Remove the entity and notify.
        if (value[0] == '\0')
        {
            switch (type)
            {
                case Cosmetic_Trail: RemoveTrail(param1);
                case Cosmetic_Aura:  RemoveAura(param1);
                case Cosmetic_Model: RestoreModel(param1);
                case Cosmetic_Sheen:        RemoveEyeEffects(param1);
                case Cosmetic_Killstreaker: RemoveEyeEffects(param1);
                case Cosmetic_Pet:   RemovePet(param1);
            }
            CPrintToChat(param1, "{green}[Leveling]{default} Unequipped.");
            OpenEquipMenu(param1);
            return 0;
        }

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
            case Cosmetic_Sheen:
            {
                RemoveEyeEffects(param1);
                CreateEyeEffects(param1);
                CPrintToChat(param1, "{green}[Leveling]{default} Sheen equipped: {green}%s", display);
            }
            case Cosmetic_Killstreaker:
            {
                RemoveEyeEffects(param1);
                CreateEyeEffects(param1);
                CPrintToChat(param1, "{green}[Leveling]{default} Killstreaker equipped: {green}%s", display);
            }
            case Cosmetic_Death:
            {
                CPrintToChat(param1, "%t", "Death_Equipped", display);
            }
            case Cosmetic_Pet:
            {
                RemovePet(param1);
                CreatePet(param1, value);
                CPrintToChat(param1, "%t", "Pet_Equipped", display);
            }
            case Cosmetic_Spawn:
            {
                // Preview it immediately
                CreateSpawnParticle(param1, value);
                CPrintToChat(param1, "{green}[Leveling]{default} Spawn particle equipped: {green}%s", display);
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
    g_SheenList.Clear();
    g_KillstreakerList.Clear();
    g_DeathList.Clear();
    g_PetList.Clear();
    g_SpawnList.Clear();

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
    ParseSection(kv, "Sheens",        g_SheenList,        "sheen");
    ParseSection(kv, "Killstreakers", g_KillstreakerList, "effect");
    ParseSection(kv, "Deaths", g_DeathList,  "effect");
    ParseSection(kv, "Pets",   g_PetList,    "model");
    ParseSection(kv, "Spawns", g_SpawnList,  "effect");

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

            // Optional Pet parameters (animations, height, scale)
            if (StrEqual(section, "Pets"))
            {
                kv.GetString("anim_idle", item.animIdle, sizeof(item.animIdle), "");
                kv.GetString("anim_walk", item.animWalk, sizeof(item.animWalk), "");
                kv.GetString("anim_jump", item.animJump, sizeof(item.animJump), "");
                item.heightType = kv.GetNum("height_type", 1);
                item.heightCustom = kv.GetNum("height_custom", 0);
                item.modelScale = kv.GetFloat("modelscale", 0.5);
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

    for (int i = 0; i < g_PetList.Length; i++)
    {
        CosmeticItem item;
        g_PetList.GetArray(i, item);
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
    delete g_SheenList;
    delete g_KillstreakerList;
    delete g_DeathList;
    delete g_PetList;
    delete g_SpawnList;
}
