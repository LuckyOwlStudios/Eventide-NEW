@icon("uid://dk1xubitf0jf0")
class_name HeadMotion
extends Node
## Moves a character's head, usually the camera, with the way the character moves.
##
## Three things happen to the [member target]:
## [br][b]Tilt[/b]: it leans the way the character is moving, a little toward the side when
## strafing and a very little forward or back when moving along. The faster the character
## goes, the more it leans, up to a maximum.
## [br][b]Bobbing[/b]: it dips and sways with each footstep. How, depends on a
## [HeadBobProfile]; the node picks a walk, sprint, stroll or crouch profile by itself, and
## anything else (an injured leg, a creature's stride) can take over with
## [method push_profile_override].
## [br][b]Jumping and landing[/b]: it tips down while rising and up while falling, by how fast
## the character is going, and dips when it lands, harder the faster it hit
## the ground.
##
## Every footstep is announced with [signal footstep] at the moment the head hits the bottom
## of its dip, so a [FootstepPlayer] listening to it is always in sync with the bobbing.
##
## Nothing here touches the character's real position or the network. It only reads the
## character's movement, so it works the same for the local player, other players and
## AI creatures.

## A foot landed. [param foot_index] is its place in the profile's footfalls and
## [param strength] is how hard, already scaled by how fast the character is going.
signal footstep(foot_index: int, strength: float, profile: HeadBobProfile)
signal profile_changed(profile: HeadBobProfile)
## The character touched ground after a fall hard enough to feel. [param impact_speed] is
## how fast it hit, and [param strength] is the same on a scale from 0 to 1.
signal landed(impact_speed: float, strength: float)

## A touchdown after less time in the air than this is not a landing step.
const LANDING_STEP_MINIMUM_AIR_TIME := 0.1

enum Gait {
	WALK,
	SPRINT,
	STROLL,
}

@export_group("Components")
## The node that gets moved. For a player this is the camera.
@export var target: Node3D
## Found next to this node when left empty.
@export var controller: CharacterController
## Whose horizontal facing defines left, right and forward for the tilt. The target's
## parent when left empty, which for a camera is the pitch pivot.
@export var view_reference: Node3D

@export_group("Tilt")
@export var tilt_enabled := true
## Scales all tilt. Handy for an accessibility setting; 0 turns it off.
@export_range(0.0, 2.0, 0.05) var tilt_strength := 1.0
## Most the target rolls toward the side the character moves.
@export_range(0.0, 15.0, 0.1, "suffix:°") var max_roll_degrees := 3.0
## Most the target tips down when moving forward.
@export_range(0.0, 5.0, 0.05, "suffix:°") var max_forward_pitch_degrees := 0.8
## Most the target tips up when moving back. A negative value tips it down instead.
@export_range(-5.0, 5.0, 0.05, "suffix:°") var max_backward_pitch_degrees := 0.6
## The speed that gives the maximum tilt. Zero means a sprint, worked out from the
## character's current movement speed.
@export_range(0.0, 30.0, 0.1, "or_greater", "suffix:m/s") var full_tilt_speed := 0.0
## How quickly the tilt follows the movement. Higher is snappier.
@export_range(0.5, 40.0, 0.5) var tilt_response := 10.0
## How much tilt is kept while in the air.
@export_range(0.0, 1.0, 0.05) var airborne_tilt := 0.5

@export_group("Bobbing")
@export var bob_enabled := true
## Scales all bobbing. Handy for an accessibility setting; 0 turns it off.
@export_range(0.0, 2.0, 0.05) var bob_strength := 1.0
@export var walk_profile: HeadBobProfile
@export var sprint_profile: HeadBobProfile
@export var stroll_profile: HeadBobProfile
@export var crouch_profile: HeadBobProfile
## How long switching from one profile to another takes.
@export_range(0.0, 1.0, 0.01, "suffix:s") var profile_blend_time := 0.2
## How quickly the bob fades away after stopping, and builds up when starting.
@export_range(0.5, 60.0, 0.5) var bob_settle_speed := 10.0

@export_group("Jumping and Falling")
@export var air_tilt_enabled := true
## Most the view tips down while rising, reached at [member full_rise_speed].
@export_range(0.0, 10.0, 0.1, "suffix:°") var rise_pitch_degrees := 1.5
## Most the view tips up while falling, reached at [member full_fall_speed].
@export_range(0.0, 10.0, 0.1, "suffix:°") var fall_pitch_degrees := 2.5
## The rising speed that gives the full downward tilt. Zero means the speed of a jump,
## worked out from the character's jump height and gravity.
@export_range(0.0, 30.0, 0.1, "or_greater", "suffix:m/s") var full_rise_speed := 0.0
## The falling speed that gives the full upward tilt.
@export_range(1.0, 60.0, 0.5, "or_greater", "suffix:m/s") var full_fall_speed := 14.0
## How quickly the view follows the rising and falling. Higher is snappier.
@export_range(0.5, 40.0, 0.5) var air_tilt_response := 8.0

@export_group("Landing")
@export var impact_enabled := true
## Scales every landing. Handy for an accessibility setting; 0 turns it off.
@export_range(0.0, 2.0, 0.05) var impact_strength := 1.0
## How far the view tips down at the bottom of a full-strength landing.
@export_range(0.0, 30.0, 0.5, "suffix:°") var impact_pitch_degrees := 8.0
## How far the view drops at the bottom of a full-strength landing.
@export_range(0.0, 0.5, 0.005, "suffix:m") var impact_drop := 0.12
## Landings slower than this do nothing.
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var minimum_impact_speed := 3.5
## The landing speed that gives a full-strength impact.
@export_range(1.0, 60.0, 0.5, "suffix:m/s") var full_impact_speed := 14.0
## Shapes how the strength grows with speed. Below 1, small landings are felt more.
@export_range(0.2, 2.0, 0.05) var impact_curve := 0.7
## How long the view takes to drop to the bottom of an impact.
@export_range(0.02, 0.5, 0.005, "suffix:s") var impact_down_time := 0.07
## How long it then takes to ease back up. It comes back once, without bouncing.
@export_range(0.05, 1.5, 0.01, "suffix:s") var impact_recover_time := 0.4

@export_group("Gait Detection")
## Moving this much faster than the walking speed counts as sprinting...
@export_range(1.0, 3.0, 0.01) var sprint_enter_ratio := 1.25
## ...until it drops under this.
@export_range(1.0, 3.0, 0.01) var sprint_exit_ratio := 1.1
## Moving slower than this share of the walking speed counts as strolling...
@export_range(0.1, 1.0, 0.01) var stroll_enter_ratio := 0.65
## ...until it rises over this.
@export_range(0.1, 1.0, 0.01) var stroll_exit_ratio := 0.8
## A new gait must hold this long before it is adopted, so speeding up or slowing down
## does not flicker through the others.
@export_range(0.0, 0.5, 0.01, "suffix:s") var gait_change_delay := 0.1

var _body: CharacterBody3D
var _rest := Transform3D.IDENTITY
var _pose := Transform3D.IDENTITY
var _tilt := Vector2.ZERO
var _amplitude := 0.0
var _phase := 0.0
var _idle_time := 0.0
var _profile: HeadBobProfile
var _previous_profile: HeadBobProfile
var _previous_phase := 0.0
var _blend := 1.0
var _gait := Gait.WALK
var _pending_gait := Gait.WALK
var _pending_time := 0.0
var _overrides: Array[Dictionary] = []
var _air_pitch := 0.0
var _prev_vertical_speed := 0.0
var _was_grounded := true
var _air_time := 0.0
## Strength of the step to play for a touchdown, or zero when there is none to play.
var _pending_landing_step := 0.0
## The landing dip, in units of "full-strength impact": positive is down.
var _impact := 0.0
var _impact_from := 0.0
var _impact_peak := 0.0
var _impact_time := 1000.0


func _ready() -> void:
	if not is_instance_valid(controller):
		controller = _find_controller()
	if not is_instance_valid(controller):
		push_error("HeadMotion needs a CharacterController next to it.")
		set_process(false)
		return
	if not is_instance_valid(target):
		push_error("HeadMotion needs a target to move.")
		set_process(false)
		return
	_rest = target.transform


func _process(delta: float) -> void:
	if not is_instance_valid(controller) or not is_instance_valid(target):
		return
	_body = controller.get_body()
	if _body == null:
		return
	var up := _body.global_basis.y.normalized()
	var velocity := _body.velocity
	var planar := velocity - up * velocity.dot(up)

	var vertical_speed := velocity.dot(up)
	_detect_landing(delta)

	var rotation := Vector3.ZERO
	var offset := Vector3.ZERO
	if tilt_enabled:
		rotation += _update_tilt(planar, up, delta)
	else:
		_tilt = Vector2.ZERO
	if air_tilt_enabled:
		rotation.x += deg_to_rad(_update_air_pitch(vertical_speed, delta)) * tilt_strength
	else:
		_air_pitch = 0.0
	if impact_enabled:
		_step_impact(delta)
		# Down is positive in the dip, but a negative pitch looks down.
		rotation.x -= deg_to_rad(_impact * impact_pitch_degrees) * impact_strength
		offset.y -= _impact * impact_drop * impact_strength
	else:
		_impact = 0.0
		_impact_time = 1000.0
	if bob_enabled:
		var pose := _update_bob(planar.length(), delta)
		if pose != null:
			offset += pose.offset * bob_strength
			rotation += pose.rotation * bob_strength
	_pose = Transform3D(Basis.from_euler(rotation), offset)
	target.transform = _rest * _pose
	_prev_vertical_speed = vertical_speed
	_was_grounded = controller.is_grounded()


# --- Public ------------------------------------------------------------------

## Takes over the bobbing with [param profile] until [method remove_profile_override] is called
## with the same [param source]. The highest [param priority] wins; among equals the
## newest does. Use it for things like an injured leg:
## [codeblock]
## head_motion.push_profile_override(&"broken_leg", limp_profile, 10)
## [/codeblock]
func push_profile_override(source: StringName, profile: HeadBobProfile, priority := 0) -> void:
	remove_profile_override(source)
	_overrides.append({"source": source, "profile": profile, "priority": priority})


func remove_profile_override(source: StringName) -> void:
	for index in range(_overrides.size() - 1, -1, -1):
		if _overrides[index]["source"] == source:
			_overrides.remove_at(index)


## The profile currently shaping the bob, or null when there is none.
func get_active_profile() -> HeadBobProfile:
	return _profile


## How far through its cycle the current gait is, from 0 to 1.
func get_phase() -> float:
	return _phase


## How far everything above has moved the target from its place at rest, as of the last frame: tilt,
## bobbing, landing dips and all. The target's transform is its rest transform times this. Things that
## hang from the target and want to move differently, such as a held item (see [ItemMotion]), read it.
func get_pose() -> Transform3D:
	return _pose


## The tilt right now: roll in X (positive leans left) and pitch in Y (negative looks
## down), in degrees.
func get_tilt_degrees() -> Vector2:
	return _tilt


## How strongly the bob is running right now, 0 at rest and 1 at a full-speed walk.
func get_bob_intensity() -> float:
	return _amplitude


## Puts the target back where it started and forgets the current step.
func reset() -> void:
	_tilt = Vector2.ZERO
	_air_pitch = 0.0
	_impact = 0.0
	_impact_time = 1000.0
	_amplitude = 0.0
	_phase = 0.0
	_previous_profile = null
	_blend = 1.0
	_pose = Transform3D.IDENTITY
	if is_instance_valid(target):
		target.transform = _rest


## Picks the profile for the way the character is moving right now. Override this in a
## subclass for characters that choose their gait differently.
func _choose_profile(speed: float, walking_speed: float, delta: float) -> HeadBobProfile:
	var forced := _best_override()
	if forced != null:
		return forced
	if controller.is_crouching() and crouch_profile != null:
		return crouch_profile
	_update_gait(speed / maxf(walking_speed, 0.01), delta)
	match _gait:
		Gait.SPRINT:
			return sprint_profile if sprint_profile != null else walk_profile
		Gait.STROLL:
			return stroll_profile if stroll_profile != null else walk_profile
	return walk_profile


# --- Tilt --------------------------------------------------------------------

func _update_tilt(planar: Vector3, up: Vector3, delta: float) -> Vector3:
	var scale := _tilt_scale()
	var right := _get_view_right(up)
	var forward := up.cross(right)
	var full_speed := maxf(full_tilt_speed if full_tilt_speed > 0.0 else _sprint_speed(), 0.01)
	var sideways := clampf(planar.dot(right) / full_speed, -1.0, 1.0)
	var ahead := clampf(planar.dot(forward) / full_speed, -1.0, 1.0)

	# Roll leans toward the side we move: positive roll leans left, so moving left rolls left.
	var wanted_roll := -sideways * max_roll_degrees * scale
	# Moving forward tips the view down (negative pitch); moving back tips it up.
	var wanted_pitch := -ahead * (max_forward_pitch_degrees if ahead > 0.0 else max_backward_pitch_degrees) * scale
	_tilt = _tilt.lerp(Vector2(wanted_roll, wanted_pitch), _exponential_weight(tilt_response, delta))
	return Vector3(deg_to_rad(_tilt.y), 0.0, deg_to_rad(_tilt.x)) * tilt_strength


func _tilt_scale() -> float:
	if controller.is_flying() or not controller.is_movement_permitted():
		return 0.0
	if controller.is_grounded():
		return 1.0
	# Drifting through zero gravity has no direction to lean into.
	return airborne_tilt if controller.has_gravity else 0.0


## The view's right-hand direction along the ground, whichever way the head is pitched.
func _get_view_right(up: Vector3) -> Vector3:
	var reference := view_reference if is_instance_valid(view_reference) else target.get_parent_node_3d()
	var reference_basis := reference.global_basis if reference != null else _body.global_basis
	var right := reference_basis.x - up * reference_basis.x.dot(up)
	if right.length_squared() < 0.0001:
		right = _body.global_basis.x - up * _body.global_basis.x.dot(up)
	return right.normalized()


# --- Jumping and landing -----------------------------------------------------

## Tips the view down while rising and up while falling, by how fast. Returns degrees,
## where negative looks down.
func _update_air_pitch(vertical_speed: float, delta: float) -> float:
	var wanted := 0.0
	# Only a character that is actually falling under gravity has this to feel.
	var airborne := (
		not controller.is_grounded()
		and not controller.is_flying()
		and controller.has_gravity
		and controller.is_movement_permitted()
	)
	if airborne:
		if vertical_speed > 0.0:
			var rise_speed := full_rise_speed if full_rise_speed > 0.0 else _jump_speed()
			wanted = -minf(vertical_speed / maxf(rise_speed, 0.01), 1.0) * rise_pitch_degrees
		else:
			wanted = minf(-vertical_speed / maxf(full_fall_speed, 0.01), 1.0) * fall_pitch_degrees
	_air_pitch = lerpf(_air_pitch, wanted, _exponential_weight(air_tilt_response, delta))
	return _air_pitch


## Notices touching down. It is a footstep, and it knocks the view by how fast the character
## hit. This looks at the movement itself rather than at a signal, so it works for other
## players and AI too.
func _detect_landing(delta: float) -> void:
	var grounded := controller.is_grounded()
	var touched_down := grounded and not _was_grounded
	# By the time ground is reported the body has stopped, so use the last speed it fell at.
	var impact_speed := -_prev_vertical_speed
	if touched_down and not controller.is_flying() and controller.is_movement_permitted():
		# Any real time in the air ends with a step, heavier the harder the fall.
		if _air_time >= LANDING_STEP_MINIMUM_AIR_TIME:
			var hardness := clampf(impact_speed / maxf(full_impact_speed, 0.01), 0.0, 1.0)
			_pending_landing_step = 1.0 + hardness * 0.8
		if impact_speed >= minimum_impact_speed:
			var span := maxf(full_impact_speed - minimum_impact_speed, 0.01)
			var linear := clampf((impact_speed - minimum_impact_speed) / span, 0.0, 1.0)
			var strength := pow(linear, impact_curve)
			# Landings below the minimum are not felt at all, but anything above it is a little.
			strength = maxf(strength, 0.08)
			_kick_impact(strength)
			landed.emit(impact_speed, strength)
	_air_time = 0.0 if grounded else _air_time + delta


## Starts a dip that reaches [param peak] (1 is a full-strength impact). A landing during
## another one carries on from wherever the view is.
func _kick_impact(peak: float) -> void:
	_impact_from = _impact
	_impact_peak = maxf(peak, _impact)
	_impact_time = 0.0


## Moves the dip on by [param delta]: down quickly, then eased back up. It never overshoots.
func _step_impact(delta: float) -> void:
	var total := impact_down_time + impact_recover_time
	if _impact_time >= total:
		_impact = 0.0
		return
	_impact_time += delta
	if _impact_time < impact_down_time:
		var falling := _impact_time / maxf(impact_down_time, 0.001)
		_impact = lerpf(_impact_from, _impact_peak, sin(falling * PI / 2.0))
	else:
		var rising := clampf((_impact_time - impact_down_time) / maxf(impact_recover_time, 0.001), 0.0, 1.0)
		_impact = _impact_peak * 0.5 * (1.0 + cos(PI * rising))


func _jump_speed() -> float:
	var gravity := controller.gravity_vector.length()
	if gravity < 0.1:
		return 6.0
	return sqrt(2.0 * gravity * controller.get_body().jump_height.value)


# --- Bobbing -----------------------------------------------------------------

func _update_bob(speed: float, delta: float) -> HeadBobProfile.Pose:
	var walking_speed := _walking_speed()
	var wanted := _choose_profile(speed, walking_speed, delta)
	if wanted != _profile:
		_switch_profile(wanted)
	if _profile == null:
		_amplitude = 0.0
		return null

	# Touching down is a step, and the cycle carries on from it: the next step is a full
	# stride away, not a second one right behind it.
	if _pending_landing_step > 0.0:
		var footfalls := _profile.get_footfalls()
		_phase = footfalls[0].phase
		_idle_time = 0.0
		footstep.emit(0, footfalls[0].strength * _pending_landing_step, _profile)
		_pending_landing_step = 0.0

	var stepping := (
		controller.is_grounded()
		and not controller.is_flying()
		and controller.is_movement_permitted()
		and speed >= _profile.minimum_speed
	)
	var full_speed := _profile.full_bob_speed if _profile.full_bob_speed > 0.0 else walking_speed
	var wanted_amplitude := 0.0
	if stepping:
		wanted_amplitude = clampf(speed / maxf(full_speed, 0.01), 0.0, _profile.maximum_intensity)
		# Setting off after standing still starts the cycle afresh, with the first step
		# straight away so that starting to walk is heard at once.
		if _idle_time > 0.3:
			var first := _profile.get_footfalls()[0]
			_phase = first.phase
			# Heard at once, so judge it by the speed being set off at, not the first few slow frames.
			var start_intensity := clampf(maxf(speed, controller.get_target_speed()) / maxf(full_speed, 0.01), 0.0, _profile.maximum_intensity)
			_amplitude = maxf(_amplitude, start_intensity * 0.6)
			footstep.emit(0, _step_strength(first, start_intensity), _profile)
		_idle_time = 0.0
		_advance(speed * delta / maxf(_profile.distance_per_cycle, 0.01), wanted_amplitude)
	else:
		_idle_time += delta
	_amplitude = lerpf(_amplitude, wanted_amplitude, _exponential_weight(bob_settle_speed, delta))

	var footfalls2 := _profile.get_footfalls()
	var pose := _profile.sample(_phase, footfalls2)
	pose = _apply_intensity(pose, _amplitude)
	if _previous_profile != null:
		_previous_phase = fposmod(_previous_phase + speed * delta / maxf(_previous_profile.distance_per_cycle, 0.01), 1.0)
		_blend = minf(_blend + delta / maxf(profile_blend_time, 0.001), 1.0)
		var previous := _apply_intensity(_previous_profile.sample(_previous_phase), _amplitude)
		pose = previous.blended_with(pose, _blend)
		if _blend >= 1.0:
			_previous_profile = null
	return pose


## Moves through the cycle by [param cycles] and announces every foot that lands on the way.
func _advance(cycles: float, intensity: float) -> void:
	var footfalls := _profile.get_footfalls()
	var start := _phase
	var end := _phase + cycles
	for cycle in range(0, int(floor(end)) + 1):
		for index in footfalls.size():
			var landing := float(cycle) + footfalls[index].phase
			if landing > start and landing <= end:
				var strength := _step_strength(footfalls[index], intensity)
				footstep.emit(index, strength, _profile)
	_phase = fposmod(end, 1.0)


func _switch_profile(next: HeadBobProfile) -> void:
	if _profile != null and next != null:
		# Carry on from the same point of the cycle, easing from the old motion to the new.
		_previous_profile = _profile
		_previous_phase = _phase
		_blend = 0.0
	_profile = next
	profile_changed.emit(next)


func _apply_intensity(pose: HeadBobProfile.Pose, intensity: float) -> HeadBobProfile.Pose:
	pose.offset *= intensity
	pose.rotation *= intensity
	return pose


func _update_gait(ratio: float, delta: float) -> void:
	# Only a character that is actually moving changes gait.
	if _profile != null and _amplitude < 0.05 and ratio < 0.2:
		_pending_time = 0.0
		return
	var wanted := _gait
	match _gait:
		Gait.WALK:
			if ratio >= sprint_enter_ratio:
				wanted = Gait.SPRINT
			elif ratio <= stroll_enter_ratio and ratio > 0.05:
				wanted = Gait.STROLL
		Gait.SPRINT:
			if ratio < sprint_exit_ratio:
				wanted = Gait.WALK
		Gait.STROLL:
			if ratio > stroll_exit_ratio:
				wanted = Gait.WALK
	if wanted == _gait:
		_pending_time = 0.0
		return
	if wanted != _pending_gait:
		_pending_gait = wanted
		_pending_time = 0.0
	_pending_time += delta
	if _pending_time >= gait_change_delay:
		_gait = wanted
		_pending_time = 0.0


func _best_override() -> HeadBobProfile:
	var best: HeadBobProfile
	var best_priority := -INF
	for entry in _overrides:
		if float(entry["priority"]) >= best_priority:
			best_priority = float(entry["priority"])
			best = entry["profile"]
	return best


# --- Helpers -----------------------------------------------------------------

func _walking_speed() -> float:
	return controller.get_body().movement_speed.value


func _sprint_speed() -> float:
	return _walking_speed() * controller.get_body().sprint_multiplier.value


func _exponential_weight(speed: float, delta: float) -> float:
	return 1.0 - exp(-speed * maxf(delta, 0.0))


func _find_controller() -> CharacterController:
	var parent := get_parent()
	if parent == null:
		return null
	for child in parent.get_children():
		if child is CharacterController:
			return child as CharacterController
	return null


## How hard a foot lands: harder with speed, and scaled by how loud the gait is. A sneak or
## a slow stroll is quiet, and both together are close to silent.
func _step_strength(footfall: Footfall, intensity: float) -> float:
	return footfall.strength * _profile.step_loudness * pow(clampf(intensity, 0.0, 1.5), 1.5)
