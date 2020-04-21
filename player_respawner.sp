#pragma semicolon 1

/* ---------------------------------
            Includes
------------------------------------ */
#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>


/* ---------------------------------
            Definitions
------------------------------------ */
#define PLUGIN_VERSION "1.1.0-dev"

#define DEF_SPAWN_LIMIT 5
#define DEF_IMMUNE_TIME 3.0

#define TEAM_T 2
#define TEAM_CT 3


/* ---------------------------------
            Globals
------------------------------------ */
new bool:g_mapHasRespawns = false;
new Float:g_immuneTime;
new g_spawnLimit;

new g_player_respawns[MAXPLAYERS+1];
new bool:g_immune[MAXPLAYERS+1] = {false, ...};

//Think timers
//new Handle:g_hThink = INVALID_HANDLE;


/* ---------------------------------
            ConVars
------------------------------------ */


/* ---------------------------------
            Plugin Info
------------------------------------ */
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
    CreateConVar("sm_spawn_version", PLUGIN_VERSION, "Player respawner version", FCVAR_PLUGIN|FCVAR_REPLICATED);
    
    RegConsoleCmd("sm_spawn", Command_Spawn);
    
    HookEvent("round_end",   OnRoundEnd);
    HookEvent("round_start", OnRoundStart);
    
    AddCommandListener(Command_Say, "say");
    AddCommandListener(Command_Say, "say2");
    AddCommandListener(Command_Say, "say_team");
    
    for (new i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i)) {
            SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
        }
    }
}

public OnClientPutInServer(client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action:OnRoundStart(Handle:event, String:name[], bool:dontBroadcast)
{
    if(g_mapHasRespawns) {
        if(g_spawnLimit < 1) {
            PrintToChatAll("There is no spawn limit for this map!");
        } else {
            PrintToChatAll("You have %d respawns for this map", g_spawnLimit);
        }
        
        PrintToChatAll("Type !spawn to respawn");
    }
}

public OnMapStart()
{
    new String:map[128];
    new String:path[PLATFORM_MAX_PATH];
    
    //Set some defaults
    g_immuneTime = DEF_IMMUNE_TIME;
    
    new Handle:kv = CreateKeyValues("MapList");
    
    BuildPath(Path_SM, path, sizeof(path), "configs/respawn_maplist.txt"); 
    FileToKeyValues(kv, path);
    
    GetCurrentMap(map, sizeof(map));
    
    if (!KvJumpToKey(kv, map)) {
        g_mapHasRespawns = false;
        
        CloseHandle(kv);
        return;
    }
    
    g_mapHasRespawns = true;
    
    if(KvGetNum(kv, "spawnlimit") >= 0) {
        g_spawnLimit = KvGetNum(kv, "spawnlimit", DEF_SPAWN_LIMIT);
    } else {
        PrintToServer("Spawn Limit cannot be negative");
    }
    
    if(KvGetFloat(kv, "immunetime") >= 0) {
        g_immuneTime = KvGetFloat(kv, "immunetime", DEF_IMMUNE_TIME);
    } else {
        PrintToServer("Immune Time cannot be negative");
    }
    
    CloseHandle(kv);
    return;
}

public Action:OnRoundEnd(Handle:event, String:name[], bool:dontBroadcast)
{
    resetSpawns();
}

public OnMapEnd()
{
    resetSpawns();
}

public Action:OnTakeDamage(client, &attacker, &inflictor, &Float:damage, &damagetype)
{
    if(g_immune[client]) {
        return Plugin_Handled;
    }
    
    return Plugin_Continue;
}

public Action:Command_Spawn(client, argc)
{
    //Respawn self
    if(argc == 0) {
        respawnSelf(client);
        return Plugin_Handled;
    }
    
    if(!isAdmin(client)) {
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
        //ReplyToTargetError(client, target_count);
        return Plugin_Handled;
    }
    
    new new_target_count;
    
    //Loop through all our targets and do some validation on them
    for (new i = 0; i < target_count; i++)
    {
        new new_target = target_list[i];
        
        //Make sure we can respawn these targets
        if(isValidClient(new_target) && canSpawn(new_target))
        {
            target_list[new_target_count] = new_target;
            new_target_count++;
        }
    }
    
    //We have no valid players to respawn
    if(new_target_count == COMMAND_TARGET_NONE)
    {
        PrintToChat(client, "Target must be dead");
        //ReplyToTargetError(client, new_target_count);
        return Plugin_Handled;
    }

    // re-set new value.
    target_count = new_target_count;

    //Log
    // if (tn_is_ml)
        // ShowActivity2(client, "[SM] ", "%t", "Respawned target", target_name);
    // else
        // ShowActivity2(client, "[SM] ", "%t", "Respawned target", "_s", target_name);

    //Finally, respawn targets
    for (new j = 0; j < target_count; j++)
    {
        new target = target_list[j];
        
        decl String:nick[64]; 
        GetClientName(client, nick, sizeof(nick));
        
        PrintToChatAll("[SM] %s respawned %s", nick, target_name);
        //LogAction(client, target, "\"%L\" respawned \"%L\"", client, target);
        respawnPlayer(target);
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
 
    if(text[strlen(text)-1] == '"') {
        text[strlen(text)-1] = '\0';
        startidx = 1;
    }
 
    if(strcmp(command, "say2", false) == 0)
        startidx += 4;
    
    //Block the client's messsage from broadcasting
    if(strcmp(text[startidx], "!spawn", false) == 0) {
        
        return Plugin_Handled;
    }
 
    //Let say continue normally
    return Plugin_Continue;
}

public respawnPlayer(client)
{
    CS_RespawnPlayer(client);
    
    g_immune[client] = true;
    CreateTimer(g_immuneTime, Timer_Immune, client); 
    
    PrintToChat(client, "(%d/%d) You have been respawned with %-.1f seconds immunity", g_player_respawns[client], g_spawnLimit, g_immuneTime);
}

public respawnSelf(client)
{
    new timeleft;
    
    //Does this map have respawns?
    if(!g_mapHasRespawns) {
        PrintToChat(client, "You cannot respawn on this map");
        return false;
    }
    
    //Do we have a valid client?
    if(!isValidClient(client)) {
        return false;
    }
    
    //Can we spawn the client?
    if(!canSpawn(client)) {
        PrintToChat(client, "You cannot respawn yourself at this time");
        return false;
    }
    
    GetMapTimeLeft(timeleft);
    if(timeleft <= 0) {
        PrintToChat(client, "Round is over, you cannot respawn");
        return false;
    }
    
    //Does the play have any respawns left?
    if(g_player_respawns[client] >= g_spawnLimit && g_spawnLimit > 0) {
        PrintToChat(client, "You have reached your spawn limit (%d)", g_player_respawns[client]);
        return false;
    }
    
    //We can respawn the player!
    g_player_respawns[client]++;
    
    respawnPlayer(client);
    
    return true;
}

public resetSpawns()
{
    for(new i; i < sizeof(g_player_respawns); i++) {
        g_player_respawns[i] = 0;
    }
}  

public canSpawn(client)
{
    new team = GetClientTeam(client);
    return !IsPlayerAlive(client) && (team == TEAM_T || team == TEAM_CT);
}

public isValidClient(client)
{
    return client > 0 && IsClientConnected(client) && IsClientInGame(client);
}

public isAdmin(client)
{
    return CheckCommandAccess(client, "allow_respawn", ADMFLAG_SLAY);
}