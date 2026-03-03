#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <chat-processor>
#include <colorvariables>
#include <leveling>

#define PLUGIN_NAME    "[Leveling] Chat Tags"
#define PLUGIN_VERSION "1.3.0"

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

    RebuildCachedTag(author);

    if (g_CachedTag[author][0] == '\0')
        return Plugin_Continue;

    // Convert {#RRGGBB} to raw \x07RRGGBB byte sequences before injecting
    // into the name buffer.  This bypasses Chat Processor's
    // sm_chatprocessor_strip_colors cvar (which strips {color} tags from
    // non-admins before the forward fires) and avoids relying on
    // CProcessVariables to convert them later.
    //
    // Reference: shavit's bhoptimer (shavit-chat.sp) uses the same raw-byte
    // approach for maximum reliability across engine versions.
    // SourceMod wiki confirms TF2 supports \x07 + 6 hex chars for RGB.
    char convertedTag[128];
    strcopy(convertedTag, sizeof(convertedTag), g_CachedTag[author]);
    ConvertHexColors(convertedTag, sizeof(convertedTag));

    // \x03 = team color.  Prepend tag, then reset to team color for the
    // player name itself so it renders in the correct team color.
    char newName[MAXLENGTH_NAME];
    Format(newName, sizeof(newName), "%s \x03%s", convertedTag, name);
    strcopy(name, MAXLENGTH_NAME, newName);

    // Colors are already raw bytes — tell Chat Processor NOT to run
    // CProcessVariables on our output (it would mangle raw \x07 bytes).
    processcolors = false;
    removecolors  = false;
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

// Convert {#RRGGBB} color tags to raw \x07RRGGBB byte sequences.
// Also converts {default} to \x01 (white) and {teamcolor} to \x03.
//
// TF2 supports \x07 followed by exactly 6 hex characters for arbitrary
// RGB colors in SayText2 messages (confirmed by AlliedModders wiki and
// the SourceMod Scripting FAQ).  Using raw bytes means we don't depend
// on Chat Processor's CProcessVariables running successfully.
void ConvertHexColors(char[] str, int maxlen)
{
    char output[256];
    int outIdx = 0;
    int len = strlen(str);

    for (int i = 0; i < len && outIdx < sizeof(output) - 8; i++)
    {
        // Check for {default}
        if (i + 9 <= len && strncmp(str[i], "{default}", 9, false) == 0)
        {
            output[outIdx++] = '\x01';
            i += 8; // skip past {default} (-1 because loop i++)
            continue;
        }

        // Check for {teamcolor}
        if (i + 11 <= len && strncmp(str[i], "{teamcolor}", 11, false) == 0)
        {
            output[outIdx++] = '\x03';
            i += 10;
            continue;
        }

        // Check for {#RRGGBB} — 10 chars total
        if (i + 10 <= len && str[i] == '{' && str[i+1] == '#' && str[i+9] == '}')
        {
            bool valid = true;
            for (int j = 2; j < 8; j++)
            {
                char c = str[i+j];
                if (!((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f')))
                {
                    valid = false;
                    break;
                }
            }

            if (valid)
            {
                output[outIdx++] = '\x07';
                for (int j = 2; j < 8 && outIdx < sizeof(output) - 1; j++)
                    output[outIdx++] = str[i+j];
                i += 9; // skip past {#RRGGBB}
                continue;
            }
        }

        output[outIdx++] = str[i];
    }
    output[outIdx] = '\0';
    strcopy(str, maxlen, output);
}

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
    delete g_TagList;
}
