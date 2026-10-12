@icon("uid://crbw5yphhlqwc")
## World-level radio registry, channel router, range evaluator, and network relay.
class_name RadioManager
extends Node

signal default_frequency_changed(frequency_code: int)
signal radio_registered(radio: Radio)
signal radio_unregistered(radio: Radio)
signal speaker_registered(speaker: RadioSpeaker3D)
signal speaker_unregistered(speaker: RadioSpeaker3D)

enum RadioChannelMode {
	LOCAL,
	GLOBAL,
	FREQUENCY,
}

const MIN_FREQUENCY_CODE := 1000
const MAX_FREQUENCY_CODE := 9999
const MAX_CONTROL_PACKET_BYTES := 2048
const MAX_AUDIO_PACKET_BYTES := 4096
const RADIO_AUDIO_CHANNEL := 5
const RADIO_CONTROL_CHANNEL := 6

@export_category("Defaults")
## Leave at 0 to generate a frequency when the world starts.
@export_range(0, MAX_FREQUENCY_CODE, 1) var default_frequency_code: int = 0

@export_category("Runtime Registry (read only)")
@export_range(0.1, 5.0, 0.1, "suffix:s") var diagnostics_refresh_seconds := 0.5
## Live list of radios, channels, ranges, authority, and positions. Inspect the
## RadioManager through the Remote scene tree while the game is running.
@export_multiline var runtime_radio_registry := "Start the game to populate the registry."

var _radios: Array[Radio] = []
var _speakers: Array[RadioSpeaker3D] = []
var _diagnostics_elapsed := 0.0


func _enter_tree() -> void:
	InGameHandler.register_radio_manager(self)
	if default_frequency_code == 0:
		set_default_frequency(randi_range(MIN_FREQUENCY_CODE, MAX_FREQUENCY_CODE))


func _ready() -> void:
	refresh_runtime_diagnostics()


func _process(delta: float) -> void:
	_diagnostics_elapsed += delta
	if _diagnostics_elapsed >= diagnostics_refresh_seconds:
		_diagnostics_elapsed = 0.0
		refresh_runtime_diagnostics()


func _exit_tree() -> void:
	InGameHandler.unregister_radio_manager(self)


func set_default_frequency(frequency_code: int) -> void:
	var normalized := clampi(frequency_code, MIN_FREQUENCY_CODE, MAX_FREQUENCY_CODE)
	if default_frequency_code == normalized:
		return
	default_frequency_code = normalized
	default_frequency_changed.emit(default_frequency_code)


func register_radio(radio: Radio) -> void:
	if not _radios.has(radio):
		_radios.append(radio)
		radio_registered.emit(radio)
		refresh_runtime_diagnostics()


func unregister_radio(radio: Radio) -> void:
	if not _radios.has(radio):
		return
	_radios.erase(radio)
	radio_unregistered.emit(radio)
	refresh_runtime_diagnostics()


func register_speaker(speaker: RadioSpeaker3D) -> void:
	if not _speakers.has(speaker):
		_speakers.append(speaker)
		speaker_registered.emit(speaker)
		refresh_runtime_diagnostics()


func unregister_speaker(speaker: RadioSpeaker3D) -> void:
	if not _speakers.has(speaker):
		return
	_speakers.erase(speaker)
	speaker_unregistered.emit(speaker)
	refresh_runtime_diagnostics()


func is_valid_frequency(frequency_code: int) -> bool:
	return frequency_code >= MIN_FREQUENCY_CODE and frequency_code <= MAX_FREQUENCY_CODE


func route_local_radio_control(source: Radio, packet: PackedByteArray) -> void:
	_route_local_packet(source, packet, true)


func route_local_radio_packet(source: Radio, packet: PackedByteArray) -> void:
	_route_local_packet(source, packet, false)


func _route_local_packet(source: Radio, packet: PackedByteArray, reliable: bool) -> void:
	if not _valid_outgoing_packet(source, packet, reliable):
		return
	if not NetworkSession.has_remote_peers():
		_deliver_packet(source, packet)
		return

	var path := source.get_path()
	if NetworkSession.is_server():
		_deliver_packet(source, packet)
		_broadcast_from_server(path, packet, reliable)
	elif reliable:
		_submit_radio_control.rpc_id(NetworkSession.SERVER_PEER_ID, path, packet)
	else:
		_submit_radio_audio.rpc_id(NetworkSession.SERVER_PEER_ID, path, packet)


@rpc("any_peer", "call_remote", "reliable", RADIO_CONTROL_CHANNEL)
func _submit_radio_control(source_path: NodePath, packet: PackedByteArray) -> void:
	_server_accept_packet(source_path, packet, true)


@rpc("any_peer", "call_remote", "unreliable", RADIO_AUDIO_CHANNEL)
func _submit_radio_audio(source_path: NodePath, packet: PackedByteArray) -> void:
	_server_accept_packet(source_path, packet, false)


func _server_accept_packet(source_path: NodePath, packet: PackedByteArray, reliable: bool) -> void:
	if not NetworkSession.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var source := get_node_or_null(source_path) as Radio
	if not _valid_network_source(source, sender_id) or not _valid_outgoing_packet(source, packet, reliable):
		return
	_deliver_packet(source, packet)
	_broadcast_from_server(source_path, packet, reliable)


func _broadcast_from_server(source_path: NodePath, packet: PackedByteArray, reliable: bool) -> void:
	for peer_id in NetworkSession.get_remote_peer_ids():
		if reliable:
			_receive_radio_control.rpc_id(peer_id, source_path, packet)
		else:
			_receive_radio_audio.rpc_id(peer_id, source_path, packet)


@rpc("authority", "call_remote", "reliable", RADIO_CONTROL_CHANNEL)
func _receive_radio_control(source_path: NodePath, packet: PackedByteArray) -> void:
	_receive_network_packet(source_path, packet, true)


@rpc("authority", "call_remote", "unreliable", RADIO_AUDIO_CHANNEL)
func _receive_radio_audio(source_path: NodePath, packet: PackedByteArray) -> void:
	_receive_network_packet(source_path, packet, false)


func _receive_network_packet(source_path: NodePath, packet: PackedByteArray, reliable: bool) -> void:
	var source := get_node_or_null(source_path) as Radio
	if _valid_outgoing_packet(source, packet, reliable):
		_deliver_packet(source, packet)


func _deliver_packet(source: Radio, packet: PackedByteArray) -> void:
	for receiver in _radios.duplicate():
		if not is_instance_valid(receiver):
			_radios.erase(receiver)
			continue
		if receiver == source and not receiver.hear_own_transmission:
			continue
		if _radio_can_receive(source, receiver):
			receiver.receive_radio_packet(source, packet)

	for speaker in _speakers.duplicate():
		if not is_instance_valid(speaker):
			_speakers.erase(speaker)
			continue
		if not speaker.hear_local_transmissions:
			continue
		if _speaker_can_receive(source, speaker):
			speaker.play_voip_packet(source.source_id(), packet)


func _radio_can_receive(source: Radio, receiver: Radio) -> bool:
	return (
		receiver.enabled
		and receiver.can_receive
		and channels_match(source.channel_mode, source.frequency_code, receiver.channel_mode, receiver.frequency_code)
		and is_in_signal_range(source, receiver.global_position)
	)


func _speaker_can_receive(source: Radio, speaker: RadioSpeaker3D) -> bool:
	return (
		speaker.enabled
		and channels_match(source.channel_mode, source.frequency_code, speaker.channel_mode, speaker.frequency_code)
		and is_in_signal_range(source, speaker.global_position)
	)


func is_in_signal_range(source: Radio, target_position: Vector3) -> bool:
	return (
		source.infinite_transmit_range
		or source.global_position.distance_to(target_position) <= maxf(source.transmit_range_meters, 0.0)
	)


func channels_match(
		transmit_mode: RadioChannelMode,
		transmit_frequency: int,
		receive_mode: RadioChannelMode,
		receive_frequency: int
) -> bool:
	# Global transmit reaches every channel. A Global receiver is a scanner and
	# hears every transmission. Frequency devices otherwise require an exact tune.
	if transmit_mode == RadioChannelMode.GLOBAL or receive_mode == RadioChannelMode.GLOBAL:
		return true
	if transmit_mode != receive_mode:
		return false
	if transmit_mode == RadioChannelMode.FREQUENCY:
		return transmit_frequency == receive_frequency
	return transmit_mode == RadioChannelMode.LOCAL


func refresh_runtime_diagnostics() -> void:
	var registry_lines := PackedStringArray()
	registry_lines.append("%s radio(s), %s standalone speaker(s)" % [_radios.size(), _speakers.size()])
	registry_lines.append("Default frequency: %s" % default_frequency_code)
	for radio in _radios:
		if not is_instance_valid(radio):
			continue
		var range_text := "INFINITE" if radio.infinite_transmit_range else "%.1f m" % radio.transmit_range_meters
		var channel_text := _channel_text(radio.channel_mode, radio.frequency_code)
		registry_lines.append("• %s | %s | range %s | authority %s | %s" % [
			radio.display_name(), channel_text, range_text,
			radio.get_multiplayer_authority(), _vector_text(radio.global_position),
		])
		_update_radio_diagnostics(radio)
	for speaker in _speakers:
		if is_instance_valid(speaker):
			registry_lines.append("  ↳ speaker %s | %s | %s" % [
				speaker.name,
				_channel_text(speaker.channel_mode, speaker.frequency_code),
				_vector_text(speaker.global_position),
			])
	runtime_radio_registry = "\n".join(registry_lines)


func _update_radio_diagnostics(radio: Radio) -> void:
	var range_text := "INFINITE" if radio.infinite_transmit_range else "%.1f m" % radio.transmit_range_meters
	radio.runtime_status = "%s\nChannel: %s\nTransmit range: %s\nPosition: %s\nTransmit: %s | Receive: %s" % [
		radio.display_name(), _channel_text(radio.channel_mode, radio.frequency_code),
		range_text, _vector_text(radio.global_position), radio.can_transmit, radio.can_receive,
	]
	var match_lines := PackedStringArray()
	for other in _radios:
		if not is_instance_valid(other) or other == radio:
			continue
		if not channels_match(radio.channel_mode, radio.frequency_code, other.channel_mode, other.frequency_code):
			continue
		var distance := radio.global_position.distance_to(other.global_position)
		var reachable := is_in_signal_range(radio, other.global_position)
		match_lines.append("%s | %.1f m | %s" % [
			other.display_name(), distance, "REACHABLE" if reachable else "OUT OF RANGE",
		])
	radio.runtime_matching_radios = (
		"Matching radios:\n" + "\n".join(match_lines)
		if not match_lines.is_empty()
		else "No other radios match this channel."
	)


func _valid_network_source(source: Radio, sender_id: int) -> bool:
	if not is_instance_valid(source) or sender_id <= 0:
		return false
	if source.get_multiplayer_authority() == sender_id:
		return true
	# A ship console is commonly server-owned while its current operator's voice
	# source belongs to that client.
	return (
		is_instance_valid(source.voice_chat)
		and source.voice_chat.get_multiplayer_authority() == sender_id
	)


func _valid_outgoing_packet(source: Radio, packet: PackedByteArray, reliable: bool) -> bool:
	var max_size := MAX_CONTROL_PACKET_BYTES if reliable else MAX_AUDIO_PACKET_BYTES
	return (
		is_instance_valid(source)
		and source.enabled
		and source.can_transmit
		and not packet.is_empty()
		and packet.size() <= max_size
	)


func _channel_text(mode: int, frequency: int) -> String:
	match mode:
		RadioChannelMode.LOCAL:
			return "Local"
		RadioChannelMode.GLOBAL:
			return "Global / scanner"
		RadioChannelMode.FREQUENCY:
			return "Frequency %s" % frequency
	return "Unknown"


func _vector_text(value: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [value.x, value.y, value.z]
