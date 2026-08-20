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
  - 昵称存入 GameState（`player_name`），登录成功后跳转到养成主界面
  - **本地存档列表**：登录面板下方显示已保存的角色存档（角色名/年月/金币摘要），每行"进入"（加载存档直接进游戏）与"删除"（确认后删除）按钮

- **存档系统**（开发者调试用，`scripts/data/save_manager.gd` Autoload）：
  - 本地目录 `user://saves/`，JSON 格式，按角色名保存（同名覆盖更新）
  - 保存入口：调试台（礼包码 `tiaoshitai`）"存档管理"分组输入角色名保存当前进度
  - **自动保存**：游戏每 10 秒自动保存到"自动存档"槽（仅主界面运行期间，登录/其他界面不覆盖）

- **离线挂机系统**（`scripts/data/offline_gains.gd`）：
  - 退出游戏时保存"自动存档"并记录时间戳；下次启动自动结算离线收益（金币/食物/木材/石料/金属/人口/科技/文化点数 + 建筑施工推进/完工/升级/拆除 + 年月推进）
  - **无挂机时间上限**：收益按时间批量数学计算、施工按完成事件分段推进，性能与离线时长无关（实测 365 天离线 0ms 结算）
  - 离线按 1x 倍速折算（5 秒 = 1 游戏月），登录首页显示"离线挂机 X 小时：金币 +Y"提示
  - 调试台"离线挂机模拟"分组可输入秒数即时验证结算逻辑
  - 存档内容：GameState 全部数值 + 建造状态（网格/建筑/加成基准），加载后完整恢复并刷新 UI
  - 登录首页显示已有存档，支持加载进入与删除

- **养成主界面**（`scenes/ui/main_ui.tscn`）：
  - 顶部信息栏：游戏时间（年/月）、金币（含增长率）、人口、幸福度、科技点数、文化点数
  - 底部操作栏：六大模块入口按钮（颜色区分）+ 时间控制按钮（暂停/1x/2x/3x加速）
  - 右下角消息日志面板（半透明、鼠标穿透，不拦截建造点击）
  - 中央区域（地图/城市视图占位）
  - 深邃星空背景 + 星星粒子 + 光晕
  - 实时资源增长系统（`scripts/ui/main_ui.gd`，数据层信号驱动 UI 刷新）
  - 消息日志独立组件（`scripts/ui/message_log.gd`），欢迎语显示玩家昵称
  - 全局主题 `assets/fonts/default_theme.tres` 已挂载（`project.godot` → `gui/theme/custom`）

- **地图与探索界面**（`scenes/ui/explore/explore_map.tscn`，默认进入）：
  - 部落冲突式网格建设：左侧可滚动建筑菜单栏 + 中央 25×14 网格建设区（1000×560px，居中填满）
  - 5 种建筑（住宅/办公楼/学校/医院/金融中心）+ 3 种装饰（花园/喷泉/雕像），数据配置于 `data/buildings.json`
  - 悬停半透明预览（绿=可建/红=不可建）、建造进度动画、完工闪光、放置缩放动画
  - 随机障碍（岩石/树木/湖泊）可花费金币清除；点击施工中建筑可取消建造并返还金币
  - **建筑升级与拆除**：点击已完工建筑弹出操作面板；升级费用随等级递增（最高 5 级）、加成 = 基础 × 等级；拆除返还总投入 60%；进度条颜色区分（建绿/升黄/拆红）；施工进度随游戏倍速加速（暂停时冻结）
  - 建筑加成（金币/人口/幸福度/科技/文化）实时接入月度增长循环，顶部信息栏同步刷新
  - **建筑产出总览面板**：界面底部实时汇总所有已建建筑/装饰的累计加成（金币/人口上限/人口增长率/科技/文化/幸福度），监听 `BuildingSystem.bonus_updated` 自动刷新，鼠标穿透不阻挡建造（实现于 `explore_map.gd` 内部类 MapSummary）
  - **科技/文化为点数制**：基础速率 0.5/0.4 点/月，累积不封顶

- **设置系统**（`scenes/ui/settings_menu.tscn` + `scripts/ui/settings_menu.gd`）：
  - 底栏右下角"设置"按钮，打开居中设置面板
  - **游戏分辨率**：下拉选择 1280×720 / 1600×900 / 1920×1080 / 2560×1440，选择即应用（`WindowManager`）
  - **礼包码**：输入兑换金币奖励，数据配置于 `data/gift_codes.json`，防重复兑换（`GiftCodeManager` Autoload）
  - **退出游戏**：确认对话框后退出
  - **开发者调试台**：输入礼包码 `tiaoshitai`（大小写不敏感）开启，可调倍速（1x-10x）/暂停、GameState 全部数值 +/- 调节、游戏资产数据浏览、**离线挂机模拟**（详见 AGENTS.md 3.2）

- **UI 美化**：
  - 全局玻璃质感深蓝视觉：圆角高光边框 + 发光阴影（登录/主界面/探索/设置面板统一）
  - 按钮动效：悬停放大 + 按下微缩（`scripts/ui/ui_anim.gd`）
  - 面板入场动画：淡入 + 轻微放大（登录面板/顶栏/底栏/消息日志/设置面板）
  - 汇总面板数值变化闪烁、建筑菜单卡片悬停高亮

- **窗口设置**：
  - 1280×720 设计分辨率（测试窗口规范，防止系统窗口遮挡影响测试截图），关闭引擎 stretch
  - 根 Control 固定 1280×720 布局，由 `WindowManager` 按 `min(宽/1280, 高/720)` 等比缩放（矢量重绘）：切换 1920×1080 等分辨率时画面清晰、UI 不错位
  - 分辨率切换由 `WindowManager` Autoload 提供接口（`set_resolution`、窗口居中、`setup_scale_root` 注册场景根）

- 字体：思源黑体（Source Han Sans CN，OFL 开源许可，Normal / Bold / Heavy 三字重）+ 思源宋体（Source Han Serif CN，Regular / Variable），位于 `assets/fonts/`
- 字体规范：
  - 标题/按钮文字：思源黑体（Heavy 或 Bold）
  - 正文/描述文字：思源宋体（Regular 或 Bold）
  - 通过 `assets/fonts/default_theme.tres` 全局主题统一管理

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
| `scripts/ui/` | UI 层：各界面逻辑脚本（main_ui.gd、login.gd、message_log.gd、top_bar.gd、explore_map.gd、grid_view.gd、building_menu.gd、settings_menu.gd、debug_console.gd、save_list.gd、ui_anim.gd 等；界面专属小模块已合并为内部类，见 AGENTS.md 3.1） |
| `scripts/game/` | 游戏逻辑层：建造系统（building_system.gd，同系统小模块以内部类组织：BuildingData/BuildingGrid/BuildingBalance/BuildingActions） |
| `scenes/ui/explore/` | 地图与探索界面场景（网格建设） |
| `assets/` | 美术 / 音频 / 字体资源 |
| `data/` | 数据文件（JSON 等） |
| `docs/design/` | 游戏设计文档 |
| `addons/` | 本地插件（**已被 git 忽略，不随仓库分发**） |

### Autoload 单例

| 单例名 | 路径 | 说明 |
| ---- | ---- | ---- |
| GameState | `scripts/data/game_state.gd` | 游戏状态管理：玩家数据（昵称）、资源数据、进度数据、信号通知、存档恢复 |
| TimeManager | `scripts/data/time_manager.gd` | 时间管理：游戏时间、倍率控制、月度更新 |
| SaveManager | `scripts/data/save_manager.gd` | 存档管理：user://saves/ 本地 JSON 存档（保存/加载/列表/删除），按角色名区分 |
| BuildingSystem | `scripts/game/building_system.gd` | 建造系统 Autoload：网格状态、放置/取消/清障、建造/升级/拆除计时（随倍速）、加成重算；内部类 BuildingData（数据加载）/BuildingGrid（网格工具）/BuildingBalance（数值平衡）/BuildingActions（建筑操作），外部经 `BuildingSystem.内部类名` 访问 |
| WindowManager | `scripts/data/window_manager.gd` | 窗口管理：根 Control 等比缩放（矢量重绘，任意分辨率清晰不错位）、分辨率切换（`set_resolution`）、窗口居中、`setup_scale_root` 注册场景根 |
| GiftCodeManager | `scripts/data/gift_code_manager.gd` | 礼包码管理：加载 `data/gift_codes.json`、校验兑换、发放金币奖励、防重复兑换 |

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
