class_name VehicleAmbience
extends Node
## The sound of being inside a vehicle: a hum that plays for anyone aboard and fades away when they get off. Put it
## in a vehicle's scene (its parent) and give it the sound.
##
## It plays the sound everywhere at once, not from a place, for the player on this machine only: it is
## heard while the view this player is looking through is from aboard (see [VehicleAboard]), fading in as they come aboard and
## out as they leave. It respects the Ambient Volume in the settings. A sound that is not set to loop is looped here, so a
## file that was imported without loop points still hums on.

## The setting that sets how loud ambience is, from 0 to 100.
const AMBIENT_VOLUME_SETTING: StringName = &"ambient_volume"
## How often it asks whether the listener is aboard, which takes a few shape tests.
const ABOARD_CHECK_TIME := 0.1
## The vehicle's interiors are looked for again this often.
const INTERIORS_REFRESH_TIME := 1.0
## Below this much of its volume it is not worth playing at all.
const SILENT := 0.002

## The sound. It plays on a loop.
@export var stream: AudioStream:
	set(value):
		stream = value
		if is_instance_valid(_player):
			_player.stream = _make_loop(value)
## How loud it is at full, in decibels, before the Ambient Volume setting.
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var volume_db := -3.0
## How long it takes to fade in once the listener is aboard, and to fade out when they are not.
@export_range(0.05, 10.0, 0.05, "suffix:s") var fade_in_time := 1.5
@export_range(0.05, 10.0, 0.05, "suffix:s") var fade_out_time := 0.8
## The audio bus it plays on.
@export var bus: StringName = &"Master"
## The vehicle it is the ambience of: its parent when left empty.
@export var vehicle: Node3D

var _player: AudioStreamPlayer
var _gain := 0.0
var _aboard := false
var _aboard_wait := 0.0
var _interiors: Array[VehicleInterior3D] = []
var _interiors_age := 0.0
var _setting_scale := 1.0


func _ready() -> void:
	if not is_instance_valid(vehicle):
		vehicle = get_parent() as Node3D
	_interiors = VehicleAboard.get_interiors(vehicle)
	_player = AudioStreamPlayer.new()
	_player.name = "Player"
	_player.bus = bus if AudioServer.get_bus_index(bus) >= 0 else &"Master"
	_player.stream = _make_loop(stream)
	_player.stream_paused = true
	add_child(_player)
	_read_setting()
	Settings.setting_changed.connect(_on_setting_changed)
	if _player.stream != null:
		_player.play()
	_apply_volume()


func _process(delta: float) -> void:
	_aboard_wait -= delta
	_interiors_age += delta
	if _aboard_wait <= 0.0:
		_aboard_wait = ABOARD_CHECK_TIME
		if _interiors_age >= INTERIORS_REFRESH_TIME and is_instance_valid(vehicle):
			# A vehicle can grow another interior (a segment added to a ship).
			_interiors_age = 0.0
			_interiors = VehicleAboard.get_interiors(vehicle)
		_aboard = _is_listener_aboard()
	var target := 1.0 if _aboard else 0.0
	if _gain != target:
		_gain = move_toward(_gain, target, delta / maxf(fade_in_time if target > _gain else fade_out_time, 0.01))
		_apply_volume()


## Whether the sound is being heard right now, fully or fading.
func is_audible() -> bool:
	return _gain > SILENT and _setting_scale > 0.0


## How much of its full volume it is at: 0 when the listener is not aboard, 1 when they have been for a while.
func get_gain() -> float:
	return _gain


## Whether the view this player is looking from is aboard.
func is_listener_aboard() -> bool:
	return _aboard


## The player that plays the sound, for tests.
func get_player() -> AudioStreamPlayer:
	return _player


func _is_listener_aboard() -> bool:
	if not is_instance_valid(vehicle) or not is_inside_tree():
		return false
	var camera := get_viewport().get_camera_3d()
	return camera != null and VehicleAboard.is_viewer_aboard(camera, vehicle, _interiors)


func _apply_volume() -> void:
	if _player == null:
		return
	var silent := _gain <= SILENT or _setting_scale <= 0.0
	_player.stream_paused = silent
	if not silent:
		_player.volume_db = volume_db + linear_to_db(_gain * _setting_scale)


## A copy of [param source] that loops, unless it already does (a file imported with loop points, or set to loop).
func _make_loop(source: AudioStream) -> AudioStream:
	var wav := source as AudioStreamWAV
	if wav != null and wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		var looped := wav.duplicate() as AudioStreamWAV
		looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
		looped.loop_begin = 0
		looped.loop_end = int(wav.get_length() * wav.mix_rate)
		return looped
	return source


func _read_setting() -> void:
	_set_setting_scale(Settings.get_setting(AMBIENT_VOLUME_SETTING, 100))


func _set_setting_scale(value: Variant) -> void:
	_setting_scale = clampf(float(value) / 100.0, 0.0, 1.0)


func _on_setting_changed(id: StringName, value: Variant) -> void:
	if id == AMBIENT_VOLUME_SETTING:
		_set_setting_scale(value)
		_apply_volume()
