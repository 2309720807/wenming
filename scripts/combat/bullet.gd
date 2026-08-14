class_name Bullet
extends Area2D

## 子弹：沿固定方向飞行，命中敌人造成伤害

@export var bullet_speed: float = 800.0
@export var lifetime: float = 2.0
@export var damage: int = 10

var direction: Vector2 = Vector2.RIGHT


func _physics_process(delta: float) -> void:
	position += direction * bullet_speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	# 敌人实现 take_damage 接口，命中后造成伤害并销毁子弹
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()