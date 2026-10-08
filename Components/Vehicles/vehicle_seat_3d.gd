class_name VehicleSeat3D
extends Seat3D
## Seat3D specialization that grants its occupant control of a Vehicle3D.

@export var vehicle: Vehicle3D

func _ready() -> void:
	if not is_instance_valid(vehicle):
		vehicle = get_parent() as Vehicle3D
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
