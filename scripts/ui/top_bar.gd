extends PanelContainer

## 顶部信息栏：游戏时间/金币/人口/幸福度/科技/文化 实时显示。
## 设计依据：docs/design/game_design.md 4-A（顶部信息栏）
## 独立组件：数据层信号订阅与显示更新集中于此，main_ui 只负责模块导航。

@onready var time_label: Label = %TimeLabel
@onready var gold_label: Label = %GoldLabel
@onready var population_label: Label = %PopulationLabel
@onready var happiness_label: Label = %HappinessLabel
@onready var tech_label: Label = %TechLabel
@onready var culture_label: Label = %CultureLabel


func _ready() -> void:
	# 数据层信号 → 显示刷新；建筑加成变化也触发整体刷新
	GameState.year_changed.connect(_on_year_changed)
	GameState.month_changed.connect(_on_month_changed)
	GameState.gold_changed.connect(_on_gold_changed)
	GameState.population_changed.connect(_on_population_changed)
	GameState.happiness_changed.connect(_on_happiness_changed)
	GameState.tech_changed.connect(_on_tech_changed)
	GameState.culture_changed.connect(_on_culture_changed)
	BuildingSystem.bonus_updated.connect(_update_all_labels)
	_update_all_labels()


func _update_all_labels() -> void:
	time_label.text = GameState.get_time_display()
	gold_label.text = GameState.get_gold_display()
	population_label.text = GameState.get_population_display()
	happiness_label.text = GameState.get_happiness_display()
	tech_label.text = GameState.get_tech_display()
	culture_label.text = GameState.get_culture_display()


func _on_year_changed(_new_year: int) -> void:
	time_label.text = GameState.get_time_display()


func _on_month_changed(_new_month: int) -> void:
	time_label.text = GameState.get_time_display()


func _on_gold_changed(_new_value: float, _rate: float) -> void:
	gold_label.text = GameState.get_gold_display()


func _on_population_changed(_new_value: int, _max_value: int) -> void:
	population_label.text = GameState.get_population_display()


func _on_happiness_changed(_new_value: int) -> void:
	happiness_label.text = GameState.get_happiness_display()


func _on_tech_changed(_new_value: float) -> void:
	tech_label.text = GameState.get_tech_display()


func _on_culture_changed(_new_value: float) -> void:
	culture_label.text = GameState.get_culture_display()
