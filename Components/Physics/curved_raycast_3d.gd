@tool
@icon("uid://dxvtpuww44k6i")
class_name CurvedRayCast3D
extends Node3D
## Casts a sequence of straight physics rays along a circular arc.
##
## The node is the center of the circle. The arc starts [member radius] meters
## along local -Z and sweeps around local +Y. Rotate the node to orient the arc.
## Collision angles are reported in degrees to match [member target_angle].

enum ArcDirection {
	COUNTERCLOCKWISE,
	CLOCKWISE,
}

const MINIMUM_RADIUS := 0.001
const MINIMUM_ANGLE_STEP := 0.1

## Enables automatic collision updates on every physics tick.
@export var enabled := true:
	set(value):
		enabled = value
		if is_inside_tree() and not Engine.is_editor_hint():
			set_physics_process(enabled)
		if not enabled:
			_clear_collision()
		_refresh_gizmo()

## Excludes the parent when it is a CollisionObject3D, matching RayCast3D.
@export var exclude_parent := true

## Maximum sweep around the circle, in degrees.
@export_range(0.0, 360.0, 0.1, "suffix:°") var target_angle := 90.0:
	set(value):
		target_angle = clampf(value, 0.0, 360.0)
		_refresh_gizmo()

## Distance from the node (the center of rotation) to the curved ray.
@export_range(MINIMUM_RADIUS, 1000.0, 0.01, "or_greater", "suffix:m") var radius := 1.0:
	set(value):
		radius = maxf(value, MINIMUM_RADIUS)
		_refresh_gizmo()

## Chooses which way the arc sweeps around local +Y.
@export_enum("Counterclockwise", "Clockwise") var arc_direction: int = ArcDirection.COUNTERCLOCKWISE:
	set(value):
		arc_direction = clampi(value, ArcDirection.COUNTERCLOCKWISE, ArcDirection.CLOCKWISE)
		_refresh_gizmo()

## Maximum angle covered by each straight collision query. Smaller values follow
## the circle more accurately at the cost of additional physics queries.
@export_range(MINIMUM_ANGLE_STEP, 45.0, 0.1, "suffix:°") var max_angle_step := 2.0:
	set(value):
		max_angle_step = maxf(value, MINIMUM_ANGLE_STEP)
		_refresh_gizmo()

@export_flags_3d_physics var collision_mask := 1
@export var hit_from_inside := false
@export var hit_back_faces := true

@export_group("Collide With")
@export var collide_with_areas := false
@export var collide_with_bodies := true

@export_group("Debug Shape")
@export var debug_shape_custom_color := Color(0.949, 0.322, 0.0, 1.0):
	set(value):
		debug_shape_custom_color = value
		_refresh_gizmo()
@export_range(1, 10, 1) var debug_shape_thickness := 3:
	set(value):
		debug_shape_thickness = clampi(value, 1, 10)
		_refresh_gizmo()

var _collision_result: Dictionary = {}
var _collision_angle_degrees := 0.0
var _exceptions: Array[RID] = []


func _ready() -> void:
	set_physics_process(enabled and not Engine.is_editor_hint())
	_refresh_gizmo()


func _physics_process(_delta: float) -> void:
	force_raycast_update()


## Immediately refreshes the collision result without waiting for the next
## physics tick. Like RayCast3D, this can be called even when disabled.
func force_raycast_update() -> void:
	if not is_inside_tree() or Engine.is_editor_hint():
		return
	var world := get_world_3d()
	if world == null or target_angle <= 0.0:
		_clear_collision()
		return

	var space_state := world.direct_space_state
	var arc_points := get_arc_points()
	var exclusions := _get_query_exclusions()
	for index in range(arc_points.size() - 1):
		var from := to_global(arc_points[index])
		var to := to_global(arc_points[index + 1])
		var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask, exclusions)
		query.collide_with_areas = collide_with_areas
		query.collide_with_bodies = collide_with_bodies
		query.hit_back_faces = hit_back_faces
		query.hit_from_inside = hit_from_inside
		var result := space_state.intersect_ray(query)
		if result.is_empty():
			continue

		_collision_result = result
		var segment_length := from.distance_to(to)
		var segment_fraction := 0.0
		if segment_length > 0.0:
			segment_fraction = clampf(
				from.distance_to(result["position"]) / segment_length,
				0.0,
				1.0,
			)
		var segment_count := arc_points.size() - 1
		var angle_per_segment := target_angle / float(segment_count)
		_collision_angle_degrees = (float(index) + segment_fraction) * angle_per_segment
		return

	_clear_collision()


## Returns local points describing the complete circular path. This is useful for
## custom visualization in addition to powering the editor gizmo.
func get_arc_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	var segment_count := maxi(1, ceili(target_angle / max_angle_step))
	for index in range(segment_count + 1):
		var fraction := float(index) / float(segment_count)
		points.append(get_arc_point(target_angle * fraction))
	return points


## Returns a local-space point on the configured circle at [param angle_degrees].
func get_arc_point(angle_degrees: float) -> Vector3:
	return Vector3.FORWARD.rotated(
		Vector3.UP,
		deg_to_rad(angle_degrees) * get_direction_sign(),
	) * radius


func is_colliding() -> bool:
	return not _collision_result.is_empty()


func get_collider() -> Object:
	return _collision_result.get("collider") as Object


func get_collider_id() -> int:
	return int(_collision_result.get("collider_id", 0))


func get_collider_rid() -> RID:
	return _collision_result.get("rid", RID()) as RID


func get_collider_shape() -> int:
	return int(_collision_result.get("shape", -1))


func get_collision_point() -> Vector3:
	return _collision_result.get("position", Vector3.ZERO) as Vector3


func get_collision_normal() -> Vector3:
	return _collision_result.get("normal", Vector3.ZERO) as Vector3


func get_collision_face_index() -> int:
	return int(_collision_result.get("face_index", -1))


## Returns the angle of the first collision in degrees, or 0 when clear.
func get_collision_angle() -> float:
	return _collision_angle_degrees if is_colliding() else 0.0


## Returns the angle of the first collision in radians, or 0 when clear.
func get_collision_angle_radians() -> float:
	return deg_to_rad(get_collision_angle())


## Returns the signed collision angle. Clockwise arcs return a negative value.
func get_signed_collision_angle() -> float:
	return get_collision_angle() * get_direction_sign()


func get_signed_collision_angle_radians() -> float:
	return deg_to_rad(get_signed_collision_angle())


## Returns the collision angle when blocked, otherwise [member target_angle].
## This is the most convenient value for a constrained door or rotating arm.
func get_safe_angle() -> float:
	return _collision_angle_degrees if is_colliding() else target_angle


func get_safe_angle_radians() -> float:
	return deg_to_rad(get_safe_angle())


## Returns the signed safe angle. Clockwise arcs return a negative value.
func get_signed_safe_angle() -> float:
	return get_safe_angle() * get_direction_sign()


func get_signed_safe_angle_radians() -> float:
	return deg_to_rad(get_signed_safe_angle())


func get_direction_sign() -> float:
	return -1.0 if arc_direction == ArcDirection.CLOCKWISE else 1.0


func get_collision_fraction() -> float:
	if target_angle <= 0.0:
		return 0.0
	return get_safe_angle() / target_angle


func add_exception(node: CollisionObject3D) -> void:
	if is_instance_valid(node):
		add_exception_rid(node.get_rid())


func add_exception_rid(rid: RID) -> void:
	if rid.is_valid() and rid not in _exceptions:
		_exceptions.append(rid)


func remove_exception(node: CollisionObject3D) -> void:
	if is_instance_valid(node):
		remove_exception_rid(node.get_rid())


func remove_exception_rid(rid: RID) -> void:
	_exceptions.erase(rid)


func clear_exceptions() -> void:
	_exceptions.clear()


func set_collision_mask_value(layer_number: int, value: bool) -> void:
	if layer_number < 1 or layer_number > 32:
		push_error("Collision layer number must be between 1 and 32.")
		return
	var layer_bit := 1 << (layer_number - 1)
	if value:
		collision_mask |= layer_bit
	else:
		collision_mask &= ~layer_bit


func get_collision_mask_value(layer_number: int) -> bool:
	if layer_number < 1 or layer_number > 32:
		return false
	return collision_mask & (1 << (layer_number - 1)) != 0


func _get_query_exclusions() -> Array[RID]:
	var exclusions: Array[RID] = []
	for exception in _exceptions:
		if exception.is_valid():
			exclusions.append(exception)
	if exclude_parent:
		var collision_parent := get_parent() as CollisionObject3D
		if is_instance_valid(collision_parent):
			var parent_rid := collision_parent.get_rid()
			if parent_rid not in exclusions:
				exclusions.append(parent_rid)
	return exclusions


func _clear_collision() -> void:
	_collision_result.clear()
	_collision_angle_degrees = 0.0


func _refresh_gizmo() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		update_gizmos()

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not collide_with_areas and not collide_with_bodies:
		warnings.append("Collide With Areas and Collide With Bodies are both disabled.")
	return warnings
