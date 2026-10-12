@tool
class_name Mule
extends SpaceShip3D
## The mule is a cargo ship with a modular hull. 
## This ship can generate in the world with a dynamic range of segments

## A segment of the ship.
const MULE_CARGO_SEGMENT = preload("uid://dcbnhr2pwhc8v")
const SEGMENT_LENGTH := 4.0
const MINIMUM_SEGMENTS := 0
const MAXIMUM_SEGMENTS := 2
## Outside of the hull, as one box the physics body collides with.
const HULL_WIDTH := 4.75
const HULL_HEIGHT := 3.25

## Changes how many cargo segments the ship will have
@export_range(MINIMUM_SEGMENTS, MAXIMUM_SEGMENTS, 1) var segments: int = 1:
	set(value):
		var clamped_value := clampi(value, MINIMUM_SEGMENTS, MAXIMUM_SEGMENTS)
		if segments == clamped_value:
			return
		segments = clamped_value
		_queue_segment_rebuild()

## An area for the cargo hull of the ship that changes depending on the amount of segments
var _segment_rebuild_queued := false

@onready var top_rear_module: Node3D = $MuleStern/CSGCylinder3D/TopRearModule

func _ready() -> void:
	super._ready()
	_rebuild_segments()

func _queue_segment_rebuild() -> void:
	if not is_inside_tree() or _segment_rebuild_queued:
		return
	_segment_rebuild_queued = true
	call_deferred("_rebuild_segments")


func _rebuild_segments() -> void:
	_segment_rebuild_queued = false
	if not is_inside_tree():
		return

	var segment_container := get_node_or_null("Segments") as Node3D
	var dynamic_cargo_area := get_node_or_null("Area/DynamicCargoArea") as CollisionShape3D
	var hull := get_node_or_null("Hull") as CollisionShape3D
	var mule_bow := get_node_or_null("MuleBow") as Node3D
	var mule_stern := get_node_or_null("MuleStern") as Node3D
	if (
		segment_container == null
		or dynamic_cargo_area == null
		or mule_bow == null
		or mule_stern == null
	):
		push_warning("Mule requires Segments, Area/DynamicCargoArea, MuleBow, and MuleStern nodes.")
		return

	for child in segment_container.get_children():
		child.free()

	var center_index := (float(segments) - 1.0) * 0.5
	for index in segments:
		var segment := MULE_CARGO_SEGMENT.instantiate() as Node3D
		segment.name = "CargoSegment%d" % (index + 1)
		segment.position = Vector3(0.0, 0.0, (float(index) - center_index) * SEGMENT_LENGTH)
		segment_container.add_child(segment)

	var cargo_length := SEGMENT_LENGTH * (float(segments) + 2.0)
	var dynamic_shape := dynamic_cargo_area.shape as BoxShape3D
	if dynamic_shape != null:
		dynamic_shape.size = Vector3(4.0, 2.5, cargo_length)
	var hull_shape := hull.shape as BoxShape3D if hull != null else null
	if hull_shape != null:
		hull_shape.size = Vector3(HULL_WIDTH, HULL_HEIGHT, cargo_length)

	var end_offset := (SEGMENT_LENGTH + SEGMENT_LENGTH * float(segments)) * 0.5
	mule_bow.position = Vector3(0.0, 0.0, -end_offset)
	mule_stern.position = Vector3(0.0, 0.0, end_offset)
