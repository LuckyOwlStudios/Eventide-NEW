class_name Seat3D
extends InteractableObject3D
## An interactable place that can hold one actor through its SeatController.

const SEAT_CONTROLLER_SCRIPT := preload("res://Components/Seats/seat_controller.gd")

signal occupied(controller: Node)
signal vacated(controller: Node)

@export var seat_mount: Node3D
@export var dismount_point: Node3D

@export_group("Items")
## Whether the occupant can still use and see their items while sitting here. Off, items are put out of
## reach like on a ladder: no input, and the one in hand is hidden. A vehicle seat is never allowed, the
## occupant is flying the vehicle.
@export var allow_items := false

@export_group("Sitting")
## Seconds it takes to ease into the seat when sitting down, and out of it when standing up, camera
## included. 0 is instant. A vehicle seat starts at 0.
@export_range(0.0, 2.0, 0.01, "suffix:s") var transition_time := 0.15

@export_group("Looking")
## Whether the occupant can look around from the seat, inside the limits below. Off, the view stays
## as it was when they sat down.
@export var occupant_can_look := false
## Total horizontal arc they can look through, centered on the way the seat faces. 180 is 90 degrees to
## each side, 360 is all the way around.
@export_range(1.0, 360.0, 1.0, "suffix:°") var look_yaw_arc := 180.0
## How far down they can look (negative) and up (positive), from level.
@export_range(-90.0, 0.0, 1.0, "suffix:°") var look_minimum_pitch := -90.0
@export_range(0.0, 90.0, 1.0, "suffix:°") var look_maximum_pitch := 90.0

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


## Whether the occupant keeps their items. A seat that flies something overrides this to false.
func are_items_allowed() -> bool:
	return allow_items


## Whether the occupant looks around for themselves, within the seat's limits.
func can_occupant_look() -> bool:
	return occupant_can_look


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
