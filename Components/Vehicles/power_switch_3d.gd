class_name PowerSwitch3D
extends InteractableObject3D
## A switch that turns a vehicle's power on and off (its lights, hydraulic doors and so on). Put it
## on a button or lever inside the vehicle. Power does not depend on the engines, and turning it
## off also stops them.
##
## It offers "Turn Power On" while the power is off and "Turn Power Off" while it is on.
##
## Give it a [Lever3D] and the lever follows the power: pulled down while the power is on, up while it
## is off. It follows whoever changed the power, so a lever does not lie when the power is cut some
## other way.

const ON_OPTION_ID: StringName = &"power_on"
const OFF_OPTION_ID: StringName = &"power_off"

## The vehicle it switches. The nearest one above this node when left empty.
@export var vehicle: Vehicle3D
## The lever that shows the power: down when on, up when off. Optional.
@export var lever: Lever3D


func _init() -> void:
	interaction_options.clear()
	for option_data in [
		[ON_OPTION_ID, "Turn Power On"],
		[OFF_OPTION_ID, "Turn Power Off"],
	]:
		var option := _create_default_interaction_option()
		option.option_id = option_data[0]
		option.prompt = option_data[1]
		interaction_options.append(option)


func _ready() -> void:
	if not is_instance_valid(vehicle):
		vehicle = _find_vehicle_above()
	if is_instance_valid(vehicle):
		vehicle.power_state_changed.connect(_on_power_state_changed)
		if is_instance_valid(lever):
			# Ready runs children first, so the lever has already noted where it starts.
			lever.snap(vehicle.power_state)
	super._ready()


func _can_interact_option(_interactor: Node3D, option_index: int) -> bool:
	if not is_instance_valid(vehicle):
		return false
	match _get_option_id(option_index):
		ON_OPTION_ID:
			return not vehicle.power_state
		OFF_OPTION_ID:
			return vehicle.power_state
	return true


func _interact_option(_interactor: Node3D, option_index: int) -> bool:
	if not is_instance_valid(vehicle):
		return false
	match _get_option_id(option_index):
		ON_OPTION_ID:
			vehicle.power_state = true
		OFF_OPTION_ID:
			vehicle.power_state = false
		_:
			vehicle.power_state = not vehicle.power_state
	return true


func _on_power_state_changed(powered: bool) -> void:
	if is_instance_valid(lever):
		lever.down = powered


func _get_option_id(option_index: int) -> StringName:
	var option := get_interaction_option(option_index)
	return StringName(option.option_id) if option != null else &""


func _find_vehicle_above() -> Vehicle3D:
	var node := get_parent()
	while node != null:
		if node is Vehicle3D:
			return node as Vehicle3D
		node = node.get_parent()
	return null
