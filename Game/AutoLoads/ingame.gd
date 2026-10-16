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

var _temperature_handler: TemperatureHandler
#region Temperature Handler Help Functions
## Whether this game session has an active [TemperatureHandler]
func has_temperature_handler() -> bool:
	return is_instance_valid(_temperature_handler)

## Register a [TemperatureHandler] to this in-game session
func register_temperature_handler(handler: TemperatureHandler) -> void:
	_temperature_handler = handler

## Remove registered [TemperatureHandler] from this in-game session
func unregister_temperature_handler(handler: TemperatureHandler) -> void:
	if _temperature_handler == handler:
		_temperature_handler = null

## Retrieve the [TemperatureHandler] from this in-game session
func get_temperature_handler() -> TemperatureHandler:
	assert(
		is_instance_valid(_temperature_handler),
		"TemperatureHandler requested outside an active game."
	)
	return _temperature_handler

func get_temperature_handler_or_null() -> TemperatureHandler:
	return _temperature_handler if is_instance_valid(_temperature_handler) else null
#endregion
