class_name LerpingAttributeBar
extends PanelContainer
## A reusable bar for any [AttributeNode], with delayed increase/decrease trails.
## The front ProgressBar shows the main ratio, the one behind it shows the trail.

enum AnimationDirection {
	NONE,
	INCREASE,
	DECREASE,
}

@export var attribute_node: AttributeNode:
	set(new_attribute):
		_disconnect_attribute()
		attribute_node = new_attribute
		if is_node_ready():
			_connect_attribute()
			_sync_immediately()
@export var increase_color := Color(0.2, 0.9, 0.35)
@export var decrease_color := Color(0.95, 0.15, 0.12)
@export var bar_gradient: Gradient
@export var icon: Texture2D:
	set(new_icon):
		icon = new_icon
		_apply_icon()
@export var icon_color := Color.WHITE:
	set(new_color):
		icon_color = new_color
		_apply_icon()
@export_range(0.0, 3.0, 0.05) var follow_delay := 0.35
@export_range(0.01, 3.0, 0.05) var lerp_duration := 0.6
@export_group("Hide When Full")
@export var hide_when_full := true:
	set(value):
		hide_when_full = value
		if is_node_ready():
			_update_visibility(true)
@export_range(0.0, 10.0, 0.1) var hide_delay := 1.0
@export_range(0.0, 3.0, 0.05) var fade_duration := 0.4

var main_ratio := 0.0:
	set(new_ratio):
		main_ratio = clampf(new_ratio, 0.0, 1.0)
		_apply_ratios()
var secondary_ratio := 0.0:
	set(new_ratio):
		secondary_ratio = clampf(new_ratio, 0.0, 1.0)
		_apply_ratios()

var _target_ratio := 0.0
var _pending_direction := AnimationDirection.NONE
var _delay_timer: Timer
var _follow_tween: Tween
var _fade_tween: Tween
var _secondary_style: StyleBoxFlat

@onready var _icon_holder: Control = $HBoxContainer/MarginContainer
@onready var _icon_rect: TextureRect = $HBoxContainer/MarginContainer/TextureRect
@onready var _secondary_bar: ProgressBar = %LerpProgressBar
@onready var _main_bar: ProgressBar = %ProgressBar


func _ready() -> void:
	# The scene's fill style is a shared resource, so the trail gets its own copy to tint.
	_secondary_style = _secondary_bar.get_theme_stylebox("fill").duplicate()
	_secondary_bar.add_theme_stylebox_override("fill", _secondary_style)
	_delay_timer = Timer.new()
	_delay_timer.one_shot = true
	_delay_timer.timeout.connect(_begin_follow_animation)
	add_child(_delay_timer)
	_apply_icon()
	_connect_attribute()
	call_deferred("_sync_immediately")


func _exit_tree() -> void:
	_disconnect_attribute()
	_stop_animation()


func _apply_icon() -> void:
	if _icon_rect == null:
		return
	_icon_rect.texture = icon
	_icon_rect.modulate = icon_color
	_icon_holder.visible = icon != null


func _apply_ratios() -> void:
	if _main_bar == null:
		return
	_main_bar.value = main_ratio * _main_bar.max_value
	_main_bar.self_modulate = _get_main_color(main_ratio)
	_secondary_bar.value = secondary_ratio * _secondary_bar.max_value


func _set_secondary_color(color: Color) -> void:
	if _secondary_style:
		_secondary_style.bg_color = color
		_secondary_style.border_color = color


func _connect_attribute() -> void:
	if attribute_node == null:
		return
	if not attribute_node.value_changed.is_connected(_on_attribute_value_changed):
		attribute_node.value_changed.connect(_on_attribute_value_changed)


func _disconnect_attribute() -> void:
	if attribute_node == null:
		return
	if attribute_node.value_changed.is_connected(_on_attribute_value_changed):
		attribute_node.value_changed.disconnect(_on_attribute_value_changed)


func _sync_immediately() -> void:
	_stop_animation()
	_target_ratio = attribute_node.get_percentage() if attribute_node else 0.0
	main_ratio = _target_ratio
	secondary_ratio = _target_ratio
	_set_secondary_color(increase_color)
	_update_visibility(true)


func _on_attribute_value_changed(
	_previous_value: float,
	_current_value: float,
	_change_amount: float,
) -> void:
	if attribute_node == null:
		return
	animate_to(attribute_node.get_percentage())


func animate_to(new_ratio: float) -> void:
	var clamped_ratio := clampf(new_ratio, 0.0, 1.0)
	if is_equal_approx(clamped_ratio, _target_ratio):
		return

	var previous_target := _target_ratio
	_target_ratio = clamped_ratio
	_stop_animation()
	if _target_ratio < 1.0:
		_update_visibility()

	if _target_ratio < previous_target:
		_pending_direction = AnimationDirection.DECREASE
		_set_secondary_color(decrease_color)
		secondary_ratio = maxf(secondary_ratio, previous_target)
		main_ratio = _target_ratio
	else:
		_pending_direction = AnimationDirection.INCREASE
		_set_secondary_color(increase_color)
		secondary_ratio = _target_ratio

	if follow_delay <= 0.0:
		_begin_follow_animation()
	else:
		_delay_timer.start(follow_delay)


func _begin_follow_animation() -> void:
	if _pending_direction == AnimationDirection.NONE:
		return
	_follow_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _pending_direction == AnimationDirection.DECREASE:
		_follow_tween.tween_property(self, "secondary_ratio", _target_ratio, lerp_duration)
	else:
		_follow_tween.tween_property(self, "main_ratio", _target_ratio, lerp_duration)
	_follow_tween.finished.connect(_on_follow_animation_finished)


func _on_follow_animation_finished() -> void:
	main_ratio = _target_ratio
	secondary_ratio = _target_ratio
	_pending_direction = AnimationDirection.NONE
	_follow_tween = null
	_update_visibility()


func _stop_animation() -> void:
	if _delay_timer:
		_delay_timer.stop()
	if _follow_tween and _follow_tween.is_valid():
		_follow_tween.kill()
	_follow_tween = null
	_pending_direction = AnimationDirection.NONE


func _get_main_color(ratio: float) -> Color:
	if bar_gradient:
		return bar_gradient.sample(clampf(ratio, 0.0, 1.0))
	return Color.WHITE


## Shows the bar while the attribute is below full and fades it out once it has been full for [member hide_delay].
func _update_visibility(instant := false) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
	if not hide_when_full or _target_ratio < 1.0:
		modulate.a = 1.0
	elif instant:
		modulate.a = 0.0
	else:
		_fade_tween = create_tween()
		_fade_tween.tween_interval(hide_delay)
		_fade_tween.tween_property(self, "modulate:a", 0.0, fade_duration)
