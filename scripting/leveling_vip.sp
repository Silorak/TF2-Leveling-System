#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <colorvariables>
#include <leveling>

#define PLUGIN_NAME    "[Leveling] VIP"
#define PLUGIN_VERSION "1.0.0"

#define VIP_WELCOME_MAX 128
#define VIP_TAG_MAX     32
#define VIP_COOLDOWN    60

public Plugin myinfo =
{
    name        = PLUGIN_NAME,
    author      = "Silorak",
    description = "VIP custom welcome messages and tags",
    version     = PLUGIN_VERSION,
    url         = "https://github.com/Silorak/TF2-Leveling-System"
};

int g_iLastWelcomeChange[MAXPLAYERS + 1];
int g_iLastTagChange[MAXPLAYERS + 1];
int g_iRainbowIdx[MAXPLAYERS + 1]; // Cycles through rainbow colors sequentially

public void OnPluginStart()
{
    LoadTranslations("leveling.phrases");

    RegConsoleCmd("sm_welcomemsg", Command_WelcomeMsg, "Set custom VIP welcome message");
    RegConsoleCmd("sm_customtag",  Command_CustomTag,  "Set custom VIP chat tag");
}

public void Leveling_OnDataLoaded(int client)
{
    DisplayCustomWelcome(client);
}

public void OnClientDisconnect(int client)
{
    g_iLastWelcomeChange[client] = 0;
    g_iLastTagChange[client] = 0;
    g_iRainbowIdx[client] = 0;
}

// ============================================================================
// VIP CHECK
// ============================================================================

bool IsVIP(int client)
{
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
        return false;
    return CheckCommandAccess(client, "sm_vip_features", ADMFLAG_RESERVATION, true);
}

// ============================================================================
// WELCOME MESSAGE
// ============================================================================

void DisplayCustomWelcome(int client)
{
    if (!IsVIP(client)) return;

    char welcome[VIP_WELCOME_MAX];
    Leveling_GetCustomWelcome(client, welcome, sizeof(welcome));
    if (welcome[0] == '\0') return;

    // Process rainbow (cycles color per display)
    char processed[VIP_WELCOME_MAX];
    ProcessRainbow(client, welcome, processed, sizeof(processed));

    if (processed[0] != '\0')
        CPrintToChatAll("%s", processed);
}

// ============================================================================
// COMMANDS
// ============================================================================

public Action Command_WelcomeMsg(int client, int args)
{
    if (!IsVIP(client))
    {
        CPrintToChat(client, "%t", "VIP_NoPermission");
        return Plugin_Handled;
    }

    if (!CheckCooldown(client, g_iLastWelcomeChange[client]))
        return Plugin_Handled;

    if (args == 0)
    {
        Leveling_SetCustomWelcome(client, "");
        CPrintToChat(client, "%t", "VIP_WelcomeCleared");
        g_iLastWelcomeChange[client] = GetTime();
        Leveling_SavePlayer(client);
        return Plugin_Handled;
    }

    char message[VIP_WELCOME_MAX];
    GetCmdArgString(message, sizeof(message));
    StripQuotes(message);

    if (!ValidateInput(message, VIP_WELCOME_MAX))
    {
        CPrintToChat(client, "%t", "VIP_InvalidMessage");
        return Plugin_Handled;
    }

    Leveling_SetCustomWelcome(client, message);
    CPrintToChat(client, "%t", "VIP_WelcomeSet");
    g_iLastWelcomeChange[client] = GetTime();
    Leveling_SavePlayer(client);

    return Plugin_Handled;
}

public Action Command_CustomTag(int client, int args)
{
    if (!IsVIP(client))
    {
        CPrintToChat(client, "%t", "VIP_NoPermission");
        return Plugin_Handled;
    }

    if (!CheckCooldown(client, g_iLastTagChange[client]))
        return Plugin_Handled;

    if (args == 0)
    {
        Leveling_SetCustomTag(client, "");
        CPrintToChat(client, "%t", "VIP_TagCleared");
        g_iLastTagChange[client] = GetTime();
        Leveling_SavePlayer(client);
        return Plugin_Handled;
    }

    char tag[VIP_TAG_MAX];
    GetCmdArgString(tag, sizeof(tag));
    StripQuotes(tag);

    if (!ValidateInput(tag, VIP_TAG_MAX))
    {
        CPrintToChat(client, "%t", "VIP_InvalidTag");
        return Plugin_Handled;
    }

    Leveling_SetCustomTag(client, tag);
    CPrintToChat(client, "%t", "VIP_TagSet");
    g_iLastTagChange[client] = GetTime();
    Leveling_SavePlayer(client);

    return Plugin_Handled;
}

// ============================================================================
// VALIDATION
// ============================================================================

bool CheckCooldown(int client, int lastChange)
{
    int remaining = VIP_COOLDOWN - (GetTime() - lastChange);
    if (remaining > 0)
    {
        CPrintToChat(client, "%t", "VIP_Cooldown", remaining);
        return false;
    }
    return true;
}

bool ValidateInput(const char[] input, int maxLen)
{
    int length = strlen(input);
    if (length == 0 || length > maxLen) return false;

    for (int i = 0; i < length; i++)
    {
        char c = input[i];

        // Alphanumeric
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))
            continue;

        // Safe punctuation
        if (c == ' ' || c == '!' || c == '?' || c == '.' || c == ',' ||
            c == '-' || c == '_' || c == ':' || c == '{' || c == '}' ||
            c == '[' || c == ']' || c == '#' || c == '+' || c == '=' ||
            c == '(' || c == ')')
            continue;

        return false;
    }
    return true;
}

// ============================================================================
// RAINBOW
// ============================================================================

static const char g_RainbowColors[][] = {
    "#FF0000", "#FF8C00", "#FFD700", "#00FF00",
    "#00BFFF", "#0000FF", "#FF00FF"
};

void ProcessRainbow(int client, const char[] input, char[] output, int maxlen)
{
    if (StrContains(input, "{RAINBOW}", false) == -1)
    {
        strcopy(output, maxlen, input);
        return;
    }

    // Cycle through rainbow colors sequentially per player
    int idx = g_iRainbowIdx[client] % sizeof(g_RainbowColors);
    g_iRainbowIdx[client] = (idx + 1) % sizeof(g_RainbowColors);

    strcopy(output, maxlen, input);
    ReplaceString(output, maxlen, "{RAINBOW}", g_RainbowColors[idx], false);
}
