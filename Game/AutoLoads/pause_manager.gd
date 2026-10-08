extends CanvasLayer
## Global owner for pause input and UI. Gameplay scenes opt in through the
## "gameplay_scene" group; temporary systems can independently block pausing.

signal pause_opened
signal pause_closed
signal pause_permission_changed(is_permitted: bool, reasons: Array[String])

const GAMEPLAY_SCENE_GROUP: StringName = &"gameplay_scene"
const OUTSIDE_GAMEPLAY_BLOCKER_ID := -1

## Public for permission queries. Use add_pause_blocker/remove_pause_blocker so
## an open menu is closed and permission signals remain accurate.
var can_pause := ActionBlocker.new()

@onready var pause_menu: PauseMenu = $PauseMenu

var _tree_paused_by_manager := false
var _mouse_mode_before_open := Input.MOUSE_MODE_VISIBLE

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	can_pause.add(OUTSIDE_GAMEPLAY_BLOCKER_ID, "Not in a gameplay scene.")
	pause_menu.resume_requested.connect(close)
	pause_menu.quit_requested.connect(get_tree().quit)
	get_tree().scene_changed.connect(_on_scene_changed)
	pause_menu.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	call_deferred("_sync_current_scene")

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel") or event.is_echo():
		return
	if pause_menu.is_settings_open():
		return
	if pause_menu.visible:
		get_viewport().set_input_as_handled()
		close()
	elif can_pause.is_permitted():
		get_viewport().set_input_as_handled()
		open()

func open() -> bool:
	if pause_menu.visible or not can_pause.is_permitted():
		return false
	_mouse_mode_before_open = Input.mouse_mode
	UIEffects.show_effects(self)
	pause_menu.open()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not NetworkSession.has_remote_peers() and not get_tree().paused:
		get_tree().paused = true
		_tree_paused_by_manager = true
	pause_opened.emit()
	return true

func close() -> void:
	var was_open := pause_menu.visible
	pause_menu.close()
	if was_open:
		UIEffects.hide_effects(self)
	if _tree_paused_by_manager:
		get_tree().paused = false
		_tree_paused_by_manager = false
	if _is_gameplay_scene(get_tree().current_scene):
		Input.mouse_mode = _mouse_mode_before_open
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if was_open:
		pause_closed.emit()

## Registers a reason pausing is unavailable. Pass the blocking object as source;
## using its instance ID lets that same object remove only its own blocker.
func add_pause_blocker(source: Object, reason: String) -> void:
	if source == null:
		push_warning("PauseManager.add_pause_blocker requires a source object.")
		return
	_set_blocker(source.get_instance_id(), reason, true)

func remove_pause_blocker(source: Object) -> void:
	if source == null:
		return
	_set_blocker(source.get_instance_id(), "", false)

func is_pause_permitted() -> bool:
	return can_pause.is_permitted()

func get_pause_blocker_reasons() -> Array[String]:
	return can_pause.get_reasons()

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
		close()
	if is_permitted != was_permitted:
		pause_permission_changed.emit(is_permitted, can_pause.get_reasons())

func _is_gameplay_scene(scene: Node) -> bool:
	return is_instance_valid(scene) and scene.is_in_group(GAMEPLAY_SCENE_GROUP)
