@icon("uid://dq4jjyei0wcf3")
class_name PlayerVoiceChat
extends Node3D

## Low-latency network voice backed by the TwoVoIP Opus GDExtension.

## Locally encoded packets intended specifically for the player's radio.
signal local_opus_control_ready(packet: PackedByteArray)
signal local_opus_packet_ready(packet: PackedByteArray)
## Emitted when this local microphone begins or stops transmitting voice.
signal talking_changed(is_talking: bool)
## Emitted when the normalized microphone activity level changes noticeably.
signal voice_activity_changed(activity: float)

const VOICE_CHANNEL := 3
const CONTROL_CHANNEL := 4
const MAX_PENDING_PACKETS := 8
const INPUT_DEVICE_SETTING: StringName = &"voice.input_device"

@export_category("Voice")
@export var start_recording_on_ready := true
## Hear your microphone
@export var has_loopback := false
@export_range(0.0, 1.0, 0.01) var microphone_gain := 1.0
@export_range(0.001, 0.2, 0.001) var voice_activation_threshold := 0.01
@export var denoise_enabled := true

@export_category("Opus Quality")
@export_enum("8000:8000", "12000:12000", "24000:24000", "48000:48000") var opus_sample_rate := 48000
@export_enum("5:5", "10:10", "20:20", "40:40", "60:60") var opus_frame_duration_ms := 10
@export_range(6000, 64000, 1000) var opus_bitrate := 64000
@export_range(1, 10, 1) var opus_complexity := 10
@export var optimize_for_voice := true

@export_category("Playback Latency")
@export_range(0.015, 0.2, 0.005) var local_buffer_target := 0.025
@export_range(0.02, 0.25, 0.005) var network_buffer_target := 0.04
@export_range(0.005, 0.1, 0.005) var buffer_tolerance := 0.015

@export_category("Debug")
@export var debug_enabled := false
@export_range(0.1, 2.0, 0.1) var debug_talking_interval := 0.5

@export_category("Scene Wiring")
@export var two_voip_mic: Node
@export var local_voip_speaker: Node
@export var network_voip_speaker: Node

var _mic_enabled_button: Button
var _push_to_talk_button: Button
var _voice_activation_button: Button
var _denoise_button: Button
var _input_device_options: OptionButton
var _talking := false
var _voice_activity := 0.0
var _last_talking_debug_ms := -1000000
var _network_stream_ready := false
var _pending_network_packets: Array[PackedByteArray] = []
var _voice_requested := false
var _radio_requested := false
var _voice_route_open := false
var _radio_route_open := false
var _active_stream_header := PackedByteArray()

func _ready() -> void:
	_configure_speaker(local_voip_speaker, local_buffer_target)
	_configure_speaker(network_voip_speaker, network_buffer_target)
	_debug("Ready. Peer=%s authority=%s is_authority=%s" % [
		NetworkSession.get_local_peer_id(),
		get_multiplayer_authority(),
		is_multiplayer_authority(),
	])
	if is_multiplayer_authority():
		_configure_microphone()
		Settings.setting_changed.connect(_on_setting_changed)


func _process(_delta: float) -> void:
	if not is_multiplayer_authority() or two_voip_mic == null:
		return
	_update_transmission_requests()
	_update_voice_activity()
	_report_talking(bool(two_voip_mic.get("currentlytalking")))


func record_voice(active: bool) -> void:
	if _mic_enabled_button == null:
		return
	_mic_enabled_button.button_pressed = active
	_debug("Microphone enabled: %s" % active)


func set_input_device(device_name: String) -> void:
	var devices := AudioServer.get_input_device_list()
	if device_name not in devices:
		push_warning("[PlayerVoiceChat] Input device not found: %s" % device_name)
		return
	AudioServer.set_input_device(device_name)
	if _input_device_options != null:
		_input_device_options.select(devices.find(device_name))
	_debug("Input device set to: %s" % device_name)


func set_transmitting(active: bool) -> void:
	## Allows a radio component to control push-to-talk directly.
	if _push_to_talk_button != null:
		_push_to_talk_button.button_pressed = active


## Returns whether this microphone is currently transmitting a voice stream.
func is_talking() -> bool:
	return _talking


## Returns current microphone strength normalized to the 0.0-1.0 range.
func get_voice_activity() -> float:
	return _voice_activity


func _configure_microphone() -> void:
	if two_voip_mic == null:
		push_error("[PlayerVoiceChat] TwoVoipMic is not assigned.")
		return
	_create_hidden_controls()
	two_voip_mic.connect("transmitaudiopacket", _on_opus_packet)
	two_voip_mic.connect("transmitaudiojsonpacket", _on_opus_control)
	two_voip_mic.call("initvoipmic", _mic_enabled_button, _input_device_options,
		_push_to_talk_button, _voice_activation_button, _denoise_button, null)
	# TwoVoIP normally makes this momentary when VOX is off. Our hidden control is
	# driven by code, so keep it toggleable and set its pressed state each frame.
	_push_to_talk_button.toggle_mode = true
	two_voip_mic.call("setopusvalues", opus_sample_rate, opus_frame_duration_ms,
		1, opus_bitrate, opus_complexity, optimize_for_voice)
	two_voip_mic.call("set_voxthreshhold", voice_activation_threshold)
	two_voip_mic.call("set_gain", microphone_gain)
	_select_input_device()
	_debug("TwoVoIP microphone initialized: %s Hz, %s ms, %s bps mono." % [
		opus_sample_rate, opus_frame_duration_ms, opus_bitrate])


func _create_hidden_controls() -> void:
	_mic_enabled_button = Button.new()
	_mic_enabled_button.toggle_mode = true
	_mic_enabled_button.button_pressed = start_recording_on_ready
	_push_to_talk_button = Button.new()
	_push_to_talk_button.toggle_mode = false
	_voice_activation_button = Button.new()
	_voice_activation_button.toggle_mode = true
	_voice_activation_button.button_pressed = false
	_denoise_button = Button.new()
	_denoise_button.toggle_mode = true
	_denoise_button.button_pressed = denoise_enabled
	_input_device_options = OptionButton.new()


func _select_input_device() -> void:
	var devices := AudioServer.get_input_device_list()
	if devices.is_empty():
		push_warning("[PlayerVoiceChat] No microphone devices were found.")
		return
	var selected_device := String(Settings.get_setting(INPUT_DEVICE_SETTING, &"Default"))
	if selected_device not in devices:
		selected_device = "Default" if "Default" in devices else devices[0]
	set_input_device(selected_device)


func _on_setting_changed(id: StringName, value: Variant) -> void:
	if id == INPUT_DEVICE_SETTING and is_multiplayer_authority():
		set_input_device(String(value))


func _configure_speaker(speaker: Node, target: float) -> void:
	if speaker == null:
		push_error("[PlayerVoiceChat] A TwoVoipSpeaker is not assigned.")
		return
	speaker.set("audiobufferlagtimetarget", target)
	speaker.set("audiobufferlagtimetargettolerance", buffer_tolerance)


func _on_opus_control(control: Dictionary) -> void:
	var packet := JSON.stringify(control).to_utf8_buffer()
	if control.has("talkingtimestart"):
		_active_stream_header = packet
		if _voice_requested:
			_open_voice_route(packet)
		if _radio_requested:
			_open_radio_route(packet)
	elif control.has("talkingtimeend"):
		if _voice_route_open:
			_send_voice_control(packet)
		if _radio_route_open:
			_send_radio_control(packet)
		_voice_route_open = false
		_radio_route_open = false
		_active_stream_header.clear()


func _on_opus_packet(packet: PackedByteArray, _frame_number: int) -> void:
	if _voice_route_open:
		if NetworkSession.has_remote_peers():
			_receive_opus_packet.rpc(packet)
		if has_loopback:
			local_voip_speaker.call("tv_incomingaudiopacket", packet)
	if _radio_route_open:
		local_opus_packet_ready.emit(packet)


func _update_transmission_requests() -> void:
	var mode := Settings.voice_chat_mode
	var wants_voice := (
		mode == Settings.VoiceChatMode.OPEN_MIC
		or (
			mode == Settings.VoiceChatMode.PUSH_TO_TALK
			and Input.is_action_pressed(Settings.VOICE_CHAT_ACTION)
		)
	)
	var wants_radio := Input.is_action_pressed(Settings.RADIO_CHAT_ACTION)

	if wants_voice and not _voice_requested and not _active_stream_header.is_empty():
		_open_voice_route(_active_stream_header)
	elif not wants_voice and _voice_route_open:
		_close_voice_route()

	if wants_radio and not _radio_requested and not _active_stream_header.is_empty():
		_open_radio_route(_active_stream_header)
	elif not wants_radio and _radio_route_open:
		_close_radio_route()

	_voice_requested = wants_voice
	_radio_requested = wants_radio
	if _push_to_talk_button != null:
		_push_to_talk_button.button_pressed = wants_voice or wants_radio


func _open_voice_route(header: PackedByteArray) -> void:
	if _voice_route_open:
		return
	_voice_route_open = true
	_send_voice_control(header)


func _open_radio_route(header: PackedByteArray) -> void:
	if _radio_route_open:
		return
	_radio_route_open = true
	_send_radio_control(header)


func _close_voice_route() -> void:
	_send_voice_control(_make_stream_end_packet())
	_voice_route_open = false


func _close_radio_route() -> void:
	_send_radio_control(_make_stream_end_packet())
	_radio_route_open = false


func _send_voice_control(packet: PackedByteArray) -> void:
	if NetworkSession.has_remote_peers():
		_receive_opus_control.rpc(packet)
	if has_loopback:
		local_voip_speaker.call("tv_incomingaudiopacket", packet)


func _send_radio_control(packet: PackedByteArray) -> void:
	local_opus_control_ready.emit(packet)


func _make_stream_end_packet() -> PackedByteArray:
	return JSON.stringify({"talkingtimeend": Time.get_ticks_msec() * 0.001}).to_utf8_buffer()


@rpc("authority", "call_remote", "reliable", CONTROL_CHANNEL)
func _receive_opus_control(packet: PackedByteArray) -> void:
	if packet.is_empty() or packet.size() > 2048:
		return
	network_voip_speaker.call("tv_incomingaudiopacket", packet)
	var control = JSON.parse_string(packet.get_string_from_utf8())
	if control is Dictionary and control.has("talkingtimestart"):
		_network_stream_ready = true
		for pending_packet in _pending_network_packets:
			network_voip_speaker.call("tv_incomingaudiopacket", pending_packet)
		_pending_network_packets.clear()
	elif control is Dictionary and control.has("talkingtimeend"):
		_network_stream_ready = false


@rpc("authority", "call_remote", "unreliable", VOICE_CHANNEL)
func _receive_opus_packet(packet: PackedByteArray) -> void:
	if packet.is_empty() or packet.size() > 4096:
		return
	if not _network_stream_ready:
		if _pending_network_packets.size() >= MAX_PENDING_PACKETS:
			_pending_network_packets.pop_front()
		_pending_network_packets.push_back(packet)
		return
	network_voip_speaker.call("tv_incomingaudiopacket", packet)


func _report_talking(talking: bool) -> void:
	var now := Time.get_ticks_msec()
	var changed := talking != _talking
	_talking = talking
	if changed:
		talking_changed.emit(_talking)
	if not debug_enabled:
		return
	if not talking:
		if changed:
			_debug("Talking stopped.")
		return
	if changed or now - _last_talking_debug_ms >= roundi(debug_talking_interval * 1000.0):
		_last_talking_debug_ms = now
		_debug("Talking! Opus packets are being transmitted.")


func _update_voice_activity() -> void:
	var raw_activity := float(two_voip_mic.get("last_chunkmax"))
	var normalization_ceiling := maxf(voice_activation_threshold * 4.0, 0.05)
	var normalized := clampf(raw_activity / normalization_ceiling, 0.0, 1.0)
	if absf(normalized - _voice_activity) < 0.005:
		return
	_voice_activity = normalized
	voice_activity_changed.emit(_voice_activity)

func _debug(message: String) -> void:
	if debug_enabled:
		print("[PlayerVoiceChat:%s] %s" % [name, message])
