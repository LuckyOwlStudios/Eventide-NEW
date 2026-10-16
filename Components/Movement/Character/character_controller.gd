@icon("uid://bsf5y3xex4km7")
class_name CharacterController
extends Node
## The one node that moves a [WalkingCharacter3D]: base class for [PlayerCharacterController]
## and [AICharacterController].
##
## A subclass only decides what the character wants, by overriding [method poll_intent]
## and returning a [MoveIntent] for each physics tick. Everything after that is here:
## walking, sprinting, strolling, crouching, jumping, stairs, air control, floating in
## zero gravity, jetpack thrust and creative flight. The base class never reads input or
## touches the network.
##
## What the character is lies in the character, not here: how fast and how high it goes, how it feels on
## the ground, what it may do (see [WalkingCharacter3D]) and what its hitbox is in each stance. This node
## decides what it does this tick and tells the character, which owns the rest. What is seen of the
## character, such as a head that lowers when it crouches, is the character's business too.
##
## Every tick is [method simulate], a step from the current [MoveState] and one
## intent to the next state. Nothing else influences it, so a client can rewind
## to a state the server sent and replay its own inputs to predict ahead. A
## [CharacterNetSync] does that; without one this node drives itself locally.
##
## Orientation toward gravity belongs to an [Orientator], which this node steps
## itself so that the rotation replays along with everything else.
##
## A subclass that overrides [method _ready] or [method _physics_process] must call
## [code]super()[/code] in them.

## Emitted on a real tick when the character leaves the ground by jumping.
signal jumped
## Emitted when the character touches ground after being airborne.
signal landed(impact_speed: float)
signal crouch_changed(is_crouching: bool)
signal flight_changed(is_flying: bool)
signal sprint_changed(is_sprinting: bool)
## Emitted after [method teleport] moves the character.
signal teleported(destination: Transform3D)
## Movement was locked through [member movement_blocker] or the node was disabled.
signal movement_suspended
## Movement unlocked again. The character may have been moved meanwhile.
signal movement_resumed

enum MoveMode {
	## Gravity is present and the character walks, jumps and falls.
	WALKING,
	## Creative flight: no gravity, direct control in every direction.
	FLYING,
	## No gravity: the character drifts, plus jetpack thrust if it has one.
	FLOATING,
}

const MINIMUM_GRAVITY := 0.001
## Smallest bump worth climbing; anything lower is left to the physics engine.
const MINIMUM_STEP_RISE := 0.05
## Extra height added to a step-up so the body clears the edge.
const STEP_LIFT_MARGIN := 0.01
## Longest a glide over a step edge may last, as a safety net.
const STEP_ASSIST_TICKS := 45
## How far ahead stairs are looked for, however slowly the character moves.
const STEP_LOOKAHEAD := 0.12
## While gliding over a step edge the body may only snap this far down.
const STEP_ASSIST_SNAP := 0.06
const STEP_PROBE_DISTANCE := 0.04
## How long a descent keeps its longer reach after the last snap down.
const DESCENT_TICKS := 4
const STEP_PROBE_LIFT := 0.05
## Height above the feet, and how far, of the ray that reads the face of a step.
const STEP_FACE_HEIGHT := 0.04
const STEP_FACE_REACH := 0.9
const SMOOTHED_SNAP_DISTANCE := 0.1

@export_group("Components")
## The character this node moves. Its parent when left empty.
@export var character: WalkingCharacter3D
## Drives this node when the character takes part in networking. Leave empty
## for single-player characters, which then drive themselves.
@export var net_sync: CharacterNetSync
## Aligns the body to gravity. This node steps it, so it need not tick on its own.
@export var orientor: Orientator
## Optional thrust for moving through zero gravity.
@export var jetpack: Jetpack
## Sprinting costs this stamina. Leave empty for free sprinting.
@export var stamina: Stamina
## Moves the character out of the way of whatever overlaps it, softly. This node runs it inside its
## own tick, so a prediction includes the push. Found next to this node when left empty.
@export var soft_collision: SoftCollision3D

@export_group("Sprint Stamina")
## Stamina spent each second of sprinting.
@export_range(0.0, 100.0, 0.5, "suffix:/s") var sprint_stamina_per_second := 15.0
## After running out, sprinting stays off until stamina recovers to this share of its maximum.
@export_range(0.0, 1.0, 0.01) var sprint_resume_fraction := 0.15

@export_group("Flight and Zero Gravity")
## Lets double-tapping jump switch creative flight on. Servers use this to refuse it.
@export var allow_creative_flight := true
## Creative flight speed as a multiple of movement speed.
@export_range(0.5, 10.0, 0.1) var flight_speed_multiplier := 2.0
@export_range(0.0, 60.0, 0.5) var flight_acceleration := 12.0
@export_range(0.0, 360.0, 1.0, "suffix:°/s") var roll_speed_degrees := 120.0

## Add a blocker to stop all movement, for example while on a ladder or in a seat.
## Remove it again and movement picks up from wherever the body ended up.
var movement_blocker := ActionBlocker.new()
var gravity_vector := Vector3.ZERO
var has_gravity := false

var _body: WalkingCharacter3D
var _step_delta := 1.0 / 60.0
var _floor_cos := cos(deg_to_rad(46.0))

var _grounded := false
var _flying := false
var _flight_left_ground := false
var _sprinting := false
var _target_speed := 0.0
var _coyote_left := 0.0
var _jump_buffer_left := 0.0
var _step_assist_ticks := 0
var _descent_ticks := 0
var _sprint_exhausted := false
var _was_permitted := true

var _events: Array = []
#var _collision := KinematicCollision3D.new()

func _ready() -> void:
	_body = character if is_instance_valid(character) else get_parent() as WalkingCharacter3D
	if _body == null:
		push_error("CharacterController must be a child of a WalkingCharacter3D, or have 'character' set.")
		set_physics_process(false)
		return
	_step_delta = 1.0 / float(Engine.physics_ticks_per_second)
	_resolve_components()
	if is_instance_valid(orientor):
		orientor.step_automatically = false
	# A network driver calls step() itself; otherwise this node runs the show.
	set_physics_process(not is_instance_valid(net_sync))


func _physics_process(_delta: float) -> void:
	if not begin_tick():
		return
	step(prepare_intent(poll_intent(_step_delta)))


# --- Driving -----------------------------------------------------------------

## Override this: what does the character want to do right now? Called once per
## physics tick on whichever machine is driving the character. Return a fresh
## [MoveIntent]; it is taken over and may be changed. The base class wants nothing.
func poll_intent(_delta: float) -> MoveIntent:
	return MoveIntent.new()


## Called first on every driven tick. Returns false while movement is locked, in
## which case nothing should be simulated.
func begin_tick() -> bool:
	var permitted := is_movement_permitted()
	if permitted != _was_permitted:
		_was_permitted = permitted
		if permitted:
			_reset_transient_state()
			movement_resumed.emit()
		else:
			movement_suspended.emit()
	return permitted


func is_movement_permitted() -> bool:
	return movement_blocker.is_permitted() and can_process()


## Applies the rules that decide which of the player's wishes are allowed right
## now: the character must be able to run, crouch and jump (see [WalkingCharacter3D]), sprinting needs
## stamina and creative flight must be permitted. Servers run this on commands from clients so a client
## cannot grant itself abilities.
func prepare_intent(intent: MoveIntent) -> MoveIntent:
	intent.quantize()
	if intent.sprint and (_sprint_exhausted or not _body.can_run()):
		intent.sprint = false
	if intent.crouch and not _body.can_crouch():
		intent.crouch = false
	if intent.jump_pressed and not _body.can_jump():
		intent.jump_pressed = false
	if intent.toggle_flight and not allow_creative_flight:
		intent.toggle_flight = false
	return intent


## Advances one real tick: simulates, then reports what happened through signals
## and spends stamina. Use [method replay] when re-running an old tick.
func step(intent: MoveIntent) -> void:
	_events.clear()
	simulate(intent)
	_flush_events()
	_apply_live_effects()


## Re-runs an old tick without side effects. Used to catch up after a correction.
func replay(intent: MoveIntent) -> void:
	simulate(intent)
	_events.clear()


## One tick of movement. The new state depends only on the old state, [param intent]
## and the world, and the only things it touches are the body and this node's
## own fields.
func simulate(intent: MoveIntent) -> void:
	if not is_instance_valid(_body):
		return
	var delta := _step_delta
	_floor_cos = cos(deg_to_rad(_body.max_floor_angle))
	_sample_gravity()
	if has_gravity and is_instance_valid(orientor):
		orientor.orient_to_gravity(gravity_vector, delta)
	var up := _get_up()
	var heading := _body.global_basis.orthonormalized() * Basis(Vector3.UP, intent.yaw)

	if intent.jump_pressed:
		_jump_buffer_left = _body.jump_buffer_time
	else:
		_jump_buffer_left = maxf(_jump_buffer_left - delta, 0.0)

	if intent.toggle_flight and allow_creative_flight:
		_set_flying(not _flying)
	_update_stance(intent)
	var speed := _update_speed(intent)

	if _flying:
		_simulate_flying(intent, heading, up, speed, delta)
	elif has_gravity:
		_simulate_walking(intent, heading, up, speed, delta)
	else:
		_simulate_floating(intent, heading, delta)
	if is_instance_valid(soft_collision):
		soft_collision.apply_to_character(delta)


# --- State -------------------------------------------------------------------

func capture_state() -> MoveState:
	var state := MoveState.new()
	state.position = _body.global_position
	state.rotation = _body.global_basis.orthonormalized().get_rotation_quaternion()
	state.velocity = _body.velocity
	state.crouching = _body.is_crouching()
	state.flying = _flying
	state.flight_left_ground = _flight_left_ground
	state.grounded = _grounded
	state.coyote_time_left = _coyote_left
	state.jump_buffer_left = _jump_buffer_left
	state.step_assist_ticks = _step_assist_ticks
	state.descent_ticks = _descent_ticks
	return state


## Puts the character into [param state] without raising any events.
func apply_state(state: MoveState) -> void:
	_body.global_transform = Transform3D(Basis(state.rotation), state.position)
	_body.velocity = state.velocity
	_set_crouching(state.crouching, true)
	_flying = state.flying
	_flight_left_ground = state.flight_left_ground
	_grounded = state.grounded
	_coyote_left = state.coyote_time_left
	_jump_buffer_left = state.jump_buffer_left
	_step_assist_ticks = state.step_assist_ticks
	_descent_ticks = state.descent_ticks
	# The engine remembers whether its last move touched the floor, and floor snapping
	# depends on it. Re-establish that for a grounded state instead of trusting
	# whatever the previous tick left behind.
	if _grounded and has_gravity:
		_body.up_direction = _get_up()
		_body.floor_snap_length = _body.step_height
		_body.apply_floor_snap()


## For characters that someone else simulates: place the body without moving it
## through the physics world.
func apply_proxy_state(state: MoveState) -> void:
	apply_state(state)


## Moves the character to [param destination] at once. Use this instead of setting
## the body's transform so networking and prediction are told.
func teleport(destination: Transform3D, new_velocity := Vector3.ZERO) -> void:
	_body.global_transform = destination
	_body.velocity = new_velocity
	_body.reset_physics_interpolation()
	_body.clear_visual_offset()
	_reset_transient_state()
	teleported.emit(destination)


func get_body() -> WalkingCharacter3D:
	return _body


func get_step_delta() -> float:
	return _step_delta


# --- Queries -----------------------------------------------------------------

## True while standing on something, including the brief glide over a stair edge.
func is_grounded() -> bool:
	return _grounded or _step_assist_ticks > 0


func is_crouching() -> bool:
	return _body.is_crouching()


func is_flying() -> bool:
	return _flying


## The speed the character is aiming for with its current stance and speed attribute, such
## as the sneaking or the sprinting speed. It is a top speed, so it is not zero when standing
## still. Zero for characters this machine does not simulate, such as other players.
func get_target_speed() -> float:
	return _target_speed


func is_sprinting() -> bool:
	return _sprinting


func get_move_mode() -> MoveMode:
	if _flying:
		return MoveMode.FLYING
	return MoveMode.WALKING if has_gravity else MoveMode.FLOATING


## Whether the character could stand up right now. False under a low ceiling.
func can_stand() -> bool:
	return _body.can_stand_up()


## Starts or stops creative flight. Only call this where the character is being
## simulated for real; clients get their flight state from the server.
func set_flying(value: bool) -> void:
	_set_flying(value)
	_flush_events()


# --- Walking -----------------------------------------------------------------

func _simulate_walking(
	intent: MoveIntent,
	heading: Basis,
	up: Vector3,
	speed: float,
	delta: float,
) -> void:
	var assisting := _step_assist_ticks > 0
	if assisting and intent.move.length_squared() < 0.01:
		_step_assist_ticks = 0
		assisting = false
	var on_ground := _grounded or assisting
	var was_on_ground := on_ground

	_body.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	_body.up_direction = up
	_body.floor_max_angle = deg_to_rad(_body.max_floor_angle)
	_body.floor_stop_on_slope = true
	_body.floor_constant_speed = true

	var velocity := _body.velocity
	var vertical := up * velocity.dot(up)
	var planar := velocity - vertical
	var wish := _get_planar_wish(heading, intent.move, up) if _body.can_walk() else Vector3.ZERO

	if on_ground:
		planar = planar.lerp(wish * speed, _exponential_weight(_body.ground_acceleration, delta))
	else:
		planar = _accelerate_in_air(planar, wish, speed, delta)

	if on_ground and vertical.dot(up) <= 0.0:
		vertical = Vector3.ZERO
	elif not on_ground:
		vertical += gravity_vector * delta

	var jumping := false
	if _jump_buffer_left > 0.0 and (_grounded or _coyote_left > 0.0):
		vertical = up * _get_jump_speed()
		_jump_buffer_left = 0.0
		_coyote_left = 0.0
		_grounded = false
		_step_assist_ticks = 0
		_descent_ticks = 0
		assisting = false
		jumping = true
		_queue_event(&"jumped")

	var snap := 0.0
	if not jumping:
		if assisting:
			snap = STEP_ASSIST_SNAP
		elif _grounded:
			snap = _body.step_height
	_body.floor_snap_length = snap
	_body.velocity = planar + vertical

	var fall_speed := -vertical.dot(up)
	var start_position := _body.global_position
	if _grounded and not jumping and _body.step_height > 0.0 and planar.length_squared() > 0.01:
		if _try_step_up(planar * delta, up):
			_step_assist_ticks = STEP_ASSIST_TICKS
			_body.floor_snap_length = STEP_ASSIST_SNAP
	_body.move_and_slide()
	# The engine only snaps down when the previous move touched the floor, which a
	# glide over a stair edge has not, so do it by hand.
	if assisting and not _body.is_on_floor():
		_body.apply_floor_snap()

	_grounded = _body.is_on_floor()
	# Stepping off an edge, the engine's own snap can hook the corner just left behind
	# and refuse, so confirm ground below with a ray and drop onto it ourselves.
	if (
		not _grounded
		and was_on_ground
		and not jumping
		and _step_assist_ticks == 0
		and _body.velocity.dot(up) <= 0.01
		and _body.step_height > 0.0
	):
		_grounded = _snap_down_to_ground(up)
	if _grounded:
		_step_assist_ticks = 0
		_descent_ticks = maxi(_descent_ticks - 1, 0)
		_coyote_left = _body.coyote_time
		if not was_on_ground:
			_queue_event(&"landed", [maxf(fall_speed, 0.0)])
		# Only a snap that began on the ground is a stair. After a fall the whole drop is real,
		# and gliding the view down to the floor would blunt the landing.
		if was_on_ground:
			_smooth_snap(start_position, up, planar, delta)
	else:
		_coyote_left = maxf(_coyote_left - delta, 0.0)
		_step_assist_ticks = maxi(_step_assist_ticks - 1, 0)
		_descent_ticks = maxi(_descent_ticks - 1, 0)


## Quake-style steering: push toward the wish direction, but never past the speed
## the player could reach on foot, and keep all existing momentum.
func _accelerate_in_air(
	planar: Vector3,
	wish: Vector3,
	speed: float,
	delta: float,
) -> Vector3:
	if wish.is_zero_approx():
		return planar
	var wish_direction := wish.normalized()
	var wish_speed := speed * wish.length()
	var gain := clampf(wish_speed - planar.dot(wish_direction), 0.0, _body.air_acceleration * delta)
	return planar + wish_direction * gain


## Climbs a step the character is walking into. The body is lifted just enough to
## clear the edge and the ordinary move then carries it over. Returns true when
## it lifted the body.
func _try_step_up(planar_motion: Vector3, up: Vector3) -> bool:
	var start := _body.global_transform
	var feet := start.origin
	var forward := planar_motion.normalized()
	var space := _body.get_world_3d().direct_space_state

	# Is something in the way? Probe from just above the feet, looking a little
	# further ahead than this tick's move. On stairs the body is usually resting on
	# the edge of the step it just climbed while also touching the next riser, and
	# that resting contact would otherwise hide the riser.
	var look := forward * maxf(planar_motion.length(), STEP_LOOKAHEAD)
	if not _body.test_move(start.translated(up * STEP_PROBE_LIFT), look):
		return false

	# What is it? A thin ray at the height of a low step reads the surface exactly,
	# which the rounded body cannot. A steep face is a riser that needs climbing; a
	# walkable slope does not.
	var face_from := feet + up * STEP_FACE_HEIGHT
	var face := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		face_from,
		face_from + forward * STEP_FACE_REACH,
		_body.collision_mask,
		[_body.get_rid()],
	))
	if face.is_empty() or (face["normal"] as Vector3).dot(up) >= _floor_cos:
		return false

	# How high is it? A ray straight down just past the edge finds the top.
	var reach := _body.step_height + 0.1
	var probe_point := (face["position"] as Vector3) + forward * STEP_PROBE_DISTANCE
	var tread_from := probe_point + up * (reach - (probe_point - feet).dot(up))
	var tread := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		tread_from,
		tread_from - up * (reach + 0.2),
		_body.collision_mask,
		[_body.get_rid()],
	))
	if tread.is_empty() or (tread["normal"] as Vector3).dot(up) < _floor_cos:
		return false
	var rise := ((tread["position"] as Vector3) - feet).dot(up)
	if rise < MINIMUM_STEP_RISE or rise > _body.step_height + 0.001:
		return false

	# There has to be room to go up, and the way forward has to be clear up there.
	var lift := up * (rise + STEP_LIFT_MARGIN)
	if _body.test_move(start, lift):
		return false
	if _body.test_move(start.translated(lift), planar_motion):
		return false

	_body.global_position += lift
	_body.add_visual_offset(-lift)
	return true



## Drops the body onto walkable ground up to a step below it. A thin ray straight
## down from the feet decides whether there is any, so the shape of the body
## cannot get snagged on an edge. Returns true when the body ends up on the ground.
func _snap_down_to_ground(up: Vector3) -> bool:
	var feet := _body.global_position
	# Mid-descent the body can be hovering one step above the tread under it, so the
	# reach grows a little for as long as the descent continues.
	var reach := _body.step_height * (2.0 if _descent_ticks > 0 else 1.0)
	var query := PhysicsRayQueryParameters3D.create(
		feet + up * 0.05,
		feet - up * (reach + 0.05),
		_body.collision_mask,
		[_body.get_rid()],
	)
	var hit := _body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var ground_normal: Vector3 = hit["normal"]
	if ground_normal.dot(up) < _floor_cos:
		return false
	var drop := (feet - (hit["position"] as Vector3)).dot(up)
	if drop > reach + 0.001:
		return false
	if drop > 0.001:
		_descent_ticks = DESCENT_TICKS
		# Slide down rather than drop straight: the body is often still perched on the
		# corner it just walked off, and sliding rolls it clear of that corner.
		var remaining := -up * drop
		for attempt in 3:
			var contact := _body.move_and_collide(remaining)
			if contact == null:
				break
			remaining = contact.get_remainder().slide(contact.get_normal())
	return true

## When the engine snaps the body down a stair, show it as a glide.
func _smooth_snap(start_position: Vector3, up: Vector3, planar: Vector3, delta: float) -> void:
	var drop := (start_position - _body.global_position).dot(up)
	# Walking down a slope drops a little every tick; only a stair-sized drop that
	# the velocity does not explain is a snap.
	var expected_drop := -_body.velocity.dot(up) * delta
	var snapped_drop := drop - maxf(expected_drop, 0.0)
	if snapped_drop > SMOOTHED_SNAP_DISTANCE:
		_body.add_visual_offset(up * snapped_drop)


# --- Flying and floating -----------------------------------------------------

func _simulate_flying(
	intent: MoveIntent,
	heading: Basis,
	up: Vector3,
	speed: float,
	delta: float,
) -> void:
	var wish := heading * Vector3(intent.move.x, intent.vertical, intent.move.y)
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	_body.velocity = _body.velocity.lerp(
		wish * speed,
		_exponential_weight(flight_acceleration, delta),
	)
	if not has_gravity:
		_apply_roll(intent, heading, delta)
		up = _body.global_basis.y.normalized()

	# With gravity present the ground still has to be detected so landing ends flight.
	_body.motion_mode = (
		CharacterBody3D.MOTION_MODE_GROUNDED
		if has_gravity
		else CharacterBody3D.MOTION_MODE_FLOATING
	)
	_body.up_direction = up
	_body.floor_snap_length = 0.0
	_body.move_and_slide()

	_grounded = has_gravity and _body.is_on_floor()
	_step_assist_ticks = 0
	if has_gravity:
		if not _flight_left_ground:
			_flight_left_ground = not _grounded
		elif _grounded:
			_set_flying(false)


func _simulate_floating(intent: MoveIntent, heading: Basis, delta: float) -> void:
	var velocity := _body.velocity
	if is_instance_valid(jetpack) and jetpack.is_active():
		var wish := heading * Vector3(intent.move.x, intent.vertical, intent.move.y)
		velocity = jetpack.compute_velocity(
			velocity,
			wish,
			_body.movement_speed.value,
			intent.sprint,
			delta,
		)
	_apply_roll(intent, heading, delta)

	_body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_body.up_direction = _body.global_basis.y.normalized()
	_body.floor_snap_length = 0.0
	_body.velocity = velocity
	_body.move_and_slide()
	_grounded = false
	_step_assist_ticks = 0


## Rolls the body around the direction the character is looking, so the view stays
## put and the horizon tilts. The body itself never turns to face anywhere (the
## camera rig does that, steered by yaw and pitch), so its own forward axis is
## not where the player is looking.
func _apply_roll(intent: MoveIntent, heading: Basis, delta: float) -> void:
	if is_zero_approx(intent.roll):
		return
	var view_direction := (heading * Basis(Vector3.RIGHT, intent.pitch) * Vector3.FORWARD).normalized()
	var angle := intent.roll * deg_to_rad(roll_speed_degrees) * delta
	var current := _body.global_basis
	_body.global_basis = (Basis(view_direction, angle) * current.orthonormalized()).scaled_local(current.get_scale())


# --- Stance, speed, flight ---------------------------------------------------

func _update_stance(intent: MoveIntent) -> void:
	# While thrusting or flying, "crouch" means "down", not "curl up".
	var crouch_means_down := _flying or (
		not has_gravity and is_instance_valid(jetpack) and jetpack.is_active()
	)
	var wants_crouch := intent.crouch and not crouch_means_down
	if wants_crouch and not _body.is_crouching():
		_set_crouching(true)
	elif not wants_crouch and _body.is_crouching() and _body.can_stand_up():
		_set_crouching(false)


## Works out the target speed for this tick and tracks whether we are sprinting.
func _update_speed(intent: MoveIntent) -> float:
	var moving := intent.move.length() > 0.1 or absf(intent.vertical) > 0.1
	var sprinting := intent.sprint and not intent.stroll and not _body.is_crouching() and moving
	if sprinting != _sprinting:
		_sprinting = sprinting
		_queue_event(&"sprint_changed", [_sprinting])

	# Slowing factors stack: strolling while crouched is the slowest creep there is.
	var multiplier := 1.0
	if _body.is_crouching():
		multiplier *= _body.crouch_multiplier.value
	if intent.stroll:
		multiplier *= _body.stroll_multiplier.value
	if sprinting:
		multiplier *= _body.sprint_multiplier.value
	if _flying:
		multiplier *= flight_speed_multiplier
	_target_speed = maxf(_body.movement_speed.value * multiplier, 0.0)
	return _target_speed


## The character owns its stance, and what its hitbox is in each; this only says which one it is in.
func _set_crouching(value: bool, silent := false) -> void:
	if _body.is_crouching() == value:
		return
	_body.stance = WalkingCharacter3D.STANCE.CROUCHING if value else WalkingCharacter3D.STANCE.STANDING
	if not silent:
		_queue_event(&"crouch_changed", [value])


func _set_flying(value: bool) -> void:
	if _flying == value:
		return
	_flying = value
	_flight_left_ground = false
	_queue_event(&"flight_changed", [value])


# --- Helpers -----------------------------------------------------------------

func _get_planar_wish(heading: Basis, move: Vector2, up: Vector3) -> Vector3:
	if move.is_zero_approx():
		return Vector3.ZERO
	var direction := (heading * Vector3(move.x, 0.0, move.y)).slide(up)
	if direction.is_zero_approx():
		return Vector3.ZERO
	return direction.normalized() * minf(move.length(), 1.0)


func _get_jump_speed() -> float:
	var strength := maxf(gravity_vector.length(), MINIMUM_GRAVITY)
	return sqrt(2.0 * strength * _body.jump_height.value)


func _sample_gravity() -> void:
	var direct_state := PhysicsServer3D.body_get_direct_state(_body.get_rid())
	gravity_vector = direct_state.total_gravity if direct_state else _get_default_gravity()
	has_gravity = gravity_vector.length_squared() > MINIMUM_GRAVITY * MINIMUM_GRAVITY


func _get_default_gravity() -> Vector3:
	var direction: Vector3 = ProjectSettings.get_setting(
		"physics/3d/default_gravity_vector",
		Vector3.DOWN,
	)
	var strength := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	return direction.normalized() * strength


func _get_up() -> Vector3:
	if has_gravity:
		return -gravity_vector.normalized()
	var body_up := _body.global_basis.y.normalized()
	return body_up if not body_up.is_zero_approx() else Vector3.UP


func _exponential_weight(speed: float, delta: float) -> float:
	return 1.0 if speed <= 0.0 else 1.0 - exp(-speed * maxf(delta, 0.0))


func _queue_event(event_name: StringName, arguments: Array = []) -> void:
	_events.append([event_name, arguments])


func _flush_events() -> void:
	var events := _events
	_events = []
	for event: Array in events:
		callv("emit_signal", [event[0]] + (event[1] as Array))


## Costs that must be paid once per real tick, never when replaying.
func _apply_live_effects() -> void:
	if not is_instance_valid(stamina):
		return
	if _sprinting and not _flying:
		stamina.decrease(sprint_stamina_per_second * _step_delta)
	if stamina.is_depleted():
		_sprint_exhausted = true
	elif _sprint_exhausted and stamina.get_percentage() >= sprint_resume_fraction:
		_sprint_exhausted = false


## Forgets timers that only make sense for an uninterrupted run of ticks.
func _reset_transient_state() -> void:
	_grounded = false
	_coyote_left = 0.0
	_jump_buffer_left = 0.0
	_step_assist_ticks = 0
	_descent_ticks = 0
	_flight_left_ground = false


func _resolve_components() -> void:
	if not is_instance_valid(orientor):
		orientor = _find_sibling(Orientator) as Orientator
	if not is_instance_valid(jetpack):
		jetpack = _find_sibling(Jetpack) as Jetpack
	if not is_instance_valid(net_sync):
		net_sync = _find_sibling(CharacterNetSync) as CharacterNetSync
	if not is_instance_valid(soft_collision):
		soft_collision = _find_sibling(SoftCollision3D) as SoftCollision3D
	if is_instance_valid(soft_collision):
		soft_collision.set_driven_by_controller()


func _find_sibling(type: Variant) -> Node:
	for child in _body.get_children():
		if is_instance_of(child, type):
			return child
	return null
