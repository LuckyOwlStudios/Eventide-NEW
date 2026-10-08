class_name LerpingAttributeBar
extends Control
## A reusable bar for any [AttributeNode], with delayed increase/decrease trails.

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
@export var icon: Texture2D
@export var icon_color := Color.WHITE
@export_range(8.0, 64.0, 1.0) var icon_size := 20.0
@export_range(0.0, 24.0, 1.0) var icon_gap := 8.0
@export_range(1.0, 24.0, 1.0) var bar_height := 8.0
@export var background_color := Color(0.035, 0.045, 0.06, 0.95)
@export_range(0.0, 3.0, 0.05) var follow_delay := 0.35
@export_range(0.01, 3.0, 0.05) var lerp_duration := 0.6

var main_ratio := 0.0:
	set(new_ratio):
		main_ratio = clampf(new_ratio, 0.0, 1.0)
		queue_redraw()
var secondary_ratio := 0.0:
	set(new_ratio):
		secondary_ratio = clampf(new_ratio, 0.0, 1.0)
		queue_redraw()

var _target_ratio := 0.0
var _secondary_color := Color.WHITE
var _pending_direction := AnimationDirection.NONE
var _delay_timer: Timer
var _follow_tween: Tween


func _ready() -> void:
	_delay_timer = Timer.new()
	_delay_timer.one_shot = true
	_delay_timer.timeout.connect(_begin_follow_animation)
	add_child(_delay_timer)
	_connect_attribute()
	call_deferred("_sync_immediately")


func _exit_tree() -> void:
	_disconnect_attribute()
	_stop_animation()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return

	var resolved_icon_size := minf(icon_size, size.y) if icon else 0.0
	var reserved_icon_width := resolved_icon_size + icon_gap if icon else 0.0
	var bar_width := maxf(size.x - reserved_icon_width, 0.0)
	var resolved_bar_height := minf(bar_height, size.y)
	var bar_position := Vector2(0.0, (size.y - resolved_bar_height) * 0.5)
	var bar_size := Vector2(bar_width, resolved_bar_height)
	draw_rect(Rect2(bar_position, bar_size), background_color)
	draw_rect(
		Rect2(bar_position, Vector2(bar_size.x * secondary_ratio, bar_size.y)),
		_secondary_color,
	)
	draw_rect(
		Rect2(bar_position, Vector2(bar_size.x * main_ratio, bar_size.y)),
		_get_main_color(main_ratio),
	)
	if icon:
		var icon_position := Vector2(
			bar_width + icon_gap,
			(size.y - resolved_icon_size) * 0.5,
		)
		draw_texture_rect(
			icon,
			Rect2(icon_position, Vector2.ONE * resolved_icon_size),
			false,
			icon_color,
		)

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
	_secondary_color = increase_color
	queue_redraw()


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

	if _target_ratio < previous_target:
		_pending_direction = AnimationDirection.DECREASE
		_secondary_color = decrease_color
		secondary_ratio = maxf(secondary_ratio, previous_target)
		main_ratio = _target_ratio
	else:
		_pending_direction = AnimationDirection.INCREASE
		_secondary_color = increase_color
		secondary_ratio = _target_ratio

	queue_redraw()
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
