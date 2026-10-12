class_name HeadBobProfile
extends Resource
## How one way of moving shakes the head: a walk, a sprint, a limp, a creature's stride.
##
## A profile describes one cycle of a gait. [HeadMotion] moves through the cycle as the
## character covers ground, so a faster character steps faster, and a stationary one
## does not step at all.
##
## The shape of the motion comes from the [member footfalls]: the head dips and nods
## as each foot lands and rises in between, and sways toward the planted foot. Two
## footfalls half a cycle apart make a normal walk; uneven strengths and spacing make
## a limp; four footfalls make a four-legged creature. For a motion that the footfalls
## cannot describe, give a channel its own [Curve] under Custom Curves.

## What a profile produces at one moment of the cycle.
class Pose:
	## Meters: X is right, Y is up.
	var offset := Vector3.ZERO
	## Radians: X is pitch (negative looks down), Y is yaw, Z is roll (positive leans left).
	var rotation := Vector3.ZERO

	func blended_with(other: Pose, weight: float) -> Pose:
		var result := Pose.new()
		result.offset = offset.lerp(other.offset, weight)
		result.rotation = rotation.lerp(other.rotation, weight)
		return result


@export_group("Gait")
## Distance covered by one full cycle, every foot landing once. Longer means slower, bigger
## steps at the same speed.
@export_range(0.1, 20.0, 0.05, "or_greater", "suffix:m") var distance_per_cycle := 3.6
## The speed at which the motion has its full size. Slower is smaller, faster is bigger up
## to [member maximum_intensity]. Zero means the character's normal walking speed.
@export_range(0.0, 30.0, 0.1, "or_greater", "suffix:m/s") var full_bob_speed := 0.0
## Most the motion may grow when moving faster than [member full_bob_speed].
@export_range(0.0, 3.0, 0.05) var maximum_intensity := 1.25
## Slower than this the character is standing, not stepping.
@export_range(0.0, 5.0, 0.05, "suffix:m/s") var minimum_speed := 0.5
## When each foot lands. Leave empty for the usual two: left at 0, right at 0.5.
@export var footfalls: Array[Footfall] = []
## How loud this gait's footsteps are, on top of the speed. A sneak or a slow stroll is
## quiet; 0 is silent.
@export_range(0.0, 2.0, 0.05) var step_loudness := 1.0

@export_group("Motion")
## How far the head dips and rises.
@export_range(0.0, 0.5, 0.001, "suffix:m") var vertical := 0.04
## How far the head sways from side to side.
@export_range(0.0, 0.5, 0.001, "suffix:m") var lateral := 0.025
## Sideways tilt toward the planted foot.
@export_range(0.0, 20.0, 0.05, "suffix:°") var roll_degrees := 0.6
## Nod: the head tips down as a foot lands.
@export_range(0.0, 20.0, 0.05, "suffix:°") var pitch_degrees := 0.4
## Turning the head with the sway. Usually left at zero.
@export_range(0.0, 20.0, 0.05, "suffix:°") var yaw_degrees := 0.0

@export_group("Custom Curves")
## Optional. Each curve covers one full cycle: X from 0 to 1, Y from -1 to 1, and replaces
## the motion the footfalls would make for that channel. For vertical, -1 is the lowest.
@export var vertical_curve: Curve
@export var lateral_curve: Curve
@export var roll_curve: Curve
@export var pitch_curve: Curve
@export var yaw_curve: Curve


static var _default_footfalls: Array[Footfall] = []


## The footfalls in cycle order. Never empty.
func get_footfalls() -> Array[Footfall]:
	var list: Array[Footfall] = []
	for footfall in footfalls:
		if footfall != null:
			list.append(footfall)
	if list.is_empty():
		if _default_footfalls.is_empty():
			_default_footfalls = [Footfall.create(0.0, 1.0, -1.0), Footfall.create(0.5, 1.0, 1.0)]
		return _default_footfalls
	list.sort_custom(func(a: Footfall, b: Footfall) -> bool: return a.phase < b.phase)
	return list


## The head's pose [param phase] of the way through a cycle, at full intensity.
## [param sorted_footfalls] saves looking them up again when sampling every frame.
func sample(phase: float, sorted_footfalls: Array[Footfall] = []) -> Pose:
	var list := sorted_footfalls if not sorted_footfalls.is_empty() else get_footfalls()
	phase = fposmod(phase, 1.0)
	var count := list.size()

	# The step in progress runs from the last footfall passed to the next one.
	var index := count - 1
	for candidate in count:
		if list[candidate].phase <= phase:
			index = candidate
	var current := list[index]
	var upcoming := list[(index + 1) % count]
	var span := upcoming.phase - current.phase
	if span <= 0.0:
		span += 1.0
	var age := phase - current.phase
	if age < 0.0:
		age += 1.0
	var progress := clampf(age / span, 0.0, 1.0)

	# Lowest as each foot lands, highest halfway to the next, deeper for a harder footfall.
	var strength := lerpf(current.strength, upcoming.strength, progress)
	var dip := -cos(TAU * progress) * strength
	# Toward the planted foot, passing through the middle as the next one lands.
	var sway := current.side * sin(PI * progress)

	var pose := Pose.new()
	pose.offset = Vector3(
		_shape(lateral_curve, phase, sway) * lateral,
		_shape(vertical_curve, phase, dip) * vertical,
		0.0,
	)
	pose.rotation = Vector3(
		deg_to_rad(_shape(pitch_curve, phase, dip) * pitch_degrees),
		deg_to_rad(_shape(yaw_curve, phase, sway) * yaw_degrees),
		deg_to_rad(-_shape(roll_curve, phase, sway) * roll_degrees),
	)
	return pose


func _shape(curve: Curve, phase: float, fallback: float) -> float:
	return curve.sample_baked(phase) if curve != null else fallback
