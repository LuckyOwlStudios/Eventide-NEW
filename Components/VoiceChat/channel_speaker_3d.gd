class_name ChannelSpeaker3D
extends Node3D
## One positional generator per talker, so nearby voices can fade independently.
@export_enum("Global", "Alpha", "Beta", "Charlie", "Delta") var channel: int = 1:
	set(value):
		if channel != value:
			channel = clampi(value, 0, 4)
			clear_audio()
@export var enabled := true:
	set(value):
		enabled = value
		if not enabled:
			clear_audio()
## Plays your own radio transmissions through this receiver, without proximity suppression.
@export var hear_own_voice := false:
	set(value):
		if hear_own_voice != value:
			hear_own_voice = value
			clear_audio()
@export var suppress_nearby_voices := true
@export_range(-60.0, 12.0) var volume_db := 0.0
@export_range(1.0, 200.0) var audible_distance := 30.0
@export var audio_bus: StringName = &"Master"

@export_category("Voice Latency")
## Total generator capacity. Smaller values limit how far playback can fall behind.
@export_range(0.05, 0.5, 0.01) var voice_buffer_seconds := 0.10
## Maximum queued audio for voices arriving over the network.
@export_range(0.02, 0.25, 0.005) var maximum_queue_seconds := 0.06
## Local microphone monitoring does not need a network jitter cushion.
@export_range(0.01, 0.15, 0.005) var local_monitor_queue_seconds := 0.025
var _outputs: Dictionary = {}


func _ready() -> void:
	add_to_group("channel_speakers")
	VoiceChannels.voice_frames.connect(_on_voice)
	VoiceChannels.broadcast_frames.connect(_on_broadcast)


func _can_receive() -> bool:
	return enabled


func _on_voice(source: Node3D, frames: PackedVector2Array, transmit_channel: int) -> void:
	if not _can_receive() or not VoiceChannels.matches(transmit_channel, channel):
		return
	# Local microphone monitoring is opt-in for each receiver.
	if (source.is_multiplayer_authority() and not hear_own_voice) or source.get("is_muted") == true:
		return
	_feed(source, frames, true)


func _on_broadcast(source: Node3D, frames: PackedVector2Array, transmit_channel: int) -> void:
	if _can_receive() and VoiceChannels.matches(transmit_channel, channel):
		_feed(source, frames, false)


func _feed(source: Node3D, frames: PackedVector2Array, live_voice: bool) -> void:
	var key := source.get_instance_id()
	if not _outputs.has(key):
		var player := AudioStreamPlayer3D.new()
		var generator := AudioStreamGenerator.new()
		generator.mix_rate = VoiceChannels.SAMPLE_RATE
		generator.buffer_length = voice_buffer_seconds
		player.stream = generator
		player.max_distance = audible_distance
		player.bus = audio_bus if AudioServer.get_bus_index(audio_bus) >= 0 else &"Master"
		add_child(player)
		player.play()
		var initial_playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
		_outputs[key] = {
			"player": player,
			"source": weakref(source),
			"live": live_voice,
			"last": 0,
			"capacity_frames": initial_playback.get_frames_available()
		}
	var output: Dictionary = _outputs[key]
	output.last = Time.get_ticks_msec()
	var playback := output.player.get_stream_playback() as AudioStreamGeneratorPlayback
	var is_local_monitor := live_voice and source.is_multiplayer_authority() and hear_own_voice
	var queue_limit := local_monitor_queue_seconds if is_local_monitor else maximum_queue_seconds
	if _queued_seconds(output, playback) > queue_limit:
		# Drop stale queued speech instead of letting latency continue to grow.
		playback = _restart_output(output)
	if not playback.can_push_buffer(frames.size()):
		playback = _restart_output(output)
	if playback.can_push_buffer(frames.size()):
		playback.push_buffer(frames)
	_update_output(output)


func _queued_seconds(output: Dictionary, playback: AudioStreamGeneratorPlayback) -> float:
	var player: AudioStreamPlayer3D = output.player
	var generator := player.stream as AudioStreamGenerator
	if generator == null or playback == null or generator.mix_rate <= 0.0:
		return 0.0
	var capacity_frames := int(output.capacity_frames)
	var queued_frames := maxi(capacity_frames - playback.get_frames_available(), 0)
	return float(queued_frames) / generator.mix_rate


func _restart_output(output: Dictionary) -> AudioStreamGeneratorPlayback:
	var player: AudioStreamPlayer3D = output.player
	player.stop()
	player.stream = player.stream.duplicate()
	player.play()
	var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
	output.capacity_frames = playback.get_frames_available()
	return playback


func _process(_delta: float) -> void:
	for key in _outputs.keys():
		var output: Dictionary = _outputs[key]
		if output.source.get_ref() == null or Time.get_ticks_msec() - int(output.last) > 1000:
			output.player.queue_free()
			_outputs.erase(key)
		else:
			_update_output(output)


func _update_output(output: Dictionary) -> void:
	var gain := 1.0 if _can_receive() else 0.0
	var source: Node3D = output.source.get_ref()
	if output.live and is_instance_valid(source):
		if source.get("is_muted") == true or source.get("is_voice_chat_active") == false:
			gain = 0.0
		elif source.is_multiplayer_authority():
			# The local voice is not played through proximity audio, so there is no overlap.
			if not hear_own_voice:
				gain = 0.0
		elif suppress_nearby_voices and source.has_method("radio_gain_for_listener"):
			gain *= source.radio_gain_for_listener()
	output.player.volume_db = volume_db + linear_to_db(maxf(gain, 0.00001))


func clear_audio() -> void:
	for output in _outputs.values():
		output.player.stop()
		output.player.queue_free()
	_outputs.clear()


func clear_source(source: Node3D) -> void:
	var key := source.get_instance_id()
	if _outputs.has(key):
		_outputs[key].player.stop()
		_outputs[key].player.queue_free()
		_outputs.erase(key)



func _exit_tree() -> void:
	clear_audio()
