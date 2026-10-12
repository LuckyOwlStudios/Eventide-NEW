@icon("uid://r8kymeskgxme")
class_name CameraRig3D
extends RemoteTransform3D
## A camera that rides a vehicle or turret but never turns with it.
##
## Put the rig under the vehicle where the pilot's eyes (or the turret's pivot) should be.
## This node, a [RemoteTransform3D], hands only its position to [code]View[/code], so the
## camera follows the vehicle without inheriting its rotation. The rig's orientation, the
## aim, is its own: it is what the vehicle should face, or a turret should point along.
##
## How the aim behaves depends on gravity, which is read from the nearest physics body above
## the rig (see [member gravity_source]):
## [br]- Weightless: look freely in every direction, over the top and upside down, plus roll.
## [br]- Gravity: the [Orientator] keeps the rig upright and looking is yaw plus pitch, with
## pitch limited to [member minimum_pitch] and [member maximum_pitch].
## [br]- [member limit_reference] (turrets): the aim may only point inside an arc measured
## against that node. The rig stays put while the vehicle turns, until the vehicle turns far
## enough that the arc catches up, and then it drags the aim along.
## [br]- Freecam (hold [member freecam_action]): the camera looks around without moving the
## aim, so a ship stops following it. Letting go swings the camera back to the aim. It looks
## around the same way the aim does: freely while weightless, and with gravity by heading and
## pitch from the horizon, so the horizon never tilts.
##
## The pieces underneath are [code]View[/code] (kept upright by the Orientator),
## [code]Pitch[/code] (up and down while there is gravity), [code]FreeLook[/code] (the freecam
## offset) and the [code]Camera[/code].

## The camera started or stopped looking around on its own, apart from the aim.
signal freecam_changed(active: bool)
## Gravity appeared or went away, which changes how looking works.
signal weightless_changed(weightless: bool)

## Smaller than this and a freecam offset counts as back on the aim.
const SETTLED_ANGLE := 0.002
## Straight along the vertical, where a heading is not defined.
const POLE_LENGTH_SQUARED := 0.000001

@export_group("Input")
## Turns the rig with the mouse and the right stick. A vehicle switches it on while its local
## player is in control.
@export var input_enabled := true
@export var roll_enabled := true
## While this is held and the rig is weightless, moving the mouse (or the right stick) sideways
## rolls the camera instead of turning it. How far it moves is how far it rolls, so rolling can
## be as gentle or as quick as you like.
@export var roll_action: StringName = &"roll"
## Right stick speed at full push, before the Controller Sensitivity setting.
@export_range(30.0, 720.0, 5.0, "suffix:°/s") var controller_look_speed_degrees := 200.0
## Shapes the stick like [Rotator] does: higher gives finer control near the middle.
@export_range(1.0, 3.0, 0.05) var controller_look_curve := 1.8
## Vertical stick turning as a share of the horizontal speed.
@export_range(0.25, 1.5, 0.05) var controller_pitch_scale := 0.7

@export_group("Camera")
## How far behind the rig the camera sits, in meters: the length of the spring arm. Set it per
## vehicle. The arm still shortens by itself when something is in the way.
@export_range(0.0, 100.0, 0.1, "or_greater", "suffix:m") var cam_distance := 3.0:
	set(value):
		cam_distance = maxf(value, 0.0)
		if is_node_ready():
			spring_arm.spring_length = cam_distance

@export_group("Gravity")
## Body whose gravity the rig follows. Empty finds the nearest physics body above the rig.
## Without any body the rig stays weightless unless something calls [method set_gravity].
@export var gravity_source: PhysicsBody3D
## While gravity is present: lowest and highest pitch, measured from the horizon.
@export_range(-89.0, 0.0, 1.0, "suffix:°") var minimum_pitch := -85.0
@export_range(0.0, 89.0, 1.0, "suffix:°") var maximum_pitch := 85.0
## How fast a pitch that is out of range (such as after floating into gravity while looking
## straight up) eases back inside it.
@export_range(10.0, 720.0, 5.0, "suffix:°/s") var pitch_correction_speed_degrees := 90.0

@export_group("Freecam")
@export var freecam_enabled := true
## Held to look around without moving the aim (C, or Y on a gamepad).
@export var freecam_action: StringName = &"freecam"
## How far up and down freecam can look. Like looking around under gravity, it turns by heading
## and pitch from the aim's horizon, so the camera can never flip over or roll.
@export_range(10.0, 90.0, 1.0, "suffix:°") var freecam_pitch_limit := 90.0
## How fast the camera swings back to the aim when freecam ends. Zero snaps back.
@export_range(0.0, 30.0, 0.5) var freecam_return_speed := 8.0

@export_group("Mount Limits")
## The vehicle or turret base the arc below is measured against. The arc is centered on its
## forward direction, so rotate this node to match the weapon's forward. Leave empty for no
## limits, as for a ship or a car.
@export var limit_reference: Node3D
## Total horizontal arc. 180 allows 90 degrees to each side; 360 is unlimited.
@export_range(1.0, 360.0, 1.0, "suffix:°") var limit_yaw_arc := 360.0
## Lowest and highest pitch relative to the reference's own horizon.
@export_range(-90.0, 0.0, 1.0, "suffix:°") var limit_minimum_pitch := -90.0
@export_range(0.0, 90.0, 1.0, "suffix:°") var limit_maximum_pitch := 90.0

## The camera. Point a vehicle's [member Vehicle3D.vehicle_camera] at this.
@onready var camera: Camera3D = %Camera
@onready var spring_arm: SpringArm3D = %SpringArm3D
@onready var view: Node3D = %View
@onready var pitch_node: Node3D = %Pitch
@onready var free_look: Node3D = %FreeLook
@onready var orientator: Orientator = %Orientator

## Blocks looking from outside, such as a cutscene.
var can_look_around := ActionBlocker.new()

var _vehicle: Vehicle3D
var _gravity := Vector3.ZERO
var _up := Vector3.UP
var _weightless := true
## Up and down while there is gravity. Always zero while weightless, when [member view]
## carries the whole orientation.
var _pitch := 0.0
## Where the camera looks relative to the aim, in any gravity: how far it has turned from the
## aim's heading, and how far it has tipped from the aim's pitch. Both are zero unless freecam
## is, or has just been, in use.
var _free_yaw := 0.0
var _free_pitch := 0.0
var _freecam := false
var _mouse_radians := 0.0
var _controller_sensitivity := 1.0
var _invert_y := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	view.global_position = global_position
	spring_arm.spring_length = cam_distance
	orientator.step_automatically = false
	orientator.gravity_source = gravity_source if is_instance_valid(gravity_source) else _find_gravity_body()

	_mouse_radians = deg_to_rad(
		float(Settings.get_setting(Rotator.MOUSE_SENSITIVITY_SETTING, 1.0)) * Rotator.ROTATION_SPEED_MULTIPLIER
	)
	_controller_sensitivity = float(Settings.get_setting(Rotator.CONTROLLER_SENSITIVITY_SETTING, 1.0))
	_invert_y = bool(Settings.get_setting(Rotator.INVERT_MOUSE_Y_SETTING, false))
	Settings.setting_changed.connect(_on_setting_changed)

	_vehicle = _find_vehicle()
	if is_instance_valid(_vehicle):
		if not is_instance_valid(_vehicle.vehicle_camera):
			_vehicle.vehicle_camera = camera
		input_enabled = _vehicle.has_local_control()
		_vehicle.control_started.connect(_on_vehicle_control_changed)
		_vehicle.control_ended.connect(_on_vehicle_control_changed)

	# Start out looking the way the mount points.
	_set_aim_basis(global_basis)


func _input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion == null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or not _can_look():
		return
	apply_mouse_motion(motion.relative)


## Turns the rig by a mouse movement in pixels. Sideways turns the camera left and right, or
## rolls it while [member roll_action] is held and the rig is weightless. Up and down pitches.
func apply_mouse_motion(relative: Vector2) -> void:
	var pitch := -relative.y * _mouse_radians * (-1.0 if _invert_y else 1.0)
	if _is_rolling():
		add_look_input(0.0, pitch, relative.x * _mouse_radians)
	else:
		add_look_input(-relative.x * _mouse_radians, pitch)


## Roll only exists in free flight. With gravity the horizon stays level, and freecam never rolls.
func _is_rolling() -> bool:
	return roll_enabled and _weightless and not _freecam and Input.is_action_pressed(roll_action)


func _process(delta: float) -> void:
	# Under physics interpolation the vehicle is drawn between its physics ticks. The
	# RemoteTransform3D only knows where it was on the last tick, so follow the drawn position.
	view.global_position = get_global_transform_interpolated().origin
	view.orthonormalize()

	_refresh_gravity()
	set_freecam(freecam_enabled and _can_use_buttons() and Input.is_action_pressed(freecam_action))
	_apply_held_input(delta)

	if not _weightless:
		orientator.orient_to_gravity(_gravity, delta)
		_ease_pitch_into_range(delta)
	_enforce_mount_limits()
	_return_from_freecam(delta)
	_apply_free_look()


# --- Looking -----------------------------------------------------------------

## Turns the rig by an already-scaled amount in radians. Positive yaw looks left, positive
## pitch looks up and positive roll banks right.
## [br]While freecam is held this only moves the camera and the aim stays put, and roll is
## ignored. Roll only happens to the aim while weightless; gravity keeps the horizon level.
func add_look_input(yaw_delta: float, pitch_delta: float, roll_delta := 0.0) -> void:
	if not is_finite(yaw_delta) or not is_finite(pitch_delta) or not is_finite(roll_delta):
		return
	if _freecam:
		# Heading turns around the aim's up and pitch tips from its horizon, as when looking
		# around under gravity, so looking up and then sideways never leaves the camera tilted
		# or flipped over. There is no roll.
		var limit := deg_to_rad(freecam_pitch_limit)
		_free_yaw = wrapf(_free_yaw + yaw_delta, -PI, PI)
		_free_pitch = clampf(_pitch + _free_pitch + pitch_delta, -limit, limit) - _pitch
		_apply_free_look()
	elif _weightless:
		# Free flight: every turn is around the camera's own axes.
		view.global_basis = (
			view.global_basis.orthonormalized()
			* Basis(Vector3.UP, yaw_delta)
			* Basis(Vector3.RIGHT, pitch_delta)
			* Basis(Vector3.FORWARD, roll_delta)
		)
	else:
		# Heading turns around the rig's up.
		view.rotate_object_local(Vector3.UP, yaw_delta)
		_pitch = _limited_pitch(_pitch, pitch_delta)
		_apply_pitch()


## Starts or stops freecam.
func set_freecam(active: bool) -> void:
	if active == _freecam:
		return
	_freecam = active
	freecam_changed.emit(_freecam)


## Faces the aim along the mount again, with the camera back on it. A vehicle does this
## when someone takes control.
func align_to_mount() -> void:
	_free_yaw = 0.0
	_free_pitch = 0.0
	_apply_free_look()
	_set_aim_basis(global_basis)


## Gives the rig gravity when it has no body to read it from, such as a turret on a plain
## Node3D. Ignored while a body is supplying gravity.
func set_gravity(gravity: Vector3) -> void:
	_gravity = gravity


# --- What the rig is pointing at ---------------------------------------------

## The orientation the controlled thing should face. Moves with the mouse, but not with the
## camera while freecam is held.
func get_aim_basis() -> Basis:
	return pitch_node.global_basis.orthonormalized()


func get_aim_forward() -> Vector3:
	return -get_aim_basis().z


## What the player sees through. Differs from [method get_aim_basis] during freecam.
func get_view_basis() -> Basis:
	return camera.global_basis.orthonormalized()


## Opposite to gravity. With no gravity the rig has no "up" of its own, so this is the aim's.
func get_up_direction() -> Vector3:
	return get_aim_basis().y if _weightless else _up


## Where the aim faces along the ground: the direction a car should drive. A car stuck
## upside down still gets the direction the camera looks.
func get_heading() -> Vector3:
	var aim := get_aim_basis()
	var up := get_up_direction()
	var heading := -aim.z - up * (-aim.z).dot(up)
	if heading.length_squared() < POLE_LENGTH_SQUARED:
		heading = -aim.y - up * (-aim.y).dot(up)
	return heading.normalized()


## Signed angle, around [method get_up_direction], from [param from_direction] (a wheel's or a
## hull's forward) to [method get_heading]. Positive means the heading is to the left.
func get_yaw_error(from_direction: Vector3) -> float:
	var up := get_up_direction()
	var flat := from_direction - up * from_direction.dot(up)
	if flat.length_squared() < POLE_LENGTH_SQUARED:
		return 0.0
	return flat.normalized().signed_angle_to(get_heading(), up)


func is_weightless() -> bool:
	return _weightless


func is_freecam_active() -> bool:
	return _freecam


# --- Internals ---------------------------------------------------------------

func _can_look() -> bool:
	return input_enabled and can_look_around.is_permitted()


## Held buttons and the stick should not do anything behind a menu.
func _can_use_buttons() -> bool:
	return _can_look() and not InGameUIHandler.is_ui_open


func _apply_held_input(delta: float) -> void:
	if not _can_use_buttons():
		return
	var yaw := 0.0
	var pitch := 0.0
	var stick := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if not stick.is_zero_approx():
		var shaped := stick.normalized() * pow(minf(stick.length(), 1.0), controller_look_curve)
		var turn := deg_to_rad(controller_look_speed_degrees) * _controller_sensitivity * delta
		yaw = -shaped.x * turn
		pitch = -shaped.y * turn * controller_pitch_scale * (-1.0 if _invert_y else 1.0)
	var roll := 0.0
	if _is_rolling():
		# The stick does what the mouse does: sideways rolls instead of turning.
		roll = -yaw
		yaw = 0.0
	if not is_zero_approx(yaw) or not is_zero_approx(pitch) or not is_zero_approx(roll):
		add_look_input(yaw, pitch, roll)


## Reads gravity and switches between free flight and upright looking without moving the
## camera: the pitch is moved between the body and the pitch pivot, so nothing visibly jumps.
func _refresh_gravity() -> void:
	if orientator.has_gravity_source():
		_gravity = orientator.sample_gravity()
	var minimum := orientator.minimum_gravity
	var weightless := _gravity.length_squared() <= minimum * minimum
	if not weightless:
		_up = -_gravity.normalized()
	if weightless == _weightless:
		return

	# Freecam keeps looking exactly where it did across the change (any roll is dropped). `seen`
	# is that direction as the aim sees it; going into gravity the body then turns by the pitch.
	var seen := _free_look_offset() * Vector3.FORWARD
	if weightless:
		view.global_basis = view.global_basis * Basis(Vector3.RIGHT, _pitch)
		_pitch = 0.0
		_apply_pitch()
		_weightless = true
	else:
		_weightless = false
		_set_aim_basis(view.global_basis)
		seen = Basis(Vector3.RIGHT, _pitch) * seen
	_set_free_look_toward(seen)
	weightless_changed.emit(_weightless)


## Makes [param aim] the aim, split into whatever the current mode keeps in the body and in
## the pitch pivot. While there is gravity a tilted body is left for the Orientator to right.
func _set_aim_basis(aim: Basis) -> void:
	aim = aim.orthonormalized()
	if _weightless:
		view.global_basis = aim
		_pitch = 0.0
	else:
		_pitch = asin(clampf((-aim.z).dot(_up), -1.0, 1.0))
		view.global_basis = aim * Basis(Vector3.RIGHT, -_pitch)
	_apply_pitch()


func _apply_pitch() -> void:
	pitch_node.rotation = Vector3(_pitch, 0.0, 0.0)


## Pitch after tipping [param current] by [param delta], held between the limits. A pitch that
## is already beyond a limit may only move back toward it.
func _limited_pitch(current: float, delta: float) -> float:
	var lowest := minf(deg_to_rad(minimum_pitch), current)
	var highest := maxf(deg_to_rad(maximum_pitch), current)
	return clampf(current + delta, lowest, highest)


## The camera's turn away from the aim, as the Pitch node sees it. The camera ends up as the View
## turned by the free heading and then tipped to the aim's pitch plus the free pitch, which has
## no roll in it however the offset was reached.
func _free_look_offset() -> Quaternion:
	return Quaternion(
		Basis(Vector3.RIGHT, -_pitch)
		* Basis(Vector3.UP, _free_yaw)
		* Basis(Vector3.RIGHT, _pitch + _free_pitch)
	)


## Sets the free heading and pitch so the camera looks along [param seen], a direction measured
## from the View.
func _set_free_look_toward(seen: Vector3) -> void:
	var limit := deg_to_rad(freecam_pitch_limit)
	var around := Vector2(seen.x, seen.z).length_squared() > POLE_LENGTH_SQUARED
	_free_yaw = atan2(-seen.x, -seen.z) if around else 0.0
	_free_pitch = clampf(asin(clampf(seen.y, -1.0, 1.0)), -limit, limit) - _pitch


func _apply_free_look() -> void:
	free_look.quaternion = _free_look_offset()


func _ease_pitch_into_range(delta: float) -> void:
	var lowest := deg_to_rad(minimum_pitch)
	var highest := deg_to_rad(maximum_pitch)
	if _pitch >= lowest and _pitch <= highest:
		return
	_pitch = move_toward(
		_pitch,
		clampf(_pitch, lowest, highest),
		deg_to_rad(pitch_correction_speed_degrees) * delta,
	)
	_apply_pitch()


## Keeps the aim inside the arc of [member limit_reference]. When the reference turns away
## from where the aim points, this is what drags the aim along.
func _enforce_mount_limits() -> void:
	if not is_instance_valid(limit_reference):
		return
	var frame := limit_reference.global_basis.orthonormalized()
	var aim := get_aim_basis()
	var forward := frame.inverse() * (-aim.z)
	var around := Vector2(forward.x, forward.z).length_squared() > POLE_LENGTH_SQUARED
	var pitch := asin(clampf(forward.y, -1.0, 1.0))
	var yaw := atan2(-forward.x, -forward.z) if around else 0.0

	var limited_pitch := clampf(pitch, deg_to_rad(limit_minimum_pitch), deg_to_rad(limit_maximum_pitch))
	var limited_yaw := yaw
	if limit_yaw_arc < 359.999 and around:
		var half_arc := deg_to_rad(limit_yaw_arc) * 0.5
		limited_yaw = clampf(yaw, -half_arc, half_arc)
	if is_equal_approx(limited_pitch, pitch) and is_equal_approx(limited_yaw, yaw):
		return

	var limited_forward := Vector3(
		-sin(limited_yaw) * cos(limited_pitch),
		sin(limited_pitch),
		-cos(limited_yaw) * cos(limited_pitch),
	)
	var drag := Quaternion(-aim.z, frame * limited_forward)
	_set_aim_basis(Basis(drag) * aim)


## Swings the camera back onto the aim once freecam is released.
func _return_from_freecam(delta: float) -> void:
	if _freecam or (_free_yaw == 0.0 and _free_pitch == 0.0):
		return
	# The heading and the pitch each ease back on their own, so the camera never rolls on the
	# way, and a heading turned more than half a circle goes back the short way.
	var weight := 1.0 if freecam_return_speed <= 0.0 else 1.0 - exp(-freecam_return_speed * delta)
	_free_yaw = lerp_angle(_free_yaw, 0.0, weight)
	_free_pitch = lerpf(_free_pitch, 0.0, weight)
	if maxf(absf(_free_yaw), absf(_free_pitch)) < SETTLED_ANGLE:
		_free_yaw = 0.0
		_free_pitch = 0.0


func _find_gravity_body() -> PhysicsBody3D:
	var node := get_parent()
	while node != null:
		if node is PhysicsBody3D:
			return node as PhysicsBody3D
		node = node.get_parent()
	return null


func _find_vehicle() -> Vehicle3D:
	var node := get_parent()
	while node != null:
		if node is Vehicle3D:
			return node as Vehicle3D
		node = node.get_parent()
	return null


func _on_vehicle_control_changed(_controller: VehicleController) -> void:
	input_enabled = _vehicle.has_local_control()
	if _vehicle.controller != null:
		align_to_mount()


func _on_setting_changed(id: StringName, value: Variant) -> void:
	if id == Rotator.MOUSE_SENSITIVITY_SETTING:
		_mouse_radians = deg_to_rad(float(value) * Rotator.ROTATION_SPEED_MULTIPLIER)
	elif id == Rotator.CONTROLLER_SENSITIVITY_SETTING:
		_controller_sensitivity = float(value)
	elif id == Rotator.INVERT_MOUSE_Y_SETTING:
		_invert_y = bool(value)
