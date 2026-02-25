#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <chat-processor>
#include <colorvariables>
#include <leveling>

#define PLUGIN_NAME    "[Leveling] Chat Tags"
#define PLUGIN_VERSION "1.0.0"

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
    char tag[64];
}

ArrayList g_TagList;

// Cached processed tags per client (rebuilt on level up or tag change)
char g_CachedTag[MAXPLAYERS + 1][128];

public void OnPluginStart()
{
    g_TagList = new ArrayList(sizeof(LevelTag));
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

    if (g_CachedTag[author][0] == '\0')
        RebuildCachedTag(author);

    char newName[128];
    Format(newName, sizeof(newName), "%s %s", g_CachedTag[author], name);
    strcopy(name, MAXLENGTH_NAME, newName);

    return Plugin_Changed;
}

// ============================================================================
// TAG LOGIC
// ============================================================================

void RebuildCachedTag(int client)
{
    if (!IsClientInGame(client)) return;

    // Priority 1: Custom VIP tag
    char customTag[32];
    Leveling_GetCustomTag(client, customTag, sizeof(customTag));
    if (customTag[0] != '\0')
    {
        ProcessColors(customTag, g_CachedTag[client], sizeof(g_CachedTag[]));
        return;
    }

    // Priority 2: Equipped specific tag
    char equippedTag[16];
    Leveling_GetEquipped(client, Cosmetic_Tag, equippedTag, sizeof(equippedTag));
    if (equippedTag[0] != '\0')
    {
        int equippedLevel = StringToInt(equippedTag);
        for (int i = 0; i < g_TagList.Length; i++)
        {
            LevelTag entry;
            g_TagList.GetArray(i, entry);
            if (entry.level == equippedLevel)
            {
                ProcessColors(entry.tag, g_CachedTag[client], sizeof(g_CachedTag[]));
                return;
            }
        }
    }

    // Priority 3: Highest unlocked tag
    int playerLevel = Leveling_GetLevel(client);
    for (int i = g_TagList.Length - 1; i >= 0; i--)
    {
        LevelTag entry;
        g_TagList.GetArray(i, entry);
        if (entry.level <= playerLevel)
        {
            ProcessColors(entry.tag, g_CachedTag[client], sizeof(g_CachedTag[]));
            return;
        }
    }

    // Fallback
    char raw[64];
    Format(raw, sizeof(raw), "{#00FF00}[Lvl %d]", playerLevel);
    ProcessColors(raw, g_CachedTag[client], sizeof(g_CachedTag[]));
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
            kv.GetString(NULL_STRING, entry.tag, sizeof(entry.tag));
            g_TagList.PushArray(entry);
        }
        while (kv.GotoNextKey(false));
    }
    delete kv;

    // Sort by level (first field in struct = int level)
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
// COLOR PROCESSING
// ============================================================================

void ProcessColors(const char[] input, char[] output, int maxlen)
{
    int inputLen = strlen(input);
    int outIdx = 0;

    for (int i = 0; i < inputLen && outIdx < maxlen - 1; i++)
    {
        if (input[i] == '{' && i + 8 < inputLen && input[i+1] == '#' && input[i+8] == '}')
        {
            bool valid = true;
            for (int h = 2; h <= 7; h++)
            {
                char c = input[i+h];
                if (!((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f')))
                { valid = false; break; }
            }

            if (valid && outIdx + 7 < maxlen)
            {
                output[outIdx++] = '\x07';
                for (int h = 2; h <= 7; h++)
                    output[outIdx++] = input[i+h];
                i += 8; // skip {#RRGGBB}, loop will i++
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
