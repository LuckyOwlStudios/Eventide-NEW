class_name Turret3D
extends Node3D
## A gun a player can take control of from a [VehicleSeat3D]. It is not a [Vehicle3D]: it has no
## body of its own and rides whatever it is mounted on.

signal look_mode_changed(previous_mode: LOOK_MODE, current_mode: LOOK_MODE)
signal control_started(controller: VehicleController)
signal control_ended(controller: VehicleController)

enum LOOK_MODE {
	LEFT,
	CENTER,
	RIGHT
}
@export_range(0.0, 2.0, 0.05) var camera_side_transition_duration := 0.25
## The camera the controlling player sees through.
@export var vehicle_camera: Camera3D

@export_group("Debugging")
@export var debug := false
@export_range(0.1, 1000.0, 0.1) var debug_arrow_length := 10.0
@export_range(0.05, 5.0, 0.05) var debug_box_size := 0.25

## The target raycast of what we are actually aiming at.
@onready var target_ray_cast: RayCast3D = %TargetRayCast3D
## The actual firing ray attached to the lerping gun pivots.
@onready var gun_ray_cast: RayCast3D = %GunRayCast3D
## Handles look input, mechanical aiming, prediction, and reconciliation.
@onready var rotator: Rotator = %Rotator
## Used to prevent camera from getting cutoff by objects
@onready var spring_arm: SpringArm3D = %SpringArm3D

@onready var camera_yaw: Node3D = $CameraYaw
@onready var camera_pitch: Node3D = $CameraYaw/CameraPitch
@onready var camera_left_point: Marker3D = %CameraLeftPoint
@onready var camera_center_point: Marker3D = %CameraCenterPoint
@onready var camera_right_point: Marker3D = %CameraRightPoint

## Universal node for camera location
@onready var camera_mount: Marker3D = %CameraMount
## All turret-specific HUD elements. Only the local controlling player sees it.
@onready var ui_base: CanvasLayer = %UIBase
## Screen-space anchor for a crosshair showing the gun barrel's real aim point.
@onready var gun_screen_space_location: Control = %GunScreenSpaceLocation

var controller: VehicleController
var look_mode := LOOK_MODE.CENTER
var _camera_side_tween: Tween
var _spring_arm_origin := Vector3.ZERO
var _camera_offset := Vector3.ZERO

func _ready() -> void:
	if is_instance_valid(vehicle_camera):
		vehicle_camera.current = false
	rotator.set_input_enabled(has_local_control())
	rotator.set_mechanical_follow_enabled(is_instance_valid(controller))
	_spring_arm_origin = spring_arm.position
	_set_camera_offset(camera_center_point.position - _spring_arm_origin)
	_update_ui_visibility()

func _process(_delta: float) -> void:
	_update_gun_screen_space_location()
	if debug and is_instance_valid(camera_mount):
		_draw_debug()

func _unhandled_input(event: InputEvent) -> void:
	if not has_local_control():
		return
	if event.is_action_pressed("turret_lean_left") and not event.is_echo():
		toggle_camera_side(LOOK_MODE.LEFT)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("turret_lean_right") and not event.is_echo():
		toggle_camera_side(LOOK_MODE.RIGHT)
		get_viewport().set_input_as_handled()

# --- Control, the same calls a VehicleSeat3D makes on a Vehicle3D -------------

func can_be_controlled_by(candidate: VehicleController) -> bool:
	return is_instance_valid(candidate) and not is_instance_valid(controller)

func claim_control(candidate: VehicleController) -> bool:
	if not can_be_controlled_by(candidate):
		return false
	controller = candidate
	_on_control_started(candidate)
	control_started.emit(candidate)
	return true

func release_control(candidate: VehicleController) -> bool:
	if not is_instance_valid(controller) or controller != candidate:
		return false
	var previous := controller
	controller = null
	_on_control_ended(previous)
	control_ended.emit(previous)
	return true

func has_local_control() -> bool:
	return is_instance_valid(controller) and controller.is_local_controller()

func _on_control_started(active_controller: VehicleController) -> void:
	var actor := active_controller.get_parent()
	rotator.set_input_peer(actor.get_multiplayer_authority() if actor else 0)
	rotator.set_input_enabled(has_local_control())
	rotator.set_mechanical_follow_enabled(true)
	_update_ui_visibility()

func _on_control_ended(_active_controller: VehicleController) -> void:
	rotator.set_input_enabled(false)
	rotator.set_mechanical_follow_enabled(false)
	rotator.set_input_peer(0)
	_update_ui_visibility()


func _update_ui_visibility() -> void:
	if is_instance_valid(ui_base):
		ui_base.visible = has_local_control()


## Projects the gun ray's actual endpoint through the turret camera. A TextureRect
## can be centered beneath GunScreenSpaceLocation to visualize barrel convergence.
func _update_gun_screen_space_location() -> void:
	if not is_instance_valid(gun_screen_space_location):
		return
	if (
		not has_local_control()
		or not is_instance_valid(vehicle_camera)
		or not vehicle_camera.current
		or not is_instance_valid(gun_ray_cast)
	):
		gun_screen_space_location.hide()
		return

	var world_target := (
		gun_ray_cast.get_collision_point()
		if gun_ray_cast.is_colliding()
		else gun_ray_cast.to_global(gun_ray_cast.target_position)
	)
	if vehicle_camera.is_position_behind(world_target):
		gun_screen_space_location.hide()
		return

	var screen_position := vehicle_camera.unproject_position(world_target)
	var canvas_layer := gun_screen_space_location.get_parent() as CanvasLayer
	if is_instance_valid(canvas_layer):
		screen_position = canvas_layer.transform.affine_inverse() * screen_position
	gun_screen_space_location.position = screen_position
	gun_screen_space_location.show()

## Toggles the requested shoulder view. Pressing the active side returns to center.
func toggle_camera_side(side: LOOK_MODE) -> void:
	if side != LOOK_MODE.LEFT and side != LOOK_MODE.RIGHT:
		return
	set_look_mode(LOOK_MODE.CENTER if look_mode == side else side)

func set_look_mode(new_mode: LOOK_MODE) -> void:
	if new_mode == look_mode:
		return
	var target_point := _get_camera_point(new_mode)
	if not is_instance_valid(target_point):
		return

	var previous_mode := look_mode
	look_mode = new_mode
	if _camera_side_tween and _camera_side_tween.is_valid():
		_camera_side_tween.kill()

	var target_offset := target_point.position - _spring_arm_origin
	var duration := _get_camera_transition_duration(target_offset)
	if duration <= 0.0:
		_set_camera_offset(target_offset)
	else:
		_camera_side_tween = create_tween()
		_camera_side_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		_camera_side_tween.set_trans(Tween.TRANS_CUBIC)
		_camera_side_tween.set_ease(Tween.EASE_IN_OUT)
		_camera_side_tween.tween_method(
			_set_camera_offset,
			_camera_offset,
			target_offset,
			duration,
		)
	look_mode_changed.emit(previous_mode, look_mode)


func _get_camera_point(mode: LOOK_MODE) -> Marker3D:
	match mode:
		LOOK_MODE.LEFT:
			return camera_left_point
		LOOK_MODE.RIGHT:
			return camera_right_point
		_:
			return camera_center_point

func _get_camera_transition_duration(target_offset: Vector3) -> float:
	if camera_side_transition_duration <= 0.0:
		return 0.0
	var center_offset := camera_center_point.position - _spring_arm_origin
	var side_distance := maxf(
		center_offset.distance_to(camera_left_point.position - _spring_arm_origin),
		center_offset.distance_to(camera_right_point.position - _spring_arm_origin),
	)
	if side_distance <= 0.0001:
		return 0.0
	return (
		camera_side_transition_duration
		* _camera_offset.distance_to(target_offset)
		/ side_distance
	)

func _set_camera_offset(offset: Vector3) -> void:
	_camera_offset = offset
	spring_arm.position = _spring_arm_origin
	var distance := offset.length()
	spring_arm.spring_length = distance
	if distance <= 0.0001:
		camera_mount.basis = spring_arm.basis.inverse()
		return

	var direction := offset / distance
	var up := Vector3.UP
	if absf(direction.dot(up)) > 0.999:
		up = Vector3.FORWARD
	# SpringArm3D extends children along local +Z, while looking_at aligns local -Z.
	spring_arm.basis = Basis.looking_at(-direction, up)
	# Keep the camera and target ray aligned with CameraPitch, not with the arm.
	camera_mount.basis = spring_arm.basis.inverse()

func _draw_debug() -> void:

	# CAMERA TARGET: red on collision, white in open space.
	_draw_raycast_arrow(
		target_ray_cast,
		Color.WHITE,
		Color.GREEN,
		debug_arrow_length,
	)

	# ACTUAL GUN PATH: green when both rays hit the same point, otherwise yellow.
	# Its configured target_position controls the maximum displayed length.
	var gun_color := Color.YELLOW
	if target_ray_cast.is_colliding() and gun_ray_cast.is_colliding():
		var hit_separation := target_ray_cast.get_collision_point().distance_to(
			gun_ray_cast.get_collision_point()
		)
		if hit_separation <= debug_box_size:
			gun_color = Color.RED
	_draw_raycast_arrow(
		gun_ray_cast,
		gun_color,
		gun_color,
		gun_ray_cast.target_position.length(),
	)


func _draw_raycast_arrow(
	ray_cast: RayCast3D,
	open_space_color: Color,
	hit_color: Color,
	maximum_length: float,
) -> void:
	if not is_instance_valid(ray_cast):
		return
	var origin := ray_cast.global_position
	var endpoint := (
		ray_cast.get_collision_point()
		if ray_cast.is_colliding()
		else ray_cast.to_global(ray_cast.target_position)
	)
	var direction := endpoint - origin
	var distance := minf(direction.length(), maxf(maximum_length, 0.0))
	if distance <= 0.001:
		return
	DebugDraw3D.draw_arrow_ray(
		origin,
		direction.normalized(),
		distance,
		hit_color if ray_cast.is_colliding() else open_space_color,
		0.25,
		true,
	)
