@icon("uid://baeicuw6syt0x")
class_name MicActivityIcon
extends TextureRect
## A local HUD icon driven by a PlayerVoiceChat microphone's talking state.

@export var player_voice_chat: PlayerVoiceChat



@export_category("Appearance")
## Alpha used while the player is not transmitting.
@export_range(0.0, 1.0, 0.05) var inactive_alpha := 0.5
## Alpha used while the player is transmitting.
@export_range(0.0, 1.0, 0.05) var active_alpha := 1.0
## Maximum extra scale contributed by live microphone volume.
@export_range(0.0, 0.5, 0.01) var activity_scale_amount := 0.12
## How quickly opacity and scale react to microphone changes.
@export_range(0.0, 60.0, 0.5) var response_speed := 16.0
## Prevents HUD icons belonging to remote player instances from appearing.
@export var hide_for_remote_player := true

var _displayed_alpha := 0.5
var _displayed_activity := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_center_pivot)
	_center_pivot()
	_displayed_alpha = inactive_alpha
	_apply_visuals()
	if not is_instance_valid(player_voice_chat):
		push_warning("MicActivityIcon requires a PlayerVoiceChat node.")


func _process(delta: float) -> void:
	if not is_instance_valid(player_voice_chat):
		_displayed_alpha = inactive_alpha
		_displayed_activity = 0.0
		_apply_visuals()
		return

	var is_local_voice := player_voice_chat.is_multiplayer_authority()
	visible = is_local_voice or not hide_for_remote_player
	if not visible:
		return

	var talking := player_voice_chat.is_talking()
	var target_alpha := active_alpha if talking else inactive_alpha
	var target_activity := player_voice_chat.get_voice_activity() if talking else 0.0
	var weight := 1.0 if response_speed <= 0.0 else 1.0 - exp(-response_speed * delta)
	_displayed_alpha = lerpf(_displayed_alpha, target_alpha, weight)
	_displayed_activity = lerpf(_displayed_activity, target_activity, weight)
	_apply_visuals()


func _center_pivot() -> void:
	pivot_offset = size * 0.5


func _apply_visuals() -> void:
	self_modulate = Color(1.0, 1.0, 1.0, _displayed_alpha)
	var activity_scale := 1.0 + _displayed_activity * activity_scale_amount
	scale = Vector2.ONE * activity_scale
