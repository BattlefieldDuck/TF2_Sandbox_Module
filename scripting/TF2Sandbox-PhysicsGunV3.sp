/** Default Key
[Mouse1] Grab
[Mouse2] Freeze
[Mouse3] Pull and push

[R] Rotate Function
{
	[W] Rotate up
	[S] Rotate down
	[A] Rotate left
	[D] Rotate right
}
[E] Reset particle
[T] Smart Copy 
[Z] Set particle
*/


/*Change log
1.0 - first release
2.0 - Add Curve Laser
2.1 - Reduce less by laser
3.0 - Add Hints + Add sound effect
3.2 - Edit the Hints + add rotate Z axis + apply force on prop_ragdoll + more particle effects
	  Removed Size display in hint to prevent server crash
3.3 - Fix OnClientDisconnect stack errors
*/
#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "BattlefieldDuck"
#define PLUGIN_VERSION "3.3"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <vphysics>
#include <morecolors>
#include <tf2_stocks>
#include <tf2items_giveweapon>

#tryinclude <build>

#pragma newdecls required

public Plugin myinfo = 
{
	name = "[TF2] TF2Sandbox - PhysicsGun Version 3",
	author = PLUGIN_AUTHOR,
	description = "Physics Gun on TF2! Grab everything!",
	version = PLUGIN_VERSION,
	url = "http://steamcommunity.com/id/battlefieldduck/"
};

#define HIDEHUD_WEAPONSELECTION			( 1<<0 ) // Hide ammo count & weapon selection 

#define PARTICLE "medicgun_beam_machinery"

//https://github.com/bouletmarc/hl2_ep2_content
#define MODEL_PHYSICSGUN 			"models/weapons/w_physics.mdl"
#define MODEL_PHYSICSGUNVIEWMODEL 	"models/weapons/v_superphyscannon.mdl"
#define MODEL_PHYSICSLASER 			"materials/sprites/physbeam.vmt"
#define MODEL_HALOINDEX 			"materials/sprites/halo01.vmt"
#define MODEL_BLUEGLOW 				"materials/sprites/blueglow2.vmt"
#define SOUND_PICKUP 				"weapons/physcannon/physcannon_pickup.wav"
#define SOUND_DROP 					"weapons/physcannon/physcannon_drop.wav"

#define GRAB_HINTS "Obj: %s\nIndex: %i [%i]\nName: %s"
#define ROTATE_HINTS "Angle: %i %i %i\nDistance: %im\nSize: %.2f"
#define SYNC_HINTS "[MOUSE2] Freeze\n[MOUSE3] Pull and Push\n[R] Rotate XY axis\n[R]+[MOUSE3] Rotate Z axis\n[R]+[Space] Resize\n[T] Smart Copy\n[Z] or [X] Set Particle"

static int g_iPhysicGunIndex = 5696124;
static int g_iPhysicGunWeaponIndex = 1001;
static int g_iPhysicGunQuality = 1;
static char g_strParticle[][] =
{
	"ping_circle", //1
	"burningplayer_red", //2
	"burningplayer_blue", //3
	"burningplayer_rainbow", //4
	"burningplayer_rainbow_blue", //5
	"burningplayer_rainbow_red", //6	
	"burningplayer_rainbow_flame", //7
	"burningplayer_rainbow_glow_old", //8
	//"burningplayer_rainbow_OLD",  //This is good
	
	"burningplayer_rainbow_glow_white", //1
	"community_sparkle", //2
	"ghost_pumpkin", //3
	"ghost_pumpkin_flyingbits", //4
	"ghost_pumpkin_blueglow", //5
	"hwn_skeleton_glow_blue", //6
	"hwn_skeleton_glow_red", //7

};


Handle g_cvForceEntity;
Handle g_cvForcePlayer;
ConVar g_cvLessLag;
ConVar g_cvRotateSpeed;
ConVar g_cvLaserRate;
ConVar g_cvMinSize;
ConVar g_cvMaxSize;
ConVar g_cvScaleBypass;

Handle g_hHud;
Handle g_hHudSyncBugDoor;

int g_ModelIndex;
int g_iPhysicsGun;
int g_iPhysicsGunWorld;
int g_HaloIndex;

int g_iGrabbingEntity[MAXPLAYERS + 1][3]; //0. Entity, 1. Glow entity index, 2. Rope index
float g_fGrabbingDistance[MAXPLAYERS + 1]; //MaxDistance
float g_fGrabbingDifference[MAXPLAYERS + 1][3]; //Difference

float g_fGrabbingAttack2Delay[MAXPLAYERS + 1];
float g_fGrabbingRotateDelay[MAXPLAYERS + 1];
float g_fGrabbingLaserDelay[MAXPLAYERS + 1];
float g_fGrabbingCopyDelay[MAXPLAYERS + 1];
float g_fHintsDelay[MAXPLAYERS + 1];

//Fix the compatibility on physgun v3 and v4
bool g_bIN_ATTACK[MAXPLAYERS + 1];

public void OnPluginStart()
{
	CreateConVar("sm_tf2sb_pg_version", PLUGIN_VERSION, "", FCVAR_SPONLY | FCVAR_NOTIFY);
	g_cvForceEntity = CreateConVar("sm_tf2sb_pg_forceentity", "70.0", "Force when throwing Entity (Default: 70.0)", 0, true, 1.0, true, 100.0);
	g_cvForcePlayer = CreateConVar("sm_tf2sb_pg_forceplayer", "20.0", "Force when throwing Player (Default: 20.0)", 0, true, 1.0, true, 100.0);
	g_cvLessLag =	  CreateConVar("sm_tf2sb_pg_lesslag", "1", "Disable some minor functions to minimise lag", 0, true, 0.0, true, 1.0);
	g_cvRotateSpeed = CreateConVar("sm_tf2sb_pg_rotatespeed", "2.0", "Rotate Speed of the prop by physics gun (1.0-10.0)", 0, true, 1.0, true, 10.0);
	g_cvLaserRate =   CreateConVar("sm_tf2sb_pg_lasercurverate", "2", "Curve rate of a laser, Smaller rate = Less lag (1-10)", 0, true, 1.0, true, 10.0);
	
	g_cvMinSize =     CreateConVar("sm_tf2sb_pg_minpropscale", "0.2", "Minimum of the prop size when rescaling (0.1-10.0)", 0, true, 0.1, true, 10.0);
	g_cvMaxSize =     CreateConVar("sm_tf2sb_pg_maxpropscale", "2.0", "Maximum of the prop size when rescaling (0.1-10.0)", 0, true, 0.1, true, 10.0);
	g_cvScaleBypass = CreateConVar("sm_tf2sb_pg_adminscalebypass", "1", "1 = Bypass the restriction of the scale limit (admin only)", 0, true, 0.0, true, 1.0);
	
	RegAdminCmd("sm_pg", Command_EquipPhysicsGun, 0, "Equip Physics Gun!");

	HookEvent("player_spawn", Event_PlayerSpawn);
	
	//Hook Voice command
	HookUserMessage(GetUserMessageId("VoiceSubtitle"), VoiceHook, true);
	
	//Hook F1
	AddCommandListener(Event_EquipPhysicsGun, "+showroundinfo");
	
	g_hHud = CreateHudSynchronizer();
	g_hHudSyncBugDoor = CreateHudSynchronizer();

} //@

//Give PhysicsGun to client
public Action Command_EquipPhysicsGun(int client, int args)
{
	EquipPhysicsGun(client);
} //@

public Action Event_EquipPhysicsGun(int client, const char[] command, int args) 
{
	EquipPhysicsGun(client);
}

void EquipPhysicsGun(int client)
{
	if(IsValidClient(client))
	{
		if(!IsGameSandbox() && !CheckCommandAccess(client, "sm_admin", ADMFLAG_GENERIC))
		{
			return;
		}
		
		if(IsPlayerAlive(client))
		{
			int iWeapon = GetPlayerWeaponSlot(client, 1);
			
			if(GetEntProp(iWeapon, Prop_Send, "m_iItemDefinitionIndex") == g_iPhysicGunWeaponIndex && GetEntProp(iWeapon, Prop_Send, "m_iEntityQuality") == g_iPhysicGunQuality)
				return;
				
			//int iActiveWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
			if(IsValidEntity(iWeapon))
			{	
				SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", iWeapon);
			}
			
			if(!TF2Items_CheckWeapon(g_iPhysicGunIndex))
			{		
				if(!IsModelPrecached(MODEL_PHYSICSGUN))	PrecacheModel(MODEL_PHYSICSGUN);
				TF2Items_CreateWeapon(g_iPhysicGunIndex, "tf_weapon_builder", g_iPhysicGunWeaponIndex, 1, g_iPhysicGunQuality, 99, "", -1, MODEL_PHYSICSGUN, true);
			}
			
			int PhysicsGun = TF2Items_GiveWeapon(client, g_iPhysicGunIndex);
			if(IsValidEntity(PhysicsGun))
			{
				SetEntProp(PhysicsGun, Prop_Send, "m_nSkin", 1);
				SetEntProp(PhysicsGun, Prop_Send, "m_iWorldModelIndex", g_iPhysicsGunWorld);
				SetEntProp(PhysicsGun, Prop_Send, "m_nModelIndexOverrides", g_iPhysicsGunWorld, _, 0);
				SetEntProp(PhysicsGun, Prop_Send, "m_nSequence", 2);
			}
			CPrintToChat(client, "{dodgerblue}[{aliceblue}{dodgerblue}PhysV3] {aliceblue}You have equip a {aqua}Physics Gun V%s{aliceblue}!", PLUGIN_VERSION);
			CPrintToChat(client, "{dodgerblue}[{aliceblue}{dodgerblue}PhysV3] {aliceblue}Made By {yellow}BattlefieldDuck{aliceblue}. Credits: {green}Pelipoika{aliceblue}, {red}Danct12{aliceblue}, {pink}LeadKiller{aliceblue}.");
			//CPrintToChat(client, "{dodgerblue}[PhysV3] {aliceblue}.");
			SendDialogToOne(client, 240, 248, 255, "You have equip a Physics Gun!");
		}
		else 	CPrintToChat(client, "{dodgerblue}[PhysV3] {aliceblue}You can NOT equip PhysicsGun V%s when DEAD!", PLUGIN_VERSION);
	}
}

//-----[ Start and End ]--------------------------------------------------(
public void OnMapStart() //Precache Sound and Model
{
	g_ModelIndex = PrecacheModel(MODEL_PHYSICSLASER);
	g_HaloIndex = PrecacheModel(MODEL_HALOINDEX);
	g_iPhysicsGun = PrecacheModel(MODEL_PHYSICSGUNVIEWMODEL);
	g_iPhysicsGunWorld = PrecacheModel(MODEL_PHYSICSGUN);

	PrecacheSound(SOUND_PICKUP);
	PrecacheSound(SOUND_DROP);

	for (int i = 1; i < MAXPLAYERS; i++)
	{
		g_iGrabbingEntity[i][0] = -1; //Grab entity
		g_iGrabbingEntity[i][1] = -1; //tf_glow
		g_iGrabbingEntity[i][2] = -1;

		if(IsValidClient(i)) 
		{
			SDKHook(i, SDKHook_WeaponSwitchPost, WeaponSwitchHookPost);
		}
	}
}

public void OnClientPutInServer(int client)
{
	g_iGrabbingEntity[client][0] = -1; //Grab entity
	g_iGrabbingEntity[client][1] = -1; //tf_glow
	g_iGrabbingEntity[client][2] = -1;
	g_fGrabbingDistance[client] = 0.0;
	
	g_fGrabbingAttack2Delay[client] = 0.0;
	g_fGrabbingRotateDelay[client] = 0.0;
	g_fGrabbingLaserDelay[client] = 0.0;
	g_fGrabbingCopyDelay[client] = 0.0;
	g_fHintsDelay[client] = 0.0;
	
	SDKHook(client, SDKHook_WeaponSwitchPost, WeaponSwitchHookPost);
}

public void OnClientDisconnect(int client)
{
	if(IsValidEntity(EntRefToEntIndex(g_iGrabbingEntity[client][0])))	
	{
		g_iGrabbingEntity[client][0] = -1;
	}
	
	for (int i = 1; i <= 2; i++) 
	{
		if(IsValidEntity(EntRefToEntIndex(g_iGrabbingEntity[client][i])))	
		{
			AcceptEntityInput(EntRefToEntIndex(g_iGrabbingEntity[client][i]), "Kill");
			g_iGrabbingEntity[client][i] = -1;
		}
	}

	g_iGrabbingEntity[client][0] = -1; //Grab entity
	g_iGrabbingEntity[client][1] = -1; //tf_glow
	g_iGrabbingEntity[client][2] = -1;
	g_fGrabbingDistance[client] = 0.0;
	SDKUnhook(client, SDKHook_WeaponCanSwitchTo, BlockWeaponSwtich);
	SDKUnhook(client, SDKHook_WeaponSwitchPost, WeaponSwitchHookPost);
}

//Disable Weapon Drop on physics gun
public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "tf_dropped_weapon"))
	{
		SDKHook(entity, SDKHook_SpawnPost, OnDroppedWeaponSpawn);
	}
}
//------------------------------------------------------------------------)

//Hook---------------------------------------------------------(
public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if(IsValidClient(client))
	{
		SDKUnhook(client, SDKHook_WeaponCanSwitchTo, BlockWeaponSwtich);
		TF2_RegeneratePlayer(client);
	}
}

//Block weapon drop physics gun
public void OnDroppedWeaponSpawn(int entity)
{  
	if(IsValidEntity(entity))
	{
		if(GetEntProp(entity, Prop_Send, "m_iItemDefinitionIndex") == g_iPhysicGunWeaponIndex && GetEntProp(entity, Prop_Send, "m_iEntityQuality") == g_iPhysicGunQuality)
		{
			AcceptEntityInput(entity, "Kill");
		}
	} 
} 

//From voicesub.sp
public Action VoiceHook(UserMsg msg_id, Handle bf, const int[] players, int playersNum, bool reliable, bool init)
{
	int client = BfReadByte(bf);
	int voicemenu1 = BfReadByte(bf);
	int voicemenu2 = BfReadByte(bf);
	
	if(IsValidClient(client) && IsPlayerAlive(client) && IsHoldingPhysicsGun(client) && IsValidEntity(EntRefToEntIndex(g_iGrabbingEntity[client][0])))
	{
		if(voicemenu1 == 0)	TE_ParticleToAll(g_strParticle[voicemenu2], _, _, _, EntRefToEntIndex(g_iGrabbingEntity[client][0]), -1, -1, true);
		else if(voicemenu1 == 1) TE_ParticleToAll(g_strParticle[voicemenu2+8], _, _, _, EntRefToEntIndex(g_iGrabbingEntity[client][0]), -1, -1, true);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

//Hook Key "Q" (Required last switched weapon to work properly and model reload) + Block Weapon Switch 
public Action BlockWeaponSwtich(int client, int entity)
{
	return Plugin_Handled;	
}

//Change viewmodel (Player hands)
public Action WeaponSwitchHookPost(int client, int entity) 
{
	if(IsValidClient(client) && IsPlayerAlive(client))
	{
		int iViewModel = GetEntPropEnt(client, Prop_Send, "m_hViewModel");
		if(IsHoldingPhysicsGun(client))
		{
			SetEntProp(iViewModel, Prop_Send, "m_nModelIndex", g_iPhysicsGun, 2);
			SetEntProp(iViewModel, Prop_Send, "m_nSequence", 2);
		}
		else
		{
			//Change back to default viewmodel when m_nModelIndex == g_iPhysicsGun only.
			if(GetEntProp(iViewModel, Prop_Send, "m_nModelIndex", 2) == g_iPhysicsGun)
			{
				char sArmModel[128];
				switch (TF2_GetPlayerClass(client))
				{
					case TFClass_Scout: 	Format(sArmModel, sizeof(sArmModel), "models/weapons/c_models/c_scout_arms.mdl");
					case TFClass_Soldier: 	Format(sArmModel, sizeof(sArmModel), "models/weapons/c_models/c_soldier_arms.mdl");
					case TFClass_Pyro: 		Format(sArmModel, sizeof(sArmModel), "models/weapons/c_models/c_pyro_arms.mdl");
					case TFClass_DemoMan: 	Format(sArmModel, sizeof(sArmModel), "models/weapons/c_models/c_demo_arms.mdl");
					case TFClass_Heavy:		Format(sArmModel, sizeof(sArmModel), "models/weapons/c_models/c_heavy_arms.mdl");
					case TFClass_Engineer: 	Format(sArmModel, sizeof(sArmModel), "models/weapons/c_models/c_engineer_arms.mdl");
					case TFClass_Medic: 	Format(sArmModel, sizeof(sArmModel), "models/weapons/c_models/c_medic_arms.mdl");
					case TFClass_Sniper: 	Format(sArmModel, sizeof(sArmModel), "models/weapons/c_models/c_sniper_arms.mdl");
					case TFClass_Spy: 		Format(sArmModel, sizeof(sArmModel), "models/weapons/c_models/c_spy_arms.mdl");
				}
				if(strlen(sArmModel) > 0)	SetEntProp(iViewModel, Prop_Send, "m_nModelIndex", PrecacheModel(sArmModel, true), 2);
			}
		}
	}	
}

//Control the Outline of Entity send to which client
public Action Hook_SetTransmit(int entity, int client) 
{
	//Pelipoka script again
	SetEdictFlags(entity, GetEdictFlags(entity) & ~FL_EDICT_ALWAYS);
	
	if (g_iGrabbingEntity[client][1] == entity)
		return Plugin_Continue;
	
	//return Plugin_Handled;
	return Plugin_Continue;
}  
//-------------------------------------------------------------)


public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (!IsValidClient(client)) //Return gay client
		return Plugin_Continue;
		
	if(IsPlayerAlive(client))
	{
		//Fix the compatibility on physgun v3 and v4
		if(buttons & IN_ATTACK)	
		{
			g_bIN_ATTACK[client] = true;
		}
		else
		{
			g_bIN_ATTACK[client] = false;
		}
		
		//GetAimEntity
		int iEntity = GetClientAimEntity(client);
		if(IsGameSandbox() && IsPropBuggedDoor(iEntity)) //Show info of Bugged Door
		{
			char szName[64];
			SetHudTextParams(-1.0, 0.6, 3.0, 255, 0, 0, 230, 1, 6.0, 1.0, 2.0);
			int iEntityOwner = Build_ReturnEntityOwner(iEntity);
			GetEntPropString(iEntity, Prop_Data, "m_iName", szName, sizeof(szName));
			if(IsValidClient(iEntityOwner)) 
			{
				ShowSyncHudText(client, g_hHudSyncBugDoor, "%s\n built by %N", szName, iEntityOwner);
			}
			else 
			{
				ShowSyncHudText(client, g_hHudSyncBugDoor, "%s\n built by *World", szName);
			}
		}
		
		//Check Is it holding Physics Gun
		if(IsHoldingPhysicsGun(client))
		{
			SetHudTextParams(0.74, 0.55, 1.0, 30, 144, 255, 255, 1, 6.0, 0.1, 0.1);

			//TODO: Fix fading problem
			if(TF2_GetPlayerClass(client) == TFClass_DemoMan || TF2_GetPlayerClass(client) == TFClass_Medic) //Fix medic and demo viewmodel not showing up problem
			{
				SetEntProp(GetEntPropEnt(client, Prop_Send, "m_hViewModel"), Prop_Send, "m_nSequence", 2);
			}
			
			//When Client mouse1
			if(buttons & IN_ATTACK)	
			{
				//Bind the index of Grabbing entity
				if(IsValidEntity(iEntity) && !IsValidEntity(EntRefToEntIndex(g_iGrabbingEntity[client][0])))	
				{		
					//If Sandbox game and grabbing client return,
					if ((!(IsGameSandbox() && IsValidClient(iEntity)) && IsPropOwner(client, iEntity)) || CheckCommandAccess(client, "sm_admin", ADMFLAG_GENERIC))
					{					
						//Hook Disable Change Weapon
						SDKHook(client, SDKHook_WeaponCanSwitchTo, BlockWeaponSwtich);
						
						//Set entity to g_iGrabbingEntity[client][0]
						SetEntityBindIndex(client, iEntity);
						
						TE_ParticleToAll("electrocuted_blue", _, _, _, EntRefToEntIndex(g_iGrabbingEntity[client][0]), -1, -1, false);
						TE_ParticleToAll("electrocuted_blue", _, _, _, client, -1, -1, false);
						//"electrocuted_blue_flash","electrocuted_gibbed_blue", "electrocuted_blue"
					}
				}
				
				if (IsValidEntity(EntRefToEntIndex(g_iGrabbingEntity[client][0])))
				{
					int entity = EntRefToEntIndex(g_iGrabbingEntity[client][0]);
					
					//Disable weapon switch (mouse wheel)
					SetEntProp(client, Prop_Send, "m_iHideHUD", GetEntProp(client, Prop_Send, "m_iHideHUD") | HIDEHUD_WEAPONSELECTION);
					
					//Get Value
					float fOrigin[3], fClientAngle[3], fEOrigin[3], fEndPosition[3];
					GetClientEyePosition(client, fOrigin);
					GetClientEyeAngles(client, fClientAngle);
					GetEntPropVector(entity, Prop_Data, "m_vecOrigin", fEOrigin);
						
					float fAimPosition[3];
					for (int i = 0; i <= 2; i++)
						fAimPosition[i] = fEOrigin[i] - g_fGrabbingDifference[client][i];
					
					SetEntityGlows(client, entity, fAimPosition);			
				
					// Angle fixed
					if(buttons & IN_RELOAD || buttons & IN_ATTACK3 || buttons & IN_ATTACK2)
					{		
						float fAngle[3];	
						GetEntPropVector(entity, Prop_Send, "m_angRotation", fAngle);	
						float fSize = GetEntPropFloat(entity, Prop_Send, "m_flModelScale");
						
						if(g_fHintsDelay[client] <= GetGameTime() && !(buttons & IN_SCORE))
						{
							ShowSyncHudText(client, g_hHud, ROTATE_HINTS, RoundFloat(fAngle[0]), RoundFloat(fAngle[1]), RoundFloat(fAngle[2]), RoundFloat(g_fGrabbingDistance[client]/100), fSize);
							g_fHintsDelay[client] = GetGameTime() + 0.05;
						}
						
						//Fix client aim angle (No lagge)
						if(!(GetEntityFlags(client) & FL_FROZEN))
						{
							ZeroVector(vel);
							float fFixAngle[3];
							GetVectorAnglesTwoPoints(fOrigin, fAimPosition, fFixAngle);
							AnglesNormalize(fFixAngle);
							TeleportEntity(client, NULL_VECTOR, fFixAngle, NULL_VECTOR);
							SetEntityFlags(client, (GetEntityFlags(client) | FL_FROZEN));
						}
						
						//Rotate X and Y 						[R]
						if(buttons & IN_RELOAD && !(buttons & IN_ATTACK2) && !(buttons & IN_ATTACK3) && !(buttons & IN_JUMP))
						{
							//Rotate--------------------------------------------------------------------
							if(buttons & IN_DUCK) //Accurate
							{
								if(g_fGrabbingRotateDelay[client] <= GetGameTime())
								{
									if (FloatAbs(float(mouse[1])) > FloatAbs(float(mouse[0]))) 
									{
										if(mouse[1] < 0)		
										{
											fAngle[0] -= 45.0; //Up
										}
										else if(mouse[1] > 0)
										{									
											fAngle[0] += 45.0; //Down
										}
		
										//fAngle[1]   (0 - 270) (-90 - 0)
										AnglesNormalize(fAngle);
										if(0.0 < fAngle[0] && fAngle[0] < 45.0)				fAngle[0] = 0.0;
										else if(45.0 < fAngle[0] && fAngle[0] < 90.0)		fAngle[0] = 45.0;
										else if(90.0 < fAngle[0] && fAngle[0] < 135.0)		fAngle[0] = 90.0;
										else if(135.0 < fAngle[0] && fAngle[0] < 180.0)		fAngle[0] = 135.0;							
										else if(180.0 < fAngle[0] && fAngle[0] < 225.0)		fAngle[0] = 180.0;
										else if(225.0 < fAngle[0] && fAngle[0] < 270.0)		fAngle[0] = 225.0;								
										else if(0.0 > fAngle[0] && fAngle[0] > -45.0)		fAngle[0] = -45.0;
										else if(-45.0 > fAngle[0] && fAngle[0] > -90.0)		fAngle[0] = -90.0;	
										AnglesNormalize(fAngle);							
									}						
									else
									{
										if(mouse[0] < 0)		fAngle[1] -= 45.0; //left
										else if(mouse[0] > 0)	fAngle[1] += 45.0; //right
		
										//fAngle[1]   (0 - 180) (0 - -180)
										AnglesNormalize(fAngle);
										if(0.0 < fAngle[1] && fAngle[1] < 45.0)				fAngle[1] = 0.0;
										else if(45.0 < fAngle[1] && fAngle[1] < 90.0)		fAngle[1] = 45.0;
										else if(90.0 < fAngle[1] && fAngle[1] < 135.0)		fAngle[1] = 90.0;
										else if(135.0 < fAngle[1] && fAngle[1] < 180.0)		fAngle[1] = 135.0;
										else if(0.0 > fAngle[1] && fAngle[1] > -45.0)		fAngle[1] = -45.0;
										else if(-45.0 > fAngle[1] && fAngle[1] > -90.0)		fAngle[1] = -90.0;
										else if(-90.0 > fAngle[1] && fAngle[1] > -135.0)	fAngle[1] = -135.0;
										else if(-135.0 > fAngle[1] && fAngle[1] > -180.0)	fAngle[1] = -180.0;		
										AnglesNormalize(fAngle);									
									}
									g_fGrabbingRotateDelay[client] = GetGameTime() + 0.05;
								}
							}
							else
							{
								fAngle[1] += mouse[0] / (10/g_cvRotateSpeed.FloatValue); //Left Right
								fAngle[0] += mouse[1] / (10/g_cvRotateSpeed.FloatValue); //Up Down	
								AnglesNormalize(fAngle);									
							}
	
							if(buttons & IN_MOVELEFT)
							{
								if(buttons & IN_DUCK)
								{
									fAngle[1] -= 1.0;								
								}
								else
								{
									fAngle[1] -= 2.0;
								}
							}
							if(buttons & IN_MOVERIGHT)	
							{
								if(buttons & IN_DUCK)
								{
									fAngle[1] += 1.0;
								}
								else
								{
									fAngle[1] += 2.0;
								}
							}
							
							//--------------------------------------------------------------------------
							
							
							
							//Push and Pull-------------------------------------------------------------
							if(buttons & IN_FORWARD)	
							{
								if(g_fGrabbingDistance[client] < 10000.0)
									g_fGrabbingDistance[client] += 10.0;
							}						
							if(buttons & IN_BACK)
							{
								if(g_fGrabbingDistance[client] > 150.0)
									g_fGrabbingDistance[client] -= 10.0;
							}		
							
							//--------------------------------------------------------------------------
							
						}
						//Rotate Z only  						[R][3]
						else if(buttons & IN_RELOAD && buttons & IN_ATTACK3 && !(buttons & IN_ATTACK2) && !(buttons & IN_JUMP))
						{
							if(buttons & IN_DUCK) //Accurate
							{
								if(g_fGrabbingRotateDelay[client] <= GetGameTime())
								{
									if(mouse[1] < 0)		
									{
										fAngle[2] -= 45.0; //Up
									}
									else if(mouse[1] > 0)
									{									
										fAngle[2] += 45.0; //Down
									}
	
									//fAngle[2]   (0 - 360)
									AnglesNormalize(fAngle);
									if(0.0 < fAngle[2] && fAngle[2] < 45.0)				fAngle[2] = 0.0;
									else if(45.0 < fAngle[2] && fAngle[2] < 90.0)		fAngle[2] = 45.0;
									else if(90.0 < fAngle[2] && fAngle[2] < 135.0)		fAngle[2] = 90.0;
									else if(135.0 < fAngle[2] && fAngle[2] < 180.0)		fAngle[2] = 135.0;							
									else if(180.0 < fAngle[2] && fAngle[2] < 225.0)		fAngle[2] = 180.0;
									else if(225.0 < fAngle[2] && fAngle[2] < 270.0)		fAngle[2] = 225.0;								
									else if(270.0 < fAngle[2] && fAngle[2] < 315.0)		fAngle[2] = 270.0;
									else if(315.0 < fAngle[2] && fAngle[2] < 360.0)		fAngle[2] = 315.0;	
									AnglesNormalize(fAngle);							
									
									g_fGrabbingRotateDelay[client] = GetGameTime() + 0.05;
								}
							}
							else
							{
								fAngle[2] += mouse[1] / (10/g_cvRotateSpeed.FloatValue);
								AnglesNormalize(fAngle);									
							}
						}
						
						//Simulate Mouse wheel 					[3]
						else if(buttons & IN_ATTACK3 && !(buttons & IN_RELOAD) && !(buttons & IN_ATTACK2) && !(buttons & IN_JUMP))
						{
							if (mouse[1] < 0) //Up
							{
								if(g_fGrabbingDistance[client] < 10000.0)
									g_fGrabbingDistance[client] -= 2.0 * mouse[1];
							}
							else if (mouse[1] > 0) //Down
							{
								if(g_fGrabbingDistance[client] > 150.0)
								{
									g_fGrabbingDistance[client] -= 2.0 * mouse[1];
									if (g_fGrabbingDistance[client] < 150.0) g_fGrabbingDistance[client] = 150.0;
								}
							}
						}
						//Freeze Entity (Only on prop_physics) 	[2]
						else if(buttons & IN_ATTACK2 && !(buttons & IN_RELOAD) && !(buttons & IN_ATTACK3) && !(buttons & IN_JUMP))
						{	
							char szClass[64];
							GetEdictClassname(entity, szClass, sizeof(szClass));
							
							if (StrEqual(szClass, "prop_physics") || StrEqual(szClass, "prop_ragdoll"))
							{
								if(g_fGrabbingAttack2Delay[client] <= GetGameTime())	
								{
									if(Phys_IsPhysicsObject(entity))
									{
										if(Phys_IsGravityEnabled(entity))
										{													
											Phys_EnableGravity(entity, false);
											Phys_EnableMotion(entity, false);
											Phys_Sleep(entity);
											PrintHintText(client, "Prop freezed");
										}
										else 
										{
											Phys_EnableGravity(entity, true);
											Phys_EnableMotion(entity, true);
											Phys_Wake(entity);
											PrintHintText(client, "Prop unfreezed");
										}
									}
								}
								g_fGrabbingAttack2Delay[client] = GetGameTime() + 0.5;								
							}		
						}
						//Resize								[R][ Space ]
						else if(buttons & IN_RELOAD && buttons & IN_JUMP && !(buttons & IN_ATTACK2) && !(buttons & IN_ATTACK3))
						{
							//Resize -------------------------------------------------------------------
							char szClass[64];
							GetEdictClassname(entity, szClass, sizeof(szClass));
							if (StrEqual(szClass, "prop_dynamic"))
							{
								fSize -= mouse[1]/100.0; //Up
								if(g_cvScaleBypass.BoolValue && CheckCommandAccess(client, "sm_admin", ADMFLAG_GENERIC))
								{
									if(fSize <= 0.1)	fSize = 0.1;
								}
								else
								{
									float fMinSize = g_cvMinSize.FloatValue;
									float fMaxSize = g_cvMaxSize .FloatValue;
									if(fSize <= fMinSize)	fSize = fMinSize;		
									if(fSize >= fMaxSize)	fSize = fMaxSize;
								}
								SetEntPropFloat(entity, Prop_Send, "m_flModelScale", fSize);
								//PhysicsGun_UpdateEntityHitbox(g_iGrabbingEntity[client][0]);
							}	
							//--------------------------------------------------------------------------
						}
												
						GetClientAimPosition(client, g_fGrabbingDistance[client], fEndPosition, tracerayfilterrocket, client);

						float fNewEntityPosition[3];
						
						//PhysicsGun_RotationCalculation_NewGrabbingDifference(g_fGrabbingDifference[client], fAngle, g_fGrabbingDifference[client]);
						
						for (int i = 0; i <= 2; i++)
							fNewEntityPosition[i] = fEndPosition[i] + g_fGrabbingDifference[client][i];
	
						AnglesNormalize(fAngle);
						TeleportEntity(entity, fNewEntityPosition, fAngle, NULL_VECTOR);
					}
					else
					{		
						//Remove fixed client angle						
						if(GetEntityFlags(client) & FL_FROZEN)
							SetEntityFlags(client, (GetEntityFlags(client) & ~FL_FROZEN));
						
						//Set Hint text
						char szClass[32];
						GetEdictClassname(entity, szClass, sizeof(szClass));
						char szName[32];
						if(IsValidClient(entity))
						{
							GetClientName(entity, szName, sizeof(szName));
						}
						else
						{
							GetEntPropString(entity, Prop_Data, "m_iName", szName, sizeof(szName));
						}
						TrimString(szName);
						if (strlen(szName) == 0)	szName = "---";
						//int iSkin = GetEntProp(entity, Prop_Send, "m_nSkin");
						
						if(g_fHintsDelay[client] <= GetGameTime() && !(buttons & IN_SCORE))
						{
							ShowSyncHudText(client, g_hHud, GRAB_HINTS, szClass, entity, EntIndexToEntRef(entity),szName);
							g_fHintsDelay[client] = GetGameTime() + 0.055;
						}
						
						
						GetClientAimPosition(client, g_fGrabbingDistance[client], fEndPosition, tracerayfilterrocket, client);
					
						float fNextPosition[3];
						for (int i = 0; i <= 2; i++)
							fNextPosition[i] = fEndPosition[i] + g_fGrabbingDifference[client][i];
						
						float vector[3], fZero[3];
						MakeVectorFromPoints(fAimPosition, fNextPosition, vector); //Set velocity
						
						if((StrEqual(szClass, "prop_physics") || StrEqual(szClass, "prop_ragdoll")) && Phys_IsGravityEnabled(entity)) //Check is it prop_physics before Phys_IsGravityEnabled(
						{
							ScaleVector(vector, GetConVarFloat(g_cvForceEntity));
							Phys_SetVelocity(EntRefToEntIndex(entity), vector, fZero, true);
							Phys_Wake(entity);
						}	
						else if(IsValidClient(entity)) //Is entity client?
						{
							ScaleVector(vector, GetConVarFloat(g_cvForcePlayer));
							TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, vector);
						}
						else TeleportEntity(entity, fNextPosition, NULL_VECTOR, NULL_VECTOR);
					}		
					
					//Hook T key (Smart copy function)
					if(impulse == 201)
					{
						if(g_fGrabbingCopyDelay[client] <= GetGameTime())
						{
							int iCopyIndex = PhysicsGun_CopyProp(client, entity);
							if(iCopyIndex != entity)
								SetEntityBindIndex(client, iCopyIndex);
								
							g_fGrabbingCopyDelay[client] = GetGameTime() + 1.5;
						}
						//else SendDialogToOne(client, 240, 248, 255, "Copy Function Cooling Down!");
					}
				}		
				else 
				{
					float fEndPosition[3];
					GetClientAimPosition(client, g_fGrabbingDistance[client], fEndPosition, tracerayfilterrocket, client);
					SetEntityGlows(client, -1, fEndPosition);
				}
			}
			else 
			{
				if(IsValidEntity(EntRefToEntIndex(g_iGrabbingEntity[client][0])))	
				{
					if (IsPropBuggedDoor(EntRefToEntIndex(g_iGrabbingEntity[client][0])))
						PhysicsGun_RespawnDoor(EntRefToEntIndex(g_iGrabbingEntity[client][0]));
						
					EmitSoundToAll(SOUND_DROP, client, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.8);	
					g_iGrabbingEntity[client][0] = -1;
				}
				
				if(!(buttons & IN_SCORE))
				{
					ShowHints(client);
				}
				
				ResetClientAttribute(client);
			}
		}
		else 
		{
			ResetClientAttribute(client);
		}
	}
	return Plugin_Continue;
} //@


//-------[Stock]----------------------------------------------------------------------------------------------------(

//Check--------------------------------------------
stock bool IsValidClient(int client)
{
	if (client <= 0)	return false;
	if (client > MaxClients)	return false;
	if (!IsClientConnected(client))	return false;
	return IsClientInGame(client);
}

bool IsHoldingPhysicsGun(int client)
{ 
	int iWeapon = GetPlayerWeaponSlot(client, 1);
	int iActiveWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		
	if(IsValidEntity(iWeapon) && iWeapon == iActiveWeapon && GetEntProp(iActiveWeapon, Prop_Send, "m_iItemDefinitionIndex") == g_iPhysicGunWeaponIndex && GetEntProp(iActiveWeapon, Prop_Send, "m_iEntityQuality") == g_iPhysicGunQuality)
	{	//Check Is it Physics Gun
		return true;
	}
	return false;
} //@

stock int GetClientAimEntity(int client)
{
	float fOrigin[3], fAngles[3];
	GetClientEyePosition(client, fOrigin);
	GetClientEyeAngles(client, fAngles);
	
	Handle trace = TR_TraceRayFilterEx(fOrigin, fAngles, MASK_SOLID, RayType_Infinite, TraceEntityFilter, client);

	if (TR_DidHit(trace)) 
	{	
		int iEntity = TR_GetEntityIndex(trace);
		if(iEntity > 0 && IsValidEntity(iEntity))
		{
			CloseHandle(trace);
			return iEntity;
		}
	}
	CloseHandle(trace);
	return -1;
}
public bool TraceEntityFilter(int entity, int mask, any data) 
{
	return data != entity;
}

bool IsGameSandbox()
{
	Handle hSandbox = FindConVar("sbox_enable");
	if (hSandbox != INVALID_HANDLE)	
		return true;
	return false;
}

bool IsPropOwner(int client, int entity)
{
	if(IsGameSandbox())
	{
		if (Build_ReturnEntityOwner(entity) == client)
			return true;
	}
	return false;
}

bool IsPropBuggedDoor(int iEntity) //For reload bug door
{
	if(IsValidEntity(iEntity))
	{
		char szModel[64];
		GetEntPropString(iEntity, Prop_Data, "m_ModelName", szModel, sizeof(szModel));
		if(StrEqual(szModel, "models/combine_gate_citizen.mdl") 
		||	StrEqual(szModel, "models/combine_gate_Vehicle.mdl") 
		||	StrEqual(szModel, "models/props_doors/doorKLab01.mdl") 
		|| 	StrEqual(szModel, "models/props_lab/elevatordoor.mdl") 
		||  StrEqual(szModel, "models/props_lab/RavenDoor.mdl"))	
			return true;
	}
	return false;
}
//----------------------------------
 
int PhysicsGun_RespawnDoor(int iEntity) //For reload bug door
{
	//Get Value-----------
	float fOrigin[3], fAngles[3], fSize;
	char szModel[64], szName[128], szClass[32];
	int iCollision, iRed, iGreen, iBlue, iAlpha, iSkin, iOwner;
	RenderFx EntityRenderFx;
	
	iOwner = Build_ReturnEntityOwner(iEntity);
	GetEntityClassname(iEntity, szClass, sizeof(szClass));
	GetEntPropString(iEntity, Prop_Data, "m_ModelName", szModel, sizeof(szModel));
	GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", fOrigin);
	GetEntPropVector(iEntity, Prop_Data, "m_angRotation", fAngles);
	iCollision = GetEntProp(iEntity, Prop_Data, "m_CollisionGroup", 4);
	fSize = GetEntPropFloat(iEntity, Prop_Send, "m_flModelScale");
	GetEntityRenderColor(iEntity, iRed, iGreen, iBlue, iAlpha);
	EntityRenderFx = GetEntityRenderFx(iEntity);
		
	iSkin = GetEntProp(iEntity, Prop_Send, "m_nSkin");
	GetEntPropString(iEntity, Prop_Data, "m_iName", szName, sizeof(szName));
	//--------------------
	int iNewEntity = CreateEntityByName("prop_dynamic");
	
	if (iNewEntity > MaxClients && IsValidEntity(iNewEntity))
	{
		SetEntProp(iNewEntity, Prop_Send, "m_nSolidType", 6);
		//SetEntProp(iNewEntity, Prop_Data, "m_nSolidType", 6);
		
		Build_SetLimit(iOwner, -1);
		if (Build_RegisterEntityOwner(iNewEntity, iOwner))
		{
			if (!IsModelPrecached(szModel))
				PrecacheModel(szModel);
			
			DispatchKeyValue(iNewEntity, "model", szModel);
			TeleportEntity(iNewEntity, fOrigin, fAngles, NULL_VECTOR);
			DispatchSpawn(iNewEntity);
			SetEntProp(iNewEntity, Prop_Data, "m_CollisionGroup", iCollision);
			SetEntPropFloat(iNewEntity, Prop_Send, "m_flModelScale", fSize);
			if(iAlpha < 255)	SetEntityRenderMode(iNewEntity, RENDER_TRANSCOLOR);
			else	SetEntityRenderMode(iNewEntity, RENDER_NORMAL);
			SetEntityRenderColor(iNewEntity, iRed, iGreen, iBlue, iAlpha);
			SetEntityRenderFx(iNewEntity, EntityRenderFx);
			SetEntProp(iNewEntity, Prop_Send, "m_nSkin", iSkin);
			
			
			
			if(StrContains(szName, "door") == -1)	
			{
				Format(szName, sizeof(szName), "door%i", GetRandomInt(1000, 5000));
			}	
			//SetEntPropString(iNewEntity, Prop_Data, "m_iName", szName);	
			DispatchKeyValue(iNewEntity, "targetname", szName);
			SetVariantString(szName);
			
						
			char szFormatStr[64];
			Format(szFormatStr, sizeof(szFormatStr), "%s,setanimation,open,0", szName);
			DispatchKeyValue(iNewEntity, "OnHealthChanged", szFormatStr);
			Format(szFormatStr, sizeof(szFormatStr), "%s,setanimation,close,4", szName);
			DispatchKeyValue(iNewEntity, "OnHealthChanged", szFormatStr);
			AcceptEntityInput(iEntity, "Kill");
		}
		return iNewEntity;
	}
	return -1;
}
 
int PhysicsGun_CopyProp(int client, int iEntity)
{
	//Get Value-----------
	float fOrigin[3], fAngles[3], fSize;
	char szModel[64], szName[128], szClass[32];
	int iCollision, iRed, iGreen, iBlue, iAlpha, iSkin;
	RenderFx EntityRenderFx;
	
	GetEntityClassname(iEntity, szClass, sizeof(szClass));
	GetEntPropString(iEntity, Prop_Data, "m_ModelName", szModel, sizeof(szModel));
	GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", fOrigin);
	GetEntPropVector(iEntity, Prop_Data, "m_angRotation", fAngles);
	iCollision = GetEntProp(iEntity, Prop_Data, "m_CollisionGroup", 4);
	fSize = GetEntPropFloat(iEntity, Prop_Send, "m_flModelScale");
	GetEntityRenderColor(iEntity, iRed, iGreen, iBlue, iAlpha);
	EntityRenderFx = GetEntityRenderFx(iEntity);
	iSkin = GetEntProp(iEntity, Prop_Send, "m_nSkin");
	GetEntPropString(iEntity, Prop_Data, "m_iName", szName, sizeof(szName));
	//--------------------
	int iNewEntity = -1;
	if(StrEqual(szClass, "player") && !g_cvLessLag.BoolValue)
	{
		iNewEntity = CreateEntityByName("prop_ragdoll");
		DispatchKeyValue(iNewEntity, "model", szModel);
		DispatchSpawn(iNewEntity);
		TeleportEntity(iNewEntity, fOrigin, NULL_VECTOR, NULL_VECTOR);  
	}
	else if(StrContains(szClass, "prop_") != -1)
	{
		if(g_cvLessLag.BoolValue)	iNewEntity = CreateEntityByName("prop_dynamic_override");
		else	iNewEntity = CreateEntityByName(szClass);
		
		if (iNewEntity > MaxClients && IsValidEntity(iNewEntity))
		{
			SetEntProp(iNewEntity, Prop_Send, "m_nSolidType", 6);
			SetEntProp(iNewEntity, Prop_Data, "m_nSolidType", 6);
			
			if (Build_RegisterEntityOwner(iNewEntity, client))
			{
				if (!IsModelPrecached(szModel))
					PrecacheModel(szModel);
				
				DispatchKeyValue(iNewEntity, "model", szModel);
				TeleportEntity(iNewEntity, fOrigin, fAngles, NULL_VECTOR);
				DispatchSpawn(iNewEntity);
				SetEntProp(iNewEntity, Prop_Data, "m_CollisionGroup", iCollision);
				SetEntProp(iNewEntity, Prop_Data, "m_CollisionGroup", 5); 
				SetEntPropFloat(iNewEntity, Prop_Send, "m_flModelScale", fSize);
				if(iAlpha < 255)	SetEntityRenderMode(iNewEntity, RENDER_TRANSCOLOR);
				else	SetEntityRenderMode(iNewEntity, RENDER_NORMAL);
				SetEntityRenderColor(iNewEntity, iRed, iGreen, iBlue, iAlpha);
				SetEntityRenderFx(iNewEntity, EntityRenderFx);
				SetEntProp(iNewEntity, Prop_Send, "m_nSkin", iSkin);
				SetEntPropString(iEntity, Prop_Data, "m_iName", szName);
			}
			else AcceptEntityInput(iNewEntity, "Kill");
			return iNewEntity;
		}
	}
	return iEntity;
} 
 
void PhysicsGun_RotationCalculation_NewGrabbingDifference(float fGrabbingDifference[3], float fDifferenceAngle[3], float outfNewDifferece[3])
{
	float A1, A2, A3, B1, B2, B3, C1, C2, C3;
	float AngleX, AngleY, AngleZ, DifferenceX, DifferenceY, DifferenceZ;
	
	DifferenceX = fGrabbingDifference[0];
	DifferenceY = fGrabbingDifference[1];
	DifferenceZ = fGrabbingDifference[2];
	
	AngleX = fDifferenceAngle[0];
	AngleY = fDifferenceAngle[1];
	AngleZ = fDifferenceAngle[2];
	
	A1 = DifferenceX * Cosine(AngleZ) - DifferenceY * Sine(AngleZ);
	B1 = DifferenceX * Sine(AngleZ) + DifferenceY * Cosine(AngleZ);
	C1 = DifferenceZ;
	
	B2 = B1 * Cosine(AngleY) - C1 * Sine(AngleY);
	C2 = B1 * Sine(AngleY) + C1 * Cosine(AngleY);
	A2 = A1;
	
	C3 = C2 * Cosine(AngleX) - A2 * Sine(AngleX);
	A3 = C2 * Sine(AngleX) + A2 * Cosine(AngleX);
	B3 = B2;
	
	outfNewDifferece[0] = A3;
	outfNewDifferece[1] = B3;
	outfNewDifferece[2] = C3;
} 

//Not working help me
bool PhysicsGun_UpdateEntityHitbox(int iEntity)
{
	char szModel[64];
	GetEntPropString(iEntity, Prop_Data, "m_ModelName", szModel, sizeof(szModel));

	//Create a dummy entity to get entity origial collison Min Max
	float fEntityMin[3], fEntityMax[3];
	int iDummyEntity = CreateEntityByName("prop_dynamic_override");
	if (iDummyEntity > MaxClients && IsValidEntity(iDummyEntity))
	{
		if (!IsModelPrecached(szModel))	PrecacheModel(szModel);
		DispatchKeyValue(iDummyEntity, "model", szModel);
		DispatchSpawn(iDummyEntity);
		GetEntPropVector(iDummyEntity, Prop_Send, "m_vecSpecifiedSurroundingMins", fEntityMin);
		GetEntPropVector(iDummyEntity, Prop_Send, "m_vecSpecifiedSurroundingMaxs", fEntityMax);
		AcceptEntityInput(iDummyEntity, "Kill");
	}
	else	return false;
	
	float fModelScale = GetEntPropFloat(iEntity, Prop_Send, "m_flModelScale");
		
	ScaleVector(fEntityMin, fModelScale);
	ScaleVector(fEntityMax, fModelScale);
	
	SetEntPropVector(iEntity, Prop_Send, "m_vecSpecifiedSurroundingMins", fEntityMin);
	SetEntPropVector(iEntity, Prop_Send, "m_vecSpecifiedSurroundingMaxs", fEntityMax);
	
	PrintCenterTextAll("%f %f %f   %f %f %f", fEntityMin[0], fEntityMin[1], fEntityMin[2], fEntityMax[0], fEntityMax[1], fEntityMax[2]);
	return true;
}

 
 
/*
int SpawnVehicle(int client)
{
	iNewEntity = CreateEntityByName("prop_vehicle_driveable");

	char TargetName[10];
	Format(TargetName, sizeof(TargetName), "%i",iNewEntity);
	DispatchKeyValue(iNewEntity, "targetname", TargetName);
	
	if(!IsModelPrecached("models/airboat.mdl")) PrecacheModel("models/airboat.mdl");
	DispatchKeyValue(iNewEntity, "model", "models/airboat.mdl");
	DispatchKeyValue(iNewEntity, "vehiclescript", "scripts/vehicles/airboat.txt");

	SetEntProp(iNewEntity, Prop_Send, "m_nSolidType", 6);
	SetEntProp(iNewEntity, Prop_Data, "m_nSolidType", 6);
	SetEntProp(iNewEntity, Prop_Data, "m_nNextThinkTick", -1);
	SetEntProp(iNewEntity, Prop_Data, "m_nVehicleType", 8);
	
	
	DispatchSpawn(iNewEntity);
	
	AcceptEntityInput(iNewEntity, "TurnOn");
	AcceptEntityInput(iNewEntity, "Unlock");
	
	TeleportEntity(iNewEntity, fOrigin, NULL_VECTOR, NULL_VECTOR);
}
*/
 
//From raindowglow.sp--------------(
stock int CreateGlow(int iEnt)
{
	if(!HasGlow(iEnt))
	{
		char oldEntName[64];
		GetEntPropString(iEnt, Prop_Data, "m_iName", oldEntName, sizeof(oldEntName));
		
		char strName[126], strClass[64];
		GetEntityClassname(iEnt, strClass, sizeof(strClass));
		Format(strName, sizeof(strName), "%s%i", strClass, iEnt);
		DispatchKeyValue(iEnt, "targetname", strName);

		char strGlowColor[18];
		Format(strGlowColor, sizeof(strGlowColor), "%i %i %i %i", 135, 224, 230, 255);
	
		int ent = CreateEntityByName("tf_glow");
		if(IsValidEntity(ent))
		{
			SDKHook(ent, SDKHook_SetTransmit, Hook_SetTransmit);
			DispatchKeyValue(ent, "targetname", "GrabGlow");
			DispatchKeyValue(ent, "target", strName);
			DispatchKeyValue(ent, "Mode", "0");
			DispatchKeyValue(ent, "GlowColor", strGlowColor); 
			//SDKHook(ent, SDKHook_SetTransmit, Hook_SetTransmit);
			DispatchSpawn(ent);
	
			AcceptEntityInput(ent, "Enable");
			
			//Change name back to old name because we don't need it anymore.
			SetEntPropString(iEnt, Prop_Data, "m_iName", oldEntName);
			return ent;
		}
	}
	return -1;
}

stock bool HasGlow(int iEnt)
{
	int index = -1;
	while ((index = FindEntityByClassname(index, "tf_glow")) != -1)
	{
		if (GetEntPropEnt(index, Prop_Send, "m_hTarget") == iEnt)
		{
			return true;
		}
	}
	return false;
}

public void OnPluginEnd()
{
	int index = -1;
	while ((index = FindEntityByClassname(index, "tf_glow")) != -1)
	{
		char strName[64];
		GetEntPropString(index, Prop_Data, "m_iName", strName, sizeof(strName));
		if(StrEqual(strName, "GrabGlow"))
		{
			AcceptEntityInput(index, "Kill");
		}
	}
}
//---------------------------------)

void SetEntityBindIndex(int client, int iEntity)
{
	for (int i = 1; i <= 2; i++)
	{
		if(IsValidEntity(EntRefToEntIndex(g_iGrabbingEntity[client][i])))	AcceptEntityInput(EntRefToEntIndex(g_iGrabbingEntity[client][i]), "Kill");
	}
	//AttachControlPointParticle(client, PARTICLE, g_iGrabbingEntity[client][0]);		
	
	//Set Entity Outline
	if(!HasGlow(iEntity))
		g_iGrabbingEntity[client][1] = EntIndexToEntRef(CreateGlow(iEntity));
		
	//Save the Entity Distance
	g_fGrabbingDistance[client] = GetEntitiesDistance(client, iEntity);
	
	float fEOrigin[3], fEndPosition[3];
	GetEntPropVector(iEntity, Prop_Data, "m_vecOrigin", fEOrigin);
	GetClientAimPosition(client, g_fGrabbingDistance[client], fEndPosition, tracerayfilterrocket, client);
	
	for (int i = 0; i <= 2; i++)
		g_fGrabbingDifference[client][i] = fEOrigin[i] - fEndPosition[i];
	
	EmitSoundToAll(SOUND_PICKUP, client, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.8);
	
	char szClass[32];
	GetEntityClassname(iEntity, szClass, sizeof(szClass));
	
	//Bind Entity
	g_iGrabbingEntity[client][0] = EntIndexToEntRef(iEntity);
}

void SetEntityGlows(int client, int iEntity, float fPointPosition[3]) //Set the Glow and laser
{
	if(g_fGrabbingLaserDelay[client] <= GetGameTime())
	{
		float fLocal_EOrigin[3];
		CopyVector(fPointPosition, fLocal_EOrigin);
	
		if(iEntity != -1)
		{
			//Curve Laser on client to Entity
			SetCurveBeam(client, fLocal_EOrigin, g_cvLaserRate.IntValue);
		}
		else
		{
			float fWeaponOrigin[3];
			GetClientWeaponPosition(client, fWeaponOrigin);
			//Laser on client and Aim position
			TE_SetupBeamPoints(fWeaponOrigin, fLocal_EOrigin, g_ModelIndex, g_HaloIndex, 0, 1, 0.1, 0.3, 0.3, 1, 0.0, {255, 255, 255, 255}, 2);
			TE_SendToAll();
		}
		g_fGrabbingLaserDelay[client] = GetGameTime() + 0.05;
	}
}

void GetClientWeaponPosition(int client, float fOut[3])
{
	float fOrigin[3], fAngle[3];
	GetClientEyePosition(client, fOrigin);
	fOrigin[2] -= 10.0;
	GetClientEyeAngles(client, fAngle);
	fAngle[1] -= 25.0;
	AnglesNormalize(fAngle);
	
	GetPointAimPosition(fOrigin, fAngle, 20.0, fOut, tracerayfilterrocket, client);
}

void SetCurveBeam(int client, float fGrabbingEntityPoint[3], int iAccerate)
{
	float fWeaponOrigin[3];
	GetClientWeaponPosition(client, fWeaponOrigin);
	
	float distance = GetVectorDistance(fWeaponOrigin, fGrabbingEntityPoint)/(iAccerate*2);
	
	int iModelIndex = g_ModelIndex;
	int iColour[4] =  { 255, 255, 255, 255 };
	
	float fNewAimPoint[3], fWeaponToNewAimAngle[3];
	GetClientAimPosition(client, distance, fNewAimPoint, tracerayfilterrocket, client);
	
	float fWeaponToEyesAngle[3];
	GetVectorAnglesTwoPoints(fWeaponOrigin, fNewAimPoint, fWeaponToEyesAngle);
	GetPointAimPosition(fWeaponOrigin, fWeaponToEyesAngle, distance/2.5, fNewAimPoint, tracerayfilterrocket, client);
	GetVectorAnglesTwoPoints(fWeaponOrigin, fGrabbingEntityPoint, fWeaponToNewAimAngle);
	TE_SetupBeamPoints(fWeaponOrigin, fNewAimPoint, iModelIndex, g_HaloIndex, 0, 15, 0.1, 1.0, 1.0, 1, 0.0, iColour, 10); //Start
	TE_SendToAll(0.01);
	
	float fPoint2[3], fPoint2Angle[3], fLastPoint[3], fLastAngle[3];
	CopyVector(fNewAimPoint, fLastPoint);
	CopyVector(fWeaponToNewAimAngle, fLastAngle);
	for (int i = 0; i <= iAccerate; i++)
	{	
		GetPointAimPosition(fLastPoint, fLastAngle, distance, fPoint2, tracerayfilterrocket, client);
		GetVectorAnglesTwoPoints(fLastPoint, fGrabbingEntityPoint, fPoint2Angle);
		TE_SetupBeamPoints(fLastPoint, fPoint2, iModelIndex, g_HaloIndex, i, 15, 0.15, 1.0, 1.0, 1, 0.0, iColour, 10); //Curve
		TE_SendToAll();
		
		CopyVector(fPoint2, fLastPoint);
		CopyVector(fPoint2Angle, fLastAngle);
	}
	
	TE_SetupBeamPoints(fLastPoint, fGrabbingEntityPoint, iModelIndex, g_HaloIndex, 0, 15, 0.1, 1.0, 1.0, 1, 0.0, iColour, 10); //End
	TE_SendToAll();		
	
	//TE_SetupGlowSprite(fGrabbingEntityPoint, g_iBlueGlow, 0.1, 1.0, 5);	
	//TE_SendToAll();
}

void ShowHints(int client)
{
	if(g_fHintsDelay[client] <= GetGameTime())
	{
		ShowSyncHudText(client, g_hHud, SYNC_HINTS);
		g_fHintsDelay[client] = GetGameTime() + 0.055;
	}
}

//Not used
stock void SetEntityOnFireOld(int client, int iEntity, int method = 1)
{
	//The Egypt Method
	if(method == 1)
	{
		int entity = CreateEntityByName("env_smokestack");
		
		DispatchKeyValue(entity, "BaseSpread", "0"); 
		
		DispatchKeyValue(entity, "SpreadSpeed", "8"); 
		DispatchKeyValue(entity, "Speed", "30"); 
		DispatchKeyValue(entity, "StartSize", "9");
		DispatchKeyValue(entity, "EndSize", "4"); 
		DispatchKeyValue(entity, "Rate", "15"); 
		DispatchKeyValue(entity, "JetLength", "24"); 
		PrecacheModel("particle/smokesprites_0001.vmt");
		DispatchKeyValue(entity, "SmokeMaterial", "particle/smokesprites_0001.vmt"); 
		DispatchKeyValue(entity, "twist", "10"); 
		
		DispatchKeyValue(entity, "rendercolor", "250 200 133"); 
		DispatchKeyValue(entity, "renderamt", "1"); 
		
		DispatchKeyValue(entity, "roll", "5");
		DispatchKeyValue(entity, "InitialState", "1"); 
		DispatchKeyValue(entity, "angles", "0 0 0"); 
		DispatchKeyValue(entity, "WindSpeed", "0"); 
		DispatchKeyValue(entity, "WindAngle", "0"); 
		
		float fOrigin[3];
		GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", fOrigin);
		TeleportEntity(entity, fOrigin, NULL_VECTOR, NULL_VECTOR);
		
		DispatchSpawn(entity); 
		AcceptEntityInput(entity, "TurnOn"); 
		SetVariantString("!activator"); 
		AcceptEntityInput(entity, "SetParent", iEntity, entity);
		
		
		int ent = CreateEntityByName( "env_sprite" );
		SetEntPropEnt( ent, Prop_Send, "m_hOwnerEntity", client );
		
		PrecacheModel("materials/Sprites/light_glow03.vmt");
		SetEntityModel( ent, "materials/Sprites/light_glow03.vmt" );
		SetEntityRenderColor( ent, 255, 140, 26 );
		
		SetEdictFlags( ent, FL_EDICT_ALWAYS );
		SetEntityRenderMode( ent, RENDER_WORLDGLOW );  
		DispatchKeyValue( ent, "GlowProxySize", "30" );
		DispatchKeyValue( ent, "renderamt", "125" ); 
		DispatchKeyValue( ent, "framerate", "10.0" ); 
		DispatchKeyValue( ent, "scale", "1.6" ); 
		SetEntProp( ent, Prop_Data, "m_bWorldSpaceScale", 1 ); 
		TeleportEntity(ent, fOrigin, NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn( ent ); 
		
		AcceptEntityInput( ent, "ShowSprite" );
		
		SetVariantString("!activator");
		AcceptEntityInput(ent, "SetParent", iEntity, entity);
	}
	//Particle Fire
	else if (method == 2)
	{
		int fire = CreateEntityByName("env_fire");
		
		if (fire > MaxClients && IsValidEntity(fire))
		{
			DispatchKeyValue(fire, "firesize", "220");
			DispatchKeyValue(fire, "health", "10");
			DispatchKeyValue(fire, "firetype", "Normal");
			DispatchKeyValue(fire, "damagescale", "0.0");
			DispatchKeyValue(fire, "spawnflags", "256");
			SetVariantString("WaterSurfaceExplosion");
			AcceptEntityInput(fire, "DispatchEffect"); 
			DispatchSpawn(fire);
			float fOrigin[3];
			GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", fOrigin);
			TeleportEntity(fire, fOrigin, NULL_VECTOR, NULL_VECTOR);
			AcceptEntityInput(fire, "StartFire");
			SetVariantString("!activator");
			AcceptEntityInput(fire, "SetParent", iEntity);
			
			int fireModel = CreateEntityByName("info_particle_system");
			if (fireModel > MaxClients && IsValidEntity(fireModel))
			{
				//DispatchKeyValue(fireModel, "targetname", tmp);
				char name[64];
				TeleportEntity(fireModel, fOrigin, NULL_VECTOR, NULL_VECTOR);
				GetEntPropString(iEntity, Prop_Data, "m_iName", name, sizeof(name));
				DispatchKeyValue(fireModel, "targetname", "tf2particle");
				DispatchKeyValue(fireModel, "parentname", name);
				DispatchKeyValue(fireModel, "effect_name", "burningplayer_red");
				DispatchSpawn(fireModel);
				AcceptEntityInput(fireModel, "SetParent", iEntity, iEntity);
				ActivateEntity(fireModel);
				AcceptEntityInput(fireModel, "start");
				//CreateTimer(time, DeleteParticle, fireModel);
			}
		}
	}
	//Tf2 fire (Rubbish)
	else if (method == 3)
	{
		if(IsValidClient(iEntity))
		{
			TF2_AddCondition(iEntity, TFCond_OnFire, 10.0);
		}
	}
}

stock bool GetPointAimPosition(float cleyepos[3], float cleyeangle[3], float maxtracedistance, float resultvecpos[3],TraceEntityFilter Tfunction, int filter)
{
	float eyeanglevector[3];

	Handle traceresulthandle = INVALID_HANDLE;
	
	traceresulthandle = TR_TraceRayFilterEx(cleyepos, cleyeangle, MASK_SOLID, RayType_Infinite, Tfunction, filter);
	
	if(TR_DidHit(traceresulthandle) == true)
	{
		float endpos[3];
		TR_GetEndPosition(endpos, traceresulthandle);
		//TR_GetPlaneNormal(traceresulthandle, resultvecnormal);
		
		if((GetVectorDistance(cleyepos, endpos) <= maxtracedistance) || maxtracedistance <= 0)
		{	
			resultvecpos[0] = endpos[0];
			resultvecpos[1] = endpos[1];
			resultvecpos[2] = endpos[2];
			
			CloseHandle(traceresulthandle);
			return true;		
		}
		else
		{	
			GetAngleVectors(cleyeangle, eyeanglevector, NULL_VECTOR, NULL_VECTOR);
			NormalizeVector(eyeanglevector, eyeanglevector);
			ScaleVector(eyeanglevector, maxtracedistance);
			
			AddVectors(cleyepos, eyeanglevector, resultvecpos);
			
			CloseHandle(traceresulthandle);
			return true;
		}	
	}
	CloseHandle(traceresulthandle);
	return false;
}

void ResetClientAttribute(int client)
{
	if(IsValidEntity(EntRefToEntIndex(g_iGrabbingEntity[client][0])))	
	{
		g_iGrabbingEntity[client][0] = -1;
	}
	for (int i = 1; i <= 2; i++) 
	{
		if(IsValidEntity(EntRefToEntIndex(g_iGrabbingEntity[client][i])))	
		{
			AcceptEntityInput(EntRefToEntIndex(g_iGrabbingEntity[client][i]), "Kill");
			g_iGrabbingEntity[client][i] = -1;
		}
	}
	
	if(GetEntityFlags(client) & FL_FROZEN && !g_bIN_ATTACK[client])
	{
		SetEntityFlags(client, (GetEntityFlags(client) & ~FL_FROZEN));
	}
			
	if(GetEntProp(client, Prop_Send, "m_iHideHUD") & HIDEHUD_WEAPONSELECTION)
	{
		SetEntProp(client, Prop_Send, "m_iHideHUD", GetEntProp(client, Prop_Send, "m_iHideHUD") &~HIDEHUD_WEAPONSELECTION);
	}	
	
	SDKUnhook(client, SDKHook_WeaponCanSwitchTo, BlockWeaponSwtich);
}

stock float GetEntitiesDistance(int entity1, int entity2)
{
	float fOrigin1[3];
	GetEntPropVector(entity1, Prop_Send, "m_vecOrigin", fOrigin1);
	
	float fOrigin2[3];
	GetEntPropVector(entity2, Prop_Send, "m_vecOrigin", fOrigin2);
	
	return GetVectorDistance(fOrigin1, fOrigin2);
}

void GetClientSightEnd(float TE_ClientEye[3], float TE_iEye[3], float out[3])
{
    TR_TraceRayFilter(TE_ClientEye, TE_iEye, MASK_SOLID, RayType_EndPoint, TraceRayDontHitPlayers);
    if (TR_DidHit())
        TR_GetEndPosition(out);
}

public bool TraceRayDontHitPlayers(int entity, int mask, any data)
{
    if (0 < entity <= MaxClients)
        return false;

    return true;
}


stock bool GetClientAimPosition(int client, float maxtracedistance, float resultvecpos[3], TraceEntityFilter Tfunction, int filter)
{
	float cleyepos[3], cleyeangle[3], eyeanglevector[3];
	GetClientEyePosition(client, cleyepos); 
	GetClientEyeAngles(client, cleyeangle);
	
	Handle traceresulthandle = INVALID_HANDLE;
	
	traceresulthandle = TR_TraceRayFilterEx(cleyepos, cleyeangle, MASK_SOLID, RayType_Infinite, Tfunction, filter);
	
	if(TR_DidHit(traceresulthandle) == true){
		
		float endpos[3];
		TR_GetEndPosition(endpos, traceresulthandle);
		//TR_GetPlaneNormal(traceresulthandle, resultvecnormal);
		
		if((GetVectorDistance(cleyepos, endpos) <= maxtracedistance) || maxtracedistance <= 0){
			
			resultvecpos[0] = endpos[0];
			resultvecpos[1] = endpos[1];
			resultvecpos[2] = endpos[2];
			
			CloseHandle(traceresulthandle);
			return true;
			
		}
		else
		{	
			GetAngleVectors(cleyeangle, eyeanglevector, NULL_VECTOR, NULL_VECTOR);
			NormalizeVector(eyeanglevector, eyeanglevector);
			ScaleVector(eyeanglevector, maxtracedistance);
			
			AddVectors(cleyepos, eyeanglevector, resultvecpos);
			
			CloseHandle(traceresulthandle);
			return true;
		}	
	}
	CloseHandle(traceresulthandle);
	return false;
}

public bool tracerayfilterrocket(int entity, int mask, any data)
{
	if (IsValidEntity(entity))
		return false;
	
	return true;	
}

float GetVectorAnglesTwoPoints(const float vStartPos[3], const float vEndPos[3], float vAngles[3])
{
	static float tmpVec[3];
	tmpVec[0] = vEndPos[0] - vStartPos[0];
	tmpVec[1] = vEndPos[1] - vStartPos[1];
	tmpVec[2] = vEndPos[2] - vStartPos[2];
	GetVectorAngles(tmpVec, vAngles);
}

void AnglesNormalize(float vAngles[3])
{
	while (vAngles[0] > 89.0)vAngles[0] -= 360.0;
	while (vAngles[0] < -89.0)vAngles[0] += 360.0;
	while (vAngles[1] > 180.0)vAngles[1] -= 360.0;
	while (vAngles[1] < -180.0)vAngles[1] += 360.0;
	while (vAngles[2] < -0.0)vAngles[2] += 360.0;
	while (vAngles[2] >= 360.0)vAngles[2] -= 360.0;
}

void SendDialogToOne(int client, int red, int green, int blue, const char[] text, any ...)
{
	char message[100];
	VFormat(message, sizeof(message), text, 4);	
	
	KeyValues kv = new KeyValues("Stuff", "title", message);
	kv.SetColor("color", red, green, blue, 255);
	kv.SetNum("level", 1);
	kv.SetNum("time", 10);
	
	CreateDialog(client, kv, DialogType_Msg);

	delete kv;
}

stock void ZeroVector(float vector[3])
{
	vector[0] = 0.0;
	vector[1] = 0.0;
	vector[2] = 0.0;
}

stock void CopyVector(const float input[3], float out[3])
{
	out[0] = input[0];
	out[1] = input[1];
	out[2] = input[2];
}

void AttachControlPointParticle(int ent, char[] strParticle, int controlpoint)
{
	int particle = CreateEntityByName("info_particle_system");
	int particle2 = CreateEntityByName("info_particle_system");
	
	if (IsValidEdict(particle))
	{ 
		char tName[128];
		Format(tName, sizeof(tName), "SimpleBuild:%i", ent);
		DispatchKeyValue(ent, "targetname", tName);

		char cpName[128];
		Format(cpName, sizeof(cpName), "SimpleBuildd:%i", ent);
		DispatchKeyValue(controlpoint, "targetname", cpName);

		char cp2Name[128];
		Format(cp2Name, sizeof(cp2Name), "tf2particle%i", controlpoint);

		DispatchKeyValue(particle2, "targetname", cp2Name);
		DispatchKeyValue(particle2, "parentname", cpName);

		float pos[3], m_vecMaxs[3], cAng[3];
		GetClientAbsAngles(ent, cAng);
		GetEntPropVector(controlpoint, Prop_Data, "m_vecOrigin", pos);
		GetEntPropVector(controlpoint, Prop_Send, "m_vecMaxs", m_vecMaxs);
		
		pos[2] += (m_vecMaxs[2] / 2.0);
		
		SetEntPropVector(particle, Prop_Data, "m_angRotation", cAng);
		SetEntPropVector(particle2, Prop_Data, "m_vecOrigin", pos);
		
		SetVariantString(cpName);
		AcceptEntityInput(particle2, "SetParent");

		DispatchKeyValue(particle, "targetname", "tf2particle");
		DispatchKeyValue(particle, "parentname", tName);
		DispatchKeyValue(particle, "effect_name", strParticle);
		DispatchKeyValue(particle, "cpoint1", cp2Name);

		DispatchSpawn(particle);

		SetVariantString(tName);
		AcceptEntityInput(particle, "SetParent");

		SetVariantString("flag");
		AcceptEntityInput(particle, "SetParentAttachment");
		cAng[0] -= 270.0;
		cAng[1] -= 69.0;
		SetEntPropVector(particle, Prop_Send, "m_angRotation", cAng);
		//The particle is finally ready
		ActivateEntity(particle);
		AcceptEntityInput(particle, "start");
	
		g_iGrabbingEntity[ent][2] = EntIndexToEntRef(particle);
		g_iGrabbingEntity[ent][3] = EntIndexToEntRef(particle2);
	}
}

//Peli script!
void TE_ParticleToAll(char[] Name, float origin[3]=NULL_VECTOR, float start[3]=NULL_VECTOR, float angles[3]=NULL_VECTOR, int entindex=-1, int attachtype=-1,int attachpoint=-1, bool resetParticles=true)
{
    // find string table
    int tblidx = FindStringTable("ParticleEffectNames");
    if (tblidx==INVALID_STRING_TABLE) 
    {
        LogError("Could not find string table: ParticleEffectNames");
        return;
    }
    
    // find particle index
    char tmp[256];
    int count = GetStringTableNumStrings(tblidx);
    int stridx = INVALID_STRING_INDEX;
    int i;
    for (i=0; i<count; i++)
    {
        ReadStringTable(tblidx, i, tmp, sizeof(tmp));
        if (StrEqual(tmp, Name, false))
        {
            stridx = i;
            break;
        }
    }
    if (stridx==INVALID_STRING_INDEX)
    {
        LogError("Could not find particle: %s", Name);
        return;
    }
    
    TE_Start("TFParticleEffect");
    TE_WriteFloat("m_vecOrigin[0]", origin[0]);
    TE_WriteFloat("m_vecOrigin[1]", origin[1]);
    TE_WriteFloat("m_vecOrigin[2]", origin[2]);
    TE_WriteFloat("m_vecStart[0]", start[0]);
    TE_WriteFloat("m_vecStart[1]", start[1]);
    TE_WriteFloat("m_vecStart[2]", start[2]);
    TE_WriteVector("m_vecAngles", angles);
    TE_WriteNum("m_iParticleSystemIndex", stridx);
    if (entindex!=-1)
    {
        TE_WriteNum("entindex", entindex);
    }
    if (attachtype!=-1)
    {
        TE_WriteNum("m_iAttachType", attachtype);
    }
    if (attachpoint!=-1)
    {
        TE_WriteNum("m_iAttachmentPointIndex", attachpoint);
    }
    TE_WriteNum("m_bResetParticles", resetParticles ? 1 : 0);    
    TE_SendToAll();
}