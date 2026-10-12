class_name VehicleSeat3D
extends Seat3D
## Seat3D specialization that grants its occupant control of a vehicle.
##
## The vehicle is a [Vehicle3D] or a [Turret3D]: anything that has can_be_controlled_by(),
## claim_control() and release_control() and a vehicle_camera.

## What the seat controls. The nearest vehicle or turret above the seat when left empty, so a
## seat can sit inside a ship's modules.
@export var vehicle: Node3D

func _ready() -> void:
	if not is_instance_valid(vehicle):
		vehicle = _find_controllable_above()
	if is_instance_valid(vehicle) and not vehicle.has_method(&"claim_control"):
		push_error("VehicleSeat3D %s: %s cannot be controlled (it is not a Vehicle3D or Turret3D)." % [name, vehicle.name])
		vehicle = null
	super._ready()

func _can_accept_occupant(candidate: Node) -> bool:
	return (
		is_instance_valid(vehicle)
		and candidate is VehicleController
		and vehicle.can_be_controlled_by(candidate as VehicleController)
	)


func _claim_specialized_occupancy(candidate: Node) -> bool:
	return vehicle.claim_control(candidate as VehicleController)


func _release_specialized_occupancy(candidate: Node) -> bool:
	return vehicle.release_control(candidate as VehicleController)


func _find_controllable_above() -> Node3D:
	var node := get_parent()
	while node != null:
		if node is Node3D and node.has_method(&"claim_control"):
			return node as Node3D
		node = node.get_parent()
	return null
