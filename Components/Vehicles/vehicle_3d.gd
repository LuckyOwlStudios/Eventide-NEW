@icon("uid://b41c6dwvtv4qm")
class_name Vehicle3D
extends Node3D
## Base for anything a player can temporarily control.

signal control_started(controller: VehicleController)
signal control_ended(controller: VehicleController)

@export var vehicle_camera: Camera3D

var controller: VehicleController

func _ready() -> void:
	if is_instance_valid(vehicle_camera):
		vehicle_camera.current = false

func can_be_controlled_by(candidate: VehicleController) -> bool:
	return is_instance_valid(candidate) and not is_instance_valid(controller)

func claim_control(candidate: VehicleController) -> bool:
	if not can_be_controlled_by(candidate):
		return false
	controller = candidate
	_on_control_started(candidate)
	control_started.emit(candidate)
	return true

func release_control(candidate: VehicleController) -> bool:
	if not is_instance_valid(controller) or controller != candidate:
		return false
	var previous := controller
	controller = null
	_on_control_ended(previous)
	control_ended.emit(previous)
	return true

func has_local_control() -> bool:
	return is_instance_valid(controller) and controller.is_local_controller()

func _on_control_started(_controller: VehicleController) -> void:
	pass

func _on_control_ended(_controller: VehicleController) -> void:
	pass
