extends Node

## 游戏状态管理器（Autoload 单例）
## 存储所有游戏数据，其他模块通过信号或直接访问修改

# === 信号 ===
signal year_changed(new_year: int)
signal month_changed(new_month: int)
signal gold_changed(new_value: float, rate: float)
signal population_changed(new_value: int, max_value: int)
signal happiness_changed(new_value: int)
signal food_changed(new_value: float, rate: float)
signal wood_changed(new_value: float)
signal stone_changed(new_value: float)
signal metal_changed(new_value: float)
signal tech_changed(new_value: float)
signal culture_changed(new_value: float)

# === 游戏时间 ===
var year: int = 1
var month: int = 1

# === 资源数据 ===
var gold: float = 100.0
var gold_rate: float = 5.0

var population: int = 10
var pop_max: int = 50
var pop_growth_rate: float = 0.2

var happiness: int = 75

var food: float = 50.0
var food_rate: float = 2.0

var wood: float = 30.0
var wood_rate: float = 1.0

var stone: float = 20.0
var stone_rate: float = 0.5

var metal: float = 10.0
var metal_rate: float = 0.2

# === 进度数据 ===
var tech_progress: float = 0.0
var tech_rate: float = 0.02

var culture_progress: float = 0.0
var culture_rate: float = 0.015


func set_month(new_year: int, new_month: int) -> void:
	if new_year != year:
		year = new_year
		year_changed.emit(year)
	if new_month != month:
		month = new_month
		month_changed.emit(month)


func add_gold(amount: float) -> void:
	gold += amount
	gold_changed.emit(gold, gold_rate)


func set_population(value: int) -> void:
	population = clampi(value, 0, pop_max)
	population_changed.emit(population, pop_max)


func set_happiness(value: int) -> void:
	happiness = clampi(value, 0, 100)
	happiness_changed.emit(happiness)


func add_food(amount: float) -> void:
	food += amount
	food_changed.emit(food, food_rate)


func add_wood(amount: float) -> void:
	wood += amount
	wood_changed.emit(wood)


func add_stone(amount: float) -> void:
	stone += amount
	stone_changed.emit(stone)


func add_metal(amount: float) -> void:
	metal += amount
	metal_changed.emit(metal)


func add_tech(amount: float) -> void:
	tech_progress = minf(tech_progress + amount, 1.0)
	tech_changed.emit(tech_progress)


func add_culture(amount: float) -> void:
	culture_progress = minf(culture_progress + amount, 1.0)
	culture_changed.emit(culture_progress)


func get_time_display() -> String:
	return "第 %d 年 第 %d 月" % [year, month]


func get_gold_display() -> String:
	return "金币 %d (+%.0f/月)" % [int(gold), gold_rate]


func get_population_display() -> String:
	return "人口 %d/%d" % [population, pop_max]


func get_happiness_display() -> String:
	return "幸福度 %d%%" % happiness


func get_tech_display() -> String:
	return "科技 %.0f%%" % (tech_progress * 100)


func get_culture_display() -> String:
	return "文化 %.0f%%" % (culture_progress * 100)
