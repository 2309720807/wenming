# 文明模拟器（wenming）

一款科幻题材的 2D 俯视角射击 + 文明模拟游戏，使用 **Godot 4.7**（GDScript）开发。

## 玩法概述

- **双层次结构**：英雄层（俯视角射击：移动、瞄准、射击、技能）与文明层（科技 / 军事 / 经济 / 探索 / 文化五条发展路线）
- **实时制**：无回合、无时间压迫，逐步发展文明
- **目标**：先以生存为目标，后期进入开放式沙盒
- **战斗形式**：副本式战斗 + 基地攻防
- **数据驱动**：数值与内容通过 `data/*.json` 配置

完整设计见 [`docs/design/game_design.md`](docs/design/game_design.md)（设计的唯一依据）。

## 当前进度

- 原型 Demo：英雄俯视角移动射击（WASD 移动 + 鼠标瞄准 + 左键射击），含测试敌人、边界墙
- 场景：`scenes/main/main.tscn` 为主场景，编辑器按 F5 直接运行

## 运行要求

- Godot **4.7.x**（Forward Plus 渲染，Windows D3D12，Jolt 物理）
- 直接克隆后打开 `project.godot` 即可运行，无需额外资源

## 目录结构

| 路径 | 说明 |
| ---- | ---- |
| `scenes/` | 游戏场景（main / player / combat / base / puzzle / ui） |
| `scripts/` | GDScript 脚本 |
| `assets/` | 美术 / 音频资源 |
| `data/` | 数据文件（JSON 等） |
| `docs/design/` | 游戏设计文档 |
| `addons/` | 本地插件（**已被 git 忽略，不随仓库分发**） |

## 多人协作（重要）

本仓库使用**占用锁（LOCK.md）**机制防止多人互相覆盖：

- **开工**：双击 `start.bat`（检查云端锁 → 同步最新 → 建立占用锁）
- **本地存档**：双击 `save_local.bat`（仅提交本地，不推送）
- **收工**：双击 `push.bat`（提交推送所有改动 + 释放占用锁）

详细规则请阅读 **[`GITHUB_RULES.md`](GITHUB_RULES.md)** 与 [`AGENTS.md`](AGENTS.md)。请只通过上述脚本操作云端，直接 `git push` 会被钩子拦截。