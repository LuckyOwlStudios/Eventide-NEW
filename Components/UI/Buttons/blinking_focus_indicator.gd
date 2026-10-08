class_name BlinkingFocusIndicator
extends Control
## Draws a blinking selector for its parent button while that button is focused.

@export_category("Indicator")
@export var color := Color.WHITE
@export var indicator_size := Vector2(8.0, 18.0)
@export var left_offset := 5.0
@export_range(0.1, 2.0, 0.05, "suffix:s") var blink_interval := 0.55

var _button: BaseButton
var _blink_elapsed := 0.0
var _indicator_visible := true
var _active := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var parent := get_parent()
	if not parent is BaseButton:
		push_error("BlinkingFocusIndicator must be a child of a BaseButton.")
		return

	_button = parent as BaseButton
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_button.resized.connect(queue_redraw)
	set_process(false)
	_button.mouse_entered.connect(_on_button_mouse_entered)
	_button.mouse_exited.connect(_sync_with_button)
	_button.focus_entered.connect(_sync_with_button)
	_button.focus_exited.connect(_sync_with_button)
	_sync_with_button()


func _process(delta: float) -> void:
	_blink_elapsed += delta
	if _blink_elapsed < blink_interval:
		return

	_blink_elapsed = fmod(_blink_elapsed, blink_interval)
	_indicator_visible = not _indicator_visible
	queue_redraw()


func _draw() -> void:
	if not _active or not _indicator_visible:
		return

	var indicator_position := Vector2(
		left_offset,
		floorf((size.y - indicator_size.y) * 0.5),
	)
	draw_rect(Rect2(indicator_position, indicator_size), color)


func _on_button_mouse_entered() -> void:
	# Keep mouse and keyboard/controller selection in sync.
	_button.grab_focus()
	_sync_with_button()


func _sync_with_button() -> void:
	var should_be_active := _button != null and (
		_button.is_hovered() or _button.has_focus()
	)
	if should_be_active == _active:
		return

	_active = should_be_active
	_blink_elapsed = 0.0
	_indicator_visible = true
	set_process(_active)
	queue_redraw()
