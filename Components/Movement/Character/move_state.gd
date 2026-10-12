class_name MoveState
extends RefCounted
## Everything about a character that one tick of movement reads and writes.
##
## A server sends this to clients, and a predicting client rewinds to it and
## replays its unacknowledged inputs. Anything that influences the next tick has
## to live here, or a replay would not match what the server simulated.

## Twelve 32-bit floats, then a byte each for flags, step-assist ticks and descent ticks.
const ENCODED_SIZE := 51

const FLAG_CROUCHING := 1
const FLAG_FLYING := 2
const FLAG_FLIGHT_LEFT_GROUND := 4
const FLAG_GROUNDED := 8

var position := Vector3.ZERO
var rotation := Quaternion.IDENTITY
var velocity := Vector3.ZERO
var crouching := false
var flying := false
var flight_left_ground := false
var grounded := false
var coyote_time_left := 0.0
var jump_buffer_left := 0.0
var step_assist_ticks := 0
var descent_ticks := 0


func duplicate() -> MoveState:
	var copy := MoveState.new()
	copy.position = position
	copy.rotation = rotation
	copy.velocity = velocity
	copy.crouching = crouching
	copy.flying = flying
	copy.flight_left_ground = flight_left_ground
	copy.grounded = grounded
	copy.coyote_time_left = coyote_time_left
	copy.jump_buffer_left = jump_buffer_left
	copy.step_assist_ticks = step_assist_ticks
	copy.descent_ticks = descent_ticks
	return copy


## True when [param other] is far enough from this state that the difference is
## a real misprediction and not rounding. Discrete state must match exactly.
func differs_from(
	other: MoveState,
	position_tolerance: float,
	velocity_tolerance: float,
) -> bool:
	return (
		position.distance_to(other.position) > position_tolerance
		or velocity.distance_to(other.velocity) > velocity_tolerance
		or crouching != other.crouching
		or flying != other.flying
	)


## A blend between this state and [param other], for showing other players.
func interpolated(other: MoveState, weight: float) -> MoveState:
	var result := other.duplicate()
	result.position = position.lerp(other.position, weight)
	result.rotation = rotation.slerp(other.rotation, weight)
	result.velocity = velocity.lerp(other.velocity, weight)
	return result


func encode() -> PackedByteArray:
	var buffer := PackedByteArray()
	buffer.resize(ENCODED_SIZE)
	var cursor := 0
	for value in [
		position.x, position.y, position.z,
		rotation.x, rotation.y, rotation.z, rotation.w,
		velocity.x, velocity.y, velocity.z,
		coyote_time_left, jump_buffer_left,
	]:
		buffer.encode_float(cursor, value)
		cursor += 4
	var flags := 0
	if crouching:
		flags |= FLAG_CROUCHING
	if flying:
		flags |= FLAG_FLYING
	if flight_left_ground:
		flags |= FLAG_FLIGHT_LEFT_GROUND
	if grounded:
		flags |= FLAG_GROUNDED
	buffer.encode_u8(cursor, flags)
	buffer.encode_u8(cursor + 1, clampi(step_assist_ticks, 0, 255))
	buffer.encode_u8(cursor + 2, clampi(descent_ticks, 0, 255))
	return buffer


## Returns null when [param buffer] is malformed or carries non-finite numbers.
static func decode(buffer: PackedByteArray) -> MoveState:
	if buffer.size() != ENCODED_SIZE:
		return null
	var floats := PackedFloat32Array()
	for index in 12:
		var value := buffer.decode_float(index * 4)
		if not is_finite(value):
			return null
		floats.append(value)
	var state := MoveState.new()
	state.position = Vector3(floats[0], floats[1], floats[2])
	state.rotation = Quaternion(floats[3], floats[4], floats[5], floats[6])
	if state.rotation.length_squared() < 0.0001:
		return null
	state.rotation = state.rotation.normalized()
	state.velocity = Vector3(floats[7], floats[8], floats[9])
	state.coyote_time_left = floats[10]
	state.jump_buffer_left = floats[11]
	var flags := buffer.decode_u8(48)
	state.crouching = flags & FLAG_CROUCHING != 0
	state.flying = flags & FLAG_FLYING != 0
	state.flight_left_ground = flags & FLAG_FLIGHT_LEFT_GROUND != 0
	state.grounded = flags & FLAG_GROUNDED != 0
	state.step_assist_ticks = buffer.decode_u8(49)
	state.descent_ticks = buffer.decode_u8(50)
	return state
