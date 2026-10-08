## Active flashlight behavior. This scene exists only while the item is in use.
class_name FlashlightActor
extends ItemActor

signal toggled(enabled: bool)

@export_range(0.0, 100.0, 0.1, "or_greater") var power_drain_per_second := 1.0

@onready var light: SpotLight3D = %Light

var is_on := false
var flashlight_instance: FlashlightInstance

func _ready() -> void:
	super._ready()

func primary_use() -> void:
	if flashlight_instance == null:
		return
	_set_enabled(not is_on and flashlight_instance.power_level > 0.0)

func _process(delta: float) -> void:
	if not is_on or flashlight_instance == null:
		return
	flashlight_instance.power_level -= power_drain_per_second * delta
	if is_zero_approx(flashlight_instance.power_level):
		_set_enabled(false)

func _on_item_instance_changed() -> void:
	flashlight_instance = item_instance as FlashlightInstance
	if item_instance != null and flashlight_instance == null:
		push_warning("[FlashlightActor] Expected a FlashlightInstance.")
	_set_enabled(false)

func _set_enabled(value: bool) -> void:
	is_on = value and flashlight_instance != null and flashlight_instance.power_level > 0.0
	if is_instance_valid(light):
		light.visible = is_on
	set_process(is_on)
	toggled.emit(is_on)
