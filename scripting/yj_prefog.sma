/* ============================================================
 *  [义聚] PreFog 3.2.4-YJ
 *  ============================================================
 *  基于开源 PreFog 3.2.4 (作者 WessTorn) 魔改:
 *    1. 不在聊天框输出任何消息 (聊天框留给比赛系统)
 *    2. HUD 位置默认居中偏下 (X:-1.0, Y:0.55)
 *    3. HUD 使用独立频道 (pre_hud 1), 避免与其他 HUD 冲突
 *    4. 100AA 自动适配, 无需手动设置
 *
 *  功能:
 *    - 实时地速显示 (Speed)
 *    - FOG (Frames On Ground, 地面帧数) 统计
 *    - Prestrafe 类型检测 (Jump / Duck / Ladder / Slide)
 *    - FOG 质量评级 (Perfect / Good / Bad / VeryBad)
 *    - 速度颜色渐变 (默认色 -> 完美色)
 *    - 观战者同步查看目标玩家 HUD
 *
 *  依赖: ReHLDS / AMX Mod X 1.9.0+ / ReAPI / ReGameDLL
 * ============================================================ */

#include <amxmodx>
#include <reapi>
#include <fakemeta>

new g_iHudObject;
new bool:g_bOnOffPre[MAX_PLAYERS + 1];
new bool:g_bOnOffSpeed[MAX_PLAYERS + 1];

/* Prestrafe 类型枚举 */
enum PRE_TYPE {
	PRE_FOG = 0,   // 地面帧数型预加速
	PRE_JUMP,      // 跳跃预加速
	PRE_DUCK,      // 蹲跳预加速
	PRE_LADDER,    // 梯子预加速
	PRE_SLIDE      // 滑墙预加速
};

new g_szPreType[PRE_TYPE][] = {
	"",
	"[Jump]",
	"[Duck]",
	"[Ladder]",
	"[Slide]"
};

/* FOG 质量评级枚举 */
enum FOG_TYPE {
	FOG_VERYBAD = 0,  // 很差
	FOG_PERFECT,      // 完美
	FOG_GOOD,         // 良好
	FOG_BAD           // 较差
};

new g_szFogType[FOG_TYPE][] = {
	"[VB]",
	"[P]",
	"[G]",
	"[B]"
};

/* HUD 预加速数据结构 */
enum _:HUD_PRE {
	HUD_FOG,             // FOG 帧数
	FOG_TYPE:HUD_FOGTYPE, // FOG 质量评级
	Float:HUD_PREST,     // 预加速前速度
	Float:HUD_POST,      // 预加速后速度
	PRE_TYPE:HUD_TYPE    // 预加速类型
};

new g_eHudPre[MAX_PLAYERS + 1][HUD_PRE];

/* 速度颜色枚举 */
enum PRE_COLOR {
	CLR_WHITE = 0,
	CLR_GREEN,
	CLR_VIOLET,
	CLR_BLUE,
	CLR_RED,
	CLR_YELLOW
};

new PRE_COLOR:g_eSpeedColorDef[MAX_PLAYERS + 1];  // 默认速度颜色
new PRE_COLOR:g_eSpeedColorPerf[MAX_PLAYERS + 1]; // 完美速度颜色

/* 速度显示类型 */
enum SPEED_TYPE {
	ST_DEF = 0,   // 默认: "xxx u/s"
	ST_QUAKE,     // 雷神之锤风格: "xxx units/seconds"
	ST_NUM        // 纯数字
}

new SPEED_TYPE:g_eSpeedType[MAX_PLAYERS + 1];

new bool:g_isPre[MAX_PLAYERS + 1];          // 是否处于预加速状态
new g_iFog[MAX_PLAYERS + 1];                // 地面帧数计数
new bool:g_isOldGround[MAX_PLAYERS + 1];    // 上一帧是否在地面
new bool:g_isOldLadder[MAX_PLAYERS + 1];    // 上一帧是否在梯子
new bool:g_isSlide[MAX_PLAYERS + 1];        // 是否在滑墙
new bool:g_bInDuck[MAX_PLAYERS + 1];        // 是否蹲下
new Float:g_flOldSpeed[MAX_PLAYERS + 1];    // 上一帧速度
new Float:g_flPreSpeed[MAX_PLAYERS + 1];    // 预加速速度
new g_iPrevButtons[MAX_PLAYERS + 1];        // 上一帧按键
new bool:g_isSGS[MAX_PLAYERS + 1];          // 蹲跳地面状态标记

new g_isSpec[MAX_PLAYERS + 1];              // 观战目标
new Float:g_flHudTime[MAX_PLAYERS + 1];     // HUD 更新时间
new bool:g_isShowPre[MAX_PLAYERS + 1];      // 是否显示预加速
new Float:g_flPreShowTime[MAX_PLAYERS + 1]; // 预加速显示时间

/* CVAR 枚举 */
enum PRE_CVAR {
	Float:c_iPreHudX,   // HUD X 位置
	Float:c_iPreHudY,   // HUD Y 位置
	c_iPreHud,          // HUD 频道
}

new g_pCvar[PRE_CVAR];

public plugin_init() {
	register_plugin("PreFog", "3.2.4-YJ", "WessTorn + YJ");

	/* 绑定 CVAR (与 prefog.cfg 对应) */
	bind_pcvar_float(register_cvar("pre_x", "-1.0"),		g_pCvar[c_iPreHudX]);
	bind_pcvar_float(register_cvar("pre_y", "0.55"),		g_pCvar[c_iPreHudY]);
	bind_pcvar_num(register_cvar("pre_hud", "1"),			g_pCvar[c_iPreHud]);

	/* 注册命令 */
	register_clcmd("say /speedmenu", "cmdPreSpeedMenu");
	register_clcmd("say /speed", "cmdPreSpeedMenu");
	register_clcmd("say /premenu", "cmdPreSpeedMenu");
	register_clcmd("say /pre", "cmdPreSpeedMenu");
	register_clcmd("say /showpre", "cmdShowPre");
	register_clcmd("say /showspeed", "cmdShowSpeed");

	/* 挂钩 PM_Move (物理移动) */
	RegisterHookChain(RG_PM_Move, "rgPM_Move");

	/* 创建同步 HUD 对象 */
	g_iHudObject = CreateHudSyncObj();
}

public client_connect(id) {
	/* 玩家连接时初始化状态 */
	g_bOnOffPre[id] = true;        // 默认开启 PreFog 显示
	g_bOnOffSpeed[id] = true;      // 默认开启速度显示
	arrayset(g_eHudPre[id], 0, HUD_PRE);
	g_eSpeedColorDef[id] = CLR_WHITE;  // 默认速度颜色: 白色
	g_eSpeedColorPerf[id] = CLR_GREEN; // 完美速度颜色: 绿色
	g_eSpeedType[id] = ST_DEF;         // 速度类型: 默认
}

/* ============================================================
 *  核心逻辑: 物理移动钩子
 *  每帧调用, 检测预加速状态并计算 FOG
 * ============================================================ */
public rgPM_Move(id) {
	/* 如果玩家关闭了所有显示, 直接跳过 */
	if (!g_bOnOffPre[id] && !g_bOnOffSpeed[id])
		return HC_CONTINUE;

	/* 玩家死亡时, 处理观战逻辑 */
	if (!is_user_alive(id)) {
		if(get_member(id, m_iObserverLastMode) == OBS_ROAMING)
			return HC_CONTINUE;

		new iTarget = get_member(id, m_hObserverTarget);
		g_isSpec[id] = iTarget;   // 记录观战目标
		return HC_CONTINUE;
	} else {
		g_isSpec[id] = 0;
	}

	/* 检测是否在梯子 / 地面 */
	new bool:isLadder = bool:(get_entvar(id, var_movetype) == MOVETYPE_FLY);
	new bool:isGround = bool:(get_entvar(id, var_flags) & FL_ONGROUND);
	isGround = isGround || isLadder;

	/* 计算速度 */
	new Float:flVelocity[3]; get_entvar(id, var_velocity, flVelocity);
	new Float:flSpeed = vector_hor_length(flVelocity);  // 水平速度
	new Float:flSpeedDef = vector_length(flVelocity);   // 三维速度

	new iOldButtons = get_entvar(id, var_oldbuttons);
	new Float:flMaxSpeed = get_maxspeed(id);
	g_bInDuck[id] = bool:(get_entvar(id, var_flags) & FL_DUCKING);

	/* 显示当前速度 */
	show_prespeed(id, flSpeed, flSpeedDef);

	/* 在地面时: 累计 FOG 帧数 */
	if (isGround) {
		g_iFog[id]++;

		/* 第一帧记录是否蹲跳 */
		if (g_iFog[id] == 1) {
			g_isSGS[id] = g_bInDuck[id];
		}

		/* 刚落地时记录预加速速度 */
		if (!g_isOldGround[id]) {
			g_flPreSpeed[id] = flSpeed;
		}
	} else {
		/* 空中: 检测滑墙 */
		if (isUserSurfing(id)) {
			g_iFog[id] = 0;
			g_isSlide[id] = true;
		} else {
			/* 滑墙结束, 记录滑墙预加速 */
			if (g_isSlide[id]) {
				format_prest(id, PRE_SLIDE, g_flOldSpeed[id]);
				g_isSlide[id] = false;
			}
		}

		/* 离地第一帧记录离地速度 */
		if (g_iFog[id] == 1) {
			g_flOldSpeed[id] = flSpeed;
		}

		/* 从地面转为空中: 判断预加速类型 */
		if (g_isOldGround[id]) {
			/* 检测蹲跳 (松开蹲键且没按跳) */
			new bool:isDuck = !g_bInDuck[id] && !(iOldButtons & IN_JUMP) && g_iPrevButtons[id] & IN_DUCK;
			/* 检测跳跃 (按下跳键) */
			new bool:isJump = !isDuck && iOldButtons & IN_JUMP && !(g_iPrevButtons[id] & IN_JUMP);

			if (g_isOldLadder[id]) {
				/* 梯子预加速 */
				format_prest(id, PRE_LADDER, flSpeed);
			} else {
				/* FOG 帧数 > 10: 普通跳跃/蹲跳 */
				if (g_iFog[id] > 10) {
					if (isDuck) {
						format_prest(id, PRE_DUCK, g_flOldSpeed[id]);
					} 
					if (isJump) {
						format_prest(id, PRE_JUMP, g_flOldSpeed[id]);
					}
				} else {
					/* FOG 帧数 <= 10: 地面帧数型预加速, 评级质量 */
					new FOG_TYPE:iFogType;
					
					if (isJump) {
						/* 跳跃: 1帧且满速 = 完美 */
						if (flSpeed < flMaxSpeed && g_iFog[id] == 1)
							iFogType = FOG_PERFECT;

						if (!iFogType) {
							switch(g_iFog[id]) {
								case 1..2: iFogType = FOG_GOOD;
								case 3: iFogType = FOG_BAD;
								default: iFogType = FOG_VERYBAD;
							}
						}
						format_prest(id, PRE_FOG, g_flOldSpeed[id], g_flPreSpeed[id], g_iFog[id], iFogType);
					} else if (isDuck) {
						/* 蹲跳: 根据是否 SGS 评级 */
						if (g_isSGS[id]) {
							switch(g_iFog[id]) {
								case 3: iFogType = FOG_PERFECT;
								case 4: iFogType = FOG_GOOD;
								case 5: iFogType = FOG_BAD;
								default: iFogType = FOG_VERYBAD;
							}
						} else {
							switch(g_iFog[id]) {
								case 2: iFogType = FOG_PERFECT;
								case 3: iFogType = FOG_GOOD;
								case 4: iFogType = FOG_BAD;
								default: iFogType = FOG_VERYBAD;
							}
						}
						format_prest(id, PRE_FOG, g_flOldSpeed[id], g_flPreSpeed[id], g_iFog[id], iFogType);
					}
				}
			}
		}

		/* 重置地面状态 */
		g_isSGS[id] = false
		g_iFog[id] = 0;
	}

	/* 保存本帧状态供下一帧使用 */
	g_isOldGround[id] = isGround;
	g_isOldLadder[id] = isLadder;
	g_iPrevButtons[id] = iOldButtons;
	g_flOldSpeed[id] = flSpeed;

	return HC_CONTINUE;
}

/* ============================================================
 *  记录预加速信息到 HUD 数据结构
 * ============================================================ */
stock format_prest(id, PRE_TYPE:iPreType, Float:flPost, Float:flPre = 0.0, iFog = 0, FOG_TYPE:iType = FOG_VERYBAD) {
	g_isPre[id] = true;
	g_eHudPre[id][HUD_TYPE] = iPreType;
	g_eHudPre[id][HUD_POST] = flPost;
	g_eHudPre[id][HUD_PREST] = flPre;
	g_eHudPre[id][HUD_FOG] = iFog;
	g_eHudPre[id][HUD_FOGTYPE] = iType;
}

/* ============================================================
 *  显示速度 + 预加速 HUD
 * ============================================================ */
stock show_prespeed(id, Float:flSpeed, Float:flSpeedDef = 0.0) {
	new Float:g_flGameTime = get_gametime();
	
	/* 限制 HUD 刷新频率 (0.05秒) */
	if(g_flHudTime[id] + 0.05 > g_flGameTime)
		return;

	/* 预加速显示逻辑: 预加速后显示 1 秒 */
	if (!g_isShowPre[id]) {
		g_isShowPre[id] = g_isPre[id];
		if (g_isShowPre[id]) {
			g_flPreShowTime[id] = g_flGameTime + 1.0;
			g_isPre[id] = false;
		}
	} else {
		if (g_isPre[id]) {
			g_flPreShowTime[id] = g_flGameTime + 1.0;
			g_isPre[id] = false;
		}
	}

	/* 显示时间结束, 清除预加速信息 */
	if(g_flPreShowTime[id] < g_flGameTime) {
		g_isShowPre[id] = false;
		arrayset(g_eHudPre[id], 0, HUD_PRE);
	}

	/* 根据速度计算颜色渐变 (40~285 u/s) */
	new iColors[3];
	new Float:val;
	val = convertToRange(floatmin(flSpeed, 285.0), 40.0, 285.0);
	FormatRGBHud(id, val, iColors);

	/* 格式化速度文本 */
	new szSpeed[32];
	if (g_bOnOffSpeed[id]) {
		switch (g_eSpeedType[id]) {
			case ST_DEF: 	formatex(szSpeed, charsmax(szSpeed), "%.0f u/s", flSpeed);
			case ST_QUAKE: 	formatex(szSpeed, charsmax(szSpeed), "%.0f units/seconds^n%.0f velocity", flSpeedDef, flSpeed);
			case ST_NUM: 	formatex(szSpeed, charsmax(szSpeed), "%.0f", flSpeed);
		}
	}

	/* 给玩家自己和观战者显示 HUD */
	for (new i = 1; i <= MaxClients; i++) {
		if (i == id || g_isSpec[i] == id) {
			set_hudmessage(iColors[0], iColors[1], iColors[2], g_pCvar[c_iPreHudX], g_pCvar[c_iPreHudY], 0, 1.0, 0.15, 0.0, 0.0, g_pCvar[c_iPreHud]);

			/* 显示预加速信息 (速度 > 30 才显示) */
			if (g_bOnOffPre[i] && g_isShowPre[id] && (g_eHudPre[id][HUD_POST] > 30.0)) {
				switch (g_eHudPre[id][HUD_TYPE]) {
					case HUD_FOG: {
						ShowSyncHudMsg(i, g_iHudObject, "%s^n^n%d %s^n%.2f^n%.2f", g_bOnOffSpeed[i] ? szSpeed : "", g_eHudPre[id][HUD_FOG], g_szFogType[g_eHudPre[id][HUD_FOGTYPE]], g_eHudPre[id][HUD_PREST], g_eHudPre[id][HUD_POST]);
					}
					default: {
						ShowSyncHudMsg(i, g_iHudObject, "%s^n^n%s^n%.2f", g_bOnOffSpeed[i] ? szSpeed : "", g_szPreType[g_eHudPre[id][HUD_TYPE]], g_eHudPre[id][HUD_POST]);
					}
				}
			} else { 
				/* 只显示速度 */
				ShowSyncHudMsg(i, g_iHudObject, "%s", g_bOnOffSpeed[i] ? szSpeed : "");
			}
		}
	}

	g_flHudTime[id] = g_flGameTime;
}

/* ============================================================
 *  PreFog 设置菜单
 * ============================================================ */
public cmdPreSpeedMenu(id) {
	if (!is_user_connected(id))
		return;

	new hMenu = menu_create("\rPreFog menu:", "SpeedMenuCode");

	/* 速度开关 */
	if (g_bOnOffSpeed[id]) {
		menu_additem(hMenu, "Speed - \yon", "1");
	} else {
		menu_additem(hMenu, "Speed - \doff", "1");
	}

	/* PreFog 开关 */
	if (g_bOnOffPre[id]) {
		menu_additem(hMenu, "Prefog - \yon", "2");
	} else {
		menu_additem(hMenu, "Prefog - \doff", "2");
	}
	
	/* 速度类型 */
	switch (g_eSpeedType[id]) {
		case ST_DEF: 	menu_additem(hMenu, "Speed type - \ydefault", "3");
		case ST_QUAKE: 	menu_additem(hMenu, "Speed type - \yquake", "3");
		case ST_NUM: 	menu_additem(hMenu, "Speed type - \ynumber", "3");
	}

	/* 完美速度颜色 */
	switch (g_eSpeedColorPerf[id]) {
		case CLR_WHITE: 	menu_additem(hMenu, "Hud perfect color - \ywhite", "4");
		case CLR_GREEN:		menu_additem(hMenu, "Hud perfect color - \ygreen", "4");
		case CLR_VIOLET:	menu_additem(hMenu, "Hud perfect color - \yviolet", "4");
		case CLR_BLUE:		menu_additem(hMenu, "Hud perfect color - \yblue", "4");
		case CLR_RED:		menu_additem(hMenu, "Hud perfect color - \yred", "4");
		case CLR_YELLOW:	menu_additem(hMenu, "Hud perfect color - \yyellow", "4");
	}

	/* 默认速度颜色 */
	switch (g_eSpeedColorDef[id]) {
		case CLR_WHITE:		menu_additem(hMenu, "Hud default color - \ywhite", "5");
		case CLR_GREEN:		menu_additem(hMenu, "Hud default color - \ygreen", "5");
		case CLR_VIOLET:	menu_additem(hMenu, "Hud default color - \yviolet", "5");
		case CLR_BLUE:		menu_additem(hMenu, "Hud default color - \yblue", "5");
		case CLR_RED:		menu_additem(hMenu, "Hud default color - \yred", "5");
		case CLR_YELLOW:	menu_additem(hMenu, "Hud default color - \yyellow", "5");
	}

	menu_display(id, hMenu, 0);
}

/* 菜单回调 */
public SpeedMenuCode(id, hMenu, item) {
	if (item == MENU_EXIT) {
		return PLUGIN_HANDLED;
	}

	menu_destroy(hMenu);

	switch (item) {
		case 0: {
			cmdShowSpeed(id);
			cmdPreSpeedMenu(id);
		}
		case 1: {
			cmdShowPre(id);
			cmdPreSpeedMenu(id);
		}
		case 2: {
			switch (g_eSpeedType[id]) {
				case ST_DEF:	g_eSpeedType[id] = ST_QUAKE;
				case ST_QUAKE:	g_eSpeedType[id] = ST_NUM;
				case ST_NUM:	g_eSpeedType[id] = ST_DEF;
			}
			cmdPreSpeedMenu(id);
		}
		case 3: {
			switch (g_eSpeedColorPerf[id]) {
				case CLR_WHITE:		g_eSpeedColorPerf[id] = CLR_GREEN;
				case CLR_GREEN:		g_eSpeedColorPerf[id] = CLR_VIOLET;
				case CLR_VIOLET:	g_eSpeedColorPerf[id] = CLR_BLUE;
				case CLR_BLUE:		g_eSpeedColorPerf[id] = CLR_RED;
				case CLR_RED:		g_eSpeedColorPerf[id] = CLR_YELLOW;
				case CLR_YELLOW:	g_eSpeedColorPerf[id] = CLR_WHITE;
			}
			cmdPreSpeedMenu(id);
		}
		case 4: {
			switch (g_eSpeedColorDef[id]) {
				case CLR_WHITE:		g_eSpeedColorDef[id] = CLR_GREEN;
				case CLR_GREEN:		g_eSpeedColorDef[id] = CLR_VIOLET;
				case CLR_VIOLET:	g_eSpeedColorDef[id] = CLR_BLUE;
				case CLR_BLUE:		g_eSpeedColorDef[id] = CLR_RED;
				case CLR_RED:		g_eSpeedColorDef[id] = CLR_YELLOW;
				case CLR_YELLOW:	g_eSpeedColorDef[id] = CLR_WHITE;
			}
			cmdPreSpeedMenu(id);
		}
	}
	return PLUGIN_HANDLED;
}

/* 开关 PreFog 显示 (魔改: 不输出聊天消息, 避免与比赛系统冲突) */
public cmdShowPre(id) {
	g_bOnOffPre[id] = g_bOnOffPre[id] ? false : true;
}

/* 开关速度显示 (魔改: 不输出聊天消息, 避免与比赛系统冲突) */
public cmdShowSpeed(id) {
	g_bOnOffSpeed[id] = g_bOnOffSpeed[id] ? false : true;
}

/* ============================================================
 *  根据速度计算 HUD 颜色渐变
 * ============================================================ */
FormatRGBHud(id, const Float:val, colors[3]) {
	new iColorPerf[3], iColorDef[3];

	/* 完美速度颜色 RGB */
	switch (g_eSpeedColorPerf[id]) {
		case CLR_WHITE: {
			iColorPerf = {255, 255, 255};
		}
		case CLR_GREEN: {
			iColorPerf = {0, 250, 0};
		}
		case CLR_VIOLET: {
			iColorPerf = {250, 0, 250};
		}
		case CLR_BLUE: {
			iColorPerf = {0, 150, 250};
		}
		case CLR_RED: {
			iColorPerf = {250, 0, 0};
		}
		case CLR_YELLOW: {
			iColorPerf = {250, 250, 0};
		}
	}

	/* 默认速度颜色 RGB (完美预加速时切换为完美色) */
	switch (g_eSpeedColorDef[id]) {
		case CLR_WHITE: {
			iColorDef = g_eHudPre[id][HUD_FOGTYPE] == FOG_PERFECT && g_eHudPre[id][HUD_PREST] > 30.0 ? iColorPerf : {255, 255, 255};
		}
		case CLR_GREEN: {
			iColorDef = g_eHudPre[id][HUD_FOGTYPE] == FOG_PERFECT && g_eHudPre[id][HUD_PREST] > 30.0 ? iColorPerf : {0, 250, 0};
		}
		case CLR_VIOLET: {
			iColorDef = g_eHudPre[id][HUD_FOGTYPE] == FOG_PERFECT && g_eHudPre[id][HUD_PREST] > 30.0 ? iColorPerf : {250, 0, 250};
		}
		case CLR_BLUE: {
			iColorDef = g_eHudPre[id][HUD_FOGTYPE] == FOG_PERFECT && g_eHudPre[id][HUD_PREST] > 30.0 ? iColorPerf : {0, 150, 250};
		}
		case CLR_RED: {
			iColorDef = g_eHudPre[id][HUD_FOGTYPE] == FOG_PERFECT && g_eHudPre[id][HUD_PREST] > 30.0 ? iColorPerf : {250, 0, 0};
		}
		case CLR_YELLOW: {
			iColorDef = g_eHudPre[id][HUD_FOGTYPE] == FOG_PERFECT && g_eHudPre[id][HUD_PREST] > 30.0 ? iColorPerf : {250, 250, 0};
		}
	}

	/* 线性插值: 速度越高越接近完美色 */
	colors[0] = floatround(float(iColorPerf[0] - iColorDef[0]) * val + iColorDef[0]);
	colors[1] = floatround(float(iColorPerf[1] - iColorDef[1]) * val + iColorDef[1]);
	colors[2] = floatround(float(iColorPerf[2] - iColorDef[2]) * val + iColorDef[2]);
}

/* ============================================================
 *  工具函数
 * ============================================================ */

/* 将值映射到 [ToMin, ToMax] 范围 */
stock Float: convertToRange(Float:value, Float:FromMin, Float:FromMax, Float:ToMin = 0.0, Float:ToMax = 1.0) {
	return floatclamp((value-FromMin) / (FromMax-FromMin) * (ToMax-ToMin + ToMin), ToMin, ToMax);
}

/* 计算水平速度 (忽略 Z 轴) */
stock Float:vector_hor_length(Float:flVel[3]) {
	new Float:flNorma = floatpower(flVel[0], 2.0) + floatpower(flVel[1], 2.0);
	if (flNorma > 0.0)
		return floatsqroot(flNorma);
		
	return 0.0;
}

/* 获取玩家最大速度 (乘 1.2 作为预加速判定阈值) */
stock Float:get_maxspeed(id) {
	new Float:flMaxSpeed;
	flMaxSpeed = get_entvar(id, var_maxspeed);
	
	return flMaxSpeed * 1.2;
}

/* 检测玩家是否在滑墙 (Surfing) */
stock bool:isUserSurfing(id) {
	new Float:origin[3], Float:dest[3];
	get_entvar(id, var_origin, origin);
	
	dest[0] = origin[0];
	dest[1] = origin[1];
	dest[2] = origin[2] - 1.0;

	new Float:flFraction;

	engfunc(EngFunc_TraceHull, origin, dest, 0, 
		g_bInDuck[id] ? HULL_HEAD : HULL_HUMAN, id, 0);

	get_tr2(0, TR_flFraction, flFraction);

	if (flFraction >= 1.0) return false;
	
	get_tr2(0, TR_vecPlaneNormal, dest);

	return dest[2] <= 0.7;
}
