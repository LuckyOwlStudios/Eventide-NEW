@tool
class_name Ladder3D
extends InteractableObject3D
## A climbable ladder built on the interaction system.
##
## Local space: the ladder runs along +Y starting at its origin (the bottom), and
## the climber stands in front of it on the +Z side, facing -Z. Add one or more
## CollisionShape3D children to shape the interaction volume, exactly like an
## Area3D. Where the interaction ray hits that volume decides the height at which
## the climber mounts.

enum DismountType {
	## Climbed off the top end.
	TOP,
	## Climbed off the bottom end.
	BOTTOM,
	## Let go mid-ladder (jump off) and kept the current position.
	JUMP_OFF,
}

## Emitted when a climber claims the ladder, before the mount transition finishes.
signal mounted(climber: Node3D, climb_height: float)
## Emitted when a climber leaves. [param destination] is the global transform the
## climber is heading to (their current transform for [constant DismountType.JUMP_OFF]).
signal dismounted(climber: Node3D, dismount_type: DismountType, destination: Transform3D)

@export_group("Ladder")
## Length of the ladder along its local +Y axis.
@export_range(0.1, 100.0, 0.05, "or_greater", "suffix:m") var height := 3.0:
	set(value):
		height = maxf(value, 0.1)
		_refresh_gizmo()
## Width of the rails. Only used for the editor gizmo and the interaction selector.
@export_range(0.1, 5.0, 0.05, "or_greater", "suffix:m") var width := 0.6:
	set(value):
		width = maxf(value, 0.1)
		_refresh_gizmo()
## How far in front of the ladder (+Z) the climber's feet are held.
@export_range(0.0, 2.0, 0.01, "or_greater", "suffix:m") var climb_offset := 0.35:
	set(value):
		climb_offset = maxf(value, 0.0)
		_refresh_gizmo()
## Climbing speed in meters per second.
@export_range(0.1, 20.0, 0.1, "or_greater", "suffix:m/s") var climb_speed := 1.5
## How many actors may use the ladder at once. Zero means unlimited.
@export_range(0, 16, 1, "or_greater") var max_climbers := 1

## How far above or below their own feet a climber may grab on. At 0 you always
## mount at the height you are standing at; raise it to let the point you look at
## pull you up or down the ladder, up to this many meters.
@export_range(0.0, 100.0, 0.05, "or_greater", "suffix:m") var mount_reach := 0.0

@export_group("Prompt")
## How quickly the whole prompt follows to where it belongs. Higher is snappier; 0 jumps
## straight there.
@export_range(0.0, 60.0, 0.5) var prompt_follow_speed := 18.0
## How much of that speed applies along the ladder. Below 1 the prompt trails a little
## further behind there than it does sideways.
@export_range(0.2, 1.0, 0.05) var prompt_vertical_follow := 0.7

@export_group("Dismount")
## Where the climber lands after leaving the top, relative to the TOP of the
## ladder (so it follows [member height]). Defaults to a little behind it. The
## climber keeps the direction they were facing.
@export var top_dismount := Vector3(0.0, 0.05, -0.7):
	set(value):
		top_dismount = value
		_refresh_gizmo()
## Where the climber lands after leaving the bottom, relative to the BASE of the
## ladder. Defaults to a little in front of it.
@export var bottom_dismount := Vector3(0.0, 0.0, 1.0):
	set(value):
		bottom_dismount = value
		_refresh_gizmo()

var _climbers: Array[LadderController] = []
var _prompt_position := Vector3.ZERO
var _prompt_last_msec := -100000


func _init() -> void:
	# The prompt rides along the ladder itself, so there is no selector box to sit beside.
	show_interaction_selector = false
	center_prompt = true
	prompt_local_offset = Vector3.ZERO
	interaction_options.clear()
	interaction_options.append(_create_default_interaction_option())


func _ready() -> void:
	super._ready()
	update_configuration_warnings()


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		for climber in _climbers.duplicate():
			if is_instance_valid(climber):
				climber.abort_climb()
	_climbers.clear()
	super._exit_tree()


# --- Queries -----------------------------------------------------------------

## True when at least one actor is on the ladder.
func is_occupied() -> bool:
	return not _climbers.is_empty()


## True when another actor may mount right now.
func has_capacity() -> bool:
	return max_climbers <= 0 or _climbers.size() < max_climbers


func get_climbers() -> Array[LadderController]:
	return _climbers.duplicate()


## [param climber] may be a LadderController or the actor that owns one.
func is_climbed_by(climber: Node) -> bool:
	return _find_climber(climber) != null


func can_be_climbed_by(candidate: LadderController) -> bool:
	return (
		interaction_enabled
		and is_instance_valid(candidate)
		and not _climbers.has(candidate)
		and has_capacity()
	)


## 0 at the bottom, 1 at the top, for a climber on this ladder. Returns 0 when
## [param climber] is not on this ladder; check [method is_climbed_by] if that matters.
func get_climb_progress(climber: Node) -> float:
	var controller := _find_climber(climber)
	return controller.get_climb_progress() if controller != null else 0.0


## Distance from the bottom in meters for a climber on this ladder, else 0.
func get_climb_height(climber: Node) -> float:
	var controller := _find_climber(climber)
	return controller.get_climb_height() if controller != null else 0.0


func progress_to_height(progress: float) -> float:
	return clampf(progress, 0.0, 1.0) * height


func height_to_progress(climb_height: float) -> float:
	return clampf(climb_height / height, 0.0, 1.0)


## Height along the ladder closest to a world point, clamped to the ladder.
func get_height_at_world_position(world_position: Vector3) -> float:
	return clampf(to_local(world_position).y, 0.0, height)


func get_progress_at_world_position(world_position: Vector3) -> float:
	return height_to_progress(get_height_at_world_position(world_position))


## World point on the ladder's spine at [param climb_height].
func get_point_at_height(climb_height: float) -> Vector3:
	return to_global(Vector3(0.0, clampf(climb_height, 0.0, height), 0.0))


func get_base_position() -> Vector3:
	return to_global(Vector3.ZERO)


func get_top_position() -> Vector3:
	return to_global(Vector3(0.0, height, 0.0))


## World direction the ladder climbs toward (its local +Y).
func get_up_direction() -> Vector3:
	return global_basis.y.normalized()


## World direction a climber faces (toward the ladder, local -Z).
func get_facing_direction() -> Vector3:
	return -global_basis.z.normalized()


## World transform a climber's feet are held at for [param climb_height].
func get_climb_transform(climb_height: float) -> Transform3D:
	return _local_to_global(Transform3D(
		Basis.IDENTITY,
		Vector3(0.0, clampf(climb_height, 0.0, height), climb_offset),
	))


## World position the climber lands at after leaving the top.
func get_top_dismount_position() -> Vector3:
	return _frame() * get_top_dismount_local_position()


## World position the climber lands at after leaving the bottom.
func get_bottom_dismount_position() -> Vector3:
	return _frame() * bottom_dismount


## The landing points in this ladder's local space. The editor gizmo draws these.
func get_top_dismount_local_position() -> Vector3:
	return Vector3(0.0, height, 0.0) + top_dismount


func get_bottom_dismount_local_position() -> Vector3:
	return bottom_dismount


## The ladder's orientation at the landing point. Climbers do not take on this
## rotation: they keep facing the way they were.
func get_top_dismount_transform() -> Transform3D:
	return Transform3D(_frame().basis.orthonormalized(), get_top_dismount_position())


func get_bottom_dismount_transform() -> Transform3D:
	return Transform3D(_frame().basis.orthonormalized(), get_bottom_dismount_position())


## Global destination for TOP or BOTTOM. JUMP_OFF has no fixed destination, so the
## ladder returns the base climb transform.
func get_dismount_transform(dismount_type: DismountType) -> Transform3D:
	match dismount_type:
		DismountType.TOP:
			return get_top_dismount_transform()
		DismountType.BOTTOM:
			return get_bottom_dismount_transform()
	return get_climb_transform(0.0)


# --- Climber bookkeeping (called by LadderController) ------------------------

func claim_climber(controller: LadderController, climb_height: float) -> bool:
	if not can_be_climbed_by(controller):
		return false
	_climbers.append(controller)
	runtime_status = "%d climber(s) on the ladder." % _climbers.size()
	mounted.emit(controller.get_body(), climb_height)
	return true


func release_climber(
	controller: LadderController,
	dismount_type: DismountType,
	destination: Transform3D,
) -> bool:
	if not _climbers.has(controller):
		return false
	_climbers.erase(controller)
	_update_runtime_status()
	dismounted.emit(controller.get_body(), dismount_type, destination)
	return true


# --- Interaction -------------------------------------------------------------

func _can_interact_option(interactor: Node3D, _option_index: int) -> bool:
	return _can_be_mounted_by(LadderController.find_on_actor(interactor))


## No hit point available: mount at the height of the actor's feet.
func _interact_option(interactor: Node3D, _option_index: int) -> bool:
	return _mount_at(interactor, interactor.global_position)


## The interaction ray's hit point picks the mount height, but never further than
## [member mount_reach] from where the actor is actually standing.
func _interact_option_at(
	interactor: Node3D,
	world_position: Vector3,
	_option_index: int,
) -> bool:
	return _mount_at(interactor, world_position)


func _mount_at(interactor: Node3D, world_position: Vector3) -> bool:
	var controller := LadderController.find_on_actor(interactor)
	if controller == null:
		return false
	var feet_height := get_height_at_world_position(interactor.global_position)
	var wanted_height := get_height_at_world_position(world_position)
	return controller.mount(self, clampf(
		wanted_height,
		feet_height - mount_reach,
		feet_height + mount_reach,
	))


func _create_default_interaction_option() -> InteractionOption:
	var option := super._create_default_interaction_option()
	option.option_id = &"climb"
	option.prompt = "Climb"
	return option


## With no gaze to follow, the prompt floats at the middle of the ladder unless a
## Prompt Anchor is assigned.
func get_prompt_world_position() -> Vector3:
	if is_instance_valid(prompt_anchor):
		return super.get_prompt_world_position()
	return to_global(Vector3(0.0, height * 0.5, 0.0) + prompt_local_offset)


## The prompt slides along the ladder to the height being looked at: the top end
## when looking down from above, the middle when looking at the middle, and so on.
func get_prompt_world_position_for(focus_point: Vector3) -> Vector3:
	if is_instance_valid(prompt_anchor):
		return super.get_prompt_world_position()
	var wanted := to_global(Vector3(0.0, get_height_at_world_position(focus_point), 0.0) + prompt_local_offset)
	var now := Time.get_ticks_msec()
	# This is asked for every frame the prompt is showing. After a pause it starts where
	# it is wanted instead of sliding in from wherever it was last time.
	if prompt_follow_speed <= 0.0 or now - _prompt_last_msec > 250:
		_prompt_position = wanted
	else:
		var delta := float(now - _prompt_last_msec) / 1000.0
		var gap := wanted - _prompt_position
		# Along the ladder it is allowed to trail a little further behind than across it.
		var up := get_up_direction()
		var along := up * gap.dot(up)
		var across := gap - along
		var across_weight := 1.0 - exp(-prompt_follow_speed * delta)
		var along_weight := 1.0 - exp(-prompt_follow_speed * prompt_vertical_follow * delta)
		_prompt_position += across * across_weight + along * along_weight
	_prompt_last_msec = now
	return _prompt_position


## The selector box, and the dot at its middle, cover the whole ladder instead of the generic selector box.
func get_selector_center_local() -> Vector3:
	return Vector3(0.0, height * 0.5, 0.0)


func get_selector_half_size_local() -> Vector3:
	return Vector3(width * 0.5, height * 0.5, 0.1)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var has_shape := false
	for child in get_children():
		if (child is CollisionShape3D and child.shape != null) or child is CollisionPolygon3D:
			has_shape = true
			break
	if not has_shape:
		warnings.append(
			"Add one or more CollisionShape3D children to define where the ladder can be used."
		)
	return warnings


func _update_runtime_status() -> void:
	if _climbers.is_empty():
		super._update_runtime_status()
	else:
		runtime_status = "%d climber(s) on the ladder." % _climbers.size()


# --- Helpers -----------------------------------------------------------------

func _find_climber(node: Node) -> LadderController:
	if node == null:
		return null
	for climber in _climbers:
		if climber == node or climber.get_body() == node:
			return climber
	return null


## Rotation comes from the orthonormalized ladder basis; positions go through the full transform so
## scaling the ladder scales its layout. It is the ladder as it is drawn: on a ship, the smoothed pose
## between physics ticks, which the climber has to match or it jitters against the rungs. During a
## physics tick that is simply the current pose.
func _local_to_global(local: Transform3D) -> Transform3D:
	var frame := _frame()
	var result := frame.orthonormalized() * local
	result.origin = frame * local.origin
	return result


## Where the ladder is, as drawn.
func _frame() -> Transform3D:
	return get_global_transform_interpolated() if is_inside_tree() else global_transform


func _refresh_gizmo() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		update_gizmos()


## Also false while the actor is busy on a ladder (this one or another), so
## their interaction ray does not offer a Climb prompt.
func _can_be_mounted_by(controller: LadderController) -> bool:
	return controller != null and controller.can_mount(self)
