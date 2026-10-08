@icon("uid://qxkixe1eu0tm")
## Positional radio output. Every transmitting radio receives its own Opus
## decoder, then Godot mixes those independent voices at this node's position.
class_name RadioSpeaker3D
extends AudioStreamPlayer3D

signal channel_changed(mode: RadioManager.RadioChannelMode, frequency_code: int)

@export var enabled := true:
	set(value):
		enabled = value
		for output: Dictionary in _source_outputs.values():
			var player := output.get("player") as AudioStreamPlayer3D
			if is_instance_valid(player):
				player.stream_paused = not enabled

@export_enum("Local", "Global", "Frequency") var channel_mode: int = RadioManager.RadioChannelMode.FREQUENCY
## A value of 0 adopts the active RadioManager's default frequency.
@export_range(0, RadioManager.MAX_FREQUENCY_CODE, 1) var frequency_code: int = 0
## Standalone speakers can receive local transmissions directly. Speakers owned
## by a Radio are routed through that Radio instead.
@export var hear_local_transmissions := false
@export var register_with_manager := true

@export_category("Voice Latency")
@export_range(0.015, 0.2, 0.005) var buffer_target := 0.04
@export_range(0.005, 0.1, 0.005) var buffer_tolerance := 0.015
@export_range(1.0, 30.0, 0.5) var inactive_source_lifetime := 4.0

var _manager: RadioManager
var _source_outputs: Dictionary = {}


func _exit_tree() -> void:
	if is_instance_valid(_manager):
		_manager.unregister_speaker(self)
	clear_all_sources()


func _ready() -> void:
	# This node is only the shared position/configuration. Child players do the
	# actual playback so simultaneous Opus streams never share one decoder.
	stream = null
	if not register_with_manager:
		return
	_manager = Game.get_radio_manager_or_null()
	if _manager == null:
		push_warning("[RadioSpeaker3D] No RadioManager exists in the active game world.")
		return
	_manager.register_speaker(self)
	if frequency_code == 0:
		frequency_code = _manager.default_frequency_code


## Feed a control or Opus packet for one distinct transmitter.
func play_voip_packet(source_id: StringName, packet: PackedByteArray) -> void:
	if not enabled or packet.is_empty():
		return
	var output := _get_or_create_source_output(source_id)
	output["last_packet_ms"] = Time.get_ticks_msec()
	var decoder := output.get("decoder") as TwoVoipSpeaker
	if is_instance_valid(decoder):
		decoder.tv_incomingaudiopacket(packet)


func clear_source(source_id: StringName) -> void:
	if not _source_outputs.has(source_id):
		return
	var output: Dictionary = _source_outputs[source_id]
	var player := output.get("player") as AudioStreamPlayer3D
	if is_instance_valid(player):
		player.queue_free()
	_source_outputs.erase(source_id)


func clear_all_sources() -> void:
	for source_id: StringName in _source_outputs.keys():
		clear_source(source_id)


func set_channel(mode: RadioManager.RadioChannelMode, new_frequency_code: int = 0) -> void:
	channel_mode = mode
	if mode == RadioManager.RadioChannelMode.FREQUENCY:
		var fallback := _manager.default_frequency_code if is_instance_valid(_manager) else RadioManager.MIN_FREQUENCY_CODE
		frequency_code = clampi(
			new_frequency_code if new_frequency_code != 0 else fallback,
			RadioManager.MIN_FREQUENCY_CODE,
			RadioManager.MAX_FREQUENCY_CODE
		)
	clear_all_sources()
	channel_changed.emit(channel_mode, frequency_code)


func _process(_delta: float) -> void:
	var expiry_ms := roundi(inactive_source_lifetime * 1000.0)
	var now := Time.get_ticks_msec()
	for source_id: StringName in _source_outputs.keys():
		var output: Dictionary = _source_outputs[source_id]
		if now - int(output.get("last_packet_ms", now)) > expiry_ms:
			clear_source(source_id)


func _get_or_create_source_output(source_id: StringName) -> Dictionary:
	if _source_outputs.has(source_id):
		return _source_outputs[source_id]

	var player := AudioStreamPlayer3D.new()
	player.name = "RadioVoice_%s" % _safe_node_name(String(source_id))
	_copy_audio_settings(player)
	add_child(player)

	var decoder := TwoVoipSpeaker.new()
	decoder.name = "TwoVoipDecoder"
	decoder.audiobufferlagtimetarget = buffer_target
	decoder.audiobufferlagtimetargettolerance = buffer_tolerance
	player.add_child(decoder)
	player.stream_paused = not enabled

	var output := {
		"player": player,
		"decoder": decoder,
		"last_packet_ms": Time.get_ticks_msec(),
	}
	_source_outputs[source_id] = output
	return output


func _copy_audio_settings(player: AudioStreamPlayer3D) -> void:
	player.attenuation_model = attenuation_model
	player.unit_size = unit_size
	player.max_db = max_db
	player.max_distance = max_distance
	player.panning_strength = panning_strength
	player.emission_angle_enabled = emission_angle_enabled
	player.emission_angle_degrees = emission_angle_degrees
	player.emission_angle_filter_attenuation_db = emission_angle_filter_attenuation_db
	player.attenuation_filter_cutoff_hz = attenuation_filter_cutoff_hz
	player.attenuation_filter_db = attenuation_filter_db
	player.volume_db = volume_db
	player.bus = bus


func _safe_node_name(value: String) -> String:
	var safe := value.replace("/", "_").replace(":", "_").replace("@", "_")
	return safe.left(48) if not safe.is_empty() else "Unknown"
