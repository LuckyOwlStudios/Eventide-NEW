class_name DoorSwitch3D
extends InteractableObject3D
## An interactable that opens and closes a HingedDoor3D. Place it on a button,
## a lever, or the door itself; several switches can share one door.
##
## It starts with an "Open" option, offered while the door is closed, and a
## "Close" option, offered while it is open. Options with other IDs just toggle.

const OPEN_OPTION_ID: StringName = &"open"
const CLOSE_OPTION_ID: StringName = &"close"

@export var door: HingedDoor3D


func _init() -> void:
	interaction_options.clear()
	for option_data in [
		[OPEN_OPTION_ID, "Open"],
		[CLOSE_OPTION_ID, "Close"],
	]:
		var option := _create_default_interaction_option()
		option.option_id = option_data[0]
		option.prompt = option_data[1]
		interaction_options.append(option)


func _can_interact_option(_interactor: Node3D, option_index: int) -> bool:
	if not is_instance_valid(door):
		return false
	match _get_option_id(option_index):
		OPEN_OPTION_ID:
			return not door.open_requested
		CLOSE_OPTION_ID:
			return door.open_requested
	return true


func _interact_option(_interactor: Node3D, option_index: int) -> bool:
	if not is_instance_valid(door):
		return false
	match _get_option_id(option_index):
		OPEN_OPTION_ID:
			door.open()
		CLOSE_OPTION_ID:
			door.close()
		_:
			door.toggle()
	return true


func _get_option_id(option_index: int) -> StringName:
	var option := get_interaction_option(option_index)
	return StringName(option.option_id) if option != null else &""
