#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <chat-processor>
#include <colorvariables>
#include <leveling>

#define PLUGIN_NAME    "[Leveling] Chat Tags"
#define PLUGIN_VERSION "1.3.1"

#if !defined MAXLENGTH_NAME
#define MAXLENGTH_NAME 128
#endif

public Plugin myinfo =
{
    name        = PLUGIN_NAME,
    author      = "Silorak",
    description = "Level-based chat tags with color support",
    version     = PLUGIN_VERSION,
    url         = "https://github.com/Silorak/TF2-Leveling-System"
};

enum struct LevelTag
{
    int level;
    int flag; // Admin flag required (0 = none, available to all)
    char tag[128];
    char nameColor[32];
}

ArrayList g_TagList;

// Track which tag is currently applied per client (for cleanup)
char g_AppliedTag[MAXPLAYERS + 1][128];

public void OnPluginStart()
{
    g_TagList = new ArrayList(sizeof(LevelTag));
    LoadTranslations("leveling.phrases");

    RegConsoleCmd("sm_tags", Command_Tags, "Select an unlocked chat tag");
    RegConsoleCmd("sm_tag",  Command_Tags, "Select an unlocked chat tag");
}

public void OnMapStart()
{
    LoadChatTags();
}

public void Leveling_OnDataLoaded(int client)
{
    ApplyTag(client);
}

public void Leveling_OnLevelUp(int client, int newLevel)
{
    ApplyTag(client);
}

public void OnClientDisconnect(int client)
{
    g_AppliedTag[client][0] = '\0';
}

// ============================================================================
// TAG APPLICATION — uses Chat Processor's native tag API
// ============================================================================

void ApplyTag(int client)
{
    if (!IsClientInGame(client)) return;

    // 1. Strip any previously applied tag
    if (g_AppliedTag[client][0] != '\0')
    {
        ChatProcessor_RemoveClientTag(client, g_AppliedTag[client]);
        g_AppliedTag[client][0] = '\0';
    }

    // 2. Determine which tag to use
    char tagStr[128];
    char nameColor[32];
    ResolveTag(client, tagStr, sizeof(tagStr), nameColor, sizeof(nameColor));

    if (tagStr[0] == '\0')
        return;

    // 3. Apply via Chat Processor's native API
    // The tag string contains embedded {#RRGGBB} / {color} tags.
    // Chat Processor's internal CP_OnChatMessage handler will render them
    // and CProcessVariables will convert them to raw bytes.
    // Append a space after the tag so it doesn't run into the name.
    char fullTag[128];
    Format(fullTag, sizeof(fullTag), "%s ", tagStr);

    ChatProcessor_AddClientTag(client, fullTag);
    strcopy(g_AppliedTag[client], sizeof(g_AppliedTag[]), fullTag);

    // 4. Set name color if specified
    if (nameColor[0] != '\0')
    {
        ChatProcessor_SetNameColor(client, nameColor);
    }
}

// Determine the tag string and name color for a client
void ResolveTag(int client, char[] tagOut, int tagMaxLen, char[] nameColorOut, int nameColorMaxLen)
{
    tagOut[0] = '\0';
    nameColorOut[0] = '\0';

    if (!IsClientInGame(client)) return;

    // Priority 1: Custom VIP tag (set via !customtag)
    char customTag[32];
    Leveling_GetCustomTag(client, customTag, sizeof(customTag));
    if (customTag[0] != '\0')
    {
        strcopy(tagOut, tagMaxLen, customTag);
        return;
    }

    // Priority 2: Manually equipped tag (set via !tags menu)
    char equippedTag[16];
    Leveling_GetEquipped(client, Cosmetic_Tag, equippedTag, sizeof(equippedTag));
    if (equippedTag[0] != '\0')
    {
        int equippedLevel = StringToInt(equippedTag);
        int playerLevel = Leveling_GetLevel(client);

        // Validate the tag is still unlocked
        if (equippedLevel <= playerLevel)
        {
            for (int i = 0; i < g_TagList.Length; i++)
            {
                LevelTag entry;
                g_TagList.GetArray(i, entry);
                if (entry.level == equippedLevel)
                {
                    bool hasFlag = (entry.flag == 0 || CheckCommandAccess(client, "sm_tag_flag", entry.flag, true));
                    if (hasFlag)
                    {
                        strcopy(tagOut, tagMaxLen, entry.tag);
                        strcopy(nameColorOut, nameColorMaxLen, entry.nameColor);
                        return;
                    }
                }
            }
        }
    }

    // Priority 3: Highest unlocked tag (auto mode)
    int playerLevel = Leveling_GetLevel(client);
    for (int i = g_TagList.Length - 1; i >= 0; i--)
    {
        LevelTag entry;
        g_TagList.GetArray(i, entry);
        if (entry.level <= playerLevel)
        {
            bool hasFlag = (entry.flag == 0 || CheckCommandAccess(client, "sm_tag_flag", entry.flag, true));
            if (hasFlag)
            {
                strcopy(tagOut, tagMaxLen, entry.tag);
                strcopy(nameColorOut, nameColorMaxLen, entry.nameColor);
                return;
            }
        }
    }

    // Fallback: generic level tag
    Format(tagOut, tagMaxLen, "{#00FF00}[Lvl %d]", playerLevel);
}

// ============================================================================
// TAG SELECTION MENU (!tags / !tag)
// ============================================================================

public Action Command_Tags(int client, int args)
{
    if (client == 0) return Plugin_Handled;
    if (!Leveling_IsDataLoaded(client))
    {
        CPrintToChat(client, "%t", "DataNotLoaded");
        return Plugin_Handled;
    }

    int playerLevel = Leveling_GetLevel(client);

    Menu menu = new Menu(Handler_TagMenu);
    menu.SetTitle("Select Chat Tag (Level %d)", playerLevel);

    // "Auto" option — always use highest unlocked tag
    menu.AddItem("auto", "Auto (Highest Unlocked)");

    for (int i = 0; i < g_TagList.Length; i++)
    {
        LevelTag entry;
        g_TagList.GetArray(i, entry);

        char info[16], display[128], stripped[64];
        IntToString(entry.level, info, sizeof(info));
        StripColorTags(entry.tag, stripped, sizeof(stripped));

        bool hasLevel = (entry.level <= playerLevel);
        bool hasFlag  = (entry.flag == 0 || CheckCommandAccess(client, "sm_tag_flag", entry.flag, true));

        if (hasLevel && hasFlag)
        {
            Format(display, sizeof(display), "%s (Lvl %d)", stripped, entry.level);
            menu.AddItem(info, display);
        }
        else
        {
            if (!hasFlag)
                Format(display, sizeof(display), "%s (VIP Only)", stripped);
            else
                Format(display, sizeof(display), "%s (Locked - Lvl %d)", stripped, entry.level);
            menu.AddItem("", display, ITEMDRAW_DISABLED);
        }
    }

    menu.Display(client, MENU_TIME_FOREVER);
    return Plugin_Handled;
}

public int Handler_TagMenu(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        char info[16];
        menu.GetItem(param2, info, sizeof(info));

        if (StrEqual(info, "auto"))
        {
            // Clear equipped tag — ApplyTag will use highest unlocked
            Leveling_SetEquipped(param1, Cosmetic_Tag, "");
            CPrintToChat(param1, "{green}[Leveling]{default} Tag set to auto (highest unlocked).");
        }
        else
        {
            // Store the level number as the equipped tag identifier
            Leveling_SetEquipped(param1, Cosmetic_Tag, info);

            int level = StringToInt(info);
            for (int i = 0; i < g_TagList.Length; i++)
            {
                LevelTag entry;
                g_TagList.GetArray(i, entry);
                if (entry.level == level)
                {
                    char stripped[64];
                    StripColorTags(entry.tag, stripped, sizeof(stripped));
                    CPrintToChat(param1, "{green}[Leveling]{default} Tag equipped: {green}%s", stripped);
                    break;
                }
            }
        }

        // Re-apply the tag via Chat Processor's API
        ApplyTag(param1);
        Leveling_SavePlayer(param1);
    }
    else if (action == MenuAction_End) delete menu;
    return 0;
}

// ============================================================================
// CONFIG
// ============================================================================

void LoadChatTags()
{
    g_TagList.Clear();

    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/leveling/tags.cfg");

    if (!FileExists(path)) return;

    KeyValues kv = new KeyValues("LevelingTags");
    if (!kv.ImportFromFile(path))
    {
        delete kv;
        return;
    }

    if (kv.GotoFirstSubKey(false))
    {
        do
        {
            LevelTag entry;
            char levelStr[16];
            kv.GetSectionName(levelStr, sizeof(levelStr));
            entry.level = StringToInt(levelStr);

            // Check if this is a subsection (has child keys) or a flat key-value
            // Subsection format: "1" { "tag" "..." "name_color" "..." "flag" "a" }
            // Flat format:       "1" "{#00FF00}[Newbie]"
            if (kv.GetDataType(NULL_STRING) != KvData_None)
            {
                // Flat format: value is the tag directly
                kv.GetString(NULL_STRING, entry.tag, sizeof(entry.tag));
                entry.flag = 0;
                entry.nameColor[0] = '\0';
            }
            else
            {
                // Subsection format: read tag, optional name_color, and optional flag
                kv.GetString("tag", entry.tag, sizeof(entry.tag));
                kv.GetString("name_color", entry.nameColor, sizeof(entry.nameColor), "");
                char flagStr[16];
                kv.GetString("flag", flagStr, sizeof(flagStr), "");
                entry.flag = (flagStr[0] != '\0') ? ReadFlagString(flagStr) : 0;
            }

            if (entry.tag[0] != '\0')
                g_TagList.PushArray(entry);
        }
        while (kv.GotoNextKey(false));
    }
    delete kv;

    SortADTArrayCustom(g_TagList, SortTagsByLevel);

    // Re-apply tags for all connected players after config reload
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && Leveling_IsDataLoaded(i))
            ApplyTag(i);
    }
}

public int SortTagsByLevel(int index1, int index2, Handle array, Handle hndl)
{
    ArrayList list = view_as<ArrayList>(array);
    LevelTag a, b;
    list.GetArray(index1, a);
    list.GetArray(index2, b);
    return a.level - b.level;
}

// ============================================================================
// HELPERS
// ============================================================================

// Strip color tags for clean menu display text
// Handles both {#RRGGBB} hex format and named tags like {default}, {red}, {teamcolor}
void StripColorTags(const char[] input, char[] output, int maxlen)
{
    int outIdx = 0;
    int inputLen = strlen(input);

    for (int i = 0; i < inputLen && outIdx < maxlen - 1; i++)
    {
        if (input[i] == '{')
        {
            // Find closing brace
            int closePos = -1;
            for (int j = i + 1; j < inputLen && j < i + 20; j++)
            {
                if (input[j] == '}')
                {
                    closePos = j;
                    break;
                }
            }

            if (closePos != -1)
            {
                // Skip everything between { and } inclusive
                i = closePos;
                continue;
            }
        }
        output[outIdx++] = input[i];
    }
    output[outIdx] = '\0';
}

public void OnPluginEnd()
{
    // Clean up tags for all clients
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && g_AppliedTag[i][0] != '\0')
        {
            ChatProcessor_RemoveClientTag(i, g_AppliedTag[i]);
        }
    }

    delete g_TagList;
}
