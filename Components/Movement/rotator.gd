@icon("uid://blk8yk4337c4g")
class_name Rotator
extends Node
## Predicted, server-authoritative look input with optional mechanical follow lag.

enum MechanicalAimMode {
	## The mechanical nodes follow the camera's yaw and pitch exactly.
	CAMERA_ROTATION,
	## The mechanical nodes converge on the camera ray's collision or far endpoint.
	RAYCAST_POINT,
}

signal authoritative_look_updated(yaw: float, pitch: float, acknowledged_sequence: int)
signal look_reconciled(yaw_error: float, pitch_error: float)

const MOUSE_SENSITIVITY_SETTING: StringName = &"controls.mouse_sensitivity"
const CONTROLLER_SENSITIVITY_SETTING: StringName = &"controls.controller_sensitivity"
const INVERT_MOUSE_Y_SETTING: StringName = &"controls.invert_mouse_y"
const ROTATION_SPEED_MULTIPLIER := 0.12
const ROLL_ACTION: StringName = &"roll"
const LOOK_NETWORK_CHANNEL := 5
const MAX_PENDING_INPUTS := 128

@export_group("View")
## Immediate horizontal view pivot, normally the camera's yaw pivot.
@export var yaw_pivot: Node3D
## Immediate vertical view pivot, normally the camera's pitch pivot.
@export var pitch_pivot: Node3D
@export_range(-89.0, 0.0, 1.0) var minimum_pitch := -85.0
@export_range(0.0, 89.0, 1.0) var maximum_pitch := 85.0
## Total horizontal aiming arc. 120 allows 60 degrees to either side; 360 is unlimited.
@export_range(1.0, 360.0, 1.0) var maximum_yaw := 360.0
@export var capture_mouse_on_start := true
## Disables local input without stopping authoritative or proxy rotation updates.
@export var input_enabled := true

@export_group("Controller Look")
## Turns the view with the right stick. The mouse always works as well.
@export var controller_look_enabled := true
## How fast the view turns with the stick pushed all the way, before the Controller
## Sensitivity setting.
@export_range(30.0, 720.0, 5.0, "suffix:°/s") var controller_look_speed_degrees := 200.0
## Shapes the stick. 1 is straight; higher gives fine control near the middle and still turns
## fast at the edge.
@export_range(1.0, 3.0, 0.05) var controller_look_curve := 1.8
## Vertical turning is this share of the horizontal speed.
@export_range(0.25, 1.5, 0.05) var controller_pitch_scale := 0.7
@export var look_left_action: StringName = &"look_left"
@export var look_right_action: StringName = &"look_right"
@export var look_up_action: StringName = &"look_up"
@export var look_down_action: StringName = &"look_down"

@export_group("Mechanical Follow")
## Controls mechanical yaw/pitch tracking without disabling view or network updates.
@export var mechanical_follow_enabled := true
## Mechanical yaw pivots that share the same smoothed rotation.
## In RAYCAST_POINT mode, the first valid entry is the world-space aim reference.
@export var lerping_yaw_nodes: Array[Node3D]
## Mechanical pitch pivots that share the same smoothed rotation.
## In RAYCAST_POINT mode, the first valid entry is the world-space aim reference.
@export var lerping_pitch_nodes: Array[Node3D]
## Chooses direct camera-angle following or third-person ray convergence.
@export_enum("Camera Rotation", "Raycast Point") var mechanical_aim_mode: int = MechanicalAimMode.CAMERA_ROTATION
## Required when mechanical_aim_mode is RAYCAST_POINT.
@export var aim_raycast: RayCast3D
## Scales turn speed from the remaining angular error. Zero aims instantly.
@export_range(0.0, 60.0, 0.5) var follow_lerp_speed := 20.0
## Prevents small mechanical corrections from becoming too slow near the target.
@export_range(0.0, 720.0, 1.0) var minimum_turn_speed_degrees := 0.0
## Caps large mechanical corrections. Zero means no speed cap.
@export_range(0.0, 1440.0, 1.0) var maximum_turn_speed_degrees := 720.0
## Snaps the mechanism onto its target inside this small error, removing visible
## lag while making precise tracking adjustments. Zero disables precision snap.
@export_range(0.0, 15.0, 0.1) var precision_snap_angle_degrees := 1.5
## Precision snap is allowed while the target moves no faster than this. Faster
## aim changes retain the normal mechanical follow lag. Zero disables precision snap.
@export_range(0.0, 360.0, 1.0) var precision_tracking_speed_degrees := 45.0

## Peer allowed to provide input. Zero uses the parent node's multiplayer authority.
var input_peer_id := 0
## Maximum look speed accepted by the server. Local prediction remains immediate.
var server_max_turn_speed_degrees := 1440.0
var proxy_lerp_speed := 20.0
var reconciliation_lerp_speed := 25.0
var reconciliation_snap_degrees := 35.0
var snapshot_interval := 0.05
## Resends an unacknowledged command because look input uses low-latency unreliable packets.
var input_resend_interval := 0.1

var sensitivity := 1.0
var controller_sensitivity := 1.0
var invert_mouse_y := false
## Set by whatever can roll the character (zero gravity). While it is true and the roll action is
## held, sideways look is roll and not turning, so the view does not also yaw.
var roll_enabled := false
var can_look_around := ActionBlocker.new()

var _initial_pitch := 0.0
var _initial_follow_yaw := 0.0
var _initial_follow_pitch := 0.0
var _applied_view_yaw := 0.0
var _applied_view_pitch := 0.0
var _predicted_yaw := 0.0
var _predicted_pitch := 0.0
var _authoritative_yaw := 0.0
var _authoritative_pitch := 0.0
var _proxy_yaw := 0.0
var _proxy_pitch := 0.0
var _applied_follow_yaw := 0.0
var _applied_follow_pitch := 0.0
var _previous_follow_target_yaw := 0.0
var _previous_follow_target_pitch := 0.0
var _has_follow_target_sample := false
var _reconciliation_yaw_remaining := 0.0
var _reconciliation_pitch_remaining := 0.0
var _unsent_yaw_delta := 0.0
var _unsent_pitch_delta := 0.0
var _input_sequence := 0
var _last_server_sequence := 0
var _last_server_input_usec := 0
var _snapshot_elapsed := 0.0
var _resend_elapsed := 0.0
var _input_dirty := false
var _pending_inputs: Array[Dictionary] = []


func _ready() -> void:
	if yaw_pivot == null or pitch_pivot == null:
		push_error("Rotator requires both yaw_pivot and pitch_pivot.")
		set_process(false)
		set_physics_process(false)
		return

	_apply_mouse_sensitivity(Settings.get_setting(MOUSE_SENSITIVITY_SETTING, 1.0))
	controller_sensitivity = float(Settings.get_setting(CONTROLLER_SENSITIVITY_SETTING, 1.0))
	invert_mouse_y = bool(Settings.get_setting(INVERT_MOUSE_Y_SETTING, false))
	Settings.setting_changed.connect(_on_setting_changed)
	_initial_pitch = pitch_pivot.rotation.x
	var reference_yaw_node := _get_first_mechanical_node(
		lerping_yaw_nodes,
		yaw_pivot,
	)
	var reference_pitch_node := _get_first_mechanical_node(
		lerping_pitch_nodes,
		pitch_pivot,
	)
	if is_instance_valid(reference_yaw_node):
		_initial_follow_yaw = reference_yaw_node.rotation.y
	if is_instance_valid(reference_pitch_node):
		_initial_follow_pitch = reference_pitch_node.rotation.x
	if mechanical_aim_mode == MechanicalAimMode.RAYCAST_POINT and not is_instance_valid(aim_raycast):
		push_warning("Rotator RAYCAST_POINT mode requires an aim_raycast; camera rotation will be used instead.")
	_apply_view_pivots(_predicted_yaw, _predicted_pitch)

	if input_enabled and capture_mouse_on_start and _is_local_input_owner():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## The stick may turn the view: this is the local player's, nothing is blocking it, and no menu
## or in-game screen is open.
## Sideways look is rolling the character right now, so it must not turn the view too.
func _is_rolling() -> bool:
	return roll_enabled and Input.is_action_pressed(ROLL_ACTION)


func _can_look_with_stick() -> bool:
	return (
		input_enabled
		and _is_local_input_owner()
		and can_look_around.is_permitted()
		and not InGameUIHandler.is_ui_open
	)


## Turns the view with the right stick. Pushing the stick all the way turns at
## [member controller_look_speed_degrees] and gentle pushes turn much slower, so aiming is easy.
func _apply_controller_look(delta: float) -> void:
	if not controller_look_enabled or not _can_look_with_stick():
		return
	var stick := Input.get_vector(look_left_action, look_right_action, look_up_action, look_down_action)
	if stick.is_zero_approx():
		return
	var shaped := stick.normalized() * pow(minf(stick.length(), 1.0), controller_look_curve)
	var turn := deg_to_rad(controller_look_speed_degrees) * controller_sensitivity * delta
	var vertical_direction := -1.0 if invert_mouse_y else 1.0
	# Stick right turns right and stick down looks down, like the mouse.
	add_look_input(
		0.0 if _is_rolling() else -shaped.x * turn,
		-shaped.y * turn * controller_pitch_scale * vertical_direction,
	)


func _input(event: InputEvent) -> void:
	if not input_enabled or not _is_local_input_owner() or not can_look_around.is_permitted():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rotation_amount := deg_to_rad(sensitivity)
		var vertical_direction := -1.0 if invert_mouse_y else 1.0
		add_look_input(
			0.0 if _is_rolling() else -event.relative.x * rotation_amount,
			-event.relative.y * rotation_amount * vertical_direction,
		)

func _process(delta: float) -> void:
	if yaw_pivot == null or pitch_pivot == null:
		return
	_apply_controller_look(delta)

	var desired_yaw: float
	var desired_pitch: float
	if _is_local_input_owner():
		_apply_reconciliation(delta)
		desired_yaw = _predicted_yaw
		desired_pitch = _predicted_pitch
	elif NetworkSession.is_network_connected() and not NetworkSession.is_server():
		_proxy_yaw = lerp_angle(
			_proxy_yaw,
			_authoritative_yaw,
			_exponential_weight(proxy_lerp_speed, delta),
		)
		_proxy_pitch = lerpf(
			_proxy_pitch,
			_authoritative_pitch,
			_exponential_weight(proxy_lerp_speed, delta),
		)
		desired_yaw = _proxy_yaw
		desired_pitch = _proxy_pitch
	else:
		desired_yaw = _authoritative_yaw
		desired_pitch = _authoritative_pitch

	# Apply the immediate view before querying a RayCast3D so its aim point matches
	# this frame's prediction or authoritative snapshot. Apply it again afterward
	# to counter any mechanical ancestor that also moved the camera hierarchy.
	_apply_view_pivots(desired_yaw, desired_pitch)
	if mechanical_follow_enabled:
		if (
			mechanical_aim_mode == MechanicalAimMode.RAYCAST_POINT
			and is_instance_valid(aim_raycast)
			and aim_raycast.enabled
		):
			aim_raycast.force_raycast_update()
		_update_follow_targets(desired_yaw, desired_pitch, delta)
	_apply_view_pivots(desired_yaw, desired_pitch)


func _physics_process(delta: float) -> void:
	if not NetworkSession.is_network_connected():
		_authoritative_yaw = _predicted_yaw
		_authoritative_pitch = _predicted_pitch
		_input_dirty = false
		_unsent_yaw_delta = 0.0
		_unsent_pitch_delta = 0.0
		return

	if _is_local_input_owner() and _input_dirty:
		_input_sequence += 1
		var command := {
			"sequence": _input_sequence,
			"yaw_delta": _unsent_yaw_delta,
			"pitch_delta": _unsent_pitch_delta,
			"yaw": _predicted_yaw,
			"pitch": _predicted_pitch,
		}
		_pending_inputs.append(command)
		if _pending_inputs.size() > MAX_PENDING_INPUTS:
			_pending_inputs.pop_front()
		_send_look_command(command)
		_resend_elapsed = 0.0
		_input_dirty = false
		_unsent_yaw_delta = 0.0
		_unsent_pitch_delta = 0.0
	elif _is_local_input_owner() and not _pending_inputs.is_empty():
		_resend_elapsed += delta
		if _resend_elapsed >= input_resend_interval:
			_send_look_command(_pending_inputs.back())
			_resend_elapsed = 0.0

	if NetworkSession.is_server():
		_snapshot_elapsed += delta
		if _snapshot_elapsed >= snapshot_interval:
			_snapshot_elapsed = fmod(_snapshot_elapsed, snapshot_interval)
			_broadcast_authoritative_look()

## Adds an already-scaled yaw and pitch delta in radians.
func add_look_input(yaw_delta: float, pitch_delta: float) -> void:
	if not is_finite(yaw_delta) or not is_finite(pitch_delta):
		return
	var previous_yaw := _predicted_yaw
	var previous_pitch := _predicted_pitch
	_predicted_yaw = _clamp_yaw(_predicted_yaw + yaw_delta)
	_predicted_pitch = _clamp_pitch(_predicted_pitch + pitch_delta)
	var applied_yaw_delta := angle_difference(previous_yaw, _predicted_yaw)
	var applied_pitch_delta := _predicted_pitch - previous_pitch
	_unsent_yaw_delta += applied_yaw_delta
	_unsent_pitch_delta += applied_pitch_delta
	_input_dirty = _input_dirty or not is_zero_approx(applied_yaw_delta) or not is_zero_approx(applied_pitch_delta)
	_apply_view_pivots(_predicted_yaw, _predicted_pitch)

func set_input_peer(peer_id: int) -> void:
	input_peer_id = maxi(peer_id, 0)

func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if input_enabled and capture_mouse_on_start and _is_local_input_owner():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func set_mechanical_follow_enabled(enabled: bool) -> void:
	if enabled and not mechanical_follow_enabled:
		_has_follow_target_sample = false
	mechanical_follow_enabled = enabled

func get_predicted_look() -> Vector2:
	return Vector2(_predicted_yaw, _predicted_pitch)

func get_authoritative_look() -> Vector2:
	return Vector2(_authoritative_yaw, _authoritative_pitch)

## Returns the yaw and pitch currently applied to the mechanical follow nodes.
func get_mechanical_look() -> Vector2:
	return Vector2(_applied_follow_yaw, _applied_follow_pitch)


## Returns the collision under the crosshair, or the ray's far endpoint.
func get_aim_point() -> Vector3:
	if not is_instance_valid(aim_raycast):
		return Vector3.ZERO
	if aim_raycast.is_colliding():
		return aim_raycast.get_collision_point()
	return aim_raycast.to_global(aim_raycast.target_position)


@rpc("any_peer", "call_remote", "unreliable_ordered", LOOK_NETWORK_CHANNEL)
func _server_submit_look_input(
	sequence: int,
	requested_yaw: float,
	requested_pitch: float,
) -> void:
	if not NetworkSession.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != _get_input_peer_id():
		return
	_server_accept_look_input(sender_id, sequence, requested_yaw, requested_pitch)


@rpc("any_peer", "call_remote", "unreliable_ordered", LOOK_NETWORK_CHANNEL)
func _receive_authoritative_look(
	yaw: float,
	pitch: float,
	acknowledged_sequence: int,
) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_apply_authoritative_snapshot(yaw, pitch, acknowledged_sequence)


func _server_accept_look_input(
	sender_id: int,
	sequence: int,
	requested_yaw: float,
	requested_pitch: float,
) -> void:
	if sender_id != _get_input_peer_id() or sequence <= _last_server_sequence:
		return
	if not is_finite(requested_yaw) or not is_finite(requested_pitch):
		return

	var now_usec := Time.get_ticks_usec()
	var elapsed := 1.0 / float(Engine.physics_ticks_per_second)
	if _last_server_input_usec > 0:
		elapsed = clampf(
			float(now_usec - _last_server_input_usec) / 1000000.0,
			0.0,
			elapsed,
		)
	_last_server_input_usec = now_usec
	var maximum_delta := deg_to_rad(server_max_turn_speed_degrees) * elapsed
	var requested_yaw_clamped := _clamp_yaw(requested_yaw)
	var requested_pitch_clamped := _clamp_pitch(requested_pitch)
	var requested_change := Vector2(
		angle_difference(_authoritative_yaw, requested_yaw_clamped),
		requested_pitch_clamped - _authoritative_pitch,
	)
	var accepted_change := requested_change.limit_length(maximum_delta)
	_authoritative_yaw = _clamp_yaw(_authoritative_yaw + accepted_change.x)
	_authoritative_pitch = _clamp_pitch(_authoritative_pitch + accepted_change.y)
	_last_server_sequence = sequence
	if _is_local_input_owner():
		_apply_authoritative_snapshot(
			_authoritative_yaw,
			_authoritative_pitch,
			_last_server_sequence,
		)
	else:
		authoritative_look_updated.emit(
			_authoritative_yaw,
			_authoritative_pitch,
			_last_server_sequence,
		)
	_broadcast_authoritative_look()


func _send_look_command(command: Dictionary) -> void:
	var sequence := int(command["sequence"])
	var requested_yaw := float(command["yaw"])
	var requested_pitch := float(command["pitch"])
	if NetworkSession.is_server():
		_server_accept_look_input(
			_get_input_peer_id(),
			sequence,
			requested_yaw,
			requested_pitch,
		)
	else:
		_server_submit_look_input.rpc_id(
			1,
			sequence,
			requested_yaw,
			requested_pitch,
		)


func _broadcast_authoritative_look() -> void:
	if NetworkSession.is_server():
		_receive_authoritative_look.rpc(
			_authoritative_yaw,
			_authoritative_pitch,
			_last_server_sequence,
		)


func _apply_authoritative_snapshot(
	yaw: float,
	pitch: float,
	acknowledged_sequence: int,
) -> void:
	if not is_finite(yaw) or not is_finite(pitch):
		return
	_authoritative_yaw = _clamp_yaw(yaw)
	_authoritative_pitch = _clamp_pitch(pitch)
	if not _is_local_input_owner():
		authoritative_look_updated.emit(
			_authoritative_yaw,
			_authoritative_pitch,
			acknowledged_sequence,
		)
		return

	while not _pending_inputs.is_empty():
		if int(_pending_inputs[0]["sequence"]) > acknowledged_sequence:
			break
		_pending_inputs.pop_front()

	var replayed_yaw := _authoritative_yaw
	var replayed_pitch := _authoritative_pitch
	for command in _pending_inputs:
		replayed_yaw = _clamp_yaw(replayed_yaw + float(command["yaw_delta"]))
		replayed_pitch = _clamp_pitch(replayed_pitch + float(command["pitch_delta"]))
	var yaw_error := angle_difference(_predicted_yaw, replayed_yaw)
	var pitch_error := replayed_pitch - _predicted_pitch
	var snap_threshold := deg_to_rad(reconciliation_snap_degrees)
	if absf(yaw_error) >= snap_threshold or absf(pitch_error) >= snap_threshold:
		_predicted_yaw = replayed_yaw
		_predicted_pitch = replayed_pitch
		_reconciliation_yaw_remaining = 0.0
		_reconciliation_pitch_remaining = 0.0
	else:
		_reconciliation_yaw_remaining = yaw_error
		_reconciliation_pitch_remaining = pitch_error
	authoritative_look_updated.emit(
		_authoritative_yaw,
		_authoritative_pitch,
		acknowledged_sequence,
	)
	look_reconciled.emit(yaw_error, pitch_error)


func _apply_reconciliation(delta: float) -> void:
	if is_zero_approx(_reconciliation_yaw_remaining) and is_zero_approx(
		_reconciliation_pitch_remaining
	):
		return
	var weight := _exponential_weight(reconciliation_lerp_speed, delta)
	var yaw_step := _reconciliation_yaw_remaining * weight
	var pitch_step := _reconciliation_pitch_remaining * weight
	_predicted_yaw = _clamp_yaw(_predicted_yaw + yaw_step)
	_predicted_pitch = _clamp_pitch(_predicted_pitch + pitch_step)
	_reconciliation_yaw_remaining -= yaw_step
	_reconciliation_pitch_remaining -= pitch_step


func _update_follow_targets(desired_yaw: float, desired_pitch: float, delta: float) -> void:
	var target_look := Vector2(desired_yaw, desired_pitch)
	if (
		mechanical_aim_mode == MechanicalAimMode.RAYCAST_POINT
		and is_instance_valid(aim_raycast)
	):
		target_look = get_mechanical_look_for_world_point(get_aim_point())

	var target_yaw_speed := INF
	var target_pitch_speed := INF
	if _has_follow_target_sample and delta > 0.0:
		target_yaw_speed = absf(
			angle_difference(_previous_follow_target_yaw, target_look.x)
		) / delta
		target_pitch_speed = absf(
			target_look.y - _previous_follow_target_pitch
		) / delta
	_previous_follow_target_yaw = target_look.x
	_previous_follow_target_pitch = target_look.y
	_has_follow_target_sample = true

	var has_yaw_follow_node := false
	var rotated_yaw_nodes: Dictionary[int, bool] = {}
	var next_follow_yaw := _track_follow_angle(
		_applied_follow_yaw,
		target_look.x,
		delta,
		target_yaw_speed,
	)
	var yaw_step := angle_difference(_applied_follow_yaw, next_follow_yaw)
	for lerping_node in lerping_yaw_nodes:
		if (
			not is_instance_valid(lerping_node)
			or lerping_node == yaw_pivot
			or rotated_yaw_nodes.has(lerping_node.get_instance_id())
		):
			continue
		rotated_yaw_nodes[lerping_node.get_instance_id()] = true
		lerping_node.rotate_object_local(Vector3.UP, yaw_step)
		has_yaw_follow_node = true
	if has_yaw_follow_node:
		_applied_follow_yaw = _clamp_yaw(next_follow_yaw)
	else:
		_applied_follow_yaw = target_look.x

	var has_pitch_follow_node := false
	var rotated_pitch_nodes: Dictionary[int, bool] = {}
	var next_follow_pitch := _track_follow_angle(
		_applied_follow_pitch,
		target_look.y,
		delta,
		target_pitch_speed,
	)
	var pitch_step := next_follow_pitch - _applied_follow_pitch
	for lerping_node in lerping_pitch_nodes:
		if (
			not is_instance_valid(lerping_node)
			or lerping_node == pitch_pivot
			or rotated_pitch_nodes.has(lerping_node.get_instance_id())
		):
			continue
		rotated_pitch_nodes[lerping_node.get_instance_id()] = true
		lerping_node.rotate_object_local(Vector3.RIGHT, pitch_step)
		has_pitch_follow_node = true
	if has_pitch_follow_node:
		_applied_follow_pitch = next_follow_pitch
	else:
		_applied_follow_pitch = target_look.y


## Solves mechanical yaw and pitch, relative to their starting rotations, for a world point.
func get_mechanical_look_for_world_point(world_point: Vector3) -> Vector2:
	var reference_yaw_node := _get_first_mechanical_node(
		lerping_yaw_nodes,
		yaw_pivot,
	)
	var reference_pitch_node := _get_first_mechanical_node(
		lerping_pitch_nodes,
		pitch_pivot,
	)
	if (
		not is_instance_valid(reference_yaw_node)
		or not is_instance_valid(reference_pitch_node)
		or not world_point.is_finite()
	):
		return Vector2(_applied_follow_yaw, _applied_follow_pitch)

	var yaw_parent := reference_yaw_node.get_parent_node_3d()
	if yaw_parent == null:
		return Vector2(_applied_follow_yaw, _applied_follow_pitch)

	var parent_basis := yaw_parent.global_basis.orthonormalized()
	var yaw_direction := parent_basis.inverse() * (
		world_point - reference_yaw_node.global_position
	)
	if Vector2(yaw_direction.x, yaw_direction.z).length_squared() <= 0.000001:
		return Vector2(_applied_follow_yaw, _applied_follow_pitch)

	var target_yaw_absolute := atan2(-yaw_direction.x, -yaw_direction.z)
	var target_yaw_relative := _clamp_yaw(
		angle_difference(_initial_follow_yaw, target_yaw_absolute)
	)
	var limited_yaw_absolute := _initial_follow_yaw + target_yaw_relative
	var pitch_direction := parent_basis.inverse() * (
		world_point - reference_pitch_node.global_position
	)
	pitch_direction = Basis(Vector3.UP, limited_yaw_absolute).inverse() * pitch_direction
	var horizontal_distance := Vector2(pitch_direction.x, pitch_direction.z).length()
	var target_pitch_absolute := clampf(
		atan2(pitch_direction.y, horizontal_distance),
		deg_to_rad(minimum_pitch),
		deg_to_rad(maximum_pitch),
	)
	return Vector2(
		target_yaw_relative,
		target_pitch_absolute - _initial_follow_pitch,
	)


func _track_follow_angle(
	current_angle: float,
	target_angle: float,
	delta: float,
	target_speed: float,
) -> float:
	if follow_lerp_speed <= 0.0:
		return target_angle

	var error := angle_difference(current_angle, target_angle)
	var error_amount := absf(error)
	if error_amount <= 0.00001:
		return target_angle

	var precision_snap_angle := deg_to_rad(precision_snap_angle_degrees)
	var precision_tracking_speed := deg_to_rad(precision_tracking_speed_degrees)
	if (
		precision_snap_angle > 0.0
		and precision_tracking_speed > 0.0
		and error_amount <= precision_snap_angle
		and target_speed <= precision_tracking_speed
	):
		return target_angle

	var minimum_speed := deg_to_rad(minimum_turn_speed_degrees)
	var turn_speed := maxf(error_amount * follow_lerp_speed, minimum_speed)
	if maximum_turn_speed_degrees > 0.0:
		turn_speed = minf(
			turn_speed,
			deg_to_rad(maxf(maximum_turn_speed_degrees, minimum_turn_speed_degrees)),
		)
	var step := turn_speed * maxf(delta, 0.0)
	if step >= error_amount:
		return target_angle
	return current_angle + signf(error) * step


func _apply_view_pivots(desired_yaw: float, desired_pitch: float) -> void:
	var yaw_residual := desired_yaw
	if _any_lerping_node_moves_pivot(lerping_yaw_nodes, yaw_pivot):
		yaw_residual = angle_difference(_applied_follow_yaw, desired_yaw)
	var yaw_step := angle_difference(_applied_view_yaw, yaw_residual)
	if not is_zero_approx(yaw_step):
		# Incremental local-axis rotation preserves gravity alignment applied by the Orientator.
		yaw_pivot.rotate_object_local(Vector3.UP, yaw_step)
	_applied_view_yaw = yaw_residual

	var pitch_residual := desired_pitch
	if _any_lerping_node_moves_pivot(lerping_pitch_nodes, pitch_pivot):
		pitch_residual = desired_pitch - _applied_follow_pitch
	var pitch_step := pitch_residual - _applied_view_pitch
	if not is_zero_approx(pitch_step):
		pitch_pivot.rotate_object_local(Vector3.RIGHT, pitch_step)
	_applied_view_pitch = pitch_residual


func _any_lerping_node_moves_pivot(
	lerping_nodes: Array[Node3D],
	pivot: Node3D,
) -> bool:
	for lerping_node in lerping_nodes:
		if (
			is_instance_valid(lerping_node)
			and lerping_node != pivot
			and lerping_node.is_ancestor_of(pivot)
		):
			return true
	return false


func _get_first_mechanical_node(
	lerping_nodes: Array[Node3D],
	view_pivot: Node3D,
) -> Node3D:
	for lerping_node in lerping_nodes:
		if is_instance_valid(lerping_node) and lerping_node != view_pivot:
			return lerping_node
	return null


func _clamp_yaw(yaw: float) -> float:
	if maximum_yaw >= 359.999:
		return wrapf(yaw, -PI, PI)
	var half_arc := deg_to_rad(maximum_yaw) * 0.5
	return clampf(yaw, -half_arc, half_arc)


func _clamp_pitch(pitch: float) -> float:
	var lower_limit := deg_to_rad(minf(minimum_pitch, maximum_pitch)) - _initial_pitch
	var upper_limit := deg_to_rad(maxf(minimum_pitch, maximum_pitch)) - _initial_pitch
	return clampf(pitch, lower_limit, upper_limit)


func _get_input_peer_id() -> int:
	if input_peer_id > 0:
		return input_peer_id
	var parent := get_parent()
	return parent.get_multiplayer_authority() if parent else 1


func _is_local_input_owner() -> bool:
	return NetworkSession.is_local_peer(_get_input_peer_id())

func _on_setting_changed(id: StringName, value: Variant) -> void:
	if id == MOUSE_SENSITIVITY_SETTING:
		_apply_mouse_sensitivity(value)
	elif id == CONTROLLER_SENSITIVITY_SETTING:
		controller_sensitivity = float(value)
	elif id == INVERT_MOUSE_Y_SETTING:
		invert_mouse_y = bool(value)

func _apply_mouse_sensitivity(value: Variant) -> void:
	sensitivity = float(value) * ROTATION_SPEED_MULTIPLIER

func _exponential_weight(speed: float, delta: float) -> float:
	return 1.0 if speed <= 0.0 else 1.0 - exp(-speed * delta)
