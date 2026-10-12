class_name MoveIntent
extends RefCounted
## What a character wants to do during one physics tick.
##
## Players, AI and network replays all describe movement with this same small
## value, so a CharacterController never has to know who is driving it. Values are
## quantized to what [method encode_to] can carry, which means the copy a client
## simulates is bit-for-bit what the server receives.

const ENCODED_SIZE := 9
const HALF_PI := PI / 2.0

const FLAG_JUMP := 1
const FLAG_SPRINT := 2
const FLAG_STROLL := 4
const FLAG_CROUCH := 8
const FLAG_TOGGLE_FLIGHT := 16

## Planar input. X is right, Y is back, so forward is -Y (matches Input.get_vector).
var move := Vector2.ZERO
## Up/down thrust for flight and jetpacks, from -1 to 1.
var vertical := 0.0
## Roll in zero gravity, from -1 (left) to 1 (right).
var roll := 0.0
## Heading in radians, relative to the body. Movement is steered along this.
var yaw := 0.0
## Looking up (positive) or down, in radians. Together with [member yaw] this is the
## view direction, which zero-gravity roll turns around.
var pitch := 0.0
## True only on the tick the jump button went down.
var jump_pressed := false
var sprint := false
## Slow walk.
var stroll := false
## Held while the character wants to crouch.
var crouch := false
## True only on the tick creative flight should switch on or off.
var toggle_flight := false


## Rounds every value to what can be sent over the network. Call this before
## simulating so both ends agree exactly.
func quantize() -> MoveIntent:
	move = Vector2(_quantize_axis(move.x), _quantize_axis(move.y))
	vertical = _quantize_axis(vertical)
	roll = _quantize_axis(roll)
	yaw = float(_yaw_to_int(yaw)) / 32767.0 * PI
	pitch = float(_pitch_to_int(pitch)) / 32767.0 * HALF_PI
	return self


func duplicate() -> MoveIntent:
	var copy := MoveIntent.new()
	copy.move = move
	copy.vertical = vertical
	copy.roll = roll
	copy.yaw = yaw
	copy.pitch = pitch
	copy.jump_pressed = jump_pressed
	copy.sprint = sprint
	copy.stroll = stroll
	copy.crouch = crouch
	copy.toggle_flight = toggle_flight
	return copy


## Writes [constant ENCODED_SIZE] bytes into [param buffer] at [param offset].
func encode_to(buffer: PackedByteArray, offset: int) -> void:
	buffer.encode_s8(offset, _axis_to_int(move.x))
	buffer.encode_s8(offset + 1, _axis_to_int(move.y))
	buffer.encode_s8(offset + 2, _axis_to_int(vertical))
	buffer.encode_s8(offset + 3, _axis_to_int(roll))
	buffer.encode_s16(offset + 4, _yaw_to_int(yaw))
	buffer.encode_s16(offset + 6, _pitch_to_int(pitch))
	var flags := 0
	if jump_pressed:
		flags |= FLAG_JUMP
	if sprint:
		flags |= FLAG_SPRINT
	if stroll:
		flags |= FLAG_STROLL
	if crouch:
		flags |= FLAG_CROUCH
	if toggle_flight:
		flags |= FLAG_TOGGLE_FLIGHT
	buffer.encode_u8(offset + 8, flags)


static func decode_from(buffer: PackedByteArray, offset: int) -> MoveIntent:
	var intent := MoveIntent.new()
	intent.move = Vector2(
		float(buffer.decode_s8(offset)) / 127.0,
		float(buffer.decode_s8(offset + 1)) / 127.0,
	)
	intent.vertical = float(buffer.decode_s8(offset + 2)) / 127.0
	intent.roll = float(buffer.decode_s8(offset + 3)) / 127.0
	intent.yaw = float(buffer.decode_s16(offset + 4)) / 32767.0 * PI
	intent.pitch = float(buffer.decode_s16(offset + 6)) / 32767.0 * HALF_PI
	var flags := buffer.decode_u8(offset + 8)
	intent.jump_pressed = flags & FLAG_JUMP != 0
	intent.sprint = flags & FLAG_SPRINT != 0
	intent.stroll = flags & FLAG_STROLL != 0
	intent.crouch = flags & FLAG_CROUCH != 0
	intent.toggle_flight = flags & FLAG_TOGGLE_FLIGHT != 0
	return intent


func _quantize_axis(value: float) -> float:
	return float(_axis_to_int(value)) / 127.0


func _axis_to_int(value: float) -> int:
	if not is_finite(value):
		return 0
	return roundi(clampf(value, -1.0, 1.0) * 127.0)


func _yaw_to_int(value: float) -> int:
	if not is_finite(value):
		return 0
	return roundi(wrapf(value, -PI, PI) / PI * 32767.0)


func _pitch_to_int(value: float) -> int:
	if not is_finite(value):
		return 0
	return roundi(clampf(value, -HALF_PI, HALF_PI) / HALF_PI * 32767.0)
