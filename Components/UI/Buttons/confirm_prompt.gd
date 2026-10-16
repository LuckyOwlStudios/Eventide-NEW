class_name ConfirmPrompt
extends Control
## The small yes/no box a [ConfirmationButton] opens. It frees itself once answered.

## Emitted once, with the player's answer, just before the prompt frees itself.
signal answered(yes: bool)

var message := "Are you sure?"

@onready var message_label: Label = %MessageLabel
@onready var yes_button: Button = %YesButton
@onready var no_button: Button = %NoButton

var _done := false


func _ready() -> void:
	message_label.text = message
	yes_button.pressed.connect(_answer.bind(true))
	no_button.pressed.connect(_answer.bind(false))
	# No is the safe default for a keyboard or controller player.
	no_button.grab_focus()


## Runs before the menus' own handlers, so Escape answers the prompt, not the pause menu.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_answer(false)


func _answer(yes: bool) -> void:
	if _done:
		return
	_done = true
	answered.emit(yes)
	queue_free()
