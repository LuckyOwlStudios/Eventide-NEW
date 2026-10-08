class_name Seat3D
extends InteractableObject3D
## An interactable place that can hold one actor through its SeatController.

const SEAT_CONTROLLER_SCRIPT := preload("res://Components/Seats/seat_controller.gd")

signal occupied(controller: Node)
signal vacated(controller: Node)

@export var seat_mount: Node3D
@export var dismount_point: Node3D

var occupant: Node

func _ready() -> void:
	_resolve_markers()
	super._ready()


func can_be_occupied_by(candidate: Node) -> bool:
	return (
		is_instance_valid(candidate)
		and not is_instance_valid(occupant)
		and _can_accept_occupant(candidate)
	)


func claim_occupancy(candidate: Node) -> bool:
	if not can_be_occupied_by(candidate):
		return false
	if not _claim_specialized_occupancy(candidate):
		return false
	occupant = candidate
	runtime_status = "Occupied by %s." % candidate.get_parent().name
	occupied.emit(candidate)
	return true


func release_occupancy(candidate: Node) -> bool:
	if not is_instance_valid(occupant) or occupant != candidate:
		return false
	if not _release_specialized_occupancy(candidate):
		return false
	var previous := occupant
	occupant = null
	runtime_status = "Seat is available."
	vacated.emit(previous)
	return true


func get_seat_transform() -> Transform3D:
	return seat_mount.global_transform if is_instance_valid(seat_mount) else global_transform


func get_dismount_transform() -> Transform3D:
	if is_instance_valid(dismount_point):
		return dismount_point.global_transform
	return global_transform.translated_local(Vector3.RIGHT * 1.5)


func _can_interact_option(interactor: Node3D, _option_index: int) -> bool:
	return can_be_occupied_by(SEAT_CONTROLLER_SCRIPT.find_on_actor(interactor))


func _interact_option(interactor: Node3D, _option_index: int) -> bool:
	var candidate = SEAT_CONTROLLER_SCRIPT.find_on_actor(interactor)
	return is_instance_valid(candidate) and candidate.enter_seat(self)


## Extension points for specialized seats. Failed claims leave the seat unoccupied.
func _can_accept_occupant(_candidate: Node) -> bool:
	return true


func _claim_specialized_occupancy(_candidate: Node) -> bool:
	return true


func _release_specialized_occupancy(_candidate: Node) -> bool:
	return true


func _resolve_markers() -> void:
	if not is_instance_valid(seat_mount):
		seat_mount = get_node_or_null("SeatMount") as Marker3D
	# Compatibility with vehicle scenes created before Seat3D existed.
	if not is_instance_valid(seat_mount):
		seat_mount = get_node_or_null("DriverMount") as Marker3D
	if not is_instance_valid(dismount_point):
		dismount_point = get_node_or_null("DismountPoint") as Marker3D
