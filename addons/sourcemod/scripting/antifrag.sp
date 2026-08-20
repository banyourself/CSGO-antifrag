#pragma semicolon 1
#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <colors>

#pragma newdecls required

// CS:GO knife damage is reduced to 85% against kevlar. hns_f_knife_damage
// represents health damage, so compensate before the engine applies armor.
const float CSGO_KNIFE_ARMOR_RATIO = 0.85;
const float CSGO_ARMOR_BONUS_RATIO = 0.5;
const float MAX_OPPOSING_KNIFE_HEALTH_DAMAGE = 50.0;

#define PLUGIN_VERSION	"1.0.13"

ConVar h_enable_plugin;
ConVar h_knife_damage;
ConVar g_notify2;
ConVar h_cooldown;
ConVar h_e_cooldown_all;
ConVar g_transparent;
ConVar g_ctransparent;
ConVar g_cbodyR;
ConVar g_cbodyG;
ConVar g_cbodyB;
ConVar g_notify;
ConVar gcv_force = null;

Handle g_bTimer[MAXPLAYERS + 1];
Handle g_bTimer2[MAXPLAYERS + 1];

bool RoundEnd;
bool h_benable_plugin = false;
bool g_bLateLoaded = false;
bool g_btransparent = false;

float h_fknife_damage;
float h_bcooldown;

int g_bnotify2 = 0;
int g_bnotify = 0;
int h_be_cooldown_all = 0;
int g_bctransparent;
int g_bcbodyR;
int g_bcbodyG;
int g_bcbodyB;
int g_iLastAnnouncementAttacker[MAXPLAYERS + 1];
float g_fLastAnnouncementTime[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "[HNS] Anti-Frag",
	author = "Gold KingZ + Kevin",
	description = "Caps opposing-team knife damage and announces knife actions.",
	version = PLUGIN_VERSION,
	url = ""
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int length)
{
	if (GetEngineVersion() != Engine_CSGO && GetEngineVersion() != Engine_CSS)
	{
		strcopy(error, length, "HNS-Anti-Frag supports only CS:GO and CS:S.");
		return APLRes_SilentFailure;
	}

	MarkNativeAsOptional("HNS_IsOvaActive");

	g_bLateLoaded = late;
	return APLRes_Success;
}

// hidenseek exposes this while the One Versus All gamemode is running.
// Optional, so this plugin still loads without hidenseek.
native int HNS_IsOvaActive();

bool IsOvaGameModeActive()
{
	return (GetFeatureStatus(FeatureType_Native, "HNS_IsOvaActive") == FeatureStatus_Available && HNS_IsOvaActive() != 0);
}

public void OnPluginStart()
{
	EnsureTranslationFile();
	LoadTranslations("HNS-Anti-Frag.phrases");
	
	CreateConVar("hns_f_version", PLUGIN_VERSION, "HNS-Anti-Frag Plugin Version", FCVAR_NOTIFY|FCVAR_DONTRECORD);

	h_enable_plugin = CreateConVar("hns_f_enable_plugin", "1", "Enable HNS-Anti-Frag?\n1= Yes\n0= No", _, true, 0.0, true, 1.0);
	h_knife_damage = CreateConVar("hns_f_knife_damage", "50.0", "Health damage any opposing-team knife hit deals, including backstabs and armor. Maximum: 50.", _, true, 1.0, true, MAX_OPPOSING_KNIFE_HEALTH_DAMAGE);
	h_cooldown = CreateConVar("hns_f_knife_cooldown", "5.0", "Cooldown duration in seconds after a Counter-Terrorist stabs a Terrorist.", _, true, 0.0, true, 60.0);
	h_e_cooldown_all = CreateConVar("hns_f_ct_cooldown", "1", "CT knife cooldown mode. 0 = off, 1 = stabbed Terrorist receives protection, 2 = both the stabbed Terrorist and attacker are on cooldown.", _, true, 0.0, true, 2.0);
	g_transparent = CreateConVar("hns_f_enable_transparent", "0", "Apply the configured render color during a stab cooldown. 1 = enabled, 0 = disabled.", _, true, 0.0, true, 1.0);
	g_ctransparent = CreateConVar("hns_f_transparent", "120", "Alpha used for the cooldown render effect. 255 = opaque.", _, true, 0.0, true, 255.0);
	g_cbodyR = CreateConVar("hns_f_color_r", "255", "Red channel for the cooldown render effect.", _, true, 0.0, true, 255.0);
	g_cbodyG = CreateConVar("hns_f_color_g", "0", "Green channel for the cooldown render effect.", _, true, 0.0, true, 255.0);
	g_cbodyB = CreateConVar("hns_f_color_b", "0", "Blue channel for the cooldown render effect.", _, true, 0.0, true, 255.0);
	g_notify = CreateConVar("hns_f_notify", "1", "Cooldown chat notifications. 0 = off, 1 = attacker, 2 = victim, 3 = both.", _, true, 0.0, true, 3.0);
	g_notify2 = CreateConVar("hns_f_notify_annoc", "1", "Announce knife stabs and kills in chat. 1 = enabled, 0 = disabled.", _, true, 0.0, true, 1.0);

	gcv_force = FindConVar("sv_disable_immunity_alpha");
	if (gcv_force != null)
		gcv_force.AddChangeHook(OnImmunityAlphaChanged);
	
	HookConVarChange(h_enable_plugin, OnSettingsChanged);
	HookConVarChange(h_knife_damage, OnSettingsChanged);
	HookConVarChange(h_cooldown, OnSettingsChanged);
	HookConVarChange(h_e_cooldown_all, OnSettingsChanged);
	HookConVarChange(g_transparent, OnSettingsChanged);
	HookConVarChange(g_ctransparent, OnSettingsChanged);
	HookConVarChange(g_cbodyR, OnSettingsChanged);
	HookConVarChange(g_cbodyG, OnSettingsChanged);
	HookConVarChange(g_cbodyB, OnSettingsChanged);
	HookConVarChange(g_notify, OnSettingsChanged);
	HookConVarChange(g_notify2, OnSettingsChanged);
	
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("round_start", Event_RoundStart);
	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
	HookEvent("player_death", Event_player_death);
	
	if (g_bLateLoaded) 
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i)) 
			{
				OnClientPutInServer(i);
			}
		}
	}
	
	AutoExecConfig(true, "HNS-Anti-Frag");
}

void EnsureTranslationFile()
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "translations/HNS-Anti-Frag.phrases.txt");
	if (FileExists(path))
		return;

	File file = OpenFile(path, "w");
	if (file == null)
	{
		LogError("[HNS-Anti-Frag] Could not create %s", path);
		return;
	}

	file.WriteLine("\"Phrases\"");
	file.WriteLine("{");
	file.WriteLine("\t\"CooldownTNotify\"");
	file.WriteLine("\t{");
	file.WriteLine("\t\t\"#format\"\t\t\"{1:.1f}\"");
	file.WriteLine("\t\t\"en\"\t\t\t\"{default}[{red}Kevin{default}] You have {purple}{1} seconds{default} of protection.\"");
	file.WriteLine("\t}");
	file.WriteLine("\t\"CooldownCTNotify\"");
	file.WriteLine("\t{");
	file.WriteLine("\t\t\"#format\"\t\t\"{1:.1f},{2:N}\"");
	file.WriteLine("\t\t\"en\"\t\t\t\"{default}[{red}Kevin{default}] Wait {purple}{1} seconds{default} before stabbing {teamcolor}{2}{default}.\"");
	file.WriteLine("\t}");
	file.WriteLine("\t\"CooldownCTNotifyTeamT\"");
	file.WriteLine("\t{");
	file.WriteLine("\t\t\"#format\"\t\t\"{1:.1f}\"");
	file.WriteLine("\t\t\"en\"\t\t\t\"{default}[{red}Kevin{default}] Wait {purple}{1} seconds{default} before stabbing terrorists.\"");
	file.WriteLine("\t}");
	file.WriteLine("}");
	file.Close();
}

public void OnImmunityAlphaChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (g_btransparent && StrEqual(newValue, "0"))
		convar.BoolValue = true;
}

public void OnConfigsExecuted()
{
	h_benable_plugin = h_enable_plugin.BoolValue;
	h_fknife_damage = ClampKnifeHealthDamage(h_knife_damage.FloatValue);
	h_bcooldown = h_cooldown.FloatValue;
	h_be_cooldown_all = h_e_cooldown_all.IntValue;
	g_btransparent = g_transparent.BoolValue;
	g_bctransparent = g_ctransparent.IntValue;
	g_bcbodyR = g_cbodyR.IntValue;
	g_bcbodyG = g_cbodyG.IntValue;
	g_bcbodyB = g_cbodyB.IntValue;
	g_bnotify = g_notify.IntValue;
	g_bnotify2 = g_notify2.IntValue;
}

public void OnSettingsChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(convar == h_enable_plugin)
		h_benable_plugin = h_enable_plugin.BoolValue;
	else if(convar == h_knife_damage)
		h_fknife_damage = ClampKnifeHealthDamage(h_knife_damage.FloatValue);
	else if(convar == h_cooldown)
	{
		h_bcooldown = h_cooldown.FloatValue;
		// Cooldown disabled: kill the running protection timers too, otherwise
		// each one keeps blocking stabs for up to its full original duration.
		if (h_bcooldown <= 0.0)
			ClearActiveCooldowns();
	}
	else if(convar == h_e_cooldown_all)
	{
		h_be_cooldown_all = h_e_cooldown_all.IntValue;
		if (h_be_cooldown_all == 0)
			ClearActiveCooldowns();
	}
	else if(convar == g_transparent)
	{
		g_btransparent = g_transparent.BoolValue;
		if (g_btransparent && gcv_force != null)
			gcv_force.BoolValue = true;
	}
	else if(convar == g_ctransparent)
		g_bctransparent = g_ctransparent.IntValue;
	else if(convar == g_cbodyR)
		g_bcbodyR = g_cbodyR.IntValue;
	else if(convar == g_cbodyG)
		g_bcbodyG = g_cbodyG.IntValue;
	else if(convar == g_cbodyB)
		g_bcbodyB = g_cbodyB.IntValue;
	else if(convar == g_notify)
		g_bnotify = g_notify.IntValue;
	else if(convar == g_notify2)
		g_bnotify2 = g_notify2.IntValue;
}

void ClearActiveCooldowns()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (g_bTimer[client] != null)
		{
			delete g_bTimer[client];
			g_bTimer[client] = null;
		}
		if (g_bTimer2[client] != null)
		{
			delete g_bTimer2[client];
			g_bTimer2[client] = null;
		}
		if (IsClientInGame(client))
		{
			SetEntityRenderMode(client, RENDER_NORMAL);
			SetEntityRenderColor(client, 255, 255, 255, 255);
		}
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OneHitDamage);
	// This late player-damage path applies the final knife cap after normal
	// OnTakeDamage modifiers, including third-party perk plugins.
	SDKHook(client, SDKHook_OnTakeDamageAlive, OneHitDamageAlive);
}

public void OnMapStart()
{
	RoundEnd = false;
	ClearActiveCooldowns();
}

public void OnClientDisconnect(int client)
{
	SDKUnhook(client, SDKHook_OnTakeDamage, OneHitDamage);
	SDKUnhook(client, SDKHook_OnTakeDamageAlive, OneHitDamageAlive);
	g_iLastAnnouncementAttacker[client] = 0;
	g_fLastAnnouncementTime[client] = 0.0;
	if (g_bTimer[client] != null)
	{
		delete g_bTimer[client];
		g_bTimer[client] = null;
	}
	if (g_bTimer2[client] != null)
	{
		delete g_bTimer2[client];
		g_bTimer2[client] = null;
	}
}
public Action Event_player_death(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	// Only announce a kill that actually landed, not one some other HNS rule
	// blocked.
	if (h_benable_plugin && g_bnotify2 > 0 && !RoundEnd
		&& IsValidClient(victim) && IsValidClient(attacker) && attacker != victim
		&& GetClientTeam(attacker) != GetClientTeam(victim))
	{
		char weapon[64];
		event.GetString("weapon", weapon, sizeof(weapon));
		if (StrContains(weapon, "knife", false) != -1)
			AnnounceKnifeAction(attacker, victim, true);
	}
	if (victim >= 1 && victim <= MaxClients)
	{
		if (g_bTimer[victim] != null)
		{
			delete g_bTimer[victim];
			g_bTimer[victim] = null;
		}
		SetEntityRenderMode(victim, RENDER_NORMAL);
		SetEntityRenderColor(victim, 255, 255, 255, 255);
	}
	g_iLastAnnouncementAttacker[victim] = 0;
	g_fLastAnnouncementTime[victim] = 0.0;
	return Plugin_Continue;
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	if (!h_benable_plugin || g_bnotify2 <= 0 || RoundEnd || GetEventInt(event, "dmg_health") <= 0)
		return;

	// Lethal knife hits are announced by player_death. This event handles only
	// confirmed nonlethal health damage.
	if (GetEventInt(event, "health") <= 0)
		return;

	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	if (!IsValidClient(victim) || !IsValidClient(attacker) || attacker == victim
		|| GetClientTeam(attacker) == GetClientTeam(victim))
		return;

	char weapon[64];
	event.GetString("weapon", weapon, sizeof(weapon));
	if (StrContains(weapon, "knife", false) != -1)
		AnnounceKnifeAction(attacker, victim, false);
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{	
	RoundEnd = true;
	ClearActiveCooldowns();
	return Plugin_Continue;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) 
{
	RoundEnd = false;
}

// The client plays the "HudChat.Message" tick only for a SayText2 whose chat
// flag is set, and PrintToChat / colors.inc's CSayText2 both set it. Every
// message this plugin prints goes out with the flag cleared, so the text still
// lands in chat without the sound.
void SilentSayText2(int client, int author, const char[] message)
{
	Handle buffer = StartMessageOne("SayText2", client, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS);
	if (buffer == null)
		return;

	if (GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available && GetUserMessageType() == UM_Protobuf)
	{
		PbSetInt(buffer, "ent_idx", author);
		PbSetBool(buffer, "chat", false);
		PbSetString(buffer, "msg_name", message);
		for (int i = 0; i < 4; i++)
			PbAddString(buffer, "params", "");
	}
	else
	{
		BfWriteByte(buffer, author);
		BfWriteByte(buffer, false);
		BfWriteString(buffer, message);
	}

	EndMessage();
}

// Silent replacement for CPrintToChat / CPrintToChatEx: same {tag} handling
// (CFormat), no tick. Pass NO_INDEX as author when there is no {teamcolor}.
void QuietPrintToChat(int client, int author, const char[] format, any ...)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
		return;

	char pattern[MAX_MESSAGE_LENGTH];
	char message[MAX_MESSAGE_LENGTH];

	SetGlobalTransTarget(client);
	FormatEx(pattern, sizeof(pattern), "\x01%s", format);
	VFormat(message, sizeof(message), pattern, 4);

	int index = CFormat(message, sizeof(message), author);
	SilentSayText2(client, (index == NO_INDEX) ? client : index, message);
}

void GetKnifeAnnouncementColor(int client, char[] color, int maxlen)
{
	switch (GetClientTeam(client))
	{
		// Use static CS:GO colors. The dynamic {blue}/{orange} tags in
		// colors.inc cannot safely render two differently colored names.
		case CS_TEAM_CT: strcopy(color, maxlen, "\x0B");
		case CS_TEAM_T: strcopy(color, maxlen, "\x10");
		default: strcopy(color, maxlen, "\x08");
	}
}

void GetSafeClientName(int client, char[] name, int maxlen)
{
	GetClientName(client, name, maxlen);
	ReplaceString(name, maxlen, "{", "(", false);
	ReplaceString(name, maxlen, "}", ")", false);
	for (int i = 0; name[i] != '\0'; i++)
	{
		if (name[i] > 0 && name[i] <= 0x10)
			name[i] = '?';
	}
}

void AnnounceKnifeAction(int attacker, int victim, bool killed)
{
	if (g_bnotify2 <= 0 || !IsValidClient(attacker) || !IsValidClient(victim))
		return;

	float now = GetGameTime();
	if (!killed && g_iLastAnnouncementAttacker[victim] == attacker && now - g_fLastAnnouncementTime[victim] < 0.2)
		return;

	g_iLastAnnouncementAttacker[victim] = attacker;
	g_fLastAnnouncementTime[victim] = now;

	char attackerName[MAX_NAME_LENGTH];
	char victimName[MAX_NAME_LENGTH];
	char attackerColor[4];
	char victimColor[4];
	GetSafeClientName(attacker, attackerName, sizeof(attackerName));
	GetSafeClientName(victim, victimName, sizeof(victimName));
	GetKnifeAnnouncementColor(attacker, attackerColor, sizeof(attackerColor));
	GetKnifeAnnouncementColor(victim, victimColor, sizeof(victimColor));

	char message[256];
	FormatEx(message, sizeof(message), " \x01\x0B\x01[\x07Kevin\x01] %s%s\x01 %s %s%s\x01",
		attackerColor, attackerName, killed ? "killed" : "stabbed", victimColor, victimName);

	// Send the chat user-message directly. CPrintToChatAll can fall back to
	// PrintToChat and turns the unsupported second team color green.
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && !IsFakeClient(client))
			SilentSayText2(client, attacker, message);
	}
}

float ClampKnifeHealthDamage(float healthDamage)
{
	if (healthDamage < 1.0)
		return 1.0;
	if (healthDamage > MAX_OPPOSING_KNIFE_HEALTH_DAMAGE)
		return MAX_OPPOSING_KNIFE_HEALTH_DAMAGE;
	return healthDamage;
}

bool IsKnifeEntity(int entity)
{
	if (entity <= MaxClients || !IsValidEntity(entity))
		return false;

	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));
	return StrContains(classname, "knife", false) != -1;
}

bool IsKnifeDamage(int attacker, int damageWeapon = -1)
{
	if (IsKnifeEntity(damageWeapon))
		return true;

	if (!IsValidClient(attacker))
		return false;

	return IsKnifeEntity(GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon"));
}

bool IsOpposingKnifeHit(int victim, int attacker, int damageWeapon = -1)
{
	if (!h_benable_plugin || RoundEnd || !IsValidClient(victim) || !IsValidClient(attacker)
		|| attacker == victim || !IsKnifeDamage(attacker, damageWeapon))
	{
		return false;
	}

	int attackerTeam = GetClientTeam(attacker);
	int victimTeam = GetClientTeam(victim);
	return (attackerTeam == CS_TEAM_CT && victimTeam == CS_TEAM_T)
		|| (attackerTeam == CS_TEAM_T && victimTeam == CS_TEAM_CT);
}

// Converts the configured health loss into the raw damage that CS:GO needs
// before kevlar. The second branch handles nearly depleted armor, where the
// normal armor-ratio calculation would otherwise overshoot the configured hit.
float GetRawKnifeDamageForHealthDamage(int victim, float healthDamage)
{
	int armor = GetClientArmor(victim);
	if (armor <= 0)
		return healthDamage;

	float rawDamage = healthDamage / CSGO_KNIFE_ARMOR_RATIO;
	float armorCost = (rawDamage - healthDamage) * CSGO_ARMOR_BONUS_RATIO;
	if (armorCost > float(armor))
		rawDamage = healthDamage + float(armor) / CSGO_ARMOR_BONUS_RATIO;

	return rawDamage;
}

public Action OneHitDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if (!IsOpposingKnifeHit(victim, attacker))
		return Plugin_Continue;

	int attackerTeam = GetClientTeam(attacker);
	bool ctAgainstT = attackerTeam == CS_TEAM_CT;

	// Check protection before touching damage. Chat comes later, off the engine
	// damage events, so a blocked hit never gets announced.
	if (ctAgainstT && (g_bTimer[victim] != null || g_bTimer2[attacker] != null))
		return Plugin_Handled;

	// Override every opposing-team knife hit, including the engine's
	// high-damage backstab. The raw damage is compensated first so armor
	// cannot turn a configured 50-damage stab into a 42-damage stab.
	float healthDamage = ClampKnifeHealthDamage(h_fknife_damage);
	damage = GetRawKnifeDamageForHealthDamage(victim, healthDamage);

	// Cooldown stays CT on T, that is the HNS mechanic. T knife hits get capped
	// too but do not start their own cooldown.
	if (!ctAgainstT)
		return Plugin_Changed;

	if (h_be_cooldown_all == 0 || h_bcooldown <= 0.0)
		return Plugin_Changed;

	// OVA passes the T role to whoever lands the stab, and that new T has to be
	// killable immediately. No post-stab protection while it is running.
	if (IsOvaGameModeActive())
		return Plugin_Changed;

	if (g_bnotify == 1 || g_bnotify == 3)
	{
		if (h_be_cooldown_all == 1)
			QuietPrintToChat(attacker, victim, "%t", "CooldownCTNotify", h_bcooldown, victim);
		else
			QuietPrintToChat(attacker, NO_INDEX, "%t", "CooldownCTNotifyTeamT", h_bcooldown);
	}
	if (g_bnotify == 2 || g_bnotify == 3)
		QuietPrintToChat(victim, NO_INDEX, "%t", "CooldownTNotify", h_bcooldown);

	int victimUserId = GetClientUserId(victim);
	if (g_bTimer[victim] != null)
		delete g_bTimer[victim];
	g_bTimer[victim] = CreateTimer(h_bcooldown, Timer_EndVictimCooldown, victimUserId);

	if (h_be_cooldown_all == 2)
	{
		int attackerUserId = GetClientUserId(attacker);
		if (g_bTimer2[attacker] != null)
			delete g_bTimer2[attacker];
		g_bTimer2[attacker] = CreateTimer(h_bcooldown, Timer_EndAttackerCooldown, attackerUserId);
	}

	if (g_btransparent)
	{
		SetEntityRenderMode(victim, RENDER_TRANSALPHA);
		SetEntityRenderColor(victim, g_bcbodyR, g_bcbodyG, g_bcbodyB, g_bctransparent);
	}
	return Plugin_Changed;
}

public Action OneHitDamageAlive(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
	if (!IsOpposingKnifeHit(victim, attacker, weapon))
		return Plugin_Continue;

	// This is the final editable player-damage path. Armor compensation belongs
	// only in the earlier general hook. Applying it here makes a 50-health cap
	// land as 58 damage, so use the configured health cap directly.
	damage = ClampKnifeHealthDamage(h_fknife_damage);
	return Plugin_Changed;
}

public Action Timer_EndVictimCooldown(Handle timer, any userId)
{
	int victim = GetClientOfUserId(userId);
	if (!IsValidClient(victim) || g_bTimer[victim] != timer)
		return Plugin_Stop;

	g_bTimer[victim] = null;
	SetEntityRenderMode(victim, RENDER_NORMAL);
	SetEntityRenderColor(victim, 255, 255, 255, 255);
	return Plugin_Stop;
}

public Action Timer_EndAttackerCooldown(Handle timer, any userId)
{
	int attacker = GetClientOfUserId(userId);
	if (!IsValidClient(attacker) || g_bTimer2[attacker] != timer)
		return Plugin_Stop;

	g_bTimer2[attacker] = null;
	return Plugin_Stop;
}

static bool IsValidClient(int client)
{
	return client >= 1 && client <= MaxClients && IsClientInGame(client);
}
