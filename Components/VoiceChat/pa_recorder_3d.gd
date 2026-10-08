class_name PARecorder3D
extends Node3D
## Records nearby decoded voices on this node's authority. Replays saved PCM on peers.
signal recording_started
signal recording_stopped(recording: AudioStreamWAV)
signal recording_saved(path: String)
signal recording_save_failed(error: int)
signal playback_finished

enum Destination { LOCAL = -1, GLOBAL, ALPHA, BETA, CHARLIE, DELTA }
@export_range(0.1, 100.0) var recording_radius := 12.0
@export_range(1.0, 120.0) var max_recording_seconds := 30.0
@export var capture_world_sounds := true
@export var destination: Destination = Destination.LOCAL
@export var local_speakers: Array[AudioStreamPlayer3D] = []
@export var save_path := "user://pa_recording.wav"

var is_recording := false
var recording: AudioStreamWAV
var _world_playbacks: Dictionary = {}
var _world_budget := 0.0
var _mix := PackedVector2Array()
var _started_ms := 0
var _source_cursors: Dictionary = {}
var _play_frames := PackedVector2Array()
var _play_cursor := 0
var _play_budget := 0.0
var _play_destination := -1
var _local_outputs: Dictionary = {}
var _last_packet_ms := 0
const CHUNK_FRAMES := 480


func _ready() -> void:
	VoiceChannels.voice_frames.connect(_on_voice)


func start_recording() -> void:
	if not is_multiplayer_authority() or is_recording:
		return
	stop_playback()
	_mix.resize(0)
	_mix.resize(roundi(clampf(max_recording_seconds, 1.0, 120.0) * VoiceChannels.SAMPLE_RATE))
	_source_cursors.clear()
	_world_playbacks.clear()
	_world_budget = 0.0
	_started_ms = Time.get_ticks_msec()
	is_recording = true
	recording_started.emit()


func stop_recording() -> AudioStreamWAV:
	if not is_recording:
		return recording
	is_recording = false
	_world_playbacks.clear()
	var length := mini(_mix.size(), maxi(1, _elapsed_frames()))
	_mix.resize(length)
	recording = AudioStreamWAV.new()
	recording.format = AudioStreamWAV.FORMAT_16_BITS
	recording.mix_rate = VoiceChannels.SAMPLE_RATE
	recording.stereo = true
	recording.data = VoiceChannels.encode_pcm(_mix)
	_mix = PackedVector2Array()
	if not save_path.is_empty():
		save_recording(save_path)
	recording_stopped.emit(recording)
	return recording


func save_recording(path: String) -> Error:
	if recording == null:
		return ERR_UNCONFIGURED
	var result := recording.save_to_wav(path)
	if result == OK:
		recording_saved.emit(path)
	else:
		recording_save_failed.emit(result)
		push_warning("PA recording could not be saved to %s (error %s)." % [path, result])
	return result


func _elapsed_frames() -> int:
	return roundi((Time.get_ticks_msec() - _started_ms) * VoiceChannels.SAMPLE_RATE / 1000.0)


func _on_voice(source: Node3D, frames: PackedVector2Array, _channel: int) -> void:
	record_audio(source, frames, VoiceChannels.SAMPLE_RATE)


## Other procedural world sounds can submit PCM here; the recorder never captures
## the listener's Master bus (which would record radios and cause feedback).
func record_audio(source: Node3D, frames: PackedVector2Array, sample_rate: int) -> void:
	if not is_recording or not is_instance_valid(source):
		return
	var distance := global_position.distance_to(source.global_position)
	if distance >= recording_radius:
		return
	var samples := VoiceChannels.resample(frames, sample_rate)
	var key := source.get_instance_id()
	var start := maxi(maxi(0, _elapsed_frames() - samples.size()), int(_source_cursors.get(key, 0)))
	var count := mini(samples.size(), _mix.size() - start)
	var gain := 1.0 - distance / maxf(recording_radius, 0.001)
	for i in maxi(count, 0):
		_mix[start + i] += samples[i] * gain
	_source_cursors[key] = start + maxi(count, 0)


func play_recording(target: int = -2) -> void:
	if not is_multiplayer_authority() or recording == null or is_recording:
		return
	if target == -2:
		target = destination
	if target != Destination.LOCAL and not VoiceChannels.valid_channel(target):
		return
	stop_playback()
	_play_destination = target
	_play_frames = VoiceChannels.decode_pcm(recording.data)
	_play_cursor = 0
	_play_budget = 0.0


func stop_playback() -> void:
	_play_frames = PackedVector2Array()
	_play_cursor = 0
	_stop_outputs()
	if is_multiplayer_authority() and NetworkSession.has_remote_peers():
		_receive_stop.rpc()


@rpc("authority", "call_remote", "reliable", 2)
func _receive_stop() -> void:
	_stop_outputs()


func _stop_outputs() -> void:
	for output in _local_outputs.values():
		if is_instance_valid(output):
			output.stop()
			output.queue_free()
	_local_outputs.clear()
	# Remove queued PA frames from tuned receivers, too.
	for receiver in get_tree().get_nodes_in_group("channel_speakers"):
		receiver.clear_source(self)


func _process(delta: float) -> void:
	if is_recording and capture_world_sounds:
		_capture_world_audio(delta)
	if is_recording and _elapsed_frames() >= _mix.size():
		stop_recording()
	if not _play_frames.is_empty():
		_play_budget = minf(_play_budget + delta * VoiceChannels.SAMPLE_RATE, CHUNK_FRAMES * 5.0)
		while _play_budget >= CHUNK_FRAMES and _play_cursor < _play_frames.size():
			var end := mini(_play_cursor + CHUNK_FRAMES, _play_frames.size())
			var pcm := VoiceChannels.encode_pcm(_play_frames.slice(_play_cursor, end))
			_deliver(pcm, _play_destination)
			if NetworkSession.has_remote_peers():
				_receive_audio.rpc(pcm, _play_destination)
			_play_budget -= end - _play_cursor
			_play_cursor = end
		if _play_cursor >= _play_frames.size():
			_play_frames = PackedVector2Array()
			playback_finished.emit()
	elif not _local_outputs.is_empty() and Time.get_ticks_msec() - _last_packet_ms > 1000:
		_stop_outputs()


@rpc("authority", "call_remote", "reliable", 2)
func _receive_audio(pcm: PackedByteArray, target: int) -> void:
	if pcm.is_empty() or pcm.size() > CHUNK_FRAMES * 4 or pcm.size() % 4 != 0:
		return
	if target != Destination.LOCAL and not VoiceChannels.valid_channel(target):
		return
	_deliver(pcm, target)


func _deliver(pcm: PackedByteArray, target: int) -> void:
	var frames := VoiceChannels.decode_pcm(pcm)
	_last_packet_ms = Time.get_ticks_msec()
	if target != Destination.LOCAL:
		VoiceChannels.broadcast_frames.emit(self, frames, target)
		return
	for speaker in local_speakers:
		if not is_instance_valid(speaker):
			continue
		var key := speaker.get_instance_id()
		if not _local_outputs.has(key) or not is_instance_valid(_local_outputs[key]):
			# A child preserves the configured speaker's existing stream.
			var output := AudioStreamPlayer3D.new()
			var generator := AudioStreamGenerator.new()
			generator.mix_rate = VoiceChannels.SAMPLE_RATE
			generator.buffer_length = 0.5
			output.stream = generator
			output.bus = speaker.bus
			output.volume_db = speaker.volume_db
			output.max_distance = speaker.max_distance
			output.unit_size = speaker.unit_size
			output.attenuation_model = speaker.attenuation_model
			speaker.add_child(output)
			output.play()
			_local_outputs[key] = output
		var playback := _local_outputs[key].get_stream_playback() as AudioStreamGeneratorPlayback
		if not playback.can_push_buffer(frames.size()):
			_local_outputs[key].stop()
			_local_outputs[key].stream = _local_outputs[key].stream.duplicate()
			_local_outputs[key].play()
			playback = _local_outputs[key].get_stream_playback() as AudioStreamGeneratorPlayback
		if playback.can_push_buffer(frames.size()):
			playback.push_buffer(frames)


func _exit_tree() -> void:
	for output in _local_outputs.values():
		if is_instance_valid(output):
			output.queue_free()


func _capture_world_audio(delta: float) -> void:
	# Decode a separate playback at each source's position. This records the sound
	# at the recorder, independent of the camera, without tapping the Master bus.
	var rate := int(AudioServer.get_mix_rate())
	_world_budget += delta * rate
	var count := mini(int(_world_budget), int(rate * 0.1))
	if count < 1:
		return
	_world_budget -= count
	var present: Dictionary = {}
	for node in get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false):
		var source := node as AudioStreamPlayer3D
		if not source.playing or source.stream_paused or source.stream == null:
			continue
		if global_position.distance_to(source.global_position) >= recording_radius:
			continue
		# Generator voices/PA feeds are handled separately; exclude them to avoid feedback.
		if not (source.stream is AudioStreamWAV or source.stream is AudioStreamOggVorbis or source.stream is AudioStreamMP3):
			continue
		var key := source.get_instance_id()
		present[key] = true
		if not _world_playbacks.has(key) or _world_playbacks[key].stream != source.stream:
			var decoder := source.stream.instantiate_playback()
			decoder.start(source.get_playback_position())
			_world_playbacks[key] = {"stream": source.stream, "decoder": decoder}
		var playback: AudioStreamPlayback = _world_playbacks[key].decoder
		if absf(playback.get_playback_position() - source.get_playback_position()) > 0.15:
			playback.seek(source.get_playback_position())
		var frames := playback.mix_audio(source.pitch_scale * AudioServer.playback_speed_scale, count)
		var gain := db_to_linear(source.volume_db)
		for i in frames.size():
			frames[i] *= gain
		record_audio(source, frames, rate)
	for key in _world_playbacks.keys():
		if not present.has(key):
			_world_playbacks.erase(key)
