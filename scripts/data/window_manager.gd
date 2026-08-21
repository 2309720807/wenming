extends Node

## 窗口管理（Autoload 单例）
## 关闭引擎 stretch，场景根 UI 固定 1280×720 设计分辨率布局，由本管理器按窗口尺寸
## 计算等比缩放系数（scale = min(宽/1280, 高/720)）施加到根 Control：
## - Control transform 缩放为矢量重绘，任意分辨率下画面清晰（viewport 拉伸模式放大会模糊）
## - 布局坐标系恒定 1280×720，窗口放大不错位（规避 Godot 4.7.1 canvas_items stretch 双重缩放缺陷）
## 场景根脚本在 _ready 中调用 setup_scale_root(self) 注册。

const DESIGN_SIZE: Vector2 = Vector2(1280, 720)
const ZOOM_MIN: float = 0.8
const ZOOM_MAX: float = 1.5
const SETTINGS_PATH: String = "user://settings.cfg"  # 界面偏好记忆（缩放比例等）

## 可选分辨率列表（设置面板使用）
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

var _scale_root: Control = null
var _window: Window = null
var zoom_scale: float = 1.0  # 界面任意缩放比例（0.8~1.5，随窗口等比缩放叠加）


func _ready() -> void:
	_window = get_window()
	_window.size_changed.connect(_on_window_size_changed)
	_load_settings()
	_on_window_size_changed()


## 设置界面缩放比例并记忆（user://settings.cfg，下次启动恢复）
func set_zoom_scale(value: float) -> void:
	zoom_scale = clampf(value, ZOOM_MIN, ZOOM_MAX)
	_save_settings()
	_apply_scale()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		zoom_scale = clampf(float(cfg.get_value("display", "zoom_scale", 1.0)), ZOOM_MIN, ZOOM_MAX)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "zoom_scale", zoom_scale)
	cfg.save(SETTINGS_PATH)


## 场景根 Control 注册（登录/主界面 _ready 调用）
func setup_scale_root(root: Control) -> void:
	_scale_root = root
	_apply_scale()


## 当前等比缩放系数（含用户界面缩放比例；子窗口如确认对话框按此缩放内容）
func current_scale_factor() -> float:
	var win_size: Vector2 = Vector2(_window.size)
	var factor: float = minf(win_size.x / DESIGN_SIZE.x, win_size.y / DESIGN_SIZE.y)
	return maxf(factor * zoom_scale, 0.0)


func current_resolution() -> Vector2i:
	return _window.size


func get_resolutions() -> Array[Vector2i]:
	return RESOLUTIONS.duplicate()


func set_resolution(size: Vector2i) -> void:
	# 不允许小于设计分辨率（放大才符合等比缩放预期）
	var clamped: Vector2i = size
	if size.x < DESIGN_SIZE.x or size.y < DESIGN_SIZE.y:
		clamped = Vector2i(DESIGN_SIZE)
	_window.size = clamped
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
	# 用户界面缩放比例叠加（任意缩放，记忆于 settings.cfg）
	factor *= zoom_scale
	# 锚点改为中心点 + 固定设计尺寸，避免全屏锚定在窗口变化时覆盖 size
	_scale_root.set_anchors_preset(Control.PRESET_CENTER)
	_scale_root.size = DESIGN_SIZE
	_scale_root.scale = Vector2(factor, factor)
	_scale_root.position = (win_size - DESIGN_SIZE * factor) / 2.0