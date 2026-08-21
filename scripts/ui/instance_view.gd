extends Control

## 副本探索界面（占位框架）：攻城系统入口，完整功能见设计文档 3.11
## 阶段规划：搜索人机防御工程 → 排兵布阵 → 攻城战斗（部落冲突式肉鸽）

const FONT_HEAVY: Font = preload("res://assets/fonts/SourceHanSansCN-Heavy.ttf")
const FONT_BOLD: Font = preload("res://assets/fonts/SourceHanSansCN-Bold.ttf")
const FONT_SERIF: Font = preload("res://assets/fonts/SourceHanSerifCN-Regular.otf")


func _ready() -> void:
	WindowManager.setup_scale_root(self)
	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.04, 0.1, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.custom_minimum_size = Vector2(560, 340)
	center.add_theme_constant_override("separation", 18)
	add_child(center)

	var title := Label.new()
	title.text = "⚔ 副本探索"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", FONT_HEAVY)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.4, 0.82, 1, 1))
	center.add_child(title)

	var desc := Label.new()
	desc.text = "副本探索系统开发中\n\n搜索其他文明的防御工程 → 排兵布阵 → 攻城战斗\n（部落冲突式肉鸽玩法，敬请期待）"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_override("font", FONT_SERIF)
	desc.add_theme_font_size_override("font_size", 16)
	desc.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95, 0.9))
	center.add_child(desc)

	var back_btn := Button.new()
	back_btn.text = "返回主界面"
	back_btn.custom_minimum_size = Vector2(200, 44)
	back_btn.add_theme_font_override("font", FONT_BOLD)
	back_btn.add_theme_font_size_override("font_size", 16)
	back_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/ui/main_ui.tscn"))
	center.add_child(back_btn)
