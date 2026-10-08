## A complete radio transceiver. It can transmit microphone packets, receive
## matching channels, enforce signal range, and expose live routing diagnostics.
class_name Radio
extends Node3D

signal channel_changed(mode: RadioManager.RadioChannelMode, frequency_code: int)
signal range_changed(range_meters: float, is_infinite: bool)

@export_category("Identity")
## Friendly name shown in RadioManager's runtime registry. The node name is used
## when this is blank.
@export var device_label := ""

@export_category("Channel")
## Selects how this radio is tuned. Frequency only communicates with the same
## frequency code. Global broadcasts to every channel and also acts as a scanner.
## Local only communicates with other radios set to Local.
@export_enum("Local", "Global", "Frequency") var channel_mode: int = RadioManager.RadioChannelMode.FREQUENCY
## Four-digit channel used when Channel Mode is Frequency. A value of 0 adopts
## the active RadioManager's default frequency when the radio enters the world.
@export_range(0, RadioManager.MAX_FREQUENCY_CODE, 1) var frequency_code: int = 0

@export_category("Signal Range")
## Maximum transmitter-to-receiver distance. This is signal range, not how far
## away a player can hear the physical speaker.
@export_range(0.0, 100000.0, 1.0, "or_greater", "suffix:m") var transmit_range_meters := 250.0
## Ignores Transmit Range Meters when enabled, allowing this radio to broadcast
## to matching receivers at any distance. Intended for ship or station radios.
@export var infinite_transmit_range := false

@export_category("Transceiver")
## Master power switch. A disabled radio cannot transmit or receive audio.
@export var enabled := true
## Allows microphone packets from Voice Chat to be broadcast through this radio.
## Disable this on receive-only devices or while another radio is being operated.
@export var can_transmit := true
## Allows this radio to play transmissions from matching, reachable radios.
## Disable this for transmit-only devices.
@export var can_receive := true
## Plays this radio's own outgoing transmission through its receiver speaker.
## Usually disabled on handheld radios to prevent hearing your own delayed voice.
@export var hear_own_transmission := false
## PlayerVoiceChat that supplies microphone packets when this radio transmits.
## Assign the owning player's voice node. Receive-only radios may leave this empty.
@export var voice_chat: PlayerVoiceChat

@export_category("Receiver Audio")
## Positional speaker that plays received radio voices. Assign a custom
## RadioSpeaker3D for precise placement or leave blank to use an automatic one.
@export var receiver_speaker: RadioSpeaker3D
## Creates a ReceiverSpeaker child at runtime when Receiver Speaker is empty.
## Disable this only when supplying a custom speaker or building a silent radio.
@export var create_receiver_automatically := true
## Maximum physical distance at which players hear this radio's speaker. This
## affects world audio attenuation only and does not change communication range.
@export_range(0.0, 1000.0, 1.0, "or_greater", "suffix:m") var speaker_audible_distance := 20.0

@export_category("Runtime Diagnostics (read only)")
## Live summary of this radio's name, channel, range, position, and capabilities.
## Run the game and select this node in the Remote scene tree to read it.
@export_multiline var runtime_status := "Start the game to inspect this radio."
## Live list of other radios on matching channels, including their distance and
## whether this radio can currently reach them. This field is diagnostic only.
@export_multiline var runtime_matching_radios := "No runtime data yet."

var _manager: RadioManager


func _exit_tree() -> void:
	if is_instance_valid(_manager):
		_manager.unregister_radio(self)


func _ready() -> void:
	_manager = Game.get_radio_manager_or_null()
	if _manager == null:
		push_warning("[Radio] No RadioManager exists in the active game world.")
		return
	if frequency_code == 0:
		frequency_code = _manager.default_frequency_code
	_ensure_receiver_speaker()
	_manager.register_radio(self)
	_connect_voice_chat()


func display_name() -> String:
	@warning_ignore("incompatible_ternary")
	return device_label if not device_label.strip_edges().is_empty() else name


func source_id() -> StringName:
	# Replicated scenes share paths, making this stable on every peer.
	return StringName(str(get_path()))


func receive_radio_packet(transmitter: Radio, packet: PackedByteArray) -> void:
	if not enabled or not can_receive or not is_instance_valid(receiver_speaker):
		return
	receiver_speaker.play_voip_packet(transmitter.source_id(), packet)


func set_channel(mode: RadioManager.RadioChannelMode, new_frequency_code: int = 0) -> void:
	channel_mode = mode
	if mode == RadioManager.RadioChannelMode.FREQUENCY:
		var fallback := _manager.default_frequency_code if is_instance_valid(_manager) else RadioManager.MIN_FREQUENCY_CODE
		frequency_code = clampi(
			new_frequency_code if new_frequency_code != 0 else fallback,
			RadioManager.MIN_FREQUENCY_CODE,
			RadioManager.MAX_FREQUENCY_CODE
		)
	if is_instance_valid(receiver_speaker):
		receiver_speaker.channel_mode = channel_mode
		receiver_speaker.frequency_code = frequency_code
		receiver_speaker.clear_all_sources()
	channel_changed.emit(channel_mode, frequency_code)
	if is_instance_valid(_manager):
		_manager.refresh_runtime_diagnostics()


func set_signal_range(range_meters: float, is_infinite: bool = false) -> void:
	transmit_range_meters = maxf(range_meters, 0.0)
	infinite_transmit_range = is_infinite
	range_changed.emit(transmit_range_meters, infinite_transmit_range)
	if is_instance_valid(_manager):
		_manager.refresh_runtime_diagnostics()


## Use this when a player starts or stops operating a ship radio. Only radios
## connected to that player's voice source and allowed to transmit will send.
func use_voice_source(source: PlayerVoiceChat) -> void:
	_disconnect_voice_chat()
	voice_chat = source
	_connect_voice_chat()


func set_transmit_enabled(active: bool) -> void:
	can_transmit = active
	if can_transmit:
		_connect_voice_chat()


func _connect_voice_chat() -> void:
	if not can_transmit or not is_instance_valid(voice_chat):
		return
	if not voice_chat.local_opus_control_ready.is_connected(_on_local_opus_control):
		voice_chat.local_opus_control_ready.connect(_on_local_opus_control)
	if not voice_chat.local_opus_packet_ready.is_connected(_on_local_opus_packet):
		voice_chat.local_opus_packet_ready.connect(_on_local_opus_packet)


func _disconnect_voice_chat() -> void:
	if not is_instance_valid(voice_chat):
		return
	if voice_chat.local_opus_control_ready.is_connected(_on_local_opus_control):
		voice_chat.local_opus_control_ready.disconnect(_on_local_opus_control)
	if voice_chat.local_opus_packet_ready.is_connected(_on_local_opus_packet):
		voice_chat.local_opus_packet_ready.disconnect(_on_local_opus_packet)


func _on_local_opus_control(packet: PackedByteArray) -> void:
	if enabled and can_transmit and is_instance_valid(_manager):
		_manager.route_local_radio_control(self, packet)


func _on_local_opus_packet(packet: PackedByteArray) -> void:
	if enabled and can_transmit and is_instance_valid(_manager):
		_manager.route_local_radio_packet(self, packet)


func _ensure_receiver_speaker() -> void:
	if not can_receive:
		return
	if not is_instance_valid(receiver_speaker) and create_receiver_automatically:
		receiver_speaker = RadioSpeaker3D.new()
		receiver_speaker.name = "ReceiverSpeaker"
		receiver_speaker.register_with_manager = false
		receiver_speaker.hear_local_transmissions = false
		add_child(receiver_speaker)
	if not is_instance_valid(receiver_speaker):
		return
	receiver_speaker.channel_mode = channel_mode
	receiver_speaker.frequency_code = frequency_code
	receiver_speaker.max_distance = speaker_audible_distance
