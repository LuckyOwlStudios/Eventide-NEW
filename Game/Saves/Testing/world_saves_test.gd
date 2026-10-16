extends Node
## Checks what a world's save holds: its name and times, and the jump count and seed that carry the
## game from one session to the next, plus how they appear on the world card in the host menu.
##
## godot --headless --fixed-fps 60 --path . res://Game/Saves/Testing/WorldSavesTest.tscn

const CARD_SCENE := preload("res://Scenes/UI/MainMenu/WorldSlotCard.tscn")

var _failures := 0
var _test_root := ""


func _ready() -> void:
	_test_root = "user://world_saves_test_%d" % Time.get_ticks_usec()
	WorldSaves.root = _test_root
	_test_jump_and_seed()
	_test_legacy_and_damage()
	await _test_card()
	_remove_dir(_test_root)
	WorldSaves.root = "user://worlds"
	if _failures == 0:
		print("World saves tests passed.")
	else:
		print("World saves tests FAILED: %d check(s)." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _test_jump_and_seed() -> void:
	print("Jump count and seed")
	var first := WorldSaves.create_world(1, "Alpha")
	var second := WorldSaves.create_world(2, "Beta")
	_check(first["jump_count"] == 0, "a new world is at jump 0")
	_check(first["world_seed"] > 0 and first["world_seed"] < (1 << 52), "and has a seed (%d), small enough to stay exact in JSON" % first["world_seed"])
	_check(first["world_seed"] != second["world_seed"], "every world has a seed of its own")
	_check(WorldSaves.read_slot(1)["world_seed"] == first["world_seed"], "which is saved")
	var seeds := {}
	for _i in 200:
		seeds[WorldSaves.new_world_seed()] = true
	_check(seeds.size() == 200, "and new seeds do not repeat")

	_check(WorldSaves.record_jump(1, 7), "a jump is recorded")
	var jumped := WorldSaves.read_slot(1)
	_check(jumped["jump_count"] == 7, "and read back (%d)" % jumped["jump_count"])
	_check(jumped["name"] == "Alpha" and jumped["created"] == first["created"] and jumped["world_seed"] == first["world_seed"], "without disturbing the name, the date or the seed")
	WorldSaves.mark_played(1)
	var played := WorldSaves.read_slot(1)
	_check(played["jump_count"] == 7 and played["world_seed"] == first["world_seed"] and played["name"] == "Alpha", "and playing the world again keeps the jump count and the seed")
	_check(WorldSaves.record_jump(1, 8) and WorldSaves.read_slot(1)["jump_count"] == 8, "every jump updates it")
	_check(WorldSaves.record_jump(1, -3) and WorldSaves.read_slot(1)["jump_count"] == 0, "a count below zero is kept at zero")
	_check(not WorldSaves.record_jump(3, 4) and not WorldSaves.read_slot(3)["exists"], "a jump cannot be recorded in an empty slot, and does not make one")
	_check(not WorldSaves.record_jump(0, 4) and not WorldSaves.record_jump(9, 4), "or in a slot that does not exist")
	var raw := FileAccess.get_file_as_string("%s/slot_1/%s" % [_test_root, WorldSaves.META_FILE])
	_check(not raw.contains("jump_count\": 0.") and not raw.contains("e+"), "the numbers are written as whole numbers")
	_check(raw.contains("\"version\": %d" % WorldSaves.FORMAT_VERSION), "the save says which version of the format it is")

	print("The Cosmic Presence's bar")
	_check(is_equal_approx(WorldSaves.read_slot(1)["presence"], -1.0) and is_equal_approx(first["presence"], -1.0), "a world that has not saved the bar says -1")
	_check(WorldSaves.record_jump(1, 9, 0.4321987), "a jump records the bar too")
	var barred := WorldSaves.read_slot(1)
	_check(barred["jump_count"] == 9 and absf(barred["presence"] - 0.4322) < 0.00005, "and it is read back to four places (%.4f)" % barred["presence"])
	_check(barred["name"] == "Alpha" and barred["world_seed"] == first["world_seed"], "without disturbing the rest")
	WorldSaves.record_jump(1, 10)
	_check(absf(WorldSaves.read_slot(1)["presence"] - 0.4322) < 0.00005 and WorldSaves.read_slot(1)["jump_count"] == 10, "a jump recorded without a bar leaves the saved bar as it was")
	WorldSaves.record_jump(1, 10, 7.0)
	_check(is_equal_approx(WorldSaves.read_slot(1)["presence"], 1.0), "a bar above full is saved as full")
	WorldSaves.record_jump(1, 10, 0.0)
	_check(is_equal_approx(WorldSaves.read_slot(1)["presence"], 0.0), "and an empty bar is saved, and is not the same as none (0 against -1)")
	WorldSaves.mark_played(1)
	_check(is_equal_approx(WorldSaves.read_slot(1)["presence"], 0.0), "playing the world again keeps it")
	WorldSaves.record_jump(1, 12)

	# A seed near the top of what is allowed comes back exactly after being read and written again.
	var big := (1 << 52) - 1
	_write_text("%s/slot_4/%s" % [_test_root, WorldSaves.META_FILE], '{"version": 2, "name": "Big", "created": 5, "last_played": 6, "jump_count": 3, "world_seed": %d}' % big)
	_check(WorldSaves.read_slot(4)["world_seed"] == big, "a seed of 2^52 - 1 reads back exactly")
	WorldSaves.mark_played(4)
	_check(WorldSaves.read_slot(4)["world_seed"] == big and WorldSaves.read_slot(4)["jump_count"] == 3, "and survives being written again")
	WorldSaves.record_jump(4, 4)
	_check(WorldSaves.read_slot(4)["world_seed"] == big, "and another write after that")

	var listed := WorldSaves.list_slots()
	_check(listed[0]["jump_count"] == 12 and listed[1]["jump_count"] == 0 and listed[2]["jump_count"] == 0 and listed[3]["jump_count"] == 4, "the slot list carries every world's jump count")


func _test_legacy_and_damage() -> void:
	print("Older and damaged saves")
	_write_text("%s/slot_3/%s" % [_test_root, WorldSaves.META_FILE], '{"version": 1, "name": "Old", "created": 100, "last_played": 200, "future_field": {"a": [1, 2]}}')
	var old := WorldSaves.read_slot(3)
	_check(old["exists"] and not old["corrupt"] and old["jump_count"] == 0 and old["world_seed"] == 0, "a save from before there were jumps is at jump 0 with no seed yet")
	var seed_value := WorldSaves.ensure_world_seed(3)
	_check(seed_value > 0 and WorldSaves.read_slot(3)["world_seed"] == seed_value, "it is given one (%d) and that is saved" % seed_value)
	_check(WorldSaves.ensure_world_seed(3) == seed_value, "which it keeps when asked again")
	var after := WorldSaves.read_slot(3)
	_check(after["name"] == "Old" and after["created"] == 100 and after["last_played"] == 200, "nothing else about it changed")
	WorldSaves.record_jump(3, 2)
	var raw := FileAccess.get_file_as_string("%s/slot_3/%s" % [_test_root, WorldSaves.META_FILE])
	_check(raw.contains("future_field"), "and a field this version knows nothing about is not thrown away")

	_remove_dir(WorldSaves.slot_dir(2))
	_check(WorldSaves.ensure_world_seed(2) == 0, "an empty slot has no seed to ensure")
	_write_text("%s/slot_2/%s" % [_test_root, WorldSaves.META_FILE], "{ this is not json")
	_check(WorldSaves.ensure_world_seed(2) == 0 and not WorldSaves.record_jump(2, 5), "a damaged save gets neither a seed nor a jump")
	_check(FileAccess.get_file_as_string("%s/slot_2/%s" % [_test_root, WorldSaves.META_FILE]) == "{ this is not json", "and is left exactly as it was")
	var damaged := WorldSaves.read_slot(2)
	_check(damaged["corrupt"] and damaged["jump_count"] == 0, "it is still flagged as damaged")


func _test_card() -> void:
	print("The world card")
	var card := CARD_SCENE.instantiate() as WorldSlotCard
	add_child(card)
	await get_tree().process_frame
	card.setup(WorldSaves.read_slot(1))
	_check(card.jump_box.visible and card.jump_label.text == "12", "a saved world shows its jump count (%s)" % card.jump_label.text)
	_check(card.name_label.text == "Alpha" and card.tag_label.text == "CONTINUE" and card.detail_label.text.begins_with("Last played"), "beside its name, its time and CONTINUE")
	card.description_requested.connect(func(text: String) -> void: _description = text)
	card.focus_entered.emit()
	_check(_description.contains("jump 12"), "and its description says what jump it is at (%s)" % _description)
	card.setup(WorldSaves.read_slot(3))
	_check(card.jump_box.visible and card.jump_label.text == "2", "a world made before there were jumps shows its count too")
	_remove_dir(WorldSaves.slot_dir(2))
	card.setup(WorldSaves.read_slot(2))
	_check(not card.jump_box.visible and card.tag_label.text == "NEW WORLD", "an empty slot shows no jump count")
	_write_text("%s/slot_2/%s" % [_test_root, WorldSaves.META_FILE], "nope")
	card.setup(WorldSaves.read_slot(2))
	_check(not card.jump_box.visible and card.disabled, "and neither does a damaged one")
	card.setup(WorldSaves.read_slot(1))
	_check(card.jump_box.visible and not card.disabled, "and a card that is set up again shows what it should")
	card.queue_free()


var _description := ""


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)


func _remove_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	for dir_name in DirAccess.get_directories_at(path):
		_remove_dir(path.path_join(dir_name))
	DirAccess.remove_absolute(path)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)
