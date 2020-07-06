#include <sourcemod>
#include <sdktools>
#include <cstrike>

#pragma semicolon 1
#pragma newdecls required

//The distance to search for other players on both axis (should be the same as EXPLOSION_RADIUS)
#define PLAYERS_DISTANCE 650
//How many players have to be near you to register the plugin
#define MIN_PERCENT_NEAR 50
//How many times in a row you have to have players near you
#define PLAYERS_NEAR_COUNT 5

//Name of the model that spawns
#define MODEL_NAME "models/props/de_dust/dust_rusty_barrel.mdl"

//Explosion defines
#define EXPLOSION_RADIUS 650
#define EXPLOSION_SPRITE "sprites/sprite_fire01.vmt"
#define EXPLOSION_FIRE "materials/sprites/fire2.vmt"
#define EXPLOSION_HALO "materials/sprites/halo01.vmt"
#define EXPLOSION_SOUND "play */infected/explode{sound}.mp3"
#define EXPLOSION_SOUND_FAR "play */infected/explode{sound}_distant.mp3"
#define EXPLOSION_BEEP "play */infected/beep.mp3"

public Plugin myinfo = {
	name = "Infected - Anti Camp",
	author = "Clarkey",
	description = "Prevents mass camping in a single spot",
	version = "1.0",
	url = "http://finalrespawn.com"
};

bool g_EnoughPlayersNear[MAXPLAYERS + 1];
float g_PlayerPosition[MAXPLAYERS + 1][3];
float g_Explosion[16][3];
int g_CTsNear[MAXPLAYERS + 1];
int g_CTsNearCount[MAXPLAYERS + 1];
int g_ExplosionCount;
int g_ExplosionSprite;
int g_ExplosionFire;
int g_ExplosionHalo;

public void OnMapStart()
{
	//Start the main timer
	CreateTimer(10.0, Timer_Position, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	
	//Precache everything that is necessary
	if (!IsModelPrecached(MODEL_NAME))PrecacheModel(MODEL_NAME);
	if (!IsModelPrecached(EXPLOSION_SPRITE))g_ExplosionSprite = PrecacheModel(EXPLOSION_SPRITE);
	if (!IsModelPrecached(EXPLOSION_FIRE))g_ExplosionFire = PrecacheModel(EXPLOSION_FIRE);
	if (!IsModelPrecached(EXPLOSION_HALO))g_ExplosionHalo = PrecacheModel(EXPLOSION_HALO);
}

public void OnClientDisconnect_Post(int client)
{
	g_PlayerPosition[client][0] = 0.0;
	g_PlayerPosition[client][1] = 0.0;
	g_PlayerPosition[client][2] = 0.0;
}

public Action Timer_Position(Handle timer, any data)
{
	float Distance[3];
	
	//Loop all clients
	for (int x = 1; x <= MaxClients; x++)
	{
		if (!IsClientInGame(x))
			continue;
			
		if (!IsPlayerAlive(x) || GetClientTeam(x) != CS_TEAM_CT)
			continue;
			
		GetClientAbsOrigin(x, g_PlayerPosition[x]);
		
		//Start from the client above the current
		for (int y = x + 1; y <= MaxClients; y++)
		{
			if (!IsClientInGame(y))
				continue;
				
			if (!IsPlayerAlive(y) || GetClientTeam(y) != CS_TEAM_CT)
				continue;
				
			for (int z; z < 3; z++)
			{
				Distance[z] = g_PlayerPosition[x][z] - g_PlayerPosition[y][z];
				if (Distance[z] < 0)
				{
					Distance[z] = FloatAbs(Distance[z]);
				}
			}
			
			//If they are further away on any axis by a specified amount, skip this iteration
			if (Distance[0] > PLAYERS_DISTANCE)
			{
				continue;
			}
			else if (Distance[1] > PLAYERS_DISTANCE)
			{
				continue;
			}
			else if (Distance[2] > 200)
			{
				continue;
			}
			
			g_CTsNear[x]++;
			g_CTsNear[y]++;
		}
		
		//Add them to the potential list
		if (g_CTsNear[x] >= MIN_PERCENT_NEAR)
		{
			g_EnoughPlayersNear[x] = true;
		}
		else
		{
			g_EnoughPlayersNear[x] = false;
		}
	}
	
	//Now that we have how many people they are near, let's see if they are over the limit, and randomly place a barrel there
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_EnoughPlayersNear[i])
		{
			g_CTsNearCount[i]++;
			
			float Percent = (100.0 * (100.0 / (g_CTsNear[i] / GetTeamClientCount(CS_TEAM_CT) * 100.0 * g_CTsNearCount[i] ^ 2.0 / (g_CTsNearCount[i] + 1.0) ^ 2.0 / 2.0)));
			
			if (GetRandomInt(0, RoundFloat(Percent)) > 100)
			{
				if (g_CTsNearCount[i] >= PLAYERS_NEAR_COUNT)
				{
					//If there are no explosions set yet, this is going to be set
					if (g_ExplosionCount == 0 && GetEntityFlags(i) & FL_ONGROUND)
					{
						g_Explosion[g_ExplosionCount] = g_PlayerPosition[i];
						g_ExplosionCount++;
					}
					
					g_CTsNearCount[i] = 0;
				}
			}
		}
		
		//Reset client variables while still in the loop
		g_CTsNear[i] = 0;
	}
	
	//After all this if there are any explosion that need triggering, do it
	for (int k; k < g_ExplosionCount; k++)
	{
		StartExplosion(k);
	}
	
	//Reset explosion count
	g_ExplosionCount = 0;
}

void StartExplosion(int explosionnumber)
{
	CreateTimer(4.0, Timer_StartExplosion, explosionnumber, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_StartExplosion(Handle timer, any data)
{
	//If any client in near enough to be affected by the barrel
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
			
		if (!IsPlayerAlive(i))
			continue;
			
		float Pos[3];
		GetClientAbsOrigin(i, Pos);
		
		int FarFromAxis;
		if (FloatAbs(Pos[0] - g_Explosion[data][0]) < 50)FarFromAxis++;
		if (FloatAbs(Pos[1] - g_Explosion[data][1]) < 50)FarFromAxis++;
		if (FloatAbs(Pos[2] - g_Explosion[data][2]) < 100)FarFromAxis++;
		
		if (FarFromAxis != 3)
		{
			CreateTimer(5.0, Timer_StartExplosion, data, TIMER_FLAG_NO_MAPCHANGE);
			return Plugin_Stop;
		}
	}
	
	//Create entity
	int EntIndex = CreateEntityByName("prop_dynamic");
	
	//Give it properties
	DispatchKeyValue(EntIndex, "model", MODEL_NAME);
	DispatchKeyValue(EntIndex, "solid", "1");
	
	if (DispatchSpawn(EntIndex))
	{
		CreateTimer(1.0, Timer_DoExplosion, EntIndex, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		TeleportEntity(EntIndex, g_Explosion[data], NULL_VECTOR, NULL_VECTOR);
	}
	
	return Plugin_Continue;
}

int g_TimerDoExplosionCount;
public Action Timer_DoExplosion(Handle timer, any data)
{
	//Position of the barrel
	float Position[3];
	GetEntPropVector(data, Prop_Send, "m_vecOrigin", Position);
	
	if (g_TimerDoExplosionCount > 10)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i))
				continue;
				
			if (!IsPlayerAlive(i) || IsFakeClient(i))
				continue;
				
			float ClientPosition[3];
			GetClientAbsOrigin(i, ClientPosition);
			float Distance = GetVectorDistance(Position, ClientPosition);
			
			//If they are in the radius
			if (Distance <= EXPLOSION_RADIUS)
			{
				ClientCommand(i, EXPLOSION_BEEP);
				PrintHintTextToAll("<font color='#FF0000'>EXPLOSION</font>\n%i seconds until the barrel is detonated.", 10 - g_TimerDoExplosionCount);
			}
		}
		
		return Plugin_Continue;
	}
	else
	{
		//Send the effects
		TE_SetupExplosion(Position, g_ExplosionSprite, 10.0, 1, 0, EXPLOSION_RADIUS, 5000);
		TE_SendToAll();
		int Colour[4] = {188, 220, 255, 200};
		TE_SetupBeamRingPoint(Position, 10.0, float(EXPLOSION_RADIUS), g_ExplosionFire, g_ExplosionHalo, 0, 10, 0.6, 10.0, 0.5, Colour, 10, 0);
		TE_SendToAll();
		
		//Not completely sure why this was done, for more effect? I just copied the code from explode.sp
		Position[2] += 10;
		TE_SetupExplosion(Position, g_ExplosionSprite, 10.0, 1, 0, EXPLOSION_RADIUS, 5000);
		TE_SendToAll();
		
		//Simulate a real explosion
		ApplyEffects(Position);
		
		//Remove the barrel
		AcceptEntityInput(data, "kill");
		
		g_TimerDoExplosionCount = 0;
		return Plugin_Stop;
	}
}

void ApplyEffects(float position[3])
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
			
		if (!IsPlayerAlive(i))
			continue;
			
		float ClientPosition[3];
		GetClientAbsOrigin(i, ClientPosition);
		float Distance = GetVectorDistance(position, ClientPosition);
		
		//Randomise a sound and play it appropriately
		int Random = GetRandomInt(3, 5);
		char Number[2];
		IntToString(Random, Number, sizeof(Number));
		
		//If they are in the radius
		if (Distance <= EXPLOSION_RADIUS)
		{
			char Buffer[64] = EXPLOSION_SOUND;
			ReplaceString(Buffer, sizeof(Buffer), "{sound}", Number);
			ClientCommand(i, Buffer);
		}
		else
		{
			char Buffer[64] = EXPLOSION_SOUND_FAR;
			ReplaceString(Buffer, sizeof(Buffer), "{sound}", Number);
			ClientCommand(i, Buffer);
			continue;
		}
		
		//Calculate and apply damage!
		int Damage = 220;
		Damage = RoundToFloor(Damage * (EXPLOSION_RADIUS - Distance) / EXPLOSION_RADIUS);
		SlapPlayer(i, Damage, false);
		
		//Set up a little explosion on the client as well I believe
		TE_SetupExplosion(ClientPosition, g_ExplosionSprite, 0.05, 1, 0, 1, 1);
		TE_SendToAll();
	}
}