@tool
@icon("uid://b3hdct1vl1edl")
class_name SpaceShip3D
extends Vehicle3D
## A space ship. It turns to face wherever its [CameraRig3D] is aimed, in direction and in
## roll, as fast as its thrusters allow. Nothing else holds it: whatever knocks it off course
## (a crash, a gravity field) turns it, and it then swings itself back.
##
## It moves relative to the camera rig, not to itself: forward is where the camera looks, up is
## the camera's up, however the ship happens to be turned at that moment. The thrusters speed it up
## to the speed asked for and brake it when nothing is held, so a ship someone is flying does not
## drift. Once the pilot leaves, nothing pushes it any more.
##
## None of this works with [member Vehicle3D.engine_state] off: the ship cannot turn or thrust, and
## it falls under full gravity. With the engine on it hovers instead: gravity does not pull it
## down, and when nobody is flying it, it turns itself upright against the gravity.
##
## Landing: the ship's landing gear are the [Suspension3D] nodes under it. It counts as landed while
## enough of them are on the ground and the pilot is not holding Space (jump). A landed ship rests on
## its gear under full gravity, even with the engine on, and does not steer or thrust. Holding Space
## lifts it off: it is no longer landed, so it hovers and flies as usual. The gear can be retracted and
## deployed with the landing gear key (G), which takes power; see [member landing_gear_deployed].

## The ship touched down or lifted off.
signal landed_changed(landed: bool)
## The landing gear was told to go down or up.
signal landing_gear_changed(deployed: bool)

## The controls, shared with moving on foot. Every ship uses all of them.
const MOVE_LEFT := &"move_left"
const MOVE_RIGHT := &"move_right"
const MOVE_FORWARD := &"move_forward"
const MOVE_BACK := &"move_back"
const MOVE_UP := &"jump"
const MOVE_DOWN := &"crouch"
const BOOST := &"sprint"
const PRECISION := &"stroll"
## Retracts or deploys the landing gear.
const LANDING_GEAR := &"landing_gear"

## Gravity weaker than this is ignored.
const MINIMUM_GRAVITY := 0.001
## The ship stays landed this long after enough of its gear last touched the ground, so a bounce
## that lifts them off for a moment does not undo the landing.
const LANDING_GRACE_TIME := 0.2

@export_group("Steering")
## The camera rig the ship follows. The first one found under the ship when left empty.
@export var camera_rig: CameraRig3D
## The fastest the ship will turn.
@export_range(10.0, 360.0, 1.0, "suffix:°/s") var max_turn_rate_degrees := 60.0
## How quickly the thrusters can speed up or slow down a turn. Low is a heavy ship.
@export_range(10.0, 720.0, 1.0, "suffix:°/s²") var turn_acceleration_degrees := 90.0
## How hard the ship turns for the angle left to go. Higher is snappier near the target.
@export_range(0.5, 10.0, 0.1) var turn_response := 2.5

@export_group("Movement")
## The ship's top speed with nothing special held.
@export_range(1.0, 500.0, 1.0, "or_greater", "suffix:m/s") var max_speed := 25.0
## How hard the thrusters push, in speed gained per second. Low is a heavy ship.
@export_range(0.5, 200.0, 0.5, "or_greater", "suffix:m/s²") var thrust_acceleration := 10.0
## Top speed and thrust are multiplied by this while boosting (Shift).
@export_range(1.0, 10.0, 0.1) var boost_multiplier := 3.0
## ...and by this while moving precisely (Alt).
@export_range(0.01, 1.0, 0.01) var precision_multiplier := 0.2
## How fast the Ship moves forward, as a share of its speed
@export var forward_direction_multiplier: float = 1
## How fast the Ship moves backward, as a share of its speed
@export var backward_direction_multiplier: float = 1
## How fast the Ship moves left, as a share of its speed
@export var left_direction_multiplier: float = 1
## How fast the Ship moves right, as a share of its speed
@export var right_direction_multiplier: float = 1
## How fast the Ship moves up, as a share of its speed
@export var up_direction_multiplier: float = 1
## How fast the Ship moves down, as a share of its speed
@export var down_direction_multiplier: float = 1

@export_group("Landing")
## Whether the landing gear is down. Changing it sends the gear up or down at its own pace, which
## takes power; the landing gear key does this from the pilot's seat.
@export var landing_gear_deployed := true:
	set(value):
		if value == landing_gear_deployed:
			return
		landing_gear_deployed = value
		landing_gear_changed.emit(value)
## How many landing gear must be on the ground for the ship to count as landed.
@export_range(1, 16, 1) var landing_gear_needed := 3
## How long the landing gear takes to go all the way down, or all the way up.
@export_range(0.2, 30.0, 0.1, "suffix:s") var landing_gear_travel_time := 2.5

@export_group("Debugging")
## Flies the ship without anyone sitting in a seat: the rig takes input and the ship follows
## it. For trying the ship out before there is a pilot seat.
@export var fly_without_pilot := false

## True while the thrusters are still stopping the turn they were making when the pilot left.
var _cutting_spin := false
## The gravity acting on the ship, as of the last physics step.
var _gravity := Vector3.ZERO
## The ship's landing gear: every Suspension3D under it.
var _landing_gear: Array[Suspension3D] = []
## 0 with the landing gear all the way up, 1 with it all the way down.
var _gear_progress := 1.0
var _gear_touching := 0
var _landed := false
## How long it has been since enough of the landing gear was on the ground.
var _time_off_ground := LANDING_GRACE_TIME


func _enter_tree() -> void:
	super._enter_tree()
	if Engine.is_editor_hint():
		return
	# A sleeping body ignores the thrusters.
	can_sleep = false


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	if not is_instance_valid(camera_rig):
		camera_rig = _find_camera_rig(self)
	if fly_without_pilot and is_instance_valid(camera_rig):
		camera_rig.input_enabled = true
		camera_rig.camera.current = true
	_ensure_landing_gear_action()
	_landing_gear = _find_landing_gear()
	_gear_progress = 1.0 if landing_gear_deployed else 0.0
	_apply_gear_progress()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	super._physics_process(delta)
	_update_landing(delta)
	if not engine_state:
		_cutting_spin = false
		return
	if _landed:
		# Parked on its gear: the thrusters do not push or turn it against the ground it rests on.
		_cutting_spin = false
		return

	if _is_piloted():
		_cutting_spin = false
		_turn_toward(camera_rig.get_aim_basis(), delta)
		_thrust(delta)
		return

	if _gravity.length_squared() > MINIMUM_GRAVITY * MINIMUM_GRAVITY:
		# Nobody is flying it, but it still hovers and rights itself against the gravity.
		_cutting_spin = false
		_turn_toward(_upright_basis(-_gravity.normalized()), delta)
	elif _cutting_spin:
		_cut_spin(delta)


## Someone is flying it: they sit in a seat (or the debug flag is on), and the ship has a rig.
func _is_piloted() -> bool:
	return is_instance_valid(camera_rig) and (fly_without_pilot or has_local_control())


## With the engine running the ship hovers: the engine pushes back exactly as hard as gravity
## pulls, so it feels no gravity and does not fall. Gravity is still there to be measured, which
## the camera rig and the self-righting need, so the pull is cancelled rather than switched off.
## With the engine off nothing is cancelled and the ship falls like any heavy object. A landed ship
## is not held up by its engine either, but by its landing gear, so it feels its full weight.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if Engine.is_editor_hint():
		return
	_gravity = state.total_gravity
	if engine_state and not _landed:
		state.apply_central_force(-_gravity * mass)


## The orientation the ship has now, turned the shortest way so that its up is [param up].
func _upright_basis(up: Vector3) -> Basis:
	var current := global_basis.orthonormalized()
	return Basis(Quaternion(current.y, up)) * current


## The velocity the pilot is asking for, in world space: the held directions along the camera's
## own right, up and forward, however fast they are allowed to go.
func get_wanted_velocity() -> Vector3:
	if not is_instance_valid(camera_rig) or InGameUIHandler.is_ui_open:
		return Vector3.ZERO
	var wanted := Vector3(
		Input.get_axis(MOVE_LEFT, MOVE_RIGHT),
		Input.get_action_strength(MOVE_UP) * (0.0 if is_start_key_in_use() else 1.0) - Input.get_action_strength(MOVE_DOWN),
		Input.get_axis(MOVE_FORWARD, MOVE_BACK),
	)
	if wanted.length() > 1.0:
		wanted = wanted.normalized()
	wanted.x *= right_direction_multiplier if wanted.x > 0.0 else left_direction_multiplier
	wanted.y *= up_direction_multiplier if wanted.y > 0.0 else down_direction_multiplier
	wanted.z *= backward_direction_multiplier if wanted.z > 0.0 else forward_direction_multiplier
	return camera_rig.get_aim_basis() * wanted * max_speed * _speed_scale()


## Boosting and moving precisely both scale how fast the ship goes and how hard it pushes.
func _speed_scale() -> float:
	var factor := 1.0
	if Input.is_action_pressed(BOOST):
		factor *= boost_multiplier
	if Input.is_action_pressed(PRECISION):
		factor *= precision_multiplier
	return factor


## Pushes the ship toward the velocity asked for, no harder than the thrusters can. The push is
## an impulse on the body scaled by its mass, so a heavy ship gets going as quickly as a light
## one, and a crash still knocks it about for real.
func _thrust(delta: float) -> void:
	var change := get_wanted_velocity() - linear_velocity
	var limit := thrust_acceleration * _speed_scale() * delta
	apply_central_impulse(change.limit_length(limit) * mass)


## The pilot got up. Whatever turn the thrusters were making is stopped, at the pace they can,
## and then they let go for good: nothing damps an empty ship, so one that gets knocked
## afterwards keeps tumbling and drifting.
func _on_control_ended(_ended_controller: VehicleController) -> void:
	_cutting_spin = true


func _cut_spin(delta: float) -> void:
	angular_velocity = angular_velocity.move_toward(
		Vector3.ZERO,
		deg_to_rad(turn_acceleration_degrees) * delta,
	)
	if angular_velocity.is_zero_approx():
		_cutting_spin = false


## How far, in degrees, the ship is from facing where the rig aims.
func get_aim_error_degrees() -> float:
	if not is_instance_valid(camera_rig):
		return 0.0
	return rad_to_deg(_rotation_to(camera_rig.get_aim_basis()).get_angle())


## Speeds the ship's spin up or down toward the one that turns it onto [param target], within
## what the thrusters can do. A hit from outside changes the spin like any other rigid body, and
## this is what then brings it back.
func _turn_toward(target: Basis, delta: float) -> void:
	var error := _rotation_to(target)
	var angle := error.get_angle()
	var wanted_spin := Vector3.ZERO
	if angle > 0.0001:
		var acceleration := deg_to_rad(turn_acceleration_degrees)
		# Never faster than the ship can still stop in the angle that is left.
		var speed := minf(
			minf(deg_to_rad(max_turn_rate_degrees), angle * turn_response),
			sqrt(2.0 * acceleration * angle),
		)
		wanted_spin = error.get_axis() * speed
	angular_velocity = angular_velocity.move_toward(
		wanted_spin,
		deg_to_rad(turn_acceleration_degrees) * delta,
	)


## The shortest turn, in world space, from the ship's orientation onto [param target].
func _rotation_to(target: Basis) -> Quaternion:
	var current := global_basis.orthonormalized().get_rotation_quaternion()
	var error := target.orthonormalized().get_rotation_quaternion() * current.inverse()
	return -error if error.w < 0.0 else error


func _find_camera_rig(node: Node) -> CameraRig3D:
	for child in node.get_children():
		if child is CameraRig3D:
			return child as CameraRig3D
		var nested := _find_camera_rig(child)
		if is_instance_valid(nested):
			return nested
	return null


# --- Landing -----------------------------------------------------------------

## True while the ship rests on its landing gear: enough of them are on the ground, there is gravity
## to rest under, and the pilot is not holding Space to lift off. A ship without landing gear is
## never landed.
func is_landed() -> bool:
	return _landed


## How many of the landing gear are on the ground.
func get_landing_gear_touching() -> int:
	return _gear_touching


## How many landing gear the ship has.
func get_landing_gear_count() -> int:
	return _landing_gear.size()


## How far down the landing gear is, from 0 (all the way up) to 1 (all the way down).
func get_landing_gear_extension() -> float:
	return smoothstep(0.0, 1.0, _gear_progress)


## True while the landing gear is on its way up or down.
func is_landing_gear_moving() -> bool:
	return not _landing_gear.is_empty() and not is_equal_approx(_gear_progress, 1.0 if landing_gear_deployed else 0.0)


## Sends the landing gear down. The gear is worked by hydraulics, so this needs power: it returns
## false, and does nothing, without it (or on a ship that has no landing gear).
func deploy_landing_gear() -> bool:
	return _command_landing_gear(true)


## Sends the landing gear up. Needs power.
func retract_landing_gear() -> bool:
	return _command_landing_gear(false)


## Sends the landing gear the other way from where it was headed. Needs power.
func toggle_landing_gear() -> bool:
	return _command_landing_gear(not landing_gear_deployed)


func _command_landing_gear(deploy: bool) -> bool:
	if not power_state or _landing_gear.is_empty():
		return false
	landing_gear_deployed = deploy
	return true


## Moves the landing gear, counts what is on the ground and decides whether the ship is landed.
func _update_landing(delta: float) -> void:
	if _landing_gear.is_empty():
		return
	_update_landing_gear(delta)
	_gear_touching = 0
	for gear in _landing_gear:
		if gear.is_touching():
			_gear_touching += 1
	if _gear_touching >= mini(landing_gear_needed, _landing_gear.size()):
		_time_off_ground = 0.0
	else:
		_time_off_ground += delta
	# Out in space there is nothing to land on, only a floor to be near: the pilot keeps full control.
	var has_gravity := _gravity.length_squared() > MINIMUM_GRAVITY * MINIMUM_GRAVITY
	_set_landed(has_gravity and _time_off_ground < LANDING_GRACE_TIME and not _is_lifting_off())


func _set_landed(landed: bool) -> void:
	if landed == _landed:
		return
	_landed = landed
	landed_changed.emit(landed)


## The pilot is holding Space with the engine on: going up, which takes the ship off the ground.
func _is_lifting_off() -> bool:
	return (
		engine_state
		and _is_piloted()
		and not InGameUIHandler.is_ui_open
		and not is_start_key_in_use()
		and Input.is_action_pressed(MOVE_UP)
	)


## Takes the key press from the pilot and sends the gear on its way, at the pace of the hydraulics.
func _update_landing_gear(delta: float) -> void:
	if _is_piloted() and not InGameUIHandler.is_ui_open and Input.is_action_just_pressed(LANDING_GEAR):
		toggle_landing_gear()
	var target := 1.0 if landing_gear_deployed else 0.0
	if power_state and not is_equal_approx(_gear_progress, target):
		_gear_progress = move_toward(_gear_progress, target, delta / landing_gear_travel_time)
		_apply_gear_progress()


## Sets every leg to how far down the gear is. It starts and ends gently, as hydraulics do.
func _apply_gear_progress() -> void:
	var extension := get_landing_gear_extension()
	for gear in _landing_gear:
		gear.extension = extension


func _find_landing_gear() -> Array[Suspension3D]:
	var found: Array[Suspension3D] = []
	for node in find_children("*", "Suspension3D", true, false):
		found.append(node as Suspension3D)
	return found


## The landing gear key is in the Input Map. It is added here too, in case the project file was saved
## by an editor that was open when the key was added, so the ship never listens for a key that does
## not exist.
func _ensure_landing_gear_action() -> void:
	if InputMap.has_action(LANDING_GEAR):
		return
	InputMap.add_action(LANDING_GEAR)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_G
	InputMap.action_add_event(LANDING_GEAR, key)
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_DPAD_DOWN
	InputMap.action_add_event(LANDING_GEAR, button)
