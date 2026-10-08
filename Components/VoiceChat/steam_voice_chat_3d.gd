class_name SteamVoiceChat3D
extends ProximityGlobalAudio3D

## Steam voice source for ProximityGlobalAudio3D.
## The multiplayer authority captures; remote copies play the captured voice.

signal voice_chat_started
signal voice_chat_stopped
signal speaking_changed(peer_id: int, is_speaking: bool)
signal debug_message(message: String)

const CAPTURE_BUFFER_SIZE := 8192
const DECODE_BUFFER_SIZE := 65536
const VOICE_CHANNEL := 1
const CONTROL_CHANNEL := 2
const DEFAULT_PUSH_TO_TALK_KEY := KEY_V
const MAX_PCM_PACKET_BYTES := 4096

enum CaptureBackend {
	## Lowest latency; sends raw mono 16-bit PCM at the engine mix rate.
	DIRECT_PCM,
	## Lower bandwidth, but Steam's voice processing adds capture latency.
	STEAM_COMPRESSED,
}

@export_category("Voice Capture")

## Direct PCM matches the original low-latency player voice script.
@export var capture_backend := CaptureBackend.DIRECT_PCM

## Maximum raw samples per network packet. 480 is 10 ms at 48 kHz and remains
## below a typical network MTU after RPC overhead.
@export_range(120, 960, 1) var pcm_packet_frames := 480

## Silence gate for open-microphone proximity chat. Radio push-to-talk bypasses it.
@export_range(0.0, 0.1, 0.0005) var silence_threshold := 0.001
@export_range(0.0, 0.5, 0.01) var voice_hold_seconds := 0.15

## Requires the local player to hold the configured input action while speaking.
## When disabled, voice chat uses an open microphone whenever the component is active.
@export var push_to_talk := false

## Input Map action used for push-to-talk. If it does not exist, the component
## creates it at runtime and binds the physical V key.
@export var push_to_talk_action := &"voice_chat_push_to_talk"

## Sample rate used to decode and play incoming Steam voice. Higher rates can
## improve clarity but require more processing; 48000 is recommended.
@export_range(11025, 48000, 1) var playback_sample_rate := 48000

## Seconds of decoded voice held to smooth network timing. Increase this if audio
## breaks up; decrease it for lower latency. Larger values delay remote speech.
@export_range(0.05, 1.0, 0.01) var playback_buffer_seconds := 0.12

## Discards stale decoded audio if playback falls this far behind live capture.
## This bounds latency instead of allowing it to grow until the buffer is full.
@export_range(0.02, 0.25, 0.005) var maximum_playback_queue_seconds := 0.06

@export_category("Voice Debug")

## Minimum seconds between repeating input-detected and packet-received messages.
## State changes and errors are still reported immediately.
@export_range(0.1, 5.0, 0.1) var debug_voice_interval_seconds := 0.5

## Set by a WalkieTalkie3D; included with every packet to avoid channel-state races.
var radio_transmitting := false
var radio_channel: int = 1
var is_voice_chat_active := false
var is_speaking := false
var is_muted := false

var _recording := false
var _draining_recording := false
var _capture_effect: AudioEffectCapture
var _capture_player: AudioStreamPlayer
var _capture_bus_name: StringName
var _direct_sample_rate := 48000
var _voice_hold_frames := 0
var _proximity_playback: AudioStreamGeneratorPlayback
var _global_playback: AudioStreamGeneratorPlayback
var _proximity_capacity_frames := 0
var _global_capacity_frames := 0
var _last_input_debug_ms := -1000000
var _last_receive_debug_ms := -1000000


func start_voice_chat() -> void:
	if is_voice_chat_active:
		return
	is_voice_chat_active = true
	start_audio()
	_debug("Voice chat started.")
	voice_chat_started.emit()
	if is_multiplayer_authority() and not push_to_talk:
		start_speaking()


func stop_voice_chat() -> void:
	if not is_voice_chat_active:
		return
	is_voice_chat_active = false
	_stop_recording(true)
	_clear_playback_buffer()
	stop_audio()
	_debug("Voice chat stopped.")
	voice_chat_stopped.emit()


func toggle_voice_chat() -> void:
	if is_voice_chat_active:
		stop_voice_chat()
	else:
		start_voice_chat()


func start_speaking() -> void:
	if (
		not is_voice_chat_active
		or not is_multiplayer_authority()
		or _recording
	):
		return
	if capture_backend == CaptureBackend.DIRECT_PCM:
		_start_direct_capture()
	else:
		if not _steam_is_active():
			return
		Steam.startVoiceRecording()
	if _steam_is_active():
		Steam.setInGameVoiceSpeaking(_local_steam_id(), true)
	_recording = true
	_draining_recording = false
	_debug("Microphone capture started.")
	_set_speaking(true)
	_broadcast_speaking_state(true)


func stop_speaking() -> void:
	_stop_recording(true)


func set_voice_muted(muted: bool) -> void:
	is_muted = muted
	_debug("Incoming voice muted: %s" % is_muted)
	if is_muted:
		_clear_playback_buffer()
	_update_channel_blend()


func set_voice_volume_db(value: float) -> void:
	set_audio_volume_db(value)
	_debug("Incoming voice volume set to %.1f dB." % value)


func set_debug_enabled(enabled: bool) -> void:
	debug_enabled = enabled
	if debug_enabled:
		_debug("Debugging enabled. Voice input detection will be reported.")


func _configure_source_stream() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = float(playback_sample_rate)
	generator.buffer_length = playback_buffer_seconds
	stream = generator


func _after_audio_outputs_created() -> void:
	_global_player.name = "GlobalVoiceOutput"
	_ensure_push_to_talk_action()
	_debug("Debugging enabled. Authority peer: %s" % get_multiplayer_authority())


func _start_audio_when_ready() -> void:
	start_voice_chat()


func _process_audio(_delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if is_voice_chat_active and _steam_is_active():
		var wants_capture := radio_transmitting or not push_to_talk or Input.is_action_pressed(push_to_talk_action)
		if wants_capture:
			start_speaking()
		elif _recording:
			stop_speaking()

	if _recording and capture_backend == CaptureBackend.DIRECT_PCM:
		_capture_and_send_direct_voice()
	elif _recording or _draining_recording:
		_capture_and_send_voice()


func _audio_exit_tree() -> void:
	_stop_recording(false)
	stop_audio()


func _on_audio_playback_started() -> void:
	_proximity_playback = get_stream_playback() as AudioStreamGeneratorPlayback
	_global_playback = _global_player.get_stream_playback() as AudioStreamGeneratorPlayback
	_proximity_capacity_frames = _proximity_playback.get_frames_available()
	_global_capacity_frames = _global_playback.get_frames_available()


func _on_audio_playback_stopped() -> void:
	_proximity_playback = null
	_global_playback = null
	_proximity_capacity_frames = 0
	_global_capacity_frames = 0


func _can_mix_audio() -> bool:
	return super._can_mix_audio() and is_voice_chat_active and not is_muted


func _capture_and_send_voice() -> void:
	var captured: Dictionary = Steam.getVoice(CAPTURE_BUFFER_SIZE)
	var result := int(captured.get("result", Steam.VOICE_RESULT_NO_DATA))
	if result == Steam.VOICE_RESULT_NOT_RECORDING:
		_draining_recording = false
		_debug("Microphone capture finished draining.")
		return
	if result != Steam.VOICE_RESULT_OK:
		if result not in [Steam.VOICE_RESULT_NO_DATA, Steam.VOICE_RESULT_NOT_RECORDING]:
			_debug("Voice capture returned result %s." % result)
		return

	var packet: PackedByteArray = captured.get("buffer", PackedByteArray())
	if packet.is_empty():
		return
	var has_peers := NetworkSession.has_remote_peers()
	_debug_input_detected(packet.size(), has_peers)
	var transmit_channel := radio_channel if radio_transmitting else VoiceChannels.NO_CHANNEL
	_decode_voice(packet, transmit_channel, false)
	if has_peers:
		_receive_voice_packet.rpc(packet, transmit_channel)


func _capture_and_send_direct_voice() -> void:
	if _capture_effect == null:
		return
	var available := _capture_effect.get_frames_available()
	if available <= 0:
		return
	var frames := _capture_effect.get_buffer(available)
	var should_send := radio_transmitting or _voice_is_active(frames)
	if should_send:
		_voice_hold_frames = roundi(_direct_sample_rate * voice_hold_seconds)
	elif _voice_hold_frames > 0:
		_voice_hold_frames = maxi(_voice_hold_frames - frames.size(), 0)
		should_send = true
	if not should_send:
		return

	var transmit_channel := radio_channel if radio_transmitting else VoiceChannels.NO_CHANNEL
	VoiceChannels.publish_voice(self, frames, _direct_sample_rate, transmit_channel)
	if not NetworkSession.has_remote_peers():
		return
	for offset in range(0, frames.size(), pcm_packet_frames):
		var count := mini(pcm_packet_frames, frames.size() - offset)
		var packet := _frames_to_mono_pcm(frames, offset, count)
		_receive_direct_voice_packet.rpc(packet, _direct_sample_rate, transmit_channel)


@rpc("any_peer", "call_remote", "unreliable", VOICE_CHANNEL)
func _receive_direct_voice_packet(
	pcm: PackedByteArray,
	sample_rate: int,
	transmit_channel: int = -1
) -> void:
	if not is_voice_chat_active or is_muted or pcm.is_empty():
		return
	if not _packet_came_from_this_player():
		return
	if pcm.size() > MAX_PCM_PACKET_BYTES or pcm.size() % 2 != 0:
		return
	if sample_rate < 8000 or sample_rate > 96000:
		return
	if transmit_channel != VoiceChannels.NO_CHANNEL and not VoiceChannels.valid_channel(transmit_channel):
		return
	var frames := _mono_pcm_to_frames(pcm)
	VoiceChannels.publish_voice(self, frames, sample_rate, transmit_channel)
	_push_frames_to_playback(frames, sample_rate)


func _start_direct_capture() -> void:
	_direct_sample_rate = int(AudioServer.get_mix_rate())
	_capture_bus_name = StringName("VoiceCapture_%s" % get_instance_id())
	AudioServer.add_bus()
	var bus_index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_index, _capture_bus_name)
	AudioServer.set_bus_mute(bus_index, true)

	_capture_effect = AudioEffectCapture.new()
	_capture_effect.buffer_length = 0.05
	AudioServer.add_bus_effect(bus_index, _capture_effect)

	_capture_player = AudioStreamPlayer.new()
	_capture_player.name = "DirectVoiceCapture"
	_capture_player.stream = AudioStreamMicrophone.new()
	_capture_player.bus = _capture_bus_name
	add_child(_capture_player)
	_capture_player.play()


func _stop_direct_capture() -> void:
	if _capture_player != null:
		_capture_player.stop()
		_capture_player.queue_free()
		_capture_player = null
	var bus_index := AudioServer.get_bus_index(_capture_bus_name)
	if bus_index >= 0:
		AudioServer.remove_bus(bus_index)
	_capture_effect = null
	_capture_bus_name = &""
	_voice_hold_frames = 0


func _voice_is_active(frames: PackedVector2Array) -> bool:
	if frames.is_empty():
		return false
	var square_sum := 0.0
	for frame in frames:
		square_sum += frame.x * frame.x
	return sqrt(square_sum / frames.size()) > silence_threshold


func _frames_to_mono_pcm(
	frames: PackedVector2Array,
	offset: int,
	count: int
) -> PackedByteArray:
	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	for i in count:
		var sample := roundi(clampf(frames[offset + i].x, -1.0, 1.0) * 32767.0)
		pcm.encode_s16(i * 2, sample)
	return pcm


func _mono_pcm_to_frames(pcm: PackedByteArray) -> PackedVector2Array:
	var frames := PackedVector2Array()
	@warning_ignore("integer_division")
	frames.resize(pcm.size() / 2)
	for i in frames.size():
		var sample := float(pcm.decode_s16(i * 2)) / 32768.0
		frames[i] = Vector2(sample, sample)
	return frames


@rpc("any_peer", "call_remote", "unreliable", VOICE_CHANNEL)
func _receive_voice_packet(compressed_voice: PackedByteArray, transmit_channel: int = -1) -> void:
	if not is_voice_chat_active or is_muted or compressed_voice.is_empty():
		return
	if not _packet_came_from_this_player():
		_debug("Rejected a voice packet from the wrong peer.")
		return
	if compressed_voice.size() > DECODE_BUFFER_SIZE:
		return
	if transmit_channel != VoiceChannels.NO_CHANNEL and not VoiceChannels.valid_channel(transmit_channel):
		return
	_debug_received_voice(compressed_voice.size())
	_decode_voice(compressed_voice, transmit_channel, true)


func _decode_voice(compressed_voice: PackedByteArray, transmit_channel: int, play_remote: bool) -> void:

	var decoded: Dictionary = Steam.decompressVoice(
		compressed_voice,
		playback_sample_rate,
		DECODE_BUFFER_SIZE
	)
	if int(decoded.get("result", -1)) != Steam.VOICE_RESULT_OK:
		_debug("Voice packet could not be decoded: result %s." % decoded.get("result", -1))
		return

	var pcm: PackedByteArray = decoded.get("uncompressed", PackedByteArray())
	var byte_count := mini(int(decoded.get("size", 0)), pcm.size())
	var frames := PackedVector2Array()
	@warning_ignore("integer_division")
	frames.resize(int(byte_count / 2))
	for i in frames.size():
		var sample := float(pcm.decode_s16(i * 2)) / 32768.0
		frames[i] = Vector2(sample, sample)
	VoiceChannels.publish_voice(self, frames, playback_sample_rate, transmit_channel)
	if play_remote:
		_push_pcm_to_playback(pcm, byte_count)


@rpc("any_peer", "call_remote", "reliable", CONTROL_CHANNEL)
func _receive_speaking_state(speaking: bool) -> void:
	if _packet_came_from_this_player():
		_set_speaking(speaking)


func _stop_recording(notify_peers: bool) -> void:
	if not _recording:
		return
	if capture_backend == CaptureBackend.DIRECT_PCM:
		_stop_direct_capture()
	else:
		Steam.stopVoiceRecording()
	if _steam_is_active():
		Steam.setInGameVoiceSpeaking(_local_steam_id(), false)
	_recording = false
	_draining_recording = capture_backend == CaptureBackend.STEAM_COMPRESSED
	_debug("Microphone capture stopped.")
	_set_speaking(false)
	if notify_peers:
		_broadcast_speaking_state(false)


func _broadcast_speaking_state(speaking: bool) -> void:
	if NetworkSession.has_remote_peers():
		_receive_speaking_state.rpc(speaking)


func _set_speaking(speaking: bool) -> void:
	if is_speaking == speaking:
		return
	is_speaking = speaking
	speaking_changed.emit(get_multiplayer_authority(), is_speaking)


func _packet_came_from_this_player() -> bool:
	return multiplayer.get_remote_sender_id() == get_multiplayer_authority()


func _steam_is_active() -> bool:
	var network := get_node_or_null("/root/SteamNetwork")
	return network != null and bool(network.get("is_active"))


func _local_steam_id() -> int:
	var network := get_node_or_null("/root/SteamNetwork")
	if network == null:
		return 0
	return int(network.get("steam_id"))


func _push_pcm_to_playback(pcm: PackedByteArray, byte_count: int) -> void:
	if _proximity_playback == null or _global_playback == null or byte_count < 2:
		return
	@warning_ignore("integer_division")
	var sample_count := byte_count / 2
	var frames := PackedVector2Array()
	frames.resize(sample_count)
	for sample_index in sample_count:
		var sample := float(pcm.decode_s16(sample_index * 2)) / 32768.0
		frames[sample_index] = Vector2(sample, sample)
	_push_frames_to_playback(frames, playback_sample_rate)


func _push_frames_to_playback(frames: PackedVector2Array, sample_rate: int) -> void:
	if _proximity_playback == null or _global_playback == null or frames.is_empty():
		return
	frames = VoiceChannels.resample_to(frames, sample_rate, playback_sample_rate)
	if _decoded_playback_queue_seconds() > maximum_playback_queue_seconds:
		_clear_playback_buffer()
	if (
		not _proximity_playback.can_push_buffer(frames.size())
		or not _global_playback.can_push_buffer(frames.size())
	):
		_clear_playback_buffer()
	if _proximity_playback.can_push_buffer(frames.size()):
		_proximity_playback.push_buffer(frames)
	if _global_playback.can_push_buffer(frames.size()):
		_global_playback.push_buffer(frames)


func _decoded_playback_queue_seconds() -> float:
	if _proximity_playback == null or _global_playback == null or playback_sample_rate <= 0:
		return 0.0
	var proximity_queued := maxi(
		_proximity_capacity_frames - _proximity_playback.get_frames_available(),
		0
	)
	var global_queued := maxi(
		_global_capacity_frames - _global_playback.get_frames_available(),
		0
	)
	return float(maxi(proximity_queued, global_queued)) / playback_sample_rate


func _clear_playback_buffer() -> void:
	# Godot rejects clear_buffer() on an active generator. Restart to discard queues.
	if not _audio_active or _global_player == null:
		return
	stop()
	_global_player.stop()
	_on_audio_playback_stopped()
	_configure_source_stream()
	_global_player.stream = stream
	play()
	_global_player.play()
	_on_audio_playback_started()


func _debug_input_detected(packet_size: int, sent_to_peers: bool) -> void:
	if not _debug_interval_elapsed(_last_input_debug_ms):
		return
	_last_input_debug_ms = Time.get_ticks_msec()
	var delivery := "sent to peers" if sent_to_peers else "no connected peers"
	_debug("Voice input detected: %s compressed bytes (%s)." % [packet_size, delivery])


func _debug_received_voice(packet_size: int) -> void:
	if not _debug_interval_elapsed(_last_receive_debug_ms):
		return
	_last_receive_debug_ms = Time.get_ticks_msec()
	_debug("Received voice packet: %s compressed bytes." % packet_size)


func _debug_interval_elapsed(previous_time_ms: int) -> bool:
	var interval_ms := int(debug_voice_interval_seconds * 1000.0)
	return Time.get_ticks_msec() - previous_time_ms >= interval_ms


func _debug(message: String) -> void:
	if not debug_enabled:
		return
	var formatted := "[SteamVoiceChat3D:%s] %s" % [name, message]
	print(formatted)
	debug_message.emit(formatted)


func _ensure_push_to_talk_action() -> void:
	if InputMap.has_action(push_to_talk_action):
		return
	InputMap.add_action(push_to_talk_action)
	var key := InputEventKey.new()
	key.physical_keycode = DEFAULT_PUSH_TO_TALK_KEY
	InputMap.action_add_event(push_to_talk_action, key)


## The camera/listener position is evaluated locally for each talker.
func radio_gain_for_listener() -> float:
	var listener: Node3D = get_viewport().get_audio_listener_3d()
	if listener == null:
		listener = get_viewport().get_camera_3d()
	if listener == null:
		return 1.0
	var start := maxf(proximity_full_distance, 0.0)
	var end := maxf(global_full_distance, start + 0.001)
	return smoothstep(start, end, global_position.distance_to(listener.global_position))


func _update_channel_blend() -> void:
	if not _can_mix_audio() or is_multiplayer_authority():
		_set_channel_gains(0.0, 0.0)
		return
	# Live distant voice is played only by tuned radio receivers.
	_set_channel_gains(1.0 - radio_gain_for_listener(), 0.0)
