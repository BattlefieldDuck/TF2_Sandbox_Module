#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "BattlefieldDuck"
#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <build>

#pragma newdecls required

public Plugin myinfo = 
{
	name = "[TF2] SandBox - Elevator", 
	author = PLUGIN_AUTHOR, 
	description = "Elevator on Sandbox", 
	version = PLUGIN_VERSION, 
	url = "http://steamcommunity.com/id/battlefieldduck/"
};

Handle g_hEnabled;
int g_iElevatorIndex[MAXPLAYERS + 1];
int g_iElevatorAction[MAXPLAYERS + 1];

public void OnPluginStart()
{
	CreateConVar("sm_tf2sb_elevator_ver", PLUGIN_VERSION, "", FCVAR_SPONLY | FCVAR_NOTIFY);
	RegAdminCmd("sm_sbelevator", Command_ElevatorMenu, 0, "Build Elevator!");
	RegAdminCmd("sm_sblift", Command_ElevatorMenu, 0, "Build Elevator!");
	g_hEnabled = CreateConVar("sm_tf2sb_elevator", "1", "Enable the Elevator plugin?", 0, true, 0.0, true, 1.0);
}

public void OnMapStart()
{
	for (int i = 1; i <= MaxClients; i++) 
	{
		g_iElevatorIndex[i] = -1;
	}
}

public void OnClientPutInServer(int client)
{
	g_iElevatorIndex[client] = -1;
	g_iElevatorAction[client] = -1;
}

public void OnClientDisconnect(int client)
{
	g_iElevatorIndex[client] = -1;
	g_iElevatorAction[client] = -1;
}

public Action Command_ElevatorMenu(int client, int args) //HackMenu
{
	char menuinfo[255];
	Menu menu = new Menu(Handler_ElevatorMenu);
	
	Format(menuinfo, sizeof(menuinfo), "TF2 Sandbox - Elevator Control Panel v%s\n ", PLUGIN_VERSION);
	menu.SetTitle(menuinfo);
	
	if (IsValidEntity(g_iElevatorIndex[client]))
	{
		Format(menuinfo, sizeof(menuinfo), " Delete the Elevator", client);
		menu.AddItem("DELETE", menuinfo);
	}
	else
	{
		Format(menuinfo, sizeof(menuinfo), " Spawn a Elevator", client);
		menu.AddItem("BUILD", menuinfo);
	}
	
	if (IsValidEntity(g_iElevatorIndex[client]))
	{
		Format(menuinfo, sizeof(menuinfo), " Set Current position as lowest position", client);
		menu.AddItem("SETLOWEST", menuinfo);
		Format(menuinfo, sizeof(menuinfo), " Set Current position as highest position", client);
		menu.AddItem("SETHIGHEST", menuinfo);
		Format(menuinfo, sizeof(menuinfo), " Go Up", client);
		menu.AddItem("UP", menuinfo);
		Format(menuinfo, sizeof(menuinfo), " Go Down", client);
		menu.AddItem("DOWN", menuinfo);
		Format(menuinfo, sizeof(menuinfo), " Stop", client);
		menu.AddItem("STOP", menuinfo);
	}
	else
	{
		Format(menuinfo, sizeof(menuinfo), " Set Current position as lowest position", client);
		menu.AddItem("SETLOWEST", menuinfo, ITEMDRAW_DISABLED);
		Format(menuinfo, sizeof(menuinfo), " Set Current position as highest position", client);
		menu.AddItem("SETHIGHEST", menuinfo, ITEMDRAW_DISABLED);
		Format(menuinfo, sizeof(menuinfo), " Go Up", client);
		menu.AddItem("UP", menuinfo, ITEMDRAW_DISABLED);
		Format(menuinfo, sizeof(menuinfo), " Go Down", client);
		menu.AddItem("DOWN", menuinfo, ITEMDRAW_DISABLED);
		Format(menuinfo, sizeof(menuinfo), " Stop", client);
		menu.AddItem("STOP", menuinfo, ITEMDRAW_DISABLED);
	}
	menu.ExitBackButton = false;
	menu.ExitButton = true;
	menu.Display(client, -1);
	return Plugin_Handled;
}

public int Handler_ElevatorMenu(Menu menu, MenuAction action, int client, int selection)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(selection, info, sizeof(info));
		
		if (StrEqual(info, "BUILD"))
		{
			float fAimPos[3];
			if (GetAimOrigin(client, fAimPos))
			{
				g_iElevatorIndex[client] = BuildElevator(client, fAimPos);			
			}
		}
		else if (StrEqual(info, "DELETE"))
		{
			if (IsValidEntity(g_iElevatorIndex[client]))
			{
				AcceptEntityInput(g_iElevatorIndex[client], "kill");
				g_iElevatorIndex[client] = -1;
			}
		}
		else if (StrEqual(info, "UP"))
		{
			if (IsValidEntity(g_iElevatorIndex[client]))
			{
				g_iElevatorAction[client] = 1;
			}
		}
		else if (StrEqual(info, "DOWN"))
		{
			if (IsValidEntity(g_iElevatorIndex[client]))
			{
				g_iElevatorAction[client] = 2;
			}
		}	
		else if (StrEqual(info, "STOP"))
		{
			if (IsValidEntity(g_iElevatorIndex[client]))
			{
				g_iElevatorAction[client] = -1;
			}
		}			
		Command_ElevatorMenu(client, -1);
	}
	else if (action == MenuAction_Cancel)
	{
		if (selection == MenuCancel_ExitBack)
		{
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)//@
{
	if (!IsValidClient(client))
		return;
	
	if(IsValidEntity(g_iElevatorIndex[client]))
	{
		if(g_iElevatorAction[client] == 1)
		{
			float fOrigin[3];
			GetEntPropVector(g_iElevatorIndex[client], Prop_Send, "m_vecOrigin", fOrigin);
			fOrigin[2] += 2.0;
			TeleportEntity(g_iElevatorIndex[client], fOrigin, NULL_VECTOR, NULL_VECTOR);
			//TeleportEntity(g_iElevatorIndex[client], NULL_VECTOR, NULL_VECTOR, fOrigin);
		}
		else if(g_iElevatorAction[client] == 2)
		{
			float fOrigin[3];
			GetEntPropVector(g_iElevatorIndex[client], Prop_Send, "m_vecOrigin", fOrigin);
			fOrigin[2] -= 2.0;
			TeleportEntity(g_iElevatorIndex[client], fOrigin, NULL_VECTOR, NULL_VECTOR);
			//TeleportEntity(g_iElevatorIndex[client], NULL_VECTOR, NULL_VECTOR, fOrigin);
		}
	}
}





//Stock
stock bool IsValidClient(int client)
{
	if (client <= 0)return false;
	if (client > MaxClients)return false;
	if (!IsClientConnected(client))return false;
	return IsClientInGame(client);
}

stock bool GetAimOrigin(int client, float hOrigin[3])
{
	float vAngles[3], fOrigin[3];
	GetClientEyePosition(client, fOrigin);
	GetClientEyeAngles(client, vAngles);
	
	Handle trace = TR_TraceRayFilterEx(fOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer);
	
	if (TR_DidHit(trace))
	{
		TR_GetEndPosition(hOrigin, trace);
		CloseHandle(trace);
		return true;
	}
	
	CloseHandle(trace);
	return false;
}

public bool TraceEntityFilterPlayer(int entity, int contentsMask)
{
	return entity > GetMaxClients();
}

int BuildElevator(int iBuilder, float fOrigin[3])
{
	if (GetClientSpawnedEntities(iBuilder) >= GetClientMaxHoldEntities())
	{
		ClientCommand(iBuilder, "playgamesound \"%s\"", "buttons/button10.wav");
		Build_PrintToChat(iBuilder, "You've hit the prop limit!");
		PrintCenterText(iBuilder, "You've hit the prop limit!");
		return 0;
	}
	
	char szModel[100];
	strcopy(szModel, sizeof(szModel), "models/props_lab/freightelevator.mdl"); //body
	
	int iElevatorBody = CreateEntityByName("prop_dynamic_override");
	if (iElevatorBody > MaxClients && IsValidEntity(iElevatorBody))
	{
		SetEntProp(iElevatorBody, Prop_Send, "m_nSolidType", 6);
		SetEntProp(iElevatorBody, Prop_Data, "m_nSolidType", 6);
		//Build_RegisterEntityOwner(iElevatorBody, iBuilder);
		
		if (!IsModelPrecached(szModel))
			PrecacheModel(szModel);
		
		SetEntityModel(iElevatorBody, szModel);
		
		TeleportEntity(iElevatorBody, fOrigin, NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(iElevatorBody);
	}
	
	strcopy(szModel, sizeof(szModel), "models/props_trainyard/crane_platform001.mdl"); //ground
	int iElevator = CreateEntityByName("prop_dynamic_override");
	if (iElevator > MaxClients && IsValidEntity(iElevator))
	{
		SetEntProp(iElevator, Prop_Send, "m_nSolidType", 6);
		SetEntProp(iElevator, Prop_Data, "m_nSolidType", 6);
		SetEntPropFloat(iElevator, Prop_Send, "m_flModelScale", 0.42);  
		Build_RegisterEntityOwner(iElevator, iBuilder);
		
		if (!IsModelPrecached(szModel))
			PrecacheModel(szModel);
		
		SetEntityModel(iElevator, szModel);
		
		TeleportEntity(iElevator, fOrigin, NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(iElevator);
				
		char Buffer[64];
		Format(Buffer, sizeof(Buffer), "Entity%d", iElevator);
		DispatchKeyValue(iElevator, "targetname", Buffer);
		SetVariantString(Buffer);
		AcceptEntityInput(iElevatorBody, "SetParent");
		Build_PrintToChat(iBuilder, "The elevator built.");
		return iElevator;
	}
	if(IsValidEntity(iElevator))	AcceptEntityInput(iElevator, "kill");
	if(IsValidEntity(iElevatorBody))	AcceptEntityInput(iElevatorBody, "kill");
	Build_PrintToChat(iBuilder, "Fail to build elevator.");
	return 0;
}

int GetClientSpawnedEntities(int client)
{
	char szClass[32];
	int iCount = 0;
	for (int i = MaxClients; i < MAX_HOOK_ENTITIES; i++)if (IsValidEdict(i))
	{
		GetEdictClassname(i, szClass, sizeof(szClass));
		if ((StrContains(szClass, "prop_dynamic") >= 0 || StrContains(szClass, "prop_physics") >= 0) && !StrEqual(szClass, "prop_ragdoll") && Build_ReturnEntityOwner(i) == client)
			iCount++;
	}
	return iCount;
}

int GetClientMaxHoldEntities()
{
	Handle iMax = FindConVar("sbox_maxpropsperplayer");
	return GetConVarInt(iMax);
} 