extends Node
## Global owner for in-game interfaces, pause/settings, blur, and dimming.

signal pause_opened
signal pause_closed
signal pause_permission_changed(is_permitted: bool, reasons: Array[String])
signal in_game_ui_opened(ui: Control)
signal in_game_ui_closed(ui: Control)
signal ui_open_state_changed(is_open: bool)

const GAMEPLAY_SCENE_GROUP: StringName = &"gameplay_scene"
const IN_GAME_UI_GROUP: StringName = &"in_game_ui"
const OUTSIDE_GAMEPLAY_BLOCKER_ID := -1

## True while the pause/settings layer or any registered in-game UI is open.
var is_ui_open := false
## Public for permission queries. Use add_pause_blocker/remove_pause_blocker.
var can_pause := ActionBlocker.new()

@onready var blur: BlurOverlay = %Blur
@onready var dimmer: DimmerOverlay = %Dimmer
@onready var in_game_ui_root: Control = %InGameUIRoot
@onready var pause_menu: PauseMenu = %PauseMenu

var _managed_uis: Dictionary[int, Dictionary] = {}
var _open_in_game_ui_ids: Dictionary[int, bool] = {}
var _pause_hidden_ui_ids: Array[int] = []
var _effect_requesters: Dictionary[int, WeakRef] = {}
var _suppress_visibility_sync := false
var _tree_paused_by_handler := false
var _mouse_mode_before_pause := Input.MOUSE_MODE_VISIBLE
var _mouse_mode_before_in_game_ui := Input.MOUSE_MODE_CAPTURED
var _has_in_game_ui_mouse_mode := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	can_pause.add(OUTSIDE_GAMEPLAY_BLOCKER_ID, "Not in a gameplay scene.")
	pause_menu.resume_requested.connect(close_pause)
	pause_menu.quit_requested.connect(get_tree().quit)
	get_tree().scene_changed.connect(_on_scene_changed)
	get_tree().node_added.connect(_on_node_added)
	blur.set_blur_immediate(0.0)
	dimmer.set_dim_immediate(0.0)
	pause_menu.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	call_deferred("_sync_current_scene")
	call_deferred("_register_grouped_in_game_uis")
	_refresh_ui_open_state()
	Settings.setting_changed.connect(_setting_changed)

func _setting_changed(id: StringName, value: Variant):
	if id == "":
		pass

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel") or event.is_echo():
		return
	if pause_menu.is_settings_open():
		return
	if pause_menu.visible:
		get_viewport().set_input_as_handled()
		close_pause()
	elif can_pause.is_permitted():
		get_viewport().set_input_as_handled()
		open_pause()

func open_pause() -> bool:
	if pause_menu.visible or not can_pause.is_permitted():
		return false
	_mouse_mode_before_pause = Input.mouse_mode
	show_effects(self)
	_suspend_open_in_game_uis()
	pause_menu.open()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not NetworkSession.has_remote_peers() and not get_tree().paused:
		get_tree().paused = true
		_tree_paused_by_handler = true
	pause_opened.emit()
	_refresh_ui_open_state()
	return true

func close_pause() -> void:
	var was_open := pause_menu.visible
	pause_menu.close()
	if was_open:
		_restore_suspended_in_game_uis()
		hide_effects(self)
	if _tree_paused_by_handler:
		get_tree().paused = false
		_tree_paused_by_handler = false
	_restore_mouse_mode()
	if was_open:
		pause_closed.emit()
	_refresh_ui_open_state()

## Compatibility names for callers that treat this as a pause controller.
func open() -> bool:
	return open_pause()

func close() -> void:
	close_pause()

## Adds an interface to the dedicated layer and opens it. Interfaces already in
## the scene tree are registered in place; add them to the in_game_ui group when
## they should be discovered automatically.
func open_in_game_ui(ui: Control, use_effects := true) -> bool:
	if not is_instance_valid(ui):
		return false
	if ui.get_parent() == null:
		in_game_ui_root.add_child(ui)
	register_in_game_ui(ui, use_effects)
	_set_in_game_ui_open(ui.get_instance_id(), true)
	if pause_menu.visible:
		if ui.get_instance_id() not in _pause_hidden_ui_ids:
			_pause_hidden_ui_ids.append(ui.get_instance_id())
		_set_ui_visible_without_sync(ui, false)
	else:
		ui.show()
	return true

func close_in_game_ui(ui: Control) -> void:
	if not is_instance_valid(ui):
		return
	_set_in_game_ui_open(ui.get_instance_id(), false)
	_set_ui_visible_without_sync(ui, false)

func register_in_game_ui(ui: Control, use_effects := true) -> void:
	if not is_instance_valid(ui):
		push_warning("InGameUIHandler.register_in_game_ui requires a valid Control.")
		return
	var ui_id := ui.get_instance_id()
	if _managed_uis.has(ui_id):
		var existing: Dictionary = _managed_uis[ui_id]
		var previously_used_effects := bool(existing.get("use_effects", true))
		existing["use_effects"] = use_effects
		_managed_uis[ui_id] = existing
		if previously_used_effects and not use_effects:
			hide_effects(ui)
		_sync_registered_ui(ui_id)
		return
	_managed_uis[ui_id] = {
		"reference": weakref(ui),
		"use_effects": use_effects,
	}
	var visibility_callback := _on_registered_ui_visibility_changed.bind(ui_id)
	if not ui.visibility_changed.is_connected(visibility_callback):
		ui.visibility_changed.connect(visibility_callback)
	var exit_callback := _on_registered_ui_exited.bind(ui_id)
	if not ui.tree_exited.is_connected(exit_callback):
		ui.tree_exited.connect(exit_callback, CONNECT_ONE_SHOT)
	_sync_registered_ui(ui_id)

func unregister_in_game_ui(ui: Control) -> void:
	if not is_instance_valid(ui):
		return
	var ui_id := ui.get_instance_id()
	_set_in_game_ui_open(ui_id, false)
	_managed_uis.erase(ui_id)
	_pause_hidden_ui_ids.erase(ui_id)

func is_in_game_ui_open(ui: Control) -> bool:
	return is_instance_valid(ui) and _open_in_game_ui_ids.has(ui.get_instance_id())

func get_open_in_game_uis() -> Array[Control]:
	var result: Array[Control] = []
	for ui_id in _open_in_game_ui_ids.keys():
		var ui := _get_managed_ui(ui_id)
		if is_instance_valid(ui):
			result.append(ui)
	return result

func show_effects(requester: Node, duration := -1.0) -> void:
	_prune_effect_requesters()
	if is_instance_valid(requester):
		var requester_id := requester.get_instance_id()
		if not _effect_requesters.has(requester_id):
			_effect_requesters[requester_id] = weakref(requester)
			var exit_callback := _on_effect_requester_exited.bind(requester_id)
			if not requester.tree_exited.is_connected(exit_callback):
				requester.tree_exited.connect(exit_callback, CONNECT_ONE_SHOT)
	blur.fade_in(blur.fade_duration if duration < 0.0 else duration)
	dimmer.fade_in(dimmer.fade_duration if duration < 0.0 else duration)

func hide_effects(requester: Node, duration := -1.0) -> void:
	if is_instance_valid(requester):
		_effect_requesters.erase(requester.get_instance_id())
	_prune_effect_requesters()
	if not _effect_requesters.is_empty():
		return
	blur.fade_out(blur.fade_duration if duration < 0.0 else duration)
	dimmer.fade_out(dimmer.fade_duration if duration < 0.0 else duration)

func clear_effects(duration := 0.0) -> void:
	_effect_requesters.clear()
	blur.fade_out(duration)
	dimmer.fade_out(duration)

func add_pause_blocker(source: Object, reason: String) -> void:
	if source == null:
		push_warning("InGameUIHandler.add_pause_blocker requires a source object.")
		return
	_set_blocker(source.get_instance_id(), reason, true)

func remove_pause_blocker(source: Object) -> void:
	if source != null:
		_set_blocker(source.get_instance_id(), "", false)

func is_pause_permitted() -> bool:
	return can_pause.is_permitted()

func get_pause_blocker_reasons() -> Array[String]:
	return can_pause.get_reasons()

func _sync_registered_ui(ui_id: int) -> void:
	if _suppress_visibility_sync:
		return
	var ui := _get_managed_ui(ui_id)
	if not is_instance_valid(ui):
		_on_registered_ui_exited(ui_id)
		return
	var ui_is_visible := ui.is_visible_in_tree()
	if pause_menu.visible and ui_is_visible:
		_set_in_game_ui_open(ui_id, true)
		if ui_id not in _pause_hidden_ui_ids:
			_pause_hidden_ui_ids.append(ui_id)
		hide_effects(ui)
		_set_ui_visible_without_sync(ui, false)
		return
	_set_in_game_ui_open(ui_id, ui_is_visible)

func _set_in_game_ui_open(ui_id: int, open_state: bool) -> void:
	var was_open := _open_in_game_ui_ids.has(ui_id)
	if open_state:
		_open_in_game_ui_ids[ui_id] = true
		if not was_open:
			if _open_in_game_ui_ids.size() == 1 and not pause_menu.visible:
				_mouse_mode_before_in_game_ui = Input.mouse_mode
				_has_in_game_ui_mouse_mode = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			var opened_ui := _get_managed_ui(ui_id)
			if is_instance_valid(opened_ui):
				in_game_ui_opened.emit(opened_ui)
		if not pause_menu.visible and _managed_ui_uses_effects(ui_id):
			var effect_ui := _get_managed_ui(ui_id)
			if is_instance_valid(effect_ui):
				show_effects(effect_ui)
	elif was_open:
		_open_in_game_ui_ids.erase(ui_id)
		_pause_hidden_ui_ids.erase(ui_id)
		var closed_ui := _get_managed_ui(ui_id)
		if is_instance_valid(closed_ui):
			hide_effects(closed_ui)
			in_game_ui_closed.emit(closed_ui)
		if _open_in_game_ui_ids.is_empty() and not pause_menu.visible:
			_restore_mouse_mode()
	_refresh_ui_open_state()

func _suspend_open_in_game_uis() -> void:
	_pause_hidden_ui_ids.clear()
	for ui_id in _open_in_game_ui_ids.keys():
		var ui := _get_managed_ui(ui_id)
		if not is_instance_valid(ui) or not ui.is_visible_in_tree():
			continue
		_pause_hidden_ui_ids.append(ui_id)
		hide_effects(ui)
		_set_ui_visible_without_sync(ui, false)

func _restore_suspended_in_game_uis() -> void:
	for ui_id in _pause_hidden_ui_ids:
		if not _open_in_game_ui_ids.has(ui_id):
			continue
		var ui := _get_managed_ui(ui_id)
		if not is_instance_valid(ui):
			continue
		_set_ui_visible_without_sync(ui, true)
		if _managed_ui_uses_effects(ui_id):
			show_effects(ui)
	_pause_hidden_ui_ids.clear()

func _set_ui_visible_without_sync(ui: Control, visible_state: bool) -> void:
	_suppress_visibility_sync = true
	ui.visible = visible_state
	_suppress_visibility_sync = false

func _get_managed_ui(ui_id: int) -> Control:
	if not _managed_uis.has(ui_id):
		return null
	var reference: WeakRef = _managed_uis[ui_id].get("reference")
	return reference.get_ref() as Control if reference != null else null

func _managed_ui_uses_effects(ui_id: int) -> bool:
	return _managed_uis.has(ui_id) and bool(_managed_uis[ui_id].get("use_effects", true))

func _on_registered_ui_visibility_changed(ui_id: int) -> void:
	_sync_registered_ui(ui_id)

func _on_registered_ui_exited(ui_id: int) -> void:
	var was_open := _open_in_game_ui_ids.has(ui_id)
	_open_in_game_ui_ids.erase(ui_id)
	_pause_hidden_ui_ids.erase(ui_id)
	_effect_requesters.erase(ui_id)
	_managed_uis.erase(ui_id)
	if was_open:
		_refresh_effects_after_requester_removed()
	_refresh_ui_open_state()

func _on_node_added(node: Node) -> void:
	if node is Control and node.is_in_group(IN_GAME_UI_GROUP):
		call_deferred("register_in_game_ui", node as Control)

func _register_grouped_in_game_uis() -> void:
	for node in get_tree().get_nodes_in_group(IN_GAME_UI_GROUP):
		if node is Control:
			register_in_game_ui(node)

func _refresh_ui_open_state() -> void:
	var next_state := pause_menu.visible or not _open_in_game_ui_ids.is_empty()
	if is_ui_open == next_state:
		return
	is_ui_open = next_state
	ui_open_state_changed.emit(is_ui_open)

func _restore_mouse_mode() -> void:
	if not _open_in_game_ui_ids.is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if _has_in_game_ui_mouse_mode:
		Input.mouse_mode = _mouse_mode_before_in_game_ui
		_has_in_game_ui_mouse_mode = false
	elif _is_gameplay_scene(get_tree().current_scene):
		Input.mouse_mode = _mouse_mode_before_pause
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_effect_requester_exited(requester_id: int) -> void:
	_effect_requesters.erase(requester_id)
	_refresh_effects_after_requester_removed()

func _prune_effect_requesters() -> void:
	for requester_id in _effect_requesters.keys():
		var requester_ref: WeakRef = _effect_requesters[requester_id]
		if requester_ref.get_ref() == null:
			_effect_requesters.erase(requester_id)

func _refresh_effects_after_requester_removed() -> void:
	_prune_effect_requesters()
	if _effect_requesters.is_empty() and is_inside_tree():
		blur.fade_out()
		dimmer.fade_out()

func _sync_current_scene() -> void:
	_on_scene_changed(get_tree().current_scene)

func _on_scene_changed(scene: Node) -> void:
	_set_blocker(
		OUTSIDE_GAMEPLAY_BLOCKER_ID,
		"Not in a gameplay scene.",
		not _is_gameplay_scene(scene),
	)

func _set_blocker(id: int, reason: String, blocked: bool) -> void:
	var was_permitted := can_pause.is_permitted()
	if blocked:
		can_pause.add(id, reason)
	else:
		can_pause.remove(id)
	var is_permitted := can_pause.is_permitted()
	if not is_permitted and pause_menu.visible:
		close_pause()
	if is_permitted != was_permitted:
		pause_permission_changed.emit(is_permitted, can_pause.get_reasons())

func _is_gameplay_scene(scene: Node) -> bool:
	return is_instance_valid(scene) and scene.is_in_group(GAMEPLAY_SCENE_GROUP)
