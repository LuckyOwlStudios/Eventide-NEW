class_name KeybindInteractionEntry
extends PanelContainer

## One visible interaction choice. Input detection here is presentation-only;
## InteractionRayCast3D remains responsible for executing the interaction.

signal action_pressed(option_index: int)
signal interaction_succeeded(option_index: int)

const HOLD_TRIGGER_TYPE := 2

@onready var key_bind_label: Label = %KeyBindLabel
@onready var description_label: Label = %DescriptionLabel
@onready var margin_container: MarginContainer = $Layout/MarginContainer
@onready var hold_progress: ProgressBar = %HoldProgress

@export var interactable_object: InteractableObject3D

var option_index := -1
var option: InteractionOption

func setup(
		interactable: InteractableObject3D,
		interaction_option: InteractionOption,
		index: int
) -> void:
	interactable_object = interactable
	option = interaction_option
	option_index = index
	key_bind_label.text = _input_hint(option.input_action)
	description_label.text = option.prompt.to_upper()
	margin_container.visible = int(option.trigger_type) == HOLD_TRIGGER_TYPE
	hold_progress.value = 0.0
	set_process_input(true)

func set_hold_progress(progress: float) -> void:
	if is_instance_valid(hold_progress):
		hold_progress.value = clampf(progress, 0.0, 1.0)

func notify_interaction_succeeded() -> void:
	interaction_succeeded.emit(option_index)

func _input(event: InputEvent) -> void:
	if option == null or not is_visible_in_tree():
		return
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed(option.input_action):
		action_pressed.emit(option_index)

func _input_hint(action: StringName) -> String:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return String(action).left(3).to_upper()
	var event := events[0]
	if event is InputEventKey:
		var key_event := event as InputEventKey
		var keycode := key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode
		return OS.get_keycode_string(keycode).to_upper()
	if event is InputEventMouseButton:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return "LMB"
			MOUSE_BUTTON_RIGHT: return "RMB"
			MOUSE_BUTTON_MIDDLE: return "MMB"
	var hint := event.as_text().replace(" (Physical)", "").replace(" - Physical", "")
	return hint if not hint.is_empty() else String(action).to_upper()
