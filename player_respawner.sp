#pragma semicolon 1

// Includes
#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>


// Definitions
#define PLUGIN_VERSION "1.1.0-dev"

#define TEAM_T 2
#define TEAM_CT 3


// Globals
ConVar g_cvar_enabled;
ConVar g_cvar_limit;
ConVar g_cvar_immuneTime;

new g_player_respawns[MAXPLAYERS+1];
new bool:g_immune[MAXPLAYERS+1] = {false, ...};
new String:g_game[40];


// Plugin Info
public Plugin:myinfo =
{
    name = "Player Respawner",
    author = "MrSmoke",
    description = "Let players respawn only on valid maps using sm_spawn",
    version = PLUGIN_VERSION,
    url = "http://nizzlebix.com"
}

public OnPluginStart()
{
    GetGameFolderName(g_game, sizeof(g_game));
    
    if(!(StrEqual(g_game, "cstrike") || StrEqual(g_game, "csgo")))
    {
        LogError("Game %s not supported", g_game);
        return;
    }

    CreateConVar("sm_spawn_version", PLUGIN_VERSION, "Player respawner version", FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);

    g_cvar_enabled = CreateConVar("sm_spawn_enabled", "1", "Enables or disables respawning", FCVAR_REPLICATED|FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvar_limit = CreateConVar("sm_spawn_limit", "0", "Number of respawn allowed. 0 = infinate", FCVAR_REPLICATED|FCVAR_NOTIFY, true, 0.0);
    g_cvar_immuneTime = CreateConVar("sm_spawn_immunetime", "3.0", "Time (in seconds) the player is immune for after spawning", FCVAR_REPLICATED|FCVAR_NOTIFY, true, 0.0);

    RegConsoleCmd("sm_spawn", Command_Spawn);

    HookEvent("round_end",   OnRoundEnd);
    HookEvent("round_start", OnRoundStart);

    AddCommandListener(Command_Say, "say");
    AddCommandListener(Command_Say, "say2");
    AddCommandListener(Command_Say, "say_team");

    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
            SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
    }
}

public OnClientPutInServer(client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action:OnRoundStart(Handle:event, String:name[], bool:dontBroadcast)
{
    if(g_cvar_enabled.BoolValue)
    {
        if(g_cvar_limit.IntValue < 1)
        {
            PrintToChatAll("There is no spawn limit for this map!");
        }
        else
        {
            PrintToChatAll("You have %d respawns for this map", g_cvar_limit.IntValue);
        }

        PrintToChatAll("Type !spawn to respawn");
    }
}

public Action:OnRoundEnd(Handle:event, String:name[], bool:dontBroadcast)
{
    ResetSpawns();
}

public OnMapEnd()
{
    ResetSpawns();
}

public Action:OnTakeDamage(client, &attacker, &inflictor, &Float:damage, &damagetype)
{
    if(g_immune[client])
        return Plugin_Handled;

    return Plugin_Continue;
}

public Action:Command_Spawn(client, argc)
{
    //Respawn self
    if(argc == 0)
    {
        RespawnSelf(client);

        return Plugin_Handled;
    }

    if(!IsAdmin(client))
    {
        PrintToChat(client, "You are not allowed to respawn this player");

        return Plugin_Handled;
    }

    //Respawn a target
    new String:arg[65];
    GetCmdArg(1, arg, sizeof(arg));

    new String:target_name[MAX_TARGET_LENGTH];
    new target_list[MaxClients], target_count, bool:tn_is_ml;

    //Get dead targets
    target_count = ProcessTargetString(
                    arg,
                    client,
                    target_list,
                    MaxClients,
                    COMMAND_FILTER_DEAD,
                    target_name,
                    sizeof(target_name),
                    tn_is_ml);

    // If we don't have dead players
    if(target_count <= COMMAND_TARGET_NONE)
    {
        PrintToChat(client, "Target must be dead");

        return Plugin_Handled;
    }

    new new_target_count;

    //Loop through all our targets and do some validation on them
    for (new i = 0; i < target_count; i++)
    {
        new new_target = target_list[i];

        //Make sure we can respawn these targets
        if(IsValidClient(new_target) && CanSpawn(new_target))
        {
            target_list[new_target_count] = new_target;
            new_target_count++;
        }
    }

    //We have no valid players to respawn
    if(new_target_count == COMMAND_TARGET_NONE)
    {
        PrintToChat(client, "Target must be dead");

        return Plugin_Handled;
    }

    // re-set new value.
    target_count = new_target_count;

    //Finally, respawn targets
    for (new j = 0; j < target_count; j++)
    {
        new target = target_list[j];

        decl String:nick[64];
        GetClientName(client, nick, sizeof(nick));

        PrintToChatAll("[SM] %s respawned %s", nick, target_name);

        RespawnPlayer(target);
    }

    return Plugin_Handled;
}

public Action:Timer_Immune(Handle:timer, any:client)
{
    g_immune[client] = false;
}

public Action:Command_Say(client, const String:command[], args)
{
    new String:text[192];
    new startidx = 0;

    if (0 < client <= MaxClients && !IsClientInGame(client))
        return Plugin_Continue;

    if(!GetCmdArgString(text, sizeof(text)))
        return Plugin_Continue;

    if(text[strlen(text)-1] == '"')
    {
        text[strlen(text)-1] = '\0';
        startidx = 1;
    }

    if(strcmp(command, "say2", false) == 0)
        startidx += 4;

    //Block the client's messsage from broadcasting
    if(strcmp(text[startidx], "!spawn", false) == 0)
        return Plugin_Handled;

    //Let say continue normally
    return Plugin_Continue;
}

public RespawnPlayer(target)
{
    if(StrEqual(g_game, "cstrike") || StrEqual(g_game, "csgo"))
    {
        CS_RespawnPlayer(target);
    }

    g_immune[target] = true;
    CreateTimer(g_cvar_immuneTime.FloatValue, Timer_Immune, target);

    PrintToChat(
        target, 
        "(%d/%d) You have been respawned with %-.1f seconds immunity", 
        g_player_respawns[target], 
        g_cvar_limit.IntValue, 
        g_cvar_immuneTime.FloatValue);
}

public RespawnSelf(client)
{
    new timeleft;

    //Does this map have respawns?
    if(!g_cvar_enabled.BoolValue)
    {
        PrintToChat(client, "You cannot respawn on this map");

        return false;
    }

    //Do we have a valid client?
    if(!IsValidClient(client))
    {
        return false;
    }

    //Can we spawn the client?
    if(!CanSpawn(client))
    {
        PrintToChat(client, "You cannot respawn yourself at this time");

        return false;
    }

    GetMapTimeLeft(timeleft);

    if(timeleft <= 0)
    {
        PrintToChat(client, "Round is over, you cannot respawn");

        return false;
    }

    //Does the play have any respawns left?
    if(g_player_respawns[client] >= g_cvar_limit.IntValue && g_cvar_limit.IntValue > 0)
    {
        PrintToChat(client, "You have reached your spawn limit (%d)", g_player_respawns[client]);

        return false;
    }

    //We can respawn the player!
    g_player_respawns[client]++;

    RespawnPlayer(client);

    return true;
}

public ResetSpawns()
{
    for(new i; i < sizeof(g_player_respawns); i++)
    {
        g_player_respawns[i] = 0;
    }
}

public CanSpawn(client)
{
    new team = GetClientTeam(client);

    return !IsPlayerAlive(client) && (team == TEAM_T || team == TEAM_CT);
}

public IsValidClient(client)
{
    return client > 0 && IsClientConnected(client) && IsClientInGame(client);
}

public IsAdmin(client)
{
    return CheckCommandAccess(client, "allow_respawn", ADMFLAG_SLAY);
}
