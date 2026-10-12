@tool
class_name BlurOverlay
extends ColorRect

## Full-screen blur with a normalized amount and pause-safe transitions.
##
## How it blurs depends on the Graphics Quality setting, because blurring the live screen
## costs a noticeable share of every frame:
## [br][b]High and Ultra[/b]: a live blur of the screen, so a game that keeps running behind
## the pause menu (multiplayer) is seen moving, blurred.
## [br][b]Low and Medium[/b]: one picture of the screen is taken when the blur starts, shrunk
## so that it is soft, and shown in its place. It looks blurred and costs nothing per frame,
## but it does not move.
## [br]The mode is chosen when the blur starts. Raising the quality while it is showing
## switches it to live; lowering it waits for the next time.

const BLUR_SHADER_MATERIAL := preload("res://Assets/Shaders/blur_shader_material.tres")

enum Mode {
	## Not blurring.
	NONE,
	## Blurring the live screen with the blur shader.
	LIVE,
	## Showing the shrunken picture taken when the blur started.
	SNAPSHOT,
}

@export_range(0.0, 1.0, 0.01) var blur_amount := 0.0:
	set(value):
		blur_amount = clampf(value, 0.0, 1.0)
		_apply_blur_amount()

@export_range(0.0, 8.0, 0.1) var maximum_blur_lod := 3.5:
	set(value):
		maximum_blur_lod = maxf(value, 0.0)
		_apply_blur_amount()

@export_range(0.0, 2.0, 0.01, "or_greater") var fade_duration := 0.2
## How many times smaller the snapshot is made than the screen. Bigger is blurrier.
@export_range(2, 48) var snapshot_downscale := 24

## Where the snapshot's picture comes from: a Callable returning an Image. When empty, the
## screen is used. This exists so a test can supply its own picture.
var screen_grabber := Callable()

var _target_amount := 0.0
var _fade_speed := 0.0
var _mode := Mode.NONE
var _blur_material: ShaderMaterial
var _snapshot_rect: TextureRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if material == null or not material is ShaderMaterial:
		material = BLUR_SHADER_MATERIAL.duplicate()
	elif not Engine.is_editor_hint():
		material = material.duplicate()
	_blur_material = material as ShaderMaterial
	if not Engine.is_editor_hint():
		# Nothing of its own to draw: in snapshot mode the picture does the work.
		color = Color(1.0, 1.0, 1.0, 0.0)
		_snapshot_rect = TextureRect.new()
		_snapshot_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_snapshot_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_snapshot_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_snapshot_rect.stretch_mode = TextureRect.STRETCH_SCALE
		_snapshot_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_snapshot_rect.visible = false
		add_child(_snapshot_rect, false, Node.INTERNAL_MODE_FRONT)
		Settings.setting_changed.connect(_on_setting_changed)
	_apply_blur_amount()
	set_process(false)


func _process(delta: float) -> void:
	blur_amount = move_toward(blur_amount, _target_amount, _fade_speed * delta)
	if is_equal_approx(blur_amount, _target_amount):
		blur_amount = _target_amount
		set_process(false)
		if is_zero_approx(blur_amount):
			_end_session()
		_present()


func fade_in(duration := -1.0) -> void:
	_fade_to(1.0, fade_duration if duration < 0.0 else duration)


func fade_out(duration := -1.0) -> void:
	_fade_to(0.0, fade_duration if duration < 0.0 else duration)


func set_blur_immediate(amount: float) -> void:
	set_process(false)
	_target_amount = clampf(amount, 0.0, 1.0)
	if _target_amount > 0.0:
		_begin_session()
	blur_amount = _target_amount
	if is_zero_approx(blur_amount):
		_end_session()
	_present()


## True while the blur on show is the still picture rather than the live screen.
func is_using_snapshot() -> bool:
	return _mode == Mode.SNAPSHOT and blur_amount > 0.0


## True while the blur on show is the live screen being blurred.
func is_using_live_blur() -> bool:
	return _mode == Mode.LIVE and blur_amount > 0.0


func _fade_to(target: float, duration: float) -> void:
	_target_amount = clampf(target, 0.0, 1.0)
	if _target_amount > 0.0:
		_begin_session()
	if duration <= 0.0 or is_equal_approx(blur_amount, _target_amount):
		set_blur_immediate(_target_amount)
		return
	_fade_speed = absf(_target_amount - blur_amount) / duration
	_present()
	set_process(true)


## Chooses how this blur will be drawn. This is when the picture is taken, which is before
## whatever is being blurred behind (a pause menu, say) has had a chance to appear.
func _begin_session() -> void:
	if _mode != Mode.NONE:
		return
	if Engine.is_editor_hint() or GraphicsQuality.is_at_least(GraphicsQuality.Level.HIGH):
		_mode = Mode.LIVE
		return
	var picture := _take_snapshot()
	if picture == null:
		_mode = Mode.LIVE
		return
	_snapshot_rect.texture = picture
	_mode = Mode.SNAPSHOT


func _end_session() -> void:
	_mode = Mode.NONE
	if _snapshot_rect != null:
		_snapshot_rect.texture = null


## One picture of the screen, shrunk so that it is soft when it is stretched back up.
func _take_snapshot() -> Texture2D:
	if DisplayServer.get_name() == "headless" and not screen_grabber.is_valid():
		return null
	var image: Image = screen_grabber.call() if screen_grabber.is_valid() else get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		return null
	image = image.duplicate()
	image.convert(Image.FORMAT_RGB8)
	@warning_ignore("integer_division")
	var target_width: int = maxi(image.get_width() / snapshot_downscale, 2)
	@warning_ignore("integer_division")
	var target_height: int = maxi(image.get_height() / snapshot_downscale, 2)
	# Shrinking by half at a time averages every pixel in. One big jump skips most of them
	# and lets thin bright lines, like a HUD bar, survive as sharp specks.
	while image.get_width() > target_width or image.get_height() > target_height:
		@warning_ignore("integer_division")
		image.resize(
			maxi(image.get_width() / 2, target_width),
			maxi(image.get_height() / 2, target_height),
			Image.INTERPOLATE_BILINEAR,
		)
	# A smooth stretch back up hides the blocky look of a very small picture.
	image.resize(image.get_width() * 4, image.get_height() * 4, Image.INTERPOLATE_CUBIC)
	return ImageTexture.create_from_image(image)


func _present() -> void:
	var active := blur_amount > 0.0 and _mode != Mode.NONE
	visible = active
	if not active:
		return
	# The blur shader is what makes the live blur expensive, so it is only attached when
	# it is the one in use.
	material = _blur_material if _mode == Mode.LIVE else null
	if _snapshot_rect != null:
		_snapshot_rect.visible = _mode == Mode.SNAPSHOT
	_apply_blur_amount()


func _apply_blur_amount() -> void:
	if _blur_material != null:
		_blur_material.set_shader_parameter(&"blur_lod", blur_amount * maximum_blur_lod)
	elif material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter(&"blur_lod", blur_amount * maximum_blur_lod)
	if _snapshot_rect != null:
		_snapshot_rect.modulate.a = blur_amount


func _on_setting_changed(id: StringName, _value: Variant) -> void:
	if id != GraphicsQuality.SETTING_ID:
		return
	# Moving up to a quality that blurs live replaces the picture with the real thing.
	if _mode == Mode.SNAPSHOT and GraphicsQuality.is_at_least(GraphicsQuality.Level.HIGH):
		_mode = Mode.LIVE
		_snapshot_rect.texture = null
		_present()
