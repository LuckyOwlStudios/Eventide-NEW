extends Node
## Headless regression test for generic seats and vehicle seats.

const VEHICLE_CONTROLLER_SCRIPT := preload("res://Components/Vehicles/vehicle_controller.gd")
const SEAT_SCRIPT := preload("res://Components/Seats/seat_3d.gd")
const VEHICLE_SCRIPT := preload("res://Components/Vehicles/vehicle_3d.gd")
const VEHICLE_SEAT_SCRIPT := preload("res://Components/Vehicles/vehicle_seat_3d.gd")

var _failures: Array[String] = []


func _ready() -> void:
	var actor := CharacterBody3D.new()
	actor.name = "TestActor"
	var mover := Node.new()
	mover.name = "Mover"
	actor.add_child(mover)
	var rotator := Node.new()
	rotator.name = "Rotator"
	actor.add_child(rotator)
	var orientor := Node.new()
	orientor.name = "Orientor"
	actor.add_child(orientor)
	var controller = VEHICLE_CONTROLLER_SCRIPT.new()
	controller.name = "VehicleController"
	controller.character_mover = mover
	controller.player_rotator = rotator
	controller.orientation_component = orientor
	actor.add_child(controller)
	add_child(actor)

	var ordinary_seat = SEAT_SCRIPT.new()
	ordinary_seat.name = "OrdinarySeat"
	var ordinary_mount := Marker3D.new()
	ordinary_mount.name = "SeatMount"
	ordinary_mount.position = Vector3(2.0, 1.0, 0.0)
	ordinary_seat.add_child(ordinary_mount)
	var ordinary_exit := Marker3D.new()
	ordinary_exit.name = "DismountPoint"
	ordinary_exit.position = Vector3(4.0, 0.0, 0.0)
	ordinary_seat.add_child(ordinary_exit)
	add_child(ordinary_seat)

	await get_tree().process_frame
	_expect(controller.enter_seat(ordinary_seat), "An available ordinary seat can be entered.")
	_expect(ordinary_seat.occupant == controller, "The ordinary seat stores its occupant.")
	_expect(controller.current_seat == ordinary_seat, "The controller stores its current seat.")
	_expect(actor.collision_layer == 0 and actor.collision_mask == 0, "Seated collision is disabled.")
	_expect(mover.process_mode == Node.PROCESS_MODE_DISABLED, "Movement is disabled while seated.")
	_expect(rotator.process_mode == Node.PROCESS_MODE_DISABLED, "Look is disabled while seated.")
	_expect(orientor.process_mode == Node.PROCESS_MODE_DISABLED, "Orientation is disabled while seated.")
	_expect(controller.exit_seat(), "An occupied ordinary seat can be exited.")
	_expect(not is_instance_valid(ordinary_seat.occupant), "The ordinary seat is released on exit.")
	_expect(actor.collision_layer == 1 and actor.collision_mask == 1, "Collision is restored on exit.")
	_expect(mover.process_mode == Node.PROCESS_MODE_INHERIT, "Movement is restored on exit.")
	_expect(actor.global_position.is_equal_approx(ordinary_exit.global_position), "The actor uses the dismount point.")

	var vehicle = VEHICLE_SCRIPT.new()
	vehicle.name = "TestVehicle"
	var vehicle_seat = VEHICLE_SEAT_SCRIPT.new()
	vehicle_seat.name = "VehicleSeat"
	vehicle_seat.vehicle = vehicle
	var vehicle_mount := Marker3D.new()
	vehicle_mount.name = "SeatMount"
	vehicle_seat.add_child(vehicle_mount)
	var vehicle_exit := Marker3D.new()
	vehicle_exit.name = "DismountPoint"
	vehicle_exit.position = Vector3.RIGHT * 3.0
	vehicle_seat.add_child(vehicle_exit)
	vehicle.add_child(vehicle_seat)
	add_child(vehicle)

	await get_tree().process_frame
	_expect(controller.enter_vehicle(vehicle), "A free vehicle seat can be entered.")
	_expect(vehicle.controller == controller, "The vehicle grants control to the occupant.")
	_expect(controller.current_vehicle == vehicle, "The controller tracks the active vehicle.")
	_expect(controller.exit_vehicle(), "The active vehicle can be exited.")
	_expect(not is_instance_valid(vehicle.controller), "Vehicle control is released on exit.")
	_expect(not is_instance_valid(controller.current_vehicle), "The controller clears the active vehicle.")

	if _failures.is_empty():
		print("SEAT SYSTEM TEST: PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("SEAT SYSTEM TEST: FAIL (%d failure(s))" % _failures.size())
		get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
