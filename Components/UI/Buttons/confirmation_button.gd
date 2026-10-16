class_name ConfirmationButton
extends Button
## A button that asks "are you sure?" before it does anything. Connect to [signal confirmed]
## instead of [signal Button.pressed]: that only fires if the player answers yes.

## The player said yes.
signal confirmed
## The player said no or pressed Escape.
signal cancelled

const PROMPT_SCENE := preload("res://Components/UI/Buttons/ConfirmPrompt.tscn")

## What the prompt asks.
@export_multiline var confirmation_message := "Are you sure?"

var _prompt: ConfirmPrompt


func _ready() -> void:
	pressed.connect(open_prompt)


## Shows the prompt. Does nothing while one is already showing.
func open_prompt() -> void:
	if is_instance_valid(_prompt):
		return
	_prompt = PROMPT_SCENE.instantiate() as ConfirmPrompt
	_prompt.message = confirmation_message
	_prompt.answered.connect(_on_answered)
	# Join the closest canvas layer so the prompt draws above the menu this button is in.
	var parent: Node = get_tree().root
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor is CanvasLayer:
			parent = ancestor
			break
		ancestor = ancestor.get_parent()
	parent.add_child(_prompt)


func _exit_tree() -> void:
	if is_instance_valid(_prompt):
		_prompt.queue_free()


func _on_answered(yes: bool) -> void:
	_prompt = null
	if yes:
		confirmed.emit()
	else:
		cancelled.emit()
		if is_inside_tree():
			grab_focus()
