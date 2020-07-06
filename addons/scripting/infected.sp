#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <cstrike>
#include <smlib>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_PREFIX "[\x07Infected\x01]"

Handle g_TacticalInsertion = null;
Handle g_GlowSprites = null;
Handle g_CTsWin = null;
Handle g_Message = null;
Handle g_MessageAdvnaced = null;
Handle g_StartGame = null;
Handle g_tShowSpawns = null;
Handle g_NextInfected = null;

bool g_EnoughPlayers;
bool g_GameStarted = false;
bool g_TacIns[MAXPLAYERS + 1];
bool g_TacInsPlacing[MAXPLAYERS + 1];
bool g_MuteSounds[MAXPLAYERS + 1];
bool g_ShowSpawns;

char g_WeaponsCT[2][64][MAX_WEAPON_STRING];
char g_WeaponsT[2][64][MAX_WEAPON_STRING];

float g_EyeAngles[128][3];
float g_SpawnPoints[128][3];
float g_NewPosition[MAXPLAYERS + 1][3];
float g_OriginalPosition[MAXPLAYERS + 1][3];
float g_TacInsEyeAngles[MAXPLAYERS + 1][3];
float g_RoundStartTime;
float g_FreezeTime;

int g_MessageCounter;
int g_WeaponAmmo[2][2];
int g_KillCount[MAXPLAYERS + 1];
int g_RoundScore[2];
int g_SpawnCount;
int g_WeaponSetToUse[2];
int g_WeaponTotalSets[2];
int g_ButtonsPressed[MAXPLAYERS + 1];
int g_TacInsSec[MAXPLAYERS + 1];
int g_BlueGlowSprite;
int g_RedGlowSprite;
int g_SpawnAttempts[MAXPLAYERS + 1];

//Ammo limit + msg telling them they picked up and sound
//Drop rate on ammo packs
//Menu on how to play game
//Tactical nuke
//Get more bots to play
//Random health and more on infected

public Plugin myinfo = {
	name = "Infected",
	author = "Clarkey",
	description = "Infected gamemode for CS:GO",
	version = "1.0",
	url = "http://finalrespawn.com"
};

public void OnPluginStart()
{
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);
	
	AddCommandListener(Command_JoinTeam, "jointeam");
	AddCommandListener(Command_Kill, "kill");
	
	RegConsoleCmd("sm_sound", Command_Sound);
	RegConsoleCmd("sm_sounds", Command_Sound);
	
	RegAdminCmd("sm_spawns", Command_Spawns, ADMFLAG_RCON);
	RegAdminCmd("sm_refreshweaponsets", Command_RefreshWeaponSets, ADMFLAG_RCON);
	
	GetWeaponSets();
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
			
		SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
		SDKHook(i, SDKHook_WeaponDrop, OnWeaponDrop);
	}
}

public void OnMapStart()
{
	LoadSpawns();
	
	//Add sounds to download table
	DirectoryListing Dir = OpenDirectory("sound/infected");
	char Buffer[64]; FileType Type;
	while (Dir.GetNext(Buffer, sizeof(Buffer), Type))
	{
		if (Type == FileType_File)
		{
			Format(Buffer, sizeof(Buffer), "sound/infected/%s", Buffer);
			AddFileToDownloadsTable(Buffer);
		}
	}
	delete Dir;
	
	g_TacticalInsertion = CreateTimer(0.1, Timer_TacticalInsertion, _, TIMER_REPEAT);
	g_GlowSprites = CreateTimer(1.0, Timer_GlowSprites, _, TIMER_REPEAT);
	g_BlueGlowSprite = PrecacheModel("sprites/blueglow1.vmt");
	g_RedGlowSprite = PrecacheModel("sprites/purpleglow1.vmt");
	
	//Get freeze time for other functions
	g_FreezeTime = GetConVarFloat(FindConVar("mp_freezetime"));
}

public void OnMapEnd()
{
	ClearTimer(g_TacticalInsertion);
	ClearTimer(g_GlowSprites);
	ClearTimer(g_CTsWin);
	ClearTimer(g_Message);
	ClearTimer(g_MessageAdvnaced);
	ClearTimer(g_StartGame);
	ClearTimer(g_NextInfected);
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKHook(client, SDKHook_WeaponDrop, OnWeaponDrop);
	
	PrintToChat(client, "%s Welcome to \x07Infected!\x01 The \x0BSurvivors (CT)\x01 must survive from the \x09Infected (T)\x01 until the time runs out.", PLUGIN_PREFIX);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "decoy_projectile"))
	{
		SDKHook(entity, SDKHook_GroundEntChangedPost, OnDecoyTouch);
	}
	
	if (StrEqual(classname, "item_defuser"))
	{
		SDKHook(entity, SDKHook_Touch, OnTouch);
	}
}

public void OnClientDisconnect_Post(int Client)
{
	if (g_EnoughPlayers)
		if (GetClientCount() < 2)
		{
			g_EnoughPlayers = false;
			float RoundDelay = GetConVarFloat(FindConVar("mp_round_restart_delay"));
			CS_TerminateRound(RoundDelay, CSRoundEnd_Draw, true);
		}
		
	if (GetTeamRealClientCount(CS_TEAM_T) == 1)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!Client)
				continue;
				
			if (!IsClientInGame(i))
				continue;
				
			if (GetClientTeam(i) == CS_TEAM_T)
			{
				GiveWeapons(i);
			}
		}
	}
	
	g_ButtonsPressed[Client] = 0;
	g_MuteSounds[Client] = false;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_GameStarted = false;
	g_WeaponAmmo[0][0] = 0;
	g_RoundStartTime = GetGameTime();
	
	GetWeaponSetToUse();
	
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
			
		CS_SwitchTeam(i, CS_TEAM_CT);
		CS_UpdateClientModel(i);
		GiveWeapons(i);
		
		g_KillCount[i] = 0;
	}
	
	g_MessageCounter = 10;
	
	float RoundTime = GetConVarFloat(FindConVar("mp_roundtime")) * 60;
	g_CTsWin = CreateTimer(RoundTime + g_FreezeTime, Timer_CTsWin);
	g_NextInfected = CreateTimer(30 + g_FreezeTime, Timer_NextInfected);
	
	if (GetClientCount() > 1)
		g_Message = CreateTimer(g_FreezeTime - 1, Timer_Message);
		
	g_RoundScore[0] = GetTeamScore(CS_TEAM_CT);
	g_RoundScore[1] = GetTeamScore(CS_TEAM_T);
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		g_TacIns[i] = false;
	}
	
	ClearTimer(g_CTsWin);
	ClearTimer(g_Message);
	ClearTimer(g_MessageAdvnaced);
	ClearTimer(g_StartGame);
	ClearTimer(g_NextInfected);
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_EnoughPlayers)
		if (GetClientCount() > 1)
		{
			g_EnoughPlayers = true;
			PrintToChatAll("%s Enough players detected, starting game.", PLUGIN_PREFIX);
			float RoundDelay = GetConVarFloat(FindConVar("mp_round_restart_delay"));
			CS_TerminateRound(RoundDelay, CSRoundEnd_GameStart, true);
		}
		
	int ClientUserId = GetEventInt(event, "userid");
	int Client = GetClientOfUserId(ClientUserId);
	
	if (Client)
	{
		Teleport(Client);
		GiveWeapons(Client);
	}
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int ClientUserId = GetEventInt(event, "userid");
	int Client = GetClientOfUserId(ClientUserId);
	int AttackerUserId = GetEventInt(event, "attacker");
	int Attacker = GetClientOfUserId(AttackerUserId);
	
	if (GetTeamClientCount(CS_TEAM_T) == 1)
	{
		if (GetClientTeam(Attacker) == CS_TEAM_T)
		{
			Client_RemoveAllWeapons(Attacker);
			GivePlayerItem(Attacker, "weapon_decoy");
			GivePlayerItem(Attacker, "weapon_knife_t");
		}
	}
	
	if (1 <= Client <= 64)
	{
		if (GetClientTeam(Client) == CS_TEAM_CT)
		{
			CreateTimer(0.5, Timer_ChangeTeam, ClientUserId);
		}
		else if (GetClientTeam(Client) == CS_TEAM_T)
		{
			int Ammo = GetRandomInt(0, 2);
			
			if (Ammo == 1)
			{
				float Pos[3];
				GetClientAbsOrigin(Client, Pos);
				
				int AmmoPack = CreateEntityByName("item_defuser");
				
				if (DispatchSpawn(AmmoPack))
				{
					TeleportEntity(AmmoPack, Pos, NULL_VECTOR, NULL_VECTOR);
				}
			}
		}
	}
	
	if (1 <= Attacker <= 64 && GetClientTeam(Attacker) == CS_TEAM_CT) {
		g_KillCount[Attacker]++;
		
		if (g_KillCount[Attacker] == 25) {
			Nuke(Attacker);
		}
	}
}

public Action Timer_ChangeTeam(Handle timer, any ClientUserId)
{
	if (!g_GameStarted)
		return Plugin_Handled;
		
	int Client = GetClientOfUserId(ClientUserId);
	CS_SwitchTeam(Client, CS_TEAM_T);
	
	PrintToChat(Client, "%s You are now \x07Infected!\x01 Knives and decoys are 1 hit, and you can press \x05[Reload]\x01 to place a spawn point.", PLUGIN_PREFIX);
	
	if (GetTeamClientCount(CS_TEAM_CT) == 0)
		CreateTimer(0.1, Timer_TsWin);
	
	return Plugin_Continue;
}

public Action Command_JoinTeam(int Client, const char[] Command, int Arg)
{
	char sJoining[32];
	GetCmdArg(1, sJoining, sizeof(sJoining));
	int iJoining = StringToInt(sJoining);
	
	if (iJoining == CS_TEAM_SPECTATOR) {
		ChangeClientTeam(Client, CS_TEAM_SPECTATOR);
	} else if (iJoining == CS_TEAM_CT) {
		if (!g_GameStarted) {
			ChangeClientTeam(Client, CS_TEAM_CT);
		} else {
			PrintToChat(Client, "%s Please join the \x09Infected (Terrorists).", PLUGIN_PREFIX);
		}
	} else if (iJoining == CS_TEAM_T) {
		if (g_GameStarted) {
			ChangeClientTeam(Client, CS_TEAM_T);
		} else {
			PrintToChat(Client, "%s Please join the \x0BSurvivors (Counter-Terrorists).", PLUGIN_PREFIX);
		}
	}
	
	return Plugin_Handled;
}

public Action Command_Kill(int Client, const char[] Command, int Arg)
{
	PrintToChat(Client, "%s You are not allowed to do that.", PLUGIN_PREFIX);
	return Plugin_Handled;
}

public Action Command_Sound(int Client, int Args)
{
	if (!g_MuteSounds[Client])
	{
		g_MuteSounds[Client] = true;
		PrintToChat(Client, "%s Sounds have been muted.", PLUGIN_PREFIX);
	}
	else
	{
		g_MuteSounds[Client] = false;
		PrintToChat(Client, "%s Sounds have been un-muted.", PLUGIN_PREFIX);
	}
}

public Action Command_Spawns(int Client, int Args)
{
	BuildSpawnMenu(Client);
}

public Action Command_RefreshWeaponSets(int Client, int Args)
{
	GetWeaponSets();
}

public void BuildSpawnMenu(int Client)
{
	Menu menu = new Menu(Menu_Handler);
	menu.SetTitle("Spawn Menu");
	menu.AddItem("addspawn", "Add Spawn");
	menu.AddItem("teleportspawn", "Teleport");
	menu.AddItem("showspawns", "Show Spawns");
	menu.Display(Client, MENU_TIME_FOREVER);
}

public void BuildTeleportMenu(int Client)
{
	Menu menu = new Menu(Menu_HandlerTeleport);
	menu.SetTitle("Teleport");
	
	for (int i; i < g_SpawnCount; i++)
	{
		char Spawn[32];
		Format(Spawn, sizeof(Spawn), "Spawn (%i)", i);
		menu.AddItem("", Spawn);
	}
	
	menu.Display(Client, MENU_TIME_FOREVER);
}

public void GetWeaponSets()
{
	char ConfigPath[256];
	BuildPath(Path_SM, ConfigPath, sizeof(ConfigPath), "configs/infected/weaponsets.txt");
	
	KeyValues kv = new KeyValues("Weapon Sets");
	kv.ImportFromFile(ConfigPath);
	kv.JumpToKey("CT");
	kv.GotoFirstSubKey();
	
	do {
		kv.GetString("primary", g_WeaponsCT[0][g_WeaponTotalSets[0]], MAX_WEAPON_STRING);
		kv.GetString("secondary", g_WeaponsCT[1][g_WeaponTotalSets[0]], MAX_WEAPON_STRING);
		g_WeaponTotalSets[0]++;
	} while (kv.GotoNextKey());
	
	kv.Rewind();
	kv.JumpToKey("T");
	kv.GotoFirstSubKey();
	
	do {
		kv.GetString("primary", g_WeaponsT[0][g_WeaponTotalSets[1]], MAX_WEAPON_STRING);
		kv.GetString("secondary", g_WeaponsT[1][g_WeaponTotalSets[1]], MAX_WEAPON_STRING);
		g_WeaponTotalSets[1]++;
	} while (kv.GotoNextKey());
	
	delete kv;
}

public void GiveWeapons(int client)
{
	int Team = GetClientTeam(client);
	
	Client_RemoveAllWeapons(client);
	
	if (Team == CS_TEAM_T)
	{
		if (GetTeamClientCount(CS_TEAM_T) > 1)
		{
			if (GetTeamClientCount(CS_TEAM_CT) / GetTeamClientCount(CS_TEAM_T) >= 0.33)
			{
				GivePlayerItem(client, "weapon_decoy");
				GivePlayerItem(client, "weapon_knife_t");
			}
			else
			{
				GivePlayerItem(client, "weapon_knife_t");
			}
		} else {
			GivePlayerItem(client, "weapon_decoy");
			GivePlayerItem(client, "weapon_knife_t");
			GivePlayerItem(client, g_WeaponsT[1][g_WeaponSetToUse[1]]);
			GivePlayerItem(client, g_WeaponsT[0][g_WeaponSetToUse[1]]);
		}
	} else if (Team == CS_TEAM_CT) {
		GivePlayerItem(client, "weapon_knife");
		int SecondaryWeapon = GivePlayerItem(client, g_WeaponsCT[1][g_WeaponSetToUse[0]]);
		int PrimaryWeapon = GivePlayerItem(client, g_WeaponsCT[0][g_WeaponSetToUse[0]]);
		
		if (g_WeaponAmmo[0][0] == 0) {
			g_WeaponAmmo[0][0] = GetEntProp(PrimaryWeapon, Prop_Data, "m_iClip1");
			if (g_WeaponAmmo[0][0] < 50) {
				g_WeaponAmmo[0][1] = g_WeaponAmmo[0][0] * 2;
			} else {
				g_WeaponAmmo[0][1] = g_WeaponAmmo[0][0];
			}
			
			g_WeaponAmmo[1][0] = GetEntProp(SecondaryWeapon, Prop_Data, "m_iClip1");
			if (g_WeaponAmmo[1][0] < 50) {
				g_WeaponAmmo[1][1] = g_WeaponAmmo[1][0] * 2;
			} else {
				g_WeaponAmmo[1][1] = g_WeaponAmmo[1][0];
			}
		}
		
		SetEntProp(PrimaryWeapon, Prop_Send, "m_iPrimaryReserveAmmoCount", g_WeaponAmmo[0][1]);
		SetEntProp(SecondaryWeapon, Prop_Send, "m_iPrimaryReserveAmmoCount", g_WeaponAmmo[1][1]);
	}
}

public void GetWeaponSetToUse()
{
	g_WeaponSetToUse[0] = GetRandomInt(0, g_WeaponTotalSets[0] - 1);
	g_WeaponSetToUse[1] = GetRandomInt(0, g_WeaponTotalSets[1] - 1);
}

public Action OnTakeDamage(int Victim, int &Attacker, int &Inflictor, float &Damage, int &DamageType)
{
	if (!(1 <= Attacker <= 64))
		return Plugin_Continue;
		
	char sInflictor[32];
	GetEdictClassname(Inflictor, sInflictor, sizeof(sInflictor));
	
	if (StrEqual("player", sInflictor))
	{
		char sWeapon[32];
		GetClientWeapon(Attacker, sWeapon, sizeof(sWeapon));
		
		if (StrEqual("weapon_knife", sWeapon))
		{
			Damage = 118.0;
			return Plugin_Changed;
		}
	}
	else if (StrContains("decoy", sInflictor))
	{
		Damage = 200.0;
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}

public void OnDecoyTouch(int entity, int other)
{
	KillEntity(entity);
}

public Action OnTouch(int entity, int other)
{
	//If the defuse kit touched a client
	if (1 <= other <= 64 && GetClientTeam(other) == CS_TEAM_CT)
	{
		int PrimaryWeapon = GetPlayerWeaponSlot(other, CS_SLOT_PRIMARY);
		int SecondaryWeapon = GetPlayerWeaponSlot(other, CS_SLOT_SECONDARY);
		
		int PrimaryAmmo = GetEntProp(PrimaryWeapon, Prop_Send, "m_iPrimaryReserveAmmoCount");
		int SecondaryAmmo = GetEntProp(SecondaryWeapon, Prop_Send, "m_iPrimaryReserveAmmoCount");
		
		if (PrimaryAmmo == g_WeaponAmmo[0][1] && SecondaryAmmo == g_WeaponAmmo[1][1])
		{
			PrintHintText(other, "You have reached max ammo.");
			return Plugin_Handled;
		}
		
		AcceptEntityInput(entity, "kill");
		
		if (PrimaryAmmo > g_WeaponAmmo[0][1] - g_WeaponAmmo[0][0])
		{
			SetEntProp(PrimaryWeapon, Prop_Send, "m_iPrimaryReserveAmmoCount", g_WeaponAmmo[0][1]);
		}
		else if (PrimaryAmmo <= g_WeaponAmmo[0][1] - g_WeaponAmmo[0][0])
		{
			SetEntProp(PrimaryWeapon, Prop_Send, "m_iPrimaryReserveAmmoCount", PrimaryAmmo + g_WeaponAmmo[0][0]);
		}
		
		if (SecondaryAmmo > g_WeaponAmmo[1][1] - g_WeaponAmmo[1][0])
		{
			SetEntProp(SecondaryWeapon, Prop_Send, "m_iPrimaryReserveAmmoCount", g_WeaponAmmo[1][1]);
		}
		else if (SecondaryAmmo <= g_WeaponAmmo[1][1] - g_WeaponAmmo[1][0])
		{
			SetEntProp(SecondaryWeapon, Prop_Send, "m_iPrimaryReserveAmmoCount", PrimaryAmmo + g_WeaponAmmo[1][0]);
		}
		
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action OnWeaponDrop(int client, int weapon)
{
	if (IsValidEdict(weapon))
	{
		AcceptEntityInput(weapon, "kill");
	}
}

public Action OnPlayerRunCmd(int Client, int &Buttons)
{
	g_ButtonsPressed[Client] = Buttons;
}

public Action Timer_TacticalInsertion(Handle timer, any data)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
			
		if (GetClientTeam(i) != CS_TEAM_T || !IsPlayerAlive(i))
			continue;
			
		if (g_TacIns[i])
			continue;
			
		if (g_TacInsPlacing[i])
		{
			if (g_TacInsSec[i] >= 20)
			{
				g_TacIns[i] = true;
				g_TacInsPlacing[i] = false;
				g_TacInsSec[i] = 0;
				TE_SetupGlowSprite(g_OriginalPosition[i], g_RedGlowSprite, 1.0, 0.5, 250);
				TE_SendToAll();
				PrintHintText(i, "Placed <font color='#FFA500'>tactical insertion!</font>");
				continue;
			}
			else
			{
				GetClientAbsOrigin(i, g_NewPosition[i]);
				GetClientEyeAngles(i, g_TacInsEyeAngles[i]);
				
				if (g_NewPosition[i][0] == g_OriginalPosition[i][0])
				{
					float TimeLeft = 2.0 - float(g_TacInsSec[i]) / 10;
					PrintHintText(i, "Please wait <font color='#008000'>%.1f</font> seconds...", TimeLeft);
					g_TacInsSec[i]++;
					continue;
				}
				else
				{
					g_TacInsPlacing[i] = false;
					g_TacInsSec[i] = 0;
					PrintHintText(i, "You <font color='#FFA500'>cannot move</font>\nwhile placing your tactical insertion.");
					continue;
				}
			}
		}
		else
		{
			int Buttons = g_ButtonsPressed[i];
			
			if (Buttons & IN_RELOAD)
			{
				if (GetEntityFlags(i) & FL_ONGROUND)
				{
					g_TacInsPlacing[i] = true;
					GetClientAbsOrigin(i, g_OriginalPosition[i]);
					continue;
				}
				else
				{
					PrintHintText(i, "You need to be <font color='#FFA500'>on the ground</font> to place a tactical insertion!");
					continue;
				}
			}
		}
	}
}

public Action Timer_GlowSprites(Handle timer)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_TacIns[i])
		{
			TE_SetupGlowSprite(g_OriginalPosition[i], g_RedGlowSprite, 1.0, 0.5, 250);
			TE_SendToAll();
		}
	}
}

public Action Timer_ShowSpawns(Handle timer)
{
	for (int i; i < g_SpawnCount; i++)
	{
		if (g_ShowSpawns && g_SpawnPoints[i][0] != 0.0 && g_SpawnPoints[i][1] != 0.0 && g_SpawnPoints[i][2] != 0.0)
		{
			TE_SetupGlowSprite(g_SpawnPoints[i], g_BlueGlowSprite, 1.0, 0.5, 250);
			TE_SendToAll();
		}
	}
}

public Action CS_OnTerminateRound(float &Delay, CSRoundEndReason &Reason)
{
	if (GetClientCount() == 1)
		return Plugin_Continue;
		
	if (Reason == CSRoundEnd_CTWin || CSRoundEnd_TerroristWin)
	{
		SetTeamScore(CS_TEAM_CT, g_RoundScore[0]);
		SetTeamScore(CS_TEAM_T, g_RoundScore[1]);
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action Timer_Message(Handle timer)
{
	g_MessageAdvnaced = CreateTimer(1.0, Timer_MessageAdvanced, _, TIMER_REPEAT);
	g_StartGame = CreateTimer(11.0, Timer_StartGame);
}

public Action Timer_MessageAdvanced(Handle timer)
{
	char MessageAdvanced[256];
	char MessageSound[64];
	Format(MessageSound, sizeof(MessageSound), "play */infected/%i.mp3", g_MessageCounter);
	
	if (g_MessageCounter > 5)
		Format(MessageAdvanced, sizeof(MessageAdvanced), "The game has started!\n<font color='#008000'>%i...</font> seconds until someone is\nrandomly selected!", g_MessageCounter);
	else if (g_MessageCounter > 2)
		Format(MessageAdvanced, sizeof(MessageAdvanced), "The game has started!\n<font color='#FFA500'>%i...</font> seconds until someone is\nrandomly selected!", g_MessageCounter);
	else
		Format(MessageAdvanced, sizeof(MessageAdvanced), "The game has started!\n<font color='#FF0000'>%i...</font> seconds until someone is\nrandomly selected!", g_MessageCounter);
		
	PrintHintTextToAll(MessageAdvanced);
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
			
		if (!g_MuteSounds[i])
			ClientCommand(i, MessageSound);
	}
	
	g_MessageCounter--;
	
	if (g_MessageCounter <= 0)
		return Plugin_Stop;
		
	return Plugin_Continue;
}

public Action Timer_StartGame(Handle timer)
{
	g_GameStarted = true;
	
	int RandomPlayer = GetRandomPlayer(CS_TEAM_CT);
	
	if (RandomPlayer != 0)
	{
		CS_SwitchTeam(RandomPlayer, CS_TEAM_T);
		CS_UpdateClientModel(RandomPlayer);
		GiveWeapons(RandomPlayer);
		
		char ClientName[32];
		GetClientName(RandomPlayer, ClientName, sizeof(ClientName));
		
		char Message[256];
		Format(Message, sizeof(Message), "<font color='#FF0000'>%s</font> has been selected\nas the first infected!", ClientName);
		
		PrintHintTextToAll(Message);
		
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i))
				continue;
				
			if (!g_MuteSounds[i])
				ClientCommand(i, "play */infected/play.mp3");
		}
	}
}

public Action Timer_NextInfected(Handle timer)
{
	if (GetTeamRealClientCount(CS_TEAM_T) <= 1)
	{
		int RandomPlayer = GetRandomPlayer(CS_TEAM_CT);
		
		if (RandomPlayer != 0)
		{
			CS_SwitchTeam(RandomPlayer, CS_TEAM_T);
			CS_UpdateClientModel(RandomPlayer);
			GiveWeapons(RandomPlayer);
			
			char ClientName[32];
			GetClientName(RandomPlayer, ClientName, sizeof(ClientName));
			
			char Message[256];
			Format(Message, sizeof(Message), "<font color='#FF0000'>%s</font> has been selected\nas the second infected!", ClientName);
			
			PrintHintTextToAll(Message);
			
			return Plugin_Handled;
		}
	}
	
	return Plugin_Stop;
}

public void Nuke(int client)
{
	for (int i = 1; i < MaxClients; i++) {
		if (!IsClientInGame(i))
			continue;
			
		if (i == client || !IsPlayerAlive(i))
			continue;
			
		ForcePlayerSuicide(i);
	}
	
	CTsWin();
}

//This function is called OnPlayerSpawn and only called once
void Teleport(int client)
{
	//Reset spawn attempts
	g_SpawnAttempts[client] = 0;
	
	if (!InFreezeTime() && g_TacIns[client])
	{
		g_TacIns[client] = false;
		
		if (CheckTacInsSpawn(g_OriginalPosition[client]) == 1)
		{
			TeleportEntity(client, g_OriginalPosition[client], g_TacInsEyeAngles[client], NULL_VECTOR);
		}
		else
		{
			FindRandomSpawn(client);
		}
	}
	else
	{
		FindRandomSpawn(client);
	}
}

void FindRandomSpawn(int client)
{
	//Add a spawn attempt
	g_SpawnAttempts[client]++;
	int RandomSpawn = GetRandomInt(0, g_SpawnCount - 1);
	
	if (CheckSpawn(client, RandomSpawn) == 0)
	{
		FindRandomSpawn(client);
	}
	else if (CheckSpawn(client, RandomSpawn) == 1)
	{
		if (client)
		{
			TeleportEntity(client, g_SpawnPoints[RandomSpawn], g_EyeAngles[client], NULL_VECTOR);
		}
	}
}

public Action Timer_CTsWin(Handle timer)
{
	CTsWin();
}

public Action Timer_TsWin(Handle timer)
{
	float RoundRestart = GetConVarFloat(FindConVar("mp_round_restart_delay"));
	CS_TerminateRound(RoundRestart, CSRoundEnd_TerroristWin, true);
	SetTeamScore(CS_TEAM_T, g_RoundScore[1] + 1);
}

public void CTsWin()
{
	float RoundRestart = GetConVarFloat(FindConVar("mp_round_restart_delay"));
	CS_TerminateRound(RoundRestart, CSRoundEnd_CTWin, true);
	SetTeamScore(CS_TEAM_CT, g_RoundScore[0] + 1);
}

public int GetRandomPlayer(int team)
{
	if (GetTeamRealClientCount(team) == 0)
	{
		return 0;
	}
	
	int RandomPlayer = GetRandomInt(1, GetTeamRealClientCount(team));
	
	int Client, Counter;
	while (Counter != RandomPlayer)
	{
		Client++;
		
		if (IsClientInGame(Client))
		{
			if (IsPlayerAlive(Client) && !IsFakeClient(Client) && GetClientTeam(Client) == team)
			{
				Counter++;
			}
		}
	}
	
	return Client;
}

public int GetTeamRealClientCount(int team)
{
	int Clients;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			if (GetClientTeam(i) == team && !IsFakeClient(i))
			{
				Clients++;
			}
		}
	}
	
	return Clients;
}

stock void ClearTimer(Handle &timer)
{
	if (timer != null)
	{
		CloseHandle(timer);
		timer = null;
	}
}

stock void KillEntity(int entity)
{
	if (entity < 1)
		return;
		
	AcceptEntityInput(entity, "kill");
}

bool InFreezeTime()
{
	if (GetGameTime() - g_RoundStartTime < g_FreezeTime)
	{
		return true;
	}
	else
	{
		return false;
	}
}

public int CheckSpawn(int client, int randomspawn)
{
	if (g_SpawnCount == 0)
	{
		PrintToChatAll("%s No spawns detected, please add some.", PLUGIN_PREFIX);
		return -1;
	}
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
			
		if (!IsPlayerAlive(i))
			continue;
			
		float Pos[3];
		GetClientAbsOrigin(i, Pos);
		
		float Distance[3];
		Distance[0] = g_SpawnPoints[randomspawn][0] - Pos[0];
		Distance[1] = g_SpawnPoints[randomspawn][1] - Pos[1];
		Distance[2] = g_SpawnPoints[randomspawn][2] - Pos[2];
		
		for (int x; x < 3; x++)
		{
			if (Distance[x] < 0)
			{
				Distance[x] = FloatAbs(Distance[x]);
			}
		}
		
		//To prevent spawning outside the map, make the distance required less and less
		if (InFreezeTime())
		{
			if (Distance[0] > 100)
			{
				continue;
			}
			else if (Distance[1] > 100)
			{
				continue;
			}
			else if (Distance[2] > 100)
			{
				continue;
			}
		}
		else if (g_SpawnAttempts[client] <= 50)
		{
			if (Distance[0] > 500)
			{
				continue;
			}
			else if (Distance[1] > 500)
			{
				continue;
			}
			else if (Distance[2] > 200)
			{
				continue;
			}
		}
		else if (g_SpawnAttempts[client] <= 100)
		{
			if (Distance[0] > 400)
			{
				continue;
			}
			else if (Distance[1] > 400)
			{
				continue;
			}
			else if (Distance[2] > 200)
			{
				continue;
			}
		}
		else if (g_SpawnAttempts[client] <= 150)
		{
			if (Distance[0] > 300)
			{
				continue;
			}
			else if (Distance[1] > 300)
			{
				continue;
			}
			else if (Distance[2] > 200)
			{
				continue;
			}
		}
		else if (g_SpawnAttempts[client] <= 200)
		{
			if (Distance[0] > 200)
			{
				continue;
			}
			else if (Distance[1] > 200)
			{
				continue;
			}
			else if (Distance[2] > 200)
			{
				continue;
			}
		}
		
		return 0;
	}
	
	return 1;
}

public int CheckTacInsSpawn(float TacInsPos[3])
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
			
		if (!IsPlayerAlive(i))
			continue;
			
		float Pos[3];
		GetClientAbsOrigin(i, Pos);
		
		float Distance[3];
		Distance[0] = TacInsPos[0] - Pos[0];
		Distance[1] = TacInsPos[1] - Pos[1];
		Distance[2] = TacInsPos[2] - Pos[2];
		
		for (int x; x < 3; x++)
		{
			if (Distance[x] < 0)
			{
				Distance[x] = FloatAbs(Distance[x]);
			}
		}
				
		if (Distance[0] > 50)
			continue;
			
		if (Distance[1] > 50)
			continue;
			
		if (Distance[2] > 200)
			continue;
			
		return 0;
	}
	
	return 1;
}

public void LoadSpawns()
{
	g_SpawnCount = 0;
	
	char CurrentMap[256];
	GetCurrentMap(CurrentMap, sizeof(CurrentMap));
	
	char ConfigPath[256];
	BuildPath(Path_SM, ConfigPath, 256, "configs/infected/spawns/%s.txt", CurrentMap);
	
	Handle hFile = OpenFile(ConfigPath, "r");
	
	char Buffer[512];
	char BuferExp[6][32];
	
	if (hFile != null)
	{
		while (ReadFileLine(hFile, Buffer, sizeof(Buffer)))
		{
			ExplodeString(Buffer, " ", BuferExp, 6, 32);
			
			g_SpawnPoints[g_SpawnCount][0] = StringToFloat(BuferExp[0]);
			g_SpawnPoints[g_SpawnCount][1] = StringToFloat(BuferExp[1]);
			g_SpawnPoints[g_SpawnCount][2] = StringToFloat(BuferExp[2]);
			g_EyeAngles[g_SpawnCount][0] = StringToFloat(BuferExp[3]);
			g_EyeAngles[g_SpawnCount][1] = StringToFloat(BuferExp[4]);
			g_EyeAngles[g_SpawnCount][2] = StringToFloat(BuferExp[5]);
			
			g_SpawnCount++;
		}
		
		CloseHandle(hFile);
	}
}

void SaveSpawns()
{
	char CurrentMap[256];
	GetCurrentMap(CurrentMap, sizeof(CurrentMap));
	
	char ConfigPath[256];
	BuildPath(Path_SM, ConfigPath, 256, "configs/infected/spawns/%s.txt", CurrentMap);
	
	Handle hFile = OpenFile(ConfigPath, "w");
	
	if (hFile != null)
		for (int i; i < g_SpawnCount; i++)
		{
			WriteFileLine(hFile, "%.2f %.2f %.2f %.2f %.2f %.2f", g_SpawnPoints[i][0], g_SpawnPoints[i][1], g_SpawnPoints[i][2], g_EyeAngles[i][0], g_EyeAngles[i][1], g_EyeAngles[i][2]);
		}
		
	CloseHandle(hFile);
}

void AddSpawn(int Client)
{
	float Pos[3], Eye[3];
	GetClientAbsOrigin(Client, Pos);
	GetClientEyeAngles(Client, Eye);
	
	g_SpawnPoints[g_SpawnCount][0] = Pos[0];
	g_SpawnPoints[g_SpawnCount][1] = Pos[1];
	g_SpawnPoints[g_SpawnCount][2] = Pos[2];
	g_EyeAngles[g_SpawnCount][0] = Eye[0];
	g_EyeAngles[g_SpawnCount][1] = Eye[1];
	g_EyeAngles[g_SpawnCount][2] = Eye[2];
	
	g_SpawnCount++;
	
	PrintToChat(Client, "%s Added spawn point. Total: %i", PLUGIN_PREFIX, g_SpawnCount);
	
	SaveSpawns();
}

public int Menu_Handler(Menu menu, MenuAction action, int client, int option)
{
	char sOption[32];
	
	if (action == MenuAction_Select)
	{
		menu.GetItem(option, sOption, sizeof(sOption));
		
		if (StrEqual(sOption, "addspawn"))
		{
			AddSpawn(client);
			BuildSpawnMenu(client);
		}
		else if (StrEqual(sOption, "teleportspawn"))
			BuildTeleportMenu(client);
		else if (StrEqual(sOption, "showspawns"))
		{
			if (g_ShowSpawns)
			{
				g_ShowSpawns = false;
				PrintToChat(client, "%s Show spawns has been disabled.", PLUGIN_PREFIX);
				ClearTimer(g_tShowSpawns);
			}
			else if (!g_ShowSpawns)
			{
				g_ShowSpawns = true;
				PrintToChat(client, "%s Show spawns has been enabled.", PLUGIN_PREFIX);
				g_tShowSpawns = CreateTimer(1.0, Timer_ShowSpawns, _, TIMER_REPEAT);
			}
			
			BuildSpawnMenu(client);
		}
	}
	else if (action == MenuAction_End)
		delete menu;
}

public int Menu_HandlerTeleport(Menu menu, MenuAction action, int Client, int Option)
{
	if (action == MenuAction_Select)
	{
		TeleportEntity(Client, g_SpawnPoints[Option], g_EyeAngles[Option], NULL_VECTOR);
		BuildTeleportMenu(Client);
	}
	else if (action == MenuAction_End)
		delete menu;
}