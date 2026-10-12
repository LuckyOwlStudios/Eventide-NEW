@icon("uid://bdtpjdtqo1qch")
class_name VehicleController
extends SeatController
## SeatController specialization that also transfers vehicle and camera control.

signal vehicle_entered(vehicle: Node3D)
signal vehicle_exited(vehicle: Node3D)

@export_category("Player Components")
@export var player_camera: Camera3D
@export var player_view_root: Node3D
@export var visual_root: Node3D

## The vehicle or turret being controlled.
var current_vehicle: Node3D

var _view_was_visible := true
var _visual_was_visible := true


func _ready() -> void:
	super._ready()
	if is_local_controller() and is_instance_valid(player_camera):
		player_camera.current = true


func enter_vehicle(vehicle: Node3D) -> bool:
	if not is_instance_valid(vehicle):
		return false
	var seat := _find_vehicle_seat(vehicle)
	return is_instance_valid(seat) and enter_seat(seat)


func exit_vehicle() -> bool:
	return is_instance_valid(current_vehicle) and exit_seat()


func _on_seat_entered(seat: Node) -> void:
	if not seat is VehicleSeat3D:
		return
	current_vehicle = (seat as VehicleSeat3D).vehicle
	if is_instance_valid(player_view_root):
		_view_was_visible = player_view_root.visible
		player_view_root.visible = false
	if is_instance_valid(visual_root):
		_visual_was_visible = visual_root.visible
		visual_root.visible = false
	if is_instance_valid(player_camera):
		player_camera.current = false
	if is_instance_valid(current_vehicle) and is_instance_valid(current_vehicle.vehicle_camera):
		current_vehicle.vehicle_camera.current = true

	vehicle_entered.emit(current_vehicle)


func _on_seat_exited(seat: Node) -> void:
	if not seat is VehicleSeat3D:
		return
	var previous := current_vehicle
	if is_instance_valid(previous) and is_instance_valid(previous.vehicle_camera):
		previous.vehicle_camera.current = false
	current_vehicle = null
	if is_instance_valid(player_view_root):
		player_view_root.visible = _view_was_visible
	if is_instance_valid(visual_root):
		visual_root.visible = _visual_was_visible
	if is_instance_valid(player_camera):
		player_camera.current = true

	vehicle_exited.emit(previous)


func _find_vehicle_seat(root: Node) -> VehicleSeat3D:
	for child in root.get_children():
		if child is VehicleSeat3D:
			return child as VehicleSeat3D
		var nested := _find_vehicle_seat(child)
		if is_instance_valid(nested):
			return nested
	return null
