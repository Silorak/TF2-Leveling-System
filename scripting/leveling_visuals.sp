#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <leveling>

#define PLUGIN_NAME    "[Leveling] Visuals"
#define PLUGIN_VERSION "1.2.0"

#define FFADE_IN 0x0001

public Plugin myinfo =
{
    name        = PLUGIN_NAME,
    author      = "Silorak",
    description = "HUD bar, floating XP, level-up effects",
    version     = PLUGIN_VERSION,
    url         = "https://github.com/Silorak/TF2-Leveling-System"
};

Handle g_HudSync;
bool   g_bHudEnabled[MAXPLAYERS + 1]; // Per-player XP HUD toggle (default: on)

public void OnPluginStart()
{
    g_HudSync = CreateHudSynchronizer();

    RegConsoleCmd("sm_xphud", Cmd_ToggleHud, "Toggle the XP bar HUD on/off");
}

public void OnClientConnected(int client)
{
    g_bHudEnabled[client] = true;
}

public Action Cmd_ToggleHud(int client, int args)
{
    if (client == 0) return Plugin_Handled;

    g_bHudEnabled[client] = !g_bHudEnabled[client];

    if (g_bHudEnabled[client])
        PrintToChat(client, "\x04[Leveling]\x01 XP bar \x04enabled\x01.");
    else
    {
        PrintToChat(client, "\x04[Leveling]\x01 XP bar \x02disabled\x01.");
        ClearSyncHud(client, g_HudSync); // Immediately wipe it from screen
    }

    return Plugin_Handled;
}

public void Leveling_OnXPGain(int client, int amount, int totalXP)
{
    PrintHintText(client, "+%d XP", amount);
    ShowXPBar(client);
}

public void Leveling_OnLevelUp(int client, int newLevel)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client)) return;

    // Confetti particle
    float pos[3];
    GetClientAbsOrigin(client, pos);

    int particle = CreateEntityByName("info_particle_system");
    if (particle != -1)
    {
        DispatchKeyValue(particle, "effect_name", "achieved");
        DispatchSpawn(particle);
        TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);
        ActivateEntity(particle);
        AcceptEntityInput(particle, "Start");
        CreateTimer(3.0, Timer_KillEntity, EntIndexToEntRef(particle), TIMER_FLAG_NO_MAPCHANGE);
    }

    // Screen shake
    Handle msg = StartMessageOne("Shake", client);
    if (msg != null)
    {
        BfWriteByte(msg, 0);
        BfWriteFloat(msg, 10.0);
        BfWriteFloat(msg, 200.0);
        BfWriteFloat(msg, 1.0);
        EndMessage();
    }

    // Gold screen flash
    Handle fade = StartMessageOne("Fade", client);
    if (fade != null)
    {
        BfWriteShort(fade, 500);
        BfWriteShort(fade, 100);
        BfWriteShort(fade, FFADE_IN);
        BfWriteByte(fade, 255);
        BfWriteByte(fade, 215);
        BfWriteByte(fade, 0);
        BfWriteByte(fade, 100);
        EndMessage();
    }

    ShowXPBar(client);
}

void ShowXPBar(int client)
{
    if (!IsClientInGame(client))          return;
    if (!g_bHudEnabled[client])           return;

    int level = Leveling_GetLevel(client);
    if (level >= LEVELING_MAX_LEVEL)      return;
    if (GetClientTeam(client) <= 1)       return;

    int xp     = Leveling_GetXP(client);
    int needed = Leveling_GetXPForLevel(level);
    if (needed <= 0) needed = 1;

    float percent = float(xp) / float(needed);
    if (percent > 1.0) percent = 1.0;

    char bar[128]; // Each █/░ is 3 UTF-8 bytes; 20 blocks × 3 = 60 bytes minimum
    int fill  = RoundToFloor(percent * 20.0);
    int empty = 20 - fill;

    bar[0] = '\0';
    for (int i = 0; i < fill; i++)  StrCat(bar, sizeof(bar), "█");
    for (int i = 0; i < empty; i++) StrCat(bar, sizeof(bar), "░");

    // Positioned just below the TFDB speed HUD (y=0.85, centered at x=-1.0)
    // Match TFDB's style: centered, green tint, short hold duration
    SetHudTextParams(-1.0, 0.91, 3.0, 100, 255, 100, 220, 0, 0.0, 0.0, 0.15);
    ShowSyncHudText(client, g_HudSync, "LVL %d [ %s ] %d / %d XP", level, bar, xp, needed);
}

public Action Timer_KillEntity(Handle timer, int ref)
{
    int entity = EntRefToEntIndex(ref);
    if (entity != INVALID_ENT_REFERENCE && IsValidEntity(entity))
        AcceptEntityInput(entity, "Kill");
    return Plugin_Stop;
}

public void OnPluginEnd()
{
    delete g_HudSync;
}
