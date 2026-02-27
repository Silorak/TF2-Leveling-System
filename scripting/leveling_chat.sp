#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <chat-processor>
#include <colorvariables>
#include <leveling>

#define PLUGIN_NAME    "[Leveling] Chat Tags"
#define PLUGIN_VERSION "1.1.0"

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
    char tag[64];
}

ArrayList g_TagList;

// Cached tag per client — stored in raw {#RRGGBB} format,
// Chat Processor's CProcessVariables handles the color conversion.
char g_CachedTag[MAXPLAYERS + 1][128];

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
    RebuildCachedTag(client);
}

public void Leveling_OnLevelUp(int client, int newLevel)
{
    RebuildCachedTag(client);
}

public void OnClientDisconnect(int client)
{
    g_CachedTag[client][0] = '\0';
}

// ============================================================================
// CHAT PROCESSOR HOOK
// ============================================================================

public Action CP_OnChatMessage(int& author, ArrayList recipients, char[] flagstring, char[] name, char[] message, bool& processcolors, bool& removecolors)
{
    if (author <= 0 || !IsClientInGame(author)) return Plugin_Continue;
    if (!Leveling_IsDataLoaded(author)) return Plugin_Continue;

    // Always rebuild — it's cheap (a few string checks + small array scan)
    // and guarantees VIP tag changes, !tags equips, and level-ups are
    // immediately reflected without needing extra forwards.
    RebuildCachedTag(author);

    // Empty = no tags config loaded
    if (g_CachedTag[author][0] == '\0')
        return Plugin_Continue;

    // Prepend tag to name.
    // We keep {#RRGGBB} format here — Chat Processor's CProcessVariables
    // will convert them to real color bytes when processcolors = true.
    // {default} resets color back to team color for the player name.
    char newName[MAXLENGTH_NAME];
    Format(newName, sizeof(newName), "%s {default}%s", g_CachedTag[author], name);
    strcopy(name, MAXLENGTH_NAME, newName);

    processcolors = true;
    return Plugin_Changed;
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
            // Clear equipped tag — RebuildCachedTag will use highest unlocked
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

        // Invalidate cache — next chat message will rebuild with new selection
        g_CachedTag[param1][0] = '\0';
        Leveling_SavePlayer(param1);
    }
    else if (action == MenuAction_End) delete menu;
    return 0;
}

// ============================================================================
// TAG LOGIC
// ============================================================================

void RebuildCachedTag(int client)
{
    if (!IsClientInGame(client)) return;

    // Priority 1: Custom VIP tag (set via !customtag)
    char customTag[32];
    Leveling_GetCustomTag(client, customTag, sizeof(customTag));
    if (customTag[0] != '\0')
    {
        strcopy(g_CachedTag[client], sizeof(g_CachedTag[]), customTag);
        return;
    }

    // Priority 2: Manually equipped tag (set via !tags menu)
    char equippedTag[16];
    Leveling_GetEquipped(client, Cosmetic_Tag, equippedTag, sizeof(equippedTag));
    if (equippedTag[0] != '\0')
    {
        int equippedLevel = StringToInt(equippedTag);
        int playerLevel = Leveling_GetLevel(client);

        // Validate the tag is still unlocked and player has flag (handles level reset)
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
                        strcopy(g_CachedTag[client], sizeof(g_CachedTag[]), entry.tag);
                        return;
                    }
                }
            }
        }
    }

    // Priority 3: Highest unlocked tag (auto mode) — must meet level AND flag
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
                strcopy(g_CachedTag[client], sizeof(g_CachedTag[]), entry.tag);
                return;
            }
        }
    }

    // Fallback: generic level tag
    Format(g_CachedTag[client], sizeof(g_CachedTag[]), "{#00FF00}[Lvl %d]", playerLevel);
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
            // Subsection format: "1" { "tag" "..." "flag" "a" }
            // Flat format:       "1" "{#00FF00}[Newbie]"
            if (kv.GetDataType(NULL_STRING) != KvData_None)
            {
                // Flat format: value is the tag directly
                kv.GetString(NULL_STRING, entry.tag, sizeof(entry.tag));
                entry.flag = 0;
            }
            else
            {
                // Subsection format: read tag and optional flag
                kv.GetString("tag", entry.tag, sizeof(entry.tag));
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

// Strip {#RRGGBB} color tags for clean menu display text
void StripColorTags(const char[] input, char[] output, int maxlen)
{
    int outIdx = 0;
    int inputLen = strlen(input);

    for (int i = 0; i < inputLen && outIdx < maxlen - 1; i++)
    {
        if (input[i] == '{' && i + 8 < inputLen && input[i+1] == '#' && input[i+8] == '}')
        {
            i += 8;
            continue;
        }
        output[outIdx++] = input[i];
    }
    output[outIdx] = '\0';
}

public void OnPluginEnd()
{
    delete g_TagList;
}
