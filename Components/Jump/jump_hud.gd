class_name JumpHud
extends CanvasLayer
## What the jump loop looks like to the player: the jump count and the system's name and kind, the
## Cosmic Presence's bar (counting up, with a "x2" beside it when something has sped it up), a countdown
## across the screen while the drive charges, banners while the ship jumps and arrives, and a flash of
## light as the world changes behind the warp bubble.
##
## It reads a [JumpDirector] and changes nothing. The director it belongs to is its parent, or the
## first one in the [code]jump_director[/code] group.

## How long the "arrived" banner stays up.
const ARRIVAL_BANNER_TIME := 4.5
## The colors the bar goes through as the presence closes in.
const CALM_COLOR := Color(0.62, 0.8, 1.0)
const WARY_COLOR := Color(1.0, 0.78, 0.3)
const DANGER_COLOR := Color(1.0, 0.32, 0.26)
const MUTED_COLOR := Color(0.66, 0.67, 0.69)
const SLOWED_COLOR := Color(0.6, 0.85, 1.0)
const FLASH_COLOR := Color(0.78, 0.9, 1.0)
## How quickly the bar's fill catches up with the real value, a few times a second, so a jump's drop is a slide.
const FILL_FOLLOW_SPEED := 14.0
## The red trail behind a drop waits this long, then follows the fill down at this share of the bar a second.
const TRAIL_HOLD_TIME := 0.7
const TRAIL_FALL_SPEED := 0.4

@export var director: JumpDirector

@onready var top_panel: Control = %TopPanel
@onready var jump_label: Label = %JumpLabel
@onready var system_label: Label = %SystemLabel
@onready var climate_label: Label = %ClimateLabel
@onready var presence_title: Label = %PresenceTitle
@onready var presence_bar: ProgressBar = %PresenceBar
@onready var trail_bar: ProgressBar = %TrailBar
@onready var multiplier_label: Label = %MultiplierLabel
@onready var banner: Control = %Banner
@onready var banner_title: Label = %BannerTitle
@onready var banner_detail: Label = %BannerDetail
@onready var hint_label: Label = %HintLabel
@onready var flash: ColorRect = %Flash

var _arrival_banner_left := 0.0
var _flash_tween: Tween
var _multiplier_tween: Tween
var _fill_style: StyleBoxFlat
var _shown := 0.0
var _trail := 0.0
var _trail_hold := 0.0
var _shown_multiplier := 1.0
var _snap_next_frame := true


func _ready() -> void:
	flash.color = Color(FLASH_COLOR, 0.0)
	banner.hide()
	top_panel.hide()
	hint_label.hide()
	presence_bar.max_value = 100.0
	trail_bar.max_value = 100.0
	# The theme's fill is shared by every bar, so this bar gets a copy of its own to color.
	var fill := presence_bar.get_theme_stylebox(&"fill")
	_fill_style = fill.duplicate() as StyleBoxFlat if fill is StyleBoxFlat else StyleBoxFlat.new()
	presence_bar.add_theme_stylebox_override(&"fill", _fill_style)
	# The trail behind it is only a colored fill: its background would show through twice.
	trail_bar.add_theme_stylebox_override(&"background", StyleBoxEmpty.new())
	_connect_director.call_deferred()


## "x2", "x1.5", "x0.5": how many times its normal speed the presence is going, to one decimal and without a
## trailing zero.
static func format_multiplier(multiplier: float) -> String:
	var text := "%.1f" % snappedf(multiplier, 0.1)
	if text.ends_with(".0"):
		text = text.substr(0, text.length() - 2)
	return "x" + text


## The color of the presence's bar with it [param progress] of the way across: cool and calm, then amber, then red.
static func color_for_progress(progress: float) -> Color:
	var color := CALM_COLOR.lerp(WARY_COLOR, smoothstep(0.3, 0.7, progress))
	return color.lerp(DANGER_COLOR, smoothstep(0.7, 1.0, progress))


func _process(delta: float) -> void:
	if not is_instance_valid(director) or director.system == null:
		return
	_arrival_banner_left = maxf(_arrival_banner_left - delta, 0.0)
	_update_presence(delta)
	_update_banner()


func _connect_director() -> void:
	if not is_instance_valid(director):
		var parent := get_parent()
		director = parent as JumpDirector if parent is JumpDirector else get_tree().get_first_node_in_group(JumpDirector.GROUP) as JumpDirector
	if not is_instance_valid(director):
		return
	director.phase_changed.connect(_on_phase_changed)
	director.system_changed.connect(_on_system_changed)
	director.jump_completed.connect(_on_jump_completed)
	director.warning.connect(_on_warning)
	if is_instance_valid(director.presence):
		director.presence.speed_changed.connect(_on_speed_changed)
	hint_label.visible = director.debug_keys and OS.is_debug_build()
	if director.system != null:
		_on_system_changed(director.system)


func _on_system_changed(system: StarSystem) -> void:
	top_panel.show()
	jump_label.text = str(director.jump_count)
	system_label.text = system.system_name.to_upper()
	climate_label.text = system.get_description().to_upper()


func _on_phase_changed(phase: JumpDirector.Phase) -> void:
	match phase:
		JumpDirector.Phase.SWITCHING:
			# The world changes behind the bubble. A world that has just begun is not changing from anything.
			if not director.is_first_arrival():
				_flash(0.55, 0.9)
		JumpDirector.Phase.WARPING_IN:
			_flash(0.35, 1.0)


func _on_jump_completed(_jump_count: int) -> void:
	_arrival_banner_left = ARRIVAL_BANNER_TIME


func _on_warning(_seconds_left: int) -> void:
	banner_detail.pivot_offset = banner_detail.size * 0.5
	var tween := create_tween()
	tween.tween_property(banner_detail, "scale", Vector2.ONE * 1.12, 0.12)
	tween.tween_property(banner_detail, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_SINE)


func _on_speed_changed(_multiplier: float) -> void:
	multiplier_label.pivot_offset = multiplier_label.size * 0.5
	if _multiplier_tween != null:
		_multiplier_tween.kill()
	_multiplier_tween = create_tween()
	_multiplier_tween.tween_property(multiplier_label, "scale", Vector2.ONE * 1.4, 0.1)
	_multiplier_tween.tween_property(multiplier_label, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_SINE)


func _update_presence(delta: float) -> void:
	var presence := director.presence
	jump_label.text = str(director.jump_count)
	var real := presence.progress
	if _snap_next_frame:
		_snap_next_frame = false
		_shown = real
		_trail = real
	if _shown > real + 0.002:
		# Something took the bar down, which is a jump: leave a red trail where it was.
		_trail = maxf(_trail, _shown)
		_trail_hold = TRAIL_HOLD_TIME
	_shown = lerpf(_shown, real, 1.0 - exp(-FILL_FOLLOW_SPEED * delta))
	if absf(_shown - real) < 0.0003:
		_shown = real
	if _trail_hold > 0.0:
		_trail_hold -= delta
	else:
		_trail = move_toward(_trail, _shown, TRAIL_FALL_SPEED * delta)
	_trail = maxf(_trail, _shown)
	presence_bar.value = _shown * 100.0
	trail_bar.value = _trail * 100.0

	# The color follows how close it is, and flickers faster the angrier it gets (and while the drive charges).
	var color := color_for_progress(_shown)
	var flicker := presence.aggression
	if director.phase == JumpDirector.Phase.CHARGING:
		color = DANGER_COLOR
		flicker = 1.0
	if flicker > 0.0:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * (3.0 + 9.0 * flicker))
		color = color.lerp(Color.WHITE, 0.45 * flicker * pulse)
	if director.is_jumping() and director.phase != JumpDirector.Phase.CHARGING:
		color = Color(color, 0.55)
	_fill_style.bg_color = color

	var multiplier := presence.get_speed_multiplier()
	if not is_equal_approx(multiplier, _shown_multiplier) or multiplier_label.text.is_empty():
		_shown_multiplier = multiplier
		multiplier_label.text = format_multiplier(multiplier)
	var label_color := MUTED_COLOR
	if multiplier > 1.05:
		label_color = WARY_COLOR.lerp(DANGER_COLOR, clampf((multiplier - 1.0) / 3.0, 0.0, 1.0))
	elif multiplier < 0.95:
		label_color = SLOWED_COLOR
	multiplier_label.add_theme_color_override(&"font_color", label_color)


func _update_banner() -> void:
	var title := ""
	var detail := ""
	var system_name := director.system.system_name.to_upper()
	match director.phase:
		JumpDirector.Phase.CHARGING:
			title = "JUMP DRIVE CHARGING"
			detail = "%d\nALL CREW BACK TO THE SHIP" % ceili(director.get_charge_left())
		JumpDirector.Phase.WARPING_OUT:
			title = "JUMPING"
		JumpDirector.Phase.SWITCHING:
			title = "ARRIVING" if director.is_first_arrival() else "JUMPING"
			detail = system_name if director.is_first_arrival() else "ENTERING %s" % system_name
		JumpDirector.Phase.WARPING_IN:
			title = "ARRIVING"
			detail = system_name
		_:
			if _arrival_banner_left > 0.0:
				title = "ARRIVED"
				detail = "%s    JUMP %d" % [system_name, director.jump_count]
	banner.visible = not title.is_empty()
	if banner.visible:
		banner_title.text = title
		banner_detail.text = detail
		var fade := 1.0
		if director.phase == JumpDirector.Phase.IN_SYSTEM:
			fade = clampf(_arrival_banner_left / 1.2, 0.0, 1.0)
		banner.modulate.a = fade


## A flash of light across the screen that fades away.
func _flash(peak: float, duration: float) -> void:
	if _flash_tween != null:
		_flash_tween.kill()
	flash.color = Color(FLASH_COLOR, peak)
	_flash_tween = create_tween()
	_flash_tween.tween_property(flash, "color:a", 0.0, duration).set_trans(Tween.TRANS_SINE)
