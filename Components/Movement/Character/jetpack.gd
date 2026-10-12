class_name Jetpack
extends Node
## Thrust for moving around in zero gravity.
##
## Without one a character just drifts. With one, the movement keys push the
## character around, and (with dampeners on) releasing them brakes to a stop.
## A CharacterController asks it for the new velocity each tick, so it takes part in
## prediction like the rest of movement and holds no state of its own.

## Turn off to drop the jetpack, for example when it is unequipped.
@export var enabled := true
## Acceleration while thrusting, in meters per second squared.
@export_range(0.0, 100.0, 0.1, "or_greater", "suffix:m/s²") var thrust_acceleration := 10.0
## Top speed the thrusters reach, as a multiple of the character's movement speed.
@export_range(0.1, 10.0, 0.1, "or_greater") var max_speed_multiplier := 2.0
## Counter-thrust that stops drift on any axis the player is not pushing.
@export var dampeners_enabled := true
@export_range(0.0, 100.0, 0.1, "or_greater", "suffix:m/s²") var dampener_deceleration := 6.0
## Thrust and top speed multiplier while sprint is held.
@export_range(1.0, 5.0, 0.05) var boost_multiplier := 2.0


func is_active() -> bool:
	return enabled


## Returns [param velocity] after one tick. [param wish] is the world-space thrust
## direction scaled from 0 to 1, and [param reference_speed] is the character's
## movement speed.
func compute_velocity(
	velocity: Vector3,
	wish: Vector3,
	reference_speed: float,
	boost: bool,
	delta: float,
) -> Vector3:
	var boost_factor := boost_multiplier if boost else 1.0
	var power := minf(wish.length(), 1.0)
	var wish_direction := wish.normalized() if power > 0.001 else Vector3.ZERO

	if power > 0.001:
		var top_speed := reference_speed * max_speed_multiplier * boost_factor * power
		var along := velocity.dot(wish_direction)
		var gain := clampf(
			top_speed - along,
			0.0,
			thrust_acceleration * boost_factor * power * delta,
		)
		velocity += wish_direction * gain

	if dampeners_enabled:
		var undriven := velocity - wish_direction * velocity.dot(wish_direction)
		velocity -= undriven.limit_length(dampener_deceleration * delta)
	return velocity
