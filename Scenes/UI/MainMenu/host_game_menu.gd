class_name HostGameMenu
extends Control
## Lists the world slots. Choosing one asks the main menu to host that world.

signal world_chosen(slot: int)
signal closed

const CARD_SCENE := preload("res://Scenes/UI/MainMenu/WorldSlotCard.tscn")

@onready var slot_list: VBoxContainer = %SlotList
@onready var description_label: Label = %DescriptionLabel
@onready var back_hint: Button = %BackHint

var _default_description := "Choose a world to host."


func _ready() -> void:
	back_hint.pressed.connect(close)
	hide()


func open() -> void:
	_rebuild_slots()
	set_description(_default_description)
	show()
	var first := slot_list.get_child(0) as Button if slot_list.get_child_count() > 0 else back_hint
	first.call_deferred("grab_focus")


func close() -> void:
	hide()
	closed.emit()


## Shows [param text] in the description line, for messages such as a failed start.
func set_description(text: String) -> void:
	description_label.text = text


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _rebuild_slots() -> void:
	for card in slot_list.get_children():
		slot_list.remove_child(card)
		card.queue_free()
	var cards: Array[WorldSlotCard] = []
	for info in WorldSaves.list_slots():
		var card := CARD_SCENE.instantiate() as WorldSlotCard
		slot_list.add_child(card)
		card.setup(info)
		card.description_requested.connect(set_description)
		card.pressed.connect(world_chosen.emit.bind(info["slot"]))
		cards.append(card)
	# Focus wraps from the last card to the first, as in the pause menu.
	for index in cards.size():
		var previous := cards[(index - 1 + cards.size()) % cards.size()]
		var next := cards[(index + 1) % cards.size()]
		cards[index].focus_neighbor_top = cards[index].get_path_to(previous)
		cards[index].focus_neighbor_bottom = cards[index].get_path_to(next)
