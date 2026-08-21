extends Node

## 窗口管理（Autoload 单例）
## 关闭引擎 stretch，场景根 UI 固定 1280×720 设计分辨率布局，由本管理器按窗口尺寸
## 计算等比缩放系数（scale = min(宽/1280, 高/720)）施加到根 Control：
## - Control transform 缩放为矢量重绘，任意分辨率下画面清晰（viewport 拉伸模式放大会模糊）
## - 布局坐标系恒定 1280×720，窗口放大不错位（规避 Godot 4.7.1 canvas_items stretch 双重缩放缺陷）
## 场景根脚本在 _ready 中调用 setup_scale_root(self) 注册。

const DESIGN_SIZE: Vector2 = Vector2(1280, 720)
const SETTINGS_PATH: String = "user://settings.cfg"  # 界面偏好记忆（画质档位等）
## 画质档位：超采样面积倍数（渲染像素 = 屏幕像素 × 档位，线性倍率 = √档位）
## 与 MSAA 语义一致：2x/4x/8x/16x 分别是 1.41x/2x/2.83x/4x 线性渲染
const QUALITY_LEVELS: Array[int] = [1, 2, 4, 8, 16]

## 可选分辨率列表（设置面板使用）
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

var _scale_root: Control = null
var _window: Window = null
var quality_level: int = 1  # 画质档位（超采样面积倍数，1/2/4/8/16）


func _ready() -> void:
	_window = get_window()
	_window.size_changed.connect(_on_window_size_changed)
	_load_settings()
	_on_window_size_changed()


## 设置画质档位（超采样面积倍数）并记忆（user://settings.cfg，下次启动恢复）
func set_quality_level(level: int) -> void:
	if not QUALITY_LEVELS.has(level):
		level = 1
	quality_level = level
	_save_settings()
	_apply_scale()  # 触发场景缩放刷新（子视口按新档位重建分辨率）


## 当前画质档位的线性超采样倍率（面积 2x → 线性 √2 ≈ 1.414）
func supersample_factor() -> float:
	return sqrt(float(quality_level))


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		var lv: int = int(cfg.get_value("display", "quality_level", 1))
		quality_level = lv if QUALITY_LEVELS.has(lv) else 1


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "quality_level", quality_level)
	cfg.save(SETTINGS_PATH)


## 场景根 Control 注册（登录/主界面 _ready 调用）
func setup_scale_root(root: Control) -> void:
	_scale_root = root
	_apply_scale()


## 当前等比缩放系数（窗口等比缩放；子窗口如确认对话框按此缩放内容）
func current_scale_factor() -> float:
	var win_size: Vector2 = Vector2(_window.size)
	var factor: float = minf(win_size.x / DESIGN_SIZE.x, win_size.y / DESIGN_SIZE.y)
	return maxf(factor, 0.0)


func current_resolution() -> Vector2i:
	return _window.size


## 可选分辨率列表（设置面板使用）：动态过滤，仅保留"物理尺寸"不超过当前屏幕的选项。
## Godot 窗口为 DPI 感知：逻辑尺寸 = 物理尺寸 × (dpi/96)，过滤必须按物理尺寸比较，
## 否则在高 DPI 屏幕（如 125% 缩放）上 1600×900 会被误判超屏而不可选。
func get_resolutions() -> Array[Vector2i]:
	var screen_phys: Vector2i = DisplayServer.screen_get_size()
	var dpi_scale: float = DisplayServer.screen_get_dpi() / 96.0
	if dpi_scale <= 0.0:
		dpi_scale = 1.0
	var result: Array[Vector2i] = []
	for res: Vector2i in RESOLUTIONS:
		# 窗口物理尺寸 = 逻辑尺寸 ÷ DPI 缩放（物理 = 逻辑 / (dpi/96)）
		var phys: Vector2i = Vector2i(int(res.x / dpi_scale), int(res.y / dpi_scale))
		if phys.x <= screen_phys.x and phys.y <= screen_phys.y:
			result.append(res)
	if result.is_empty():
		result.append(Vector2i(DESIGN_SIZE))
	return result


func set_resolution(size: Vector2i) -> void:
	# 不允许小于设计分辨率（放大才符合等比缩放预期）
	var clamped: Vector2i = size
	if size.x < DESIGN_SIZE.x or size.y < DESIGN_SIZE.y:
		clamped = Vector2i(DESIGN_SIZE)
	# 确保窗口处于普通窗口模式（最大化/全屏时窗口大小由系统管理，设置无效）
	if _window.mode != Window.MODE_WINDOWED:
		_window.mode = Window.MODE_WINDOWED
	# 双保险设置窗口大小（Window.size 与引擎级 API 互补）
	DisplayServer.window_set_size(clamped)
	_window.size = clamped
	_apply_scale()  # 窗口变化后手动应用等比缩放（防 size_changed 未触发）
	_center_window()


func _center_window() -> void:
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(_window.current_screen)
	_window.position = usable.position + (usable.size - _window.size) / 2


func _on_window_size_changed() -> void:
	_apply_scale()


func _apply_scale() -> void:
	if _scale_root == null or not is_instance_valid(_scale_root):
		return
	var win_size: Vector2 = Vector2(_window.size)
	var factor: float = minf(win_size.x / DESIGN_SIZE.x, win_size.y / DESIGN_SIZE.y)
	if factor <= 0.0:
		factor = 1.0
	# 锚点改为中心点 + 固定设计尺寸，避免全屏锚定在窗口变化时覆盖 size
	_scale_root.set_anchors_preset(Control.PRESET_CENTER)
	_scale_root.size = DESIGN_SIZE
	_scale_root.scale = Vector2(factor, factor)
	_scale_root.position = (win_size - DESIGN_SIZE * factor) / 2.0