class_name Player
extends CharacterBody2D

## 英雄角色：俯视角移动 + 鼠标瞄准射击

const BULLET_SCENE: PackedScene = preload("res://scenes/combat/bullet.tscn")

@export var move_speed: float = 300.0
@export var fire_interval: float = 0.15
@export var max_hp: int = 100

var hp: int

@onready var muzzle: Marker2D = $Muzzle
@onready var body_visual: Polygon2D = $Visual

var _fire_cooldown: float = 0.0


func _ready() -> void:
	hp = max_hp


func _physics_process(delta: float) -> void:
	_fire_cooldown -= delta
	_handle_movement()
	_handle_aim()
	_handle_shoot()


func _handle_movement() -> void:
	# 使用项目自定义输入动作，方向键/WASD 移动
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_dir * move_speed
	move_and_slide()


func _handle_aim() -> void:
	# 角色朝鼠标方向旋转（+X 轴指向鼠标）
	look_at(get_global_mouse_position())


func _handle_shoot() -> void:
	if Input.is_action_pressed("shoot") and _fire_cooldown <= 0.0:
		_fire_cooldown = fire_interval
		_spawn_bullet()


func _spawn_bullet() -> void:
	var bullet := BULLET_SCENE.instantiate() as Bullet
	bullet.global_position = muzzle.global_position
	bullet.direction = (get_global_mouse_position() - muzzle.global_position).normalized()
	get_tree().current_scene.add_child(bullet)


func take_damage(amount: int) -> void:
	hp -= amount
	if hp <= 0:
		queue_free()