extends Node

## --- INGAME NODES ---
## Used for nodes that are only enabled during game sessions
var _radio_manager: RadioManager
#region Radio Manager Help Functions
## Whether this game session has a active [RadioManager]
func has_radio_manager() -> bool:
	return is_instance_valid(_radio_manager)

## Register an [RadioManager] to this in-game session
func register_radio_manager(manager: RadioManager) -> void:
	_radio_manager = manager

## Remove registered [RadioManager] from this in-game session
func unregister_radio_manager(manager: RadioManager) -> void:
	if _radio_manager == manager:
		_radio_manager = null

## Retrieve a [RadioManager] from this in-game session
func get_radio_manager() -> RadioManager:
	assert(
		is_instance_valid(_radio_manager),
		"RadioManager requested outside an active game."
	)
	return _radio_manager

func get_radio_manager_or_null() -> RadioManager:
	return _radio_manager if is_instance_valid(_radio_manager) else null
#endregion
