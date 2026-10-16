class_name WorldSlotCard
extends Button
## One world slot in the host menu: a saved world to continue, or an empty slot for a new one.

signal description_requested(text: String)

@onready var number_label: Label = %NumberLabel
@onready var name_label: Label = %NameLabel
@onready var detail_label: Label = %DetailLabel
@onready var tag_label: Label = %TagLabel
## How many jumps the world's ship has made. Shown for a saved world only.
@onready var jump_box: Control = %JumpBox
@onready var jump_label: Label = %JumpLabel

var slot := 0
var _description := ""


func _ready() -> void:
	mouse_entered.connect(grab_focus)
	mouse_entered.connect(_request_description)
	focus_entered.connect(_request_description)


## [param info] is an entry of [method WorldSaves.list_slots].
func setup(info: Dictionary) -> void:
	slot = info["slot"]
	number_label.text = "%02d" % slot
	jump_box.hide()
	if info["corrupt"]:
		name_label.text = "UNREADABLE SAVE"
		detail_label.text = "This slot's data could not be read."
		tag_label.text = ""
		disabled = true
		_description = "Slot %d holds a save that cannot be loaded, so it cannot be used." % slot
	elif info["exists"]:
		name_label.text = info["name"]
		var played := WorldSaves.format_time(info["last_played"])
		detail_label.text = "Last played %s" % played if not played.is_empty() else "Saved world"
		tag_label.text = "CONTINUE"
		jump_label.text = str(info.get("jump_count", 0))
		jump_box.show()
		disabled = false
		_description = "Continue %s, at jump %d, and open it to your lobby." % [info["name"], info.get("jump_count", 0)]
	else:
		name_label.text = "EMPTY SLOT"
		detail_label.text = "No world saved here yet"
		tag_label.text = "NEW WORLD"
		disabled = false
		_description = "Start a new world in slot %d and open it to your lobby." % slot


func _request_description() -> void:
	description_requested.emit(_description)
