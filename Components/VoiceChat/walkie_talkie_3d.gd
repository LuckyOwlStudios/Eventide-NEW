class_name WalkieTalkie3D
extends ChannelSpeaker3D
## Attach below a replicated player, with the same authority as its voice source.
signal transmitting_changed(active: bool)
@export var voice_source: SteamVoiceChat3D
@export var use_input := true
@export var transmit_action: StringName = &"radio_push_to_talk"
var transmitting := false

func _ready() -> void:
	super._ready()
	if not InputMap.has_action(transmit_action):
		InputMap.add_action(transmit_action)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_B
		InputMap.action_add_event(transmit_action, key)


func _can_receive() -> bool:
	return enabled and is_multiplayer_authority()


func _process(delta: float) -> void:
	super._process(delta)
	if not is_multiplayer_authority():
		return
	if use_input:
		set_transmitting(enabled and Input.is_action_pressed(transmit_action))
	elif not enabled:
		set_transmitting(false)
	if transmitting and is_instance_valid(voice_source):
		voice_source.radio_channel = channel


func set_transmitting(active: bool) -> void:
	active = active and enabled and is_multiplayer_authority() and is_instance_valid(voice_source)
	if active and not voice_source.is_multiplayer_authority():
		active = false
	if transmitting == active:
		return
	transmitting = active
	if is_instance_valid(voice_source):
		voice_source.radio_channel = channel
		voice_source.radio_transmitting = active
	transmitting_changed.emit(active)


func _exit_tree() -> void:
	super._exit_tree()
	if transmitting and is_instance_valid(voice_source):
		voice_source.radio_transmitting = false
