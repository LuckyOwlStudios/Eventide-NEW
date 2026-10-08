@icon("uid://dchupx4fnos6l")
class_name Health
extends AttributeNode

signal health_changed(previous_value: float, current_value: float, change_amount: float)
signal health_depleted
signal injured_state_changed(is_injured: bool)
signal injured_state_entered
signal injured_state_exited

## If we will start at max health
@export var start_full := true
## The health we will start at
@export var starting_health := 100.0
@export var starting_max_health := 100.0
## Signed health change per second. Positive heals; negative drains health.
@export var starting_health_change_rate := 0.0
## The percentage of health we consider low
@export_range(0.0, 1.0, 0.01) var low_health_percentage := 0.15:
	set(new_percentage):
		low_health_percentage = clampf(new_percentage, 0.0, 1.0)
		if is_node_ready():
			_update_injured_state()

var health := 0.0
var max_health := Attribute.new()
var health_change_rate := Attribute.new()
var is_injured := false

func _ready() -> void:
	max_health.base_value = starting_max_health
	health_change_rate.base_value = starting_health_change_rate
	max_health.value_changed.connect(_on_max_health_changed)
	health_change_rate.value_changed.connect(_on_health_change_rate_changed)

	health = max_health.value if start_full else clampf(
		starting_health,
		0.0,
		maxf(max_health.value, 0.0),
	)
	_update_injured_state()
	_update_change_rate_processing()

func _process(delta: float) -> void:
	if is_depleted():
		_update_change_rate_processing()
		return
	var change_per_second := health_change_rate.value
	if not is_zero_approx(change_per_second):
		set_health(health + change_per_second * delta)

func increase(amount: float) -> float:
	return set_health(health + absf(amount))

func decrease(amount: float) -> float:
	return set_health(health - absf(amount))

func set_health(new_value: float) -> float:
	var previous_value := health
	health = clampf(new_value, 0.0, maxf(max_health.value, 0.0))
	if is_equal_approx(previous_value, health):
		return 0.0

	var change_amount := health - previous_value
	health_changed.emit(previous_value, health, change_amount)
	value_changed.emit(previous_value, health, change_amount)
	if previous_value > 0.0 and is_depleted():
		health_depleted.emit()
	_update_injured_state()
	_update_change_rate_processing()
	return change_amount

func get_percentage() -> float:
	if max_health.value <= 0.0:
		return 0.0
	return health / max_health.value


func get_current_value() -> float:
	return health


func get_maximum_value() -> float:
	return max_health.value

func is_depleted() -> bool:
	return is_zero_approx(health)

func is_full() -> bool:
	return is_equal_approx(health, max_health.value)

func _update_injured_state() -> void:
	var should_be_injured := get_percentage() <= low_health_percentage
	if should_be_injured == is_injured:
		return

	is_injured = should_be_injured
	injured_state_changed.emit(is_injured)
	if is_injured:
		injured_state_entered.emit()
	else:
		injured_state_exited.emit()

func _update_change_rate_processing() -> void:
	var change_per_second := health_change_rate.value
	var can_increase := change_per_second > 0.0 and not is_full()
	var can_decrease := change_per_second < 0.0
	# Passive changes cannot revive depleted health.
	set_process(is_node_ready() and not is_depleted() and (can_increase or can_decrease))

func _on_max_health_changed(
	_previous_maximum: float,
	new_maximum: float,
	_change_amount: float,
) -> void:
	# Increasing maximum health does not automatically heal.
	if health > new_maximum:
		set_health(new_maximum)
	else:
		# Notify generic displays because the percentage changed.
		value_changed.emit(health, health, 0.0)
		_update_injured_state()
		_update_change_rate_processing()

func _on_health_change_rate_changed(
	_previous_rate: float,
	_current_rate: float,
	_change_amount: float,
) -> void:
	_update_change_rate_processing()
