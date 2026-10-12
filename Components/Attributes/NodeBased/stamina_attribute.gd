@icon("uid://ctb4scdjy5tbx")
class_name Stamina
extends AttributeNode

signal stamina_changed(previous_value: float, current_value: float, change_amount: float)
signal stamina_depleted
signal stamina_filled
signal regen_cooldown_started(duration: float)
signal regen_cooldown_finished

@export var start_full := true
@export var starting_stamina := 100.0
@export var starting_max_stamina := 100.0
@export var starting_regen_cooldown := 1.0
## Signed stamina change per second. Positive regenerates; negative consumes.
@export var starting_stamina_change_rate := 25.0

var stamina := 0.0
var max_stamina := Attribute.new()
var regen_cooldown := Attribute.new()
var stamina_change_rate := Attribute.new()

var _time_since_decrease := 0.0
var _was_on_regen_cooldown := false


func _ready() -> void:
	max_stamina.base_value = starting_max_stamina
	regen_cooldown.base_value = starting_regen_cooldown
	stamina_change_rate.base_value = starting_stamina_change_rate
	max_stamina.value_changed.connect(_on_max_stamina_changed)
	regen_cooldown.value_changed.connect(_on_regen_cooldown_changed)
	stamina_change_rate.value_changed.connect(_on_stamina_change_rate_changed)

	stamina = max_stamina.value if start_full else clampf(
		starting_stamina,
		0.0,
		maxf(max_stamina.value, 0.0),
	)
	_time_since_decrease = maxf(regen_cooldown.value, 0.0)
	_update_processing()


func _process(delta: float) -> void:
	var change_per_second := stamina_change_rate.value

	if change_per_second < 0.0 and not is_depleted():
		_set_stamina(stamina + change_per_second * delta, true)
		return

	var regeneration_delta := delta
	var cooldown_remaining := get_regen_cooldown_remaining()
	var was_on_cooldown := cooldown_remaining > 0.0
	if was_on_cooldown:
		_time_since_decrease += delta
		regeneration_delta = maxf(delta - cooldown_remaining, 0.0)
	if was_on_cooldown and not is_regen_on_cooldown():
		_was_on_regen_cooldown = false
		regen_cooldown_finished.emit()

	if change_per_second > 0.0 and not is_regen_on_cooldown() and not is_full():
		_set_stamina(stamina + change_per_second * regeneration_delta, false)

	_update_processing()


## Atomically consumes stamina. Returns false without consuming if there is not enough.
func consume(amount: float) -> bool:
	var cost := absf(amount)
	if cost <= 0.0:
		return true
	if stamina + 0.00001 < cost:
		return false
	_set_stamina(stamina - cost, true)
	return true


func can_consume(amount: float) -> bool:
	return stamina + 0.00001 >= absf(amount)


## Partially consumes stamina and returns the amount actually consumed.
func decrease(amount: float) -> float:
	var previous_value := stamina
	_set_stamina(stamina - absf(amount), true)
	return previous_value - stamina


## Restores stamina and returns the amount actually restored.
func increase(amount: float) -> float:
	var previous_value := stamina
	_set_stamina(stamina + absf(amount), false)
	return stamina - previous_value


func set_stamina(new_value: float) -> float:
	return _set_stamina(new_value, new_value < stamina)


func get_percentage() -> float:
	if max_stamina.value <= 0.0:
		return 0.0
	return stamina / max_stamina.value


func get_current_value() -> float:
	return stamina


func get_maximum_value() -> float:
	return max_stamina.value


func get_regen_cooldown_remaining() -> float:
	return maxf(maxf(regen_cooldown.value, 0.0) - _time_since_decrease, 0.0)


func is_regen_on_cooldown() -> bool:
	return get_regen_cooldown_remaining() > 0.0


func is_depleted() -> bool:
	return is_zero_approx(stamina)


func is_full() -> bool:
	return is_equal_approx(stamina, max_stamina.value)


func _set_stamina(new_value: float, restart_regen_cooldown: bool) -> float:
	var previous_value := stamina
	stamina = clampf(new_value, 0.0, maxf(max_stamina.value, 0.0))
	if is_equal_approx(previous_value, stamina):
		return 0.0

	if restart_regen_cooldown and stamina < previous_value:
		_restart_regen_cooldown()

	var change_amount := stamina - previous_value
	stamina_changed.emit(previous_value, stamina, change_amount)
	value_changed.emit(previous_value, stamina, change_amount)
	if previous_value > 0.0 and is_depleted():
		stamina_depleted.emit()
	if previous_value < max_stamina.value and is_full():
		stamina_filled.emit()
	_update_processing()
	return change_amount


func _restart_regen_cooldown() -> void:
	_time_since_decrease = 0.0
	var is_now_on_cooldown := is_regen_on_cooldown()
	if is_now_on_cooldown and not _was_on_regen_cooldown:
		_was_on_regen_cooldown = true
		regen_cooldown_started.emit(maxf(regen_cooldown.value, 0.0))


func _update_processing() -> void:
	var rate := stamina_change_rate.value
	var can_drain := rate < 0.0 and not is_depleted()
	var can_recover := not is_full() and (is_regen_on_cooldown() or rate > 0.0)
	var should_process := is_node_ready() and (can_drain or can_recover)
	set_process(should_process)


func _on_max_stamina_changed(
	_previous_maximum: float,
	new_maximum: float,
	_change_amount: float,
) -> void:
	if stamina > new_maximum:
		_set_stamina(new_maximum, false)
	else:
		# Notify generic displays because the percentage changed.
		value_changed.emit(stamina, stamina, 0.0)
		_update_processing()


func _on_regen_cooldown_changed(
	_previous_cooldown: float,
	_current_cooldown: float,
	_change_amount: float,
) -> void:
	var is_now_on_cooldown := is_regen_on_cooldown()
	if _was_on_regen_cooldown and not is_now_on_cooldown:
		_was_on_regen_cooldown = false
		regen_cooldown_finished.emit()
	elif not _was_on_regen_cooldown and is_now_on_cooldown:
		_was_on_regen_cooldown = true
		regen_cooldown_started.emit(maxf(regen_cooldown.value, 0.0))
	_update_processing()


func _on_stamina_change_rate_changed(
	_previous_rate: float,
	_current_rate: float,
	_change_amount: float,
) -> void:
	_update_processing()
