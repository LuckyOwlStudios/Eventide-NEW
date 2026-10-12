class_name DetectionArea3D
extends Area3D

enum SEARCH_TYPE {
	## We compare the direction this object is facing to the direction of another to see if we can see it.
	ANGLE_BASED,
	## We compare this objects yaw and pitch to the direction to another node to see if we can see it
	ORIENTATION_ANGLE_BASED
}

## The search distance of this [DetectionArea3D]
@export var radius: float:
	set(value):
		sphere_shape.radius = value
	get():
		return sphere_shape.radius
@export_group("Angle Based Search")
## The angle in which we can detect an object
@export var max_angle: float = 135
@export_group("Orientation Based Searching")
## Uses this node's up direction [param global_transform.basis.y] for orientation based searching.
## If not present, the node will default to angle based search.
@export var orientation_reference: Node3D
@export var max_yaw: float = 90
@export var max_pitch: float = 90

var collision_shape: CollisionShape3D:
	get(): return get_node("CollisionShape3D")
var sphere_shape: SphereShape3D:
	set(value): collision_shape.shape = value
	get(): return collision_shape.shape as SphereShape3D

## An array of objects that are considered detected
var detected_objects: Array[Node3D]

func _ready() -> void:
	var new_collision_shape := CollisionShape3D.new()
	add_child(new_collision_shape)

func closest_detected_object() -> Node3D:
	if detected_objects.is_empty():
		return null
	var closest: Node3D = null
	var closest_distance: float = INF
	for object in detected_objects:
		var distance := global_position.distance_to(object.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest = object
	return closest
