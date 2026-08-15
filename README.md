# 文明模拟器（wenming）

一款科幻题材的 2D 实时文明经营策略游戏，使用 **Godot 4.7**（GDScript）开发。

## 玩法概述

- **六大养成方向**：人口与民生、科技与研发、经济与资源、军事与防御、文化与外交、地图与探索
- **实时制**：所有系统资源随时间自然变化，无回合概念
- **核心体验**：从零开始建设一个文明的成就感
- **数据驱动**：数值与内容通过 `data/*.json` 配置

完整设计见 [`docs/design/game_design.md`](docs/design/game_design.md)（设计的唯一依据）。

## 当前进度

- **登录界面**（`scenes/ui/login.tscn`）：
  - 深邃星空渐变背景（shader 逐像素计算，左上深蓝 → 中暗蓝紫 → 右下深紫）
  - 双层星空粒子（小星闪烁 + 亮星光晕脉动）
  - 半透明圆角面板、青色发光标题、按钮悬停/按下态
  - 登录逻辑：昵称输入校验 + 错误提示淡入（`scripts/ui/login.gd`）
  - 登录成功后跳转到养成主界面

- **养成主界面**（`scenes/ui/main_ui.tscn`）：
  - 顶部信息栏：游戏时间（年/月）、金币（含增长率）、人口、幸福度、科技进度、文化进度
  - 底部操作栏：六大模块入口按钮（颜色区分）+ 时间控制按钮（暂停/1x/2x/3x加速）
  - 右下角消息日志面板
  - 中央区域（地图/城市视图占位）
  - 深邃星空背景 + 星星粒子 + 光晕
  - 实时资源增长系统（`scripts/ui/main_ui.gd`）

- **窗口设置**：
  - 1920×1080 分辨率，允许用户缩放窗口
  - 比例锁定 16:9（`aspect="keep"`）

- 字体：思源黑体（Source Han Sans CN，OFL 开源许可，Normal / Bold / Heavy 三字重，位于 `assets/fonts/`）

## 运行要求

- Godot **4.7.x**（Forward Plus 渲染，Windows D3D12，Jolt 物理）
- 直接克隆后打开 `project.godot` 即可运行，无需额外资源

## 目录结构

| 路径 | 说明 |
| ---- | ---- |
| `scenes/` | 游戏场景（按模块划分） |
| `scenes/ui/` | UI 场景（登录、主界面、各模块子界面） |
| `scenes/game/` | 游戏世界场景 |
| `scripts/` | GDScript 脚本（外部 `.gd`，不在场景内嵌逻辑） |
| `scripts/data/` | 数据层：GameState（游戏状态）、TimeManager（时间管理）等 Autoload 单例 |
| `scripts/ui/` | UI 层：各界面逻辑脚本（main_ui.gd、login.gd 等） |
| `scripts/game/` | 游戏逻辑层：战斗、建造、AI 等系统 |
| `assets/` | 美术 / 音频 / 字体资源 |
| `data/` | 数据文件（JSON 等） |
| `docs/design/` | 游戏设计文档 |
| `addons/` | 本地插件（**已被 git 忽略，不随仓库分发**） |

### Autoload 单例

| 单例名 | 路径 | 说明 |
| ---- | ---- | ---- |
| GameState | `scripts/data/game_state.gd` | 游戏状态管理：资源数据、进度数据、信号通知 |
| TimeManager | `scripts/data/time_manager.gd` | 时间管理：游戏时间、倍率控制、月度更新 |

## 脚本工具（重要）

| 脚本 | 用途 | 说明 |
| ---- | ---- | ---- |
| `start.bat` | 开工 | 检查云端占用锁（他设备锁则禁止）→ 检查本地残留改动（云端被改则禁止推送）→ 拉取最新 → 建立本设备占用锁。参数：`/y` 迷你收工自动确认、`/nopause` 不暂停 |
| `save_local.bat` | 本地存档 | 提交所有改动到本地 git（不推送，可随时使用） |
| `push.bat` | 收工 | 提交并推送所有改动 → 释放占用锁。提交说明可用首参数或环境变量 `COMMIT_MSG` 指定，`/nopause` 不暂停 |
| `history.bat` | 历史查看 / 回档 | 交互菜单或参数模式：`view` 历史、`show <提交号>` 改动详情、`file <提交号> <路径>` 历史文件内容、`checkout <提交号>` 临时切换试运行（`git checkout main` 切回）、`reset <提交号> /y` 永久回退（危险，必须显式确认） |

> 请只通过上述脚本操作云端：直接 `git push` 会被 pre-push 钩子拦截，除非满足收工流程条件（`ALLOW_PUSH`）或仅推送锁文件。

## 多人协作（重要）

本仓库使用**占用锁（LOCK.md）**机制防止多人互相覆盖：

- **开工**：双击 `start.bat`（检查云端锁 → 同步最新 → 建立占用锁）
- **本地存档**：双击 `save_local.bat`（仅提交本地，不推送）
- **收工**：双击 `push.bat`（提交推送所有改动 + 释放占用锁）

详细规则请阅读 **[`GITHUB_RULES.md`](GITHUB_RULES.md)** 与 [`AGENTS.md`](AGENTS.md)。
