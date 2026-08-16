# [义聚] PreFog 3.2.4-YJ

> 基于开源 [PreFog 3.2.4](https://github.com/OpenHNS/PreFog)（作者 WessTorn）魔改的 HNS 预加速辅助插件，适用于 Counter-Strike 1.6。

![AMX Mod X](https://img.shields.io/badge/AMX_Mod_X-1.9.0+-blue)
![ReAPI](https://img.shields.io/badge/ReAPI-last-orange)
![ReGameDLL](https://img.shields.io/badge/ReGameDLL-last-orange)
![Version](https://img.shields.io/badge/Version-3.2.4--YJ-green)
![License](https://img.shields.io/badge/License-GPLv3-success)

---

## 一、它是怎么形成的

本插件是 **义聚（YJ）服务器** 对开源 PreFog 3.2.4 的定制魔改版本，形成过程如下：

1. **上游来源**：开源项目 [OpenHNS/PreFog](https://github.com/OpenHNS/PreFog)，作者 WessTorn，版本 3.2.4，功能为 CS 1.6 的预加速（Prestrafe）与 FOG（地面帧数）统计。
2. **魔改动机**：义聚服务器同时运行 HNS 比赛系统（`HnsMatchSystem`），比赛系统需要独占聊天框。原版 PreFog 在开关速度/预加速显示时会向聊天框输出 `[PreFog] Show Speed: ON/OFF` 等英文消息，与比赛系统冲突。
3. **魔改内容**：
   - 删除所有 `client_print_color` 聊天消息输出，聊天框完全让给比赛系统。
   - HUD 位置默认居中偏下（`pre_x -1.0` / `pre_y 0.55`），避免遮挡视野。
   - HUD 使用独立频道（`pre_hud 1`），避免与其他 HUD 插件冲突。
   - 适配 100AA 服务器（`sv_airaccelerate 100`），无需手动设置。
4. **版本命名**：`3.2.4-YJ`，作者署名 `WessTorn + YJ`，表示基于上游 3.2.4 由义聚定制。

---

## 二、功能概述

| 功能 | 说明 |
|------|------|
| 实时地速显示 | 屏幕显示当前水平速度（默认 `xxx u/s`） |
| FOG 统计 | 统计起跳前在地面停留的帧数（Frames On Ground） |
| 预加速类型检测 | 自动识别 Jump / Duck / Ladder / Slide 四种预加速 |
| FOG 质量评级 | Perfect / Good / Bad / VeryBad 四级评级 |
| 速度颜色渐变 | 速度越高颜色越接近"完美色"（默认绿） |
| 观战同步 | 观战者自动看到被观战玩家的 HUD |
| 设置菜单 | `/speedmenu` 菜单可调速度类型、颜色、开关 |

---

## 三、源码逐部分解释

### 3.1 依赖与头文件

```pawn
#include <amxmodx>
#include <reapi>
#include <fakemeta>
```

- `amxmodx`：AMX Mod X 核心 API（注册插件、CVAR、菜单、HUD）。
- `reapi`：ReAPI 模块，提供 `RegisterHookChain(RG_PM_Move)` 物理移动钩子，这是本插件的核心依赖。
- `fakemeta`：提供 `get_entvar` / `set_entvar` 等实体变量访问。

### 3.2 枚举定义

```pawn
enum PRE_TYPE { PRE_FOG, PRE_JUMP, PRE_DUCK, PRE_LADDER, PRE_SLIDE };
enum FOG_TYPE { FOG_VERYBAD, FOG_PERFECT, FOG_GOOD, FOG_BAD };
enum PRE_COLOR { CLR_WHITE, CLR_GREEN, CLR_VIOLET, CLR_BLUE, CLR_RED, CLR_YELLOW };
enum SPEED_TYPE { ST_DEF, ST_QUAKE, ST_NUM };
```

- `PRE_TYPE`：预加速类型，决定 HUD 显示 `[Jump]` / `[Duck]` / `[Ladder]` / `[Slide]`。
- `FOG_TYPE`：FOG 质量评级，显示 `[P]`（完美）/ `[G]`（良好）/ `[B]`（较差）/ `[VB]`（很差）。
- `PRE_COLOR`：速度颜色选项。
- `SPEED_TYPE`：速度显示格式（默认 / 雷神之锤风格 / 纯数字）。

### 3.3 核心逻辑：`rgPM_Move`

```pawn
RegisterHookChain(RG_PM_Move, "rgPM_Move");
```

这是插件的**心脏**，每物理帧调用一次，完成以下工作：

1. **观战处理**：玩家死亡时记录观战目标，让观战者能看到被观战者的 HUD。
2. **地面/空中判断**：通过 `FL_ONGROUND` 标志和 `MOVETYPE_FLY` 判断玩家是否在地面或梯子上。
3. **速度计算**：`vector_hor_length` 计算水平速度（忽略 Z 轴），`vector_length` 计算三维速度。
4. **FOG 累计**：在地面时每帧 `g_iFog[id]++`，记录地面停留帧数。
5. **预加速判定**：离地瞬间判断预加速类型：
   - FOG 帧数 > 10：判定为普通跳跃（`PRE_JUMP`）或蹲跳（`PRE_DUCK`）。
   - FOG 帧数 ≤ 10：判定为地面帧数型预加速（`PRE_FOG`），并按帧数评级质量。
   - 梯子：判定为 `PRE_LADDER`。
   - 滑墙：通过 `isUserSurfing` 检测，判定为 `PRE_SLIDE`。

### 3.4 FOG 质量评级规则

| 预加速类型 | Perfect | Good | Bad | VeryBad |
|-----------|---------|------|-----|---------|
| 跳跃（Jump） | 1 帧且满速 | 1-2 帧 | 3 帧 | 4+ 帧 |
| 蹲跳（SGS） | 3 帧 | 4 帧 | 5 帧 | 6+ 帧 |
| 蹲跳（普通） | 2 帧 | 3 帧 | 4 帧 | 5+ 帧 |

### 3.5 速度颜色渐变：`FormatRGBHud`

```pawn
val = convertToRange(floatmin(flSpeed, 285.0), 40.0, 285.0);
```

- 将速度 40~285 u/s 映射到 0.0~1.0。
- 通过线性插值在"默认色"和"完美色"之间渐变。
- 速度越高颜色越接近完美色（默认绿色），给玩家直观的速度反馈。

### 3.6 HUD 显示：`show_prespeed`

- 限制刷新频率为 0.05 秒，避免 HUD 闪烁。
- 预加速后显示 1 秒预加速信息（速度 + FOG 帧数 + 评级 + 前后速度）。
- 使用 `ShowSyncHudMsg` 同步 HUD，避免与其他频道冲突。
- 给玩家自己和观战者同时显示。

### 3.7 设置菜单

```pawn
register_clcmd("say /speedmenu", "cmdPreSpeedMenu");
```

- `/speedmenu` / `/speed` / `/premenu` / `/pre`：打开设置菜单。
- `/showpre`：开关预加速显示。
- `/showspeed`：开关速度显示。
- 菜单可调：速度开关、预加速开关、速度类型、完美色、默认色。

### 3.8 魔改点（相对上游 3.2.4）

```pawn
/* 开关 PreFog 显示 (魔改: 不输出聊天消息, 避免与比赛系统冲突) */
public cmdShowPre(id) {
	g_bOnOffPre[id] = g_bOnOffPre[id] ? false : true;
}
```

- **删除了**原版 `cmdShowPre` / `cmdShowSpeed` 中的 `client_print_color` 聊天消息。
- 开关功能保留，但不再向聊天框输出任何文字，聊天框完全让给比赛系统。

---

## 四、适用服务器

### 4.1 环境要求

| 组件 | 版本 |
|------|------|
| 游戏 | Counter-Strike 1.6 |
| 服务端 | ReHLDS |
| AMX Mod X | 1.9.0 或更高 |
| ReAPI | 最新版 |
| ReGameDLL | 最新版 |

### 4.2 适用服务器类型

本插件专为 **HNS（Hide and Seek）模式服务器** 设计，特别适合：

- **HNS 比赛服务器**：配合 HNS 比赛系统（`HnsMatchSystem`）使用，提供预加速数据辅助。
- **HNS 娱乐/公共服务器**：玩家练习预加速、跳跃技巧时实时反馈。
- **KZ / 跳跃类服务器**：需要预加速和速度反馈的跳跃服务器。
- **100AA 服务器**：`sv_airaccelerate 100` 的高空速服务器，插件自动适配。

### 4.3 不适用场景

- 普通混战（Deathmatch）服务器：预加速数据对普通玩家无意义。
- 非 ReHLDS 服务器：需要 ReAPI 的 `RG_PM_Move` 钩子。

---

## 五、安装部署

### 5.1 文件结构

```
addons/amxmodx/
├── plugins/
│   └── yj_prefog.amxx          # 编译后的插件
└── configs/
    └── prefog.cfg              # 插件配置
```

### 5.2 安装步骤

1. 将 `yj_prefog.amxx` 放入服务器 `addons/amxmodx/plugins/` 目录。
2. 将 `prefog.cfg` 放入服务器 `addons/amxmodx/configs/` 目录。
3. 在 `addons/amxmodx/configs/plugins.ini` 末尾添加一行：
   ```
   yj_prefog.amxx
   ```
4. 重启服务器，或控制台执行 `amxx plugins` 确认加载。

### 5.3 编译方法

```bash
# 需要 AMX Mod X 1.9.0+ 编译器 (amxxpc)
amxxpc yj_prefog.sma
```

编译依赖：`reapi`、`fakemeta` 头文件。

---

## 六、配置说明 (prefog.cfg)

| CVAR | 默认值 | 说明 |
|------|--------|------|
| `pre_x` | `-1.0` | HUD 水平位置（-1.0 = 居中） |
| `pre_y` | `0.55` | HUD 垂直位置（0.55 = 屏幕中部偏下） |
| `pre_hud` | `1` | HUD 频道（1 = 独立频道，避免冲突） |

> 100AA 由服务器 `sv_airaccelerate 100` 控制，无需在插件中设置。

---

## 七、玩家命令

| 命令 | 功能 |
|------|------|
| `/speedmenu` | 打开 PreFog 设置菜单 |
| `/speed` | 同上（快捷） |
| `/premenu` | 同上（快捷） |
| `/pre` | 同上（快捷） |
| `/showpre` | 开关预加速显示 |
| `/showspeed` | 开关速度显示 |

---

## 八、HUD 显示说明

屏幕中部偏下位置显示：

```
285 u/s          ← 当前速度（颜色随速度渐变）

3 [P]            ← FOG 帧数 + 质量评级
280.00           ← 预加速前速度
285.00           ← 预加速后速度
```

或跳跃预加速时：

```
285 u/s

[Jump]           ← 预加速类型
285.00           ← 离地速度
```

---

## 九、致谢

- 上游作者：WessTorn（开源 PreFog 3.2.4）
- 魔改定制：义聚（YJ）
- 开源地址：https://github.com/OpenHNS/PreFog
