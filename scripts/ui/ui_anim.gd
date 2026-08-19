class_name UiAnim
extends RefCounted

## UI 动效工具：按钮悬停/按下过渡、面板入场、数值变化闪烁。
## 纯视觉动画（transform/modulate），不改变布局与游戏逻辑。
## 设计依据：docs/design/game_design.md（界面打磨阶段）

const BTN_HOVER_SCALE: float = 1.04
const BTN_PRESS_SCALE: float = 0.96
const ANIM_TIME: float = 0.12


static func attach_button(btn: Button) -> void:
	## 按钮悬停放大 + 按下微缩，营造按压手感
	btn.mouse_entered.connect(func() -> void: _btn_tween(btn, BTN_HOVER_SCALE))
	btn.mouse_exited.connect(func() -> void: _btn_tween(btn, 1.0))
	btn.button_down.connect(func() -> void: _btn_tween(btn, BTN_PRESS_SCALE))
	btn.button_up.connect(func() -> void: _btn_tween(btn, BTN_HOVER_SCALE if btn.is_hovered() else 1.0))


static func _btn_tween(btn: Button, target: float) -> void:
	var tw: Tween = btn.create_tween()
	tw.tween_property(btn, "scale", Vector2.ONE * target, ANIM_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


static func panel_enter(node: Control, delay: float = 0.0) -> void:
	## 面板入场：淡入 + 轻微放大（transform 动画，不影响布局）
	node.modulate.a = 0.0
	node.scale = Vector2(0.94, 0.94)
	var tw: Tween = node.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(node, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(node, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


static func value_flash(label: Label) -> void:
	## 数值变化闪烁：提亮后恢复
	var tw: Tween = label.create_tween()
	tw.tween_property(label, "modulate", Color(1.5, 1.5, 0.9, 1), 0.12)
	tw.tween_property(label, "modulate", Color.WHITE, 0.35)
