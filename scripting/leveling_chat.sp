#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <chat-processor>
#include <colorvariables>
#include <leveling>

#define PLUGIN_NAME    "[Leveling] Chat Tags"
#define PLUGIN_VERSION "1.5.0"

// chat-processor.inc defines MAXLENGTH_NAME as 128 and MAXLENGTH_BUFFER as 255.
// Tags with multiple {#RRGGBB} codes (9 bytes each) can get large fast.
// We use a generous tag buffer internally and let Chat Processor truncate
// to MAXLENGTH_NAME when it copies the name buffer back.
#define TAG_MAX_LENGTH 192

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
    int adminFlag;
    char tag[TAG_MAX_LENGTH];
    char nameColor[32];
}

ArrayList g_TagList;

// Per-client cached tag and name color (resolved from config + equipped selection)
char g_CachedTag[MAXPLAYERS + 1][TAG_MAX_LENGTH];
char g_CachedNameColor[MAXPLAYERS + 1][32];

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

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

public void OnClientDisconnect(int client)
{
    g_CachedTag[client][0] = '\0';
    g_CachedNameColor[client][0] = '\0';
}

public void OnPluginEnd()
{
    delete g_TagList;
}

// ---------------------------------------------------------------------------
// Leveling forwards
// ---------------------------------------------------------------------------

public void Leveling_OnDataLoaded(int client)
{
    RebuildCachedTag(client);
}

public void Leveling_OnLevelUp(int client, int newLevel)
{
    RebuildCachedTag(client);
}

// ---------------------------------------------------------------------------
// Chat Processor forward
// ---------------------------------------------------------------------------

public Action CP_OnChatMessage(int& author, ArrayList recipients,
    char[] flagstring, char[] name, char[] message,
    bool& processcolors, bool& removecolors)
{
    if (author <= 0 || author > MaxClients || !IsClientInGame(author))
        return Plugin_Continue;

    // Don't apply tags to bots
    if (IsFakeClient(author))
        return Plugin_Continue;

    // Lazy-rebuild on first message if cache is empty
    if (g_CachedTag[author][0] == '\0')
        RebuildCachedTag(author);

    if (g_CachedTag[author][0] == '\0')
        return Plugin_Continue;

    // Pick name color — fall back to team color if none configured
    char colorPrefix[32];
    if (g_CachedNameColor[author][0] != '\0')
        strcopy(colorPrefix, sizeof(colorPrefix), g_CachedNameColor[author]);
    else
        strcopy(colorPrefix, sizeof(colorPrefix), "{teamcolor}");

    // Build: "{tag} {nameColor}{playerName}"
    // Use MAXLENGTH_NAME (128) because that is the buffer Chat Processor gives us.
    Format(name, MAXLENGTH_NAME, "%s %s%s", g_CachedTag[author], colorPrefix, name);

    // Let CProcessVariables convert {#RRGGBB} / {color} tags to raw bytes
    processcolors = true;
    removecolors  = false;
    return Plugin_Changed;
}

// ---------------------------------------------------------------------------
// Tag resolution
// ---------------------------------------------------------------------------

void RebuildCachedTag(int client)
{
    g_CachedTag[client][0] = '\0';
    g_CachedNameColor[client][0] = '\0';

    if (!IsClientInGame(client))
        return;

    // Priority 1: Manually equipped tag from !tags menu (explicit choice overrides everything)
    char equipped[16];
    Leveling_GetEquipped(client, Cosmetic_Tag, equipped, sizeof(equipped));

    if (equipped[0] != '\0')
    {
        int equippedLevel = StringToInt(equipped);
        int level         = Leveling_GetLevel(client);

        if (equippedLevel <= level)
        {
            LevelTag entry;
            for (int i = 0; i < g_TagList.Length; i++)
            {
                g_TagList.GetArray(i, entry);

                if (entry.level != equippedLevel)
                    continue;

                if (entry.adminFlag != 0
                    && !CheckCommandAccess(client, "sm_tag_flag", entry.adminFlag, true))
                    continue;

                strcopy(g_CachedTag[client], TAG_MAX_LENGTH, entry.tag);
                strcopy(g_CachedNameColor[client], sizeof(g_CachedNameColor[]), entry.nameColor);
                return;
            }
        }
    }

    // Priority 2: VIP custom tag (!customtag) — used when no explicit !tags selection
    char customTag[32];
    Leveling_GetCustomTag(client, customTag, sizeof(customTag));

    if (customTag[0] != '\0')
    {
        strcopy(g_CachedTag[client], TAG_MAX_LENGTH, customTag);
        return;
    }

    // Priority 3: Auto — highest unlocked tag
    int level = Leveling_GetLevel(client);
    LevelTag entry;

    for (int i = g_TagList.Length - 1; i >= 0; i--)
    {
        g_TagList.GetArray(i, entry);

        if (entry.level > level)
            continue;

        if (entry.adminFlag != 0
            && !CheckCommandAccess(client, "sm_tag_flag", entry.adminFlag, true))
            continue;

        strcopy(g_CachedTag[client], TAG_MAX_LENGTH, entry.tag);
        strcopy(g_CachedNameColor[client], sizeof(g_CachedNameColor[]), entry.nameColor);
        return;
    }

    // Fallback: generic "[Lvl N]" tag in green
    Format(g_CachedTag[client], TAG_MAX_LENGTH, "{green}[Lvl %d]", level);
}

// ---------------------------------------------------------------------------
// !tags / !tag command
// ---------------------------------------------------------------------------

public Action Command_Tags(int client, int args)
{
    if (client == 0)
        return Plugin_Handled;

    if (!Leveling_IsDataLoaded(client))
    {
        CPrintToChat(client, "%t", "DataNotLoaded");
        return Plugin_Handled;
    }

    int level = Leveling_GetLevel(client);

    Menu menu = new Menu(TagMenuHandler);
    menu.SetTitle("Select Chat Tag (Level %d)", level);

    // Show VIP custom tag option if player has one set
    char customTag[32];
    Leveling_GetCustomTag(client, customTag, sizeof(customTag));
    if (customTag[0] != '\0')
    {
        char stripped[64];
        StripColorTags(customTag, stripped, sizeof(stripped));
        char display[128];
        Format(display, sizeof(display), "★ VIP: %s", stripped);
        menu.AddItem("custom", display);
    }

    menu.AddItem("auto", "Auto (Highest Unlocked)");

    LevelTag entry;
    for (int i = 0; i < g_TagList.Length; i++)
    {
        g_TagList.GetArray(i, entry);

        char info[16];
        char display[128];
        char stripped[64];

        IntToString(entry.level, info, sizeof(info));
        StripColorTags(entry.tag, stripped, sizeof(stripped));

        bool unlocked = (entry.level <= level);
        bool hasFlag  = (entry.adminFlag == 0
                         || CheckCommandAccess(client, "sm_tag_flag", entry.adminFlag, true));

        if (unlocked && hasFlag)
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

public int TagMenuHandler(Menu menu, MenuAction action, int client, int slot)
{
    if (action == MenuAction_Select)
    {
        char info[16];
        menu.GetItem(slot, info, sizeof(info));

        if (StrEqual(info, "custom"))
        {
            // Clear equipped tag so RebuildCachedTag uses Priority 1 (custom tag)
            Leveling_SetEquipped(client, Cosmetic_Tag, "");
            CPrintToChat(client, "%t", "Tag_CustomActive");
        }
        else if (StrEqual(info, "auto"))
        {
            Leveling_SetEquipped(client, Cosmetic_Tag, "");
            CPrintToChat(client, "%t", "Tag_AutoSet");
        }
        else
        {
            Leveling_SetEquipped(client, Cosmetic_Tag, info);

            int tagLevel = StringToInt(info);
            LevelTag entry;

            for (int i = 0; i < g_TagList.Length; i++)
            {
                g_TagList.GetArray(i, entry);
                if (entry.level == tagLevel)
                {
                    char stripped[64];
                    StripColorTags(entry.tag, stripped, sizeof(stripped));
                    CPrintToChat(client, "%t", "Tag_Equipped", stripped);
                    break;
                }
            }
        }

        // Invalidate cache and rebuild
        g_CachedTag[client][0] = '\0';
        g_CachedNameColor[client][0] = '\0';
        RebuildCachedTag(client);
        Leveling_SavePlayer(client);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    return 0;
}

// ---------------------------------------------------------------------------
// Config loader
// ---------------------------------------------------------------------------

void LoadChatTags()
{
    g_TagList.Clear();

    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/leveling/tags.cfg");

    if (!FileExists(path))
        return;

    KeyValues kv = new KeyValues("LevelingTags");
    if (!kv.ImportFromFile(path))
    {
        delete kv;
        return;
    }

    if (!kv.GotoFirstSubKey(false))
    {
        delete kv;
        return;
    }

    do
    {
        LevelTag entry;
        char levelStr[16];
        kv.GetSectionName(levelStr, sizeof(levelStr));
        entry.level = StringToInt(levelStr);

        if (kv.GetDataType(NULL_STRING) != KvData_None)
        {
            // Simple format: "level" "{color}[Tag]"
            kv.GetString(NULL_STRING, entry.tag, sizeof(entry.tag));
            entry.adminFlag = 0;
            entry.nameColor[0] = '\0';
        }
        else
        {
            // Extended format: "level" { "tag" "..." "name_color" "..." "flag" "a" }
            kv.GetString("tag", entry.tag, sizeof(entry.tag));
            kv.GetString("name_color", entry.nameColor, sizeof(entry.nameColor), "");

            char flagStr[16];
            kv.GetString("flag", flagStr, sizeof(flagStr), "");
            entry.adminFlag = (flagStr[0] != '\0') ? ReadFlagString(flagStr) : 0;
        }

        if (entry.tag[0] != '\0')
            g_TagList.PushArray(entry);
    }
    while (kv.GotoNextKey(false));

    delete kv;

    SortADTArrayCustom(g_TagList, SortTagsByLevel);

    // Rebuild cache for all connected players after config reload
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && Leveling_IsDataLoaded(i))
            RebuildCachedTag(i);
    }
}

public int SortTagsByLevel(int index1, int index2, Handle array, Handle hndl)
{
    ArrayList list = view_as<ArrayList>(array);
    LevelTag a;
    LevelTag b;
    list.GetArray(index1, a);
    list.GetArray(index2, b);
    return a.level - b.level;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Strips {color} and {#RRGGBB} tags for clean menu display.
 * Scans for '{' → '}' pairs up to 20 chars apart and skips them.
 */
void StripColorTags(const char[] input, char[] output, int maxlen)
{
    int out = 0;
    int len = strlen(input);

    for (int i = 0; i < len && out < maxlen - 1; i++)
    {
        if (input[i] == '{')
        {
            // Look for closing brace within a reasonable range
            int close = -1;
            for (int j = i + 1; j < len && j < i + 20; j++)
            {
                if (input[j] == '}')
                {
                    close = j;
                    break;
                }
            }

            if (close != -1)
            {
                i = close; // skip entire {…} block
                continue;
            }
        }

        output[out++] = input[i];
    }

    output[out] = '\0';
}
