extends Node
## Shared decoded-audio routing. Global transmissions reach every tuned receiver.
signal voice_frames(source: Node3D, frames: PackedVector2Array, channel: int)
signal broadcast_frames(source: Node3D, frames: PackedVector2Array, channel: int)

enum Channel { GLOBAL, ALPHA, BETA, CHARLIE, DELTA }
const SAMPLE_RATE := 24000
const NO_CHANNEL := -1


func valid_channel(channel: int) -> bool:
	return channel >= Channel.GLOBAL and channel <= Channel.DELTA


func matches(transmit: int, receive: int) -> bool:
	return valid_channel(transmit) and valid_channel(receive) and (
		transmit == Channel.GLOBAL or transmit == receive
	)


func publish_voice(source: Node3D, frames: PackedVector2Array, rate: int, channel: int) -> void:
	voice_frames.emit(source, resample(frames, rate), channel)


func resample(frames: PackedVector2Array, rate: int) -> PackedVector2Array:
	return resample_to(frames, rate, SAMPLE_RATE)


func resample_to(frames: PackedVector2Array, source_rate: int, target_rate: int) -> PackedVector2Array:
	if source_rate == target_rate or frames.is_empty():
		return frames
	var output := PackedVector2Array()
	output.resize(maxi(1, roundi(frames.size() * float(target_rate) / source_rate)))
	for i in output.size():
		var position := i * float(source_rate) / target_rate
		var left := mini(int(position), frames.size() - 1)
		output[i] = frames[left].lerp(frames[mini(left + 1, frames.size() - 1)], fmod(position, 1.0))
	return output


func encode_pcm(frames: PackedVector2Array) -> PackedByteArray:
	var pcm := PackedByteArray()
	pcm.resize(frames.size() * 4)
	for i in frames.size():
		pcm.encode_s16(i * 4, roundi(clampf(frames[i].x, -1.0, 1.0) * 32767.0))
		pcm.encode_s16(i * 4 + 2, roundi(clampf(frames[i].y, -1.0, 1.0) * 32767.0))
	return pcm


func decode_pcm(pcm: PackedByteArray) -> PackedVector2Array:
	var frames := PackedVector2Array()
	@warning_ignore("integer_division")
	frames.resize(int(pcm.size() / 4))
	for i in frames.size():
		frames[i] = Vector2(pcm.decode_s16(i * 4), pcm.decode_s16(i * 4 + 2)) / 32768.0
	return frames
