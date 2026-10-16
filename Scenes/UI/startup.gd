class_name Startup
extends Control
## The opening sequence. A black screen fades the studio title in and out, then the boot
## menu waits for any button. Pressing one sets the game up (Steam, the lobby, the main
## menu) and hands over to the main menu. Without Steam the game carries on offline.

const MAIN_MENU_SCENE := "res://Scenes/UI/MainMenu/MainMenu.tscn"

const SPLASH_FADE_IN := 1.6
const SPLASH_HOLD := 1.6
const SPLASH_FADE_OUT := 1.2
const PAGE_FADE_TIME := 0.8
const PROMPT_PULSE_TIME := 0.9
## Each setup step stays on screen at least this long so its message can be read.
const STEP_MIN_TIME := 0.4
const HANDOFF_PAUSE := 0.5
const HANDOFF_FADE_TIME := 0.7

enum Phase { SPLASH, TO_BOOT, WAITING, BOOTING }

@onready var intro: Control = %Intro
@onready var splash_label: Label = %SplashLabel
@onready var boot_page: Control = %BootPage
@onready var prompt_label: Label = %PromptLabel
@onready var status_label: Label = %StatusLabel

var _phase := Phase.SPLASH
var _splash_tween: Tween
var _prompt_tween: Tween
var _status_lines: PackedStringArray = []
var _menu_scene: PackedScene


func _ready() -> void:
	splash_label.modulate.a = 0.0
	boot_page.modulate.a = 0.0
	boot_page.hide()
	status_label.text = ""
	_splash_tween = create_tween()
	_splash_tween.tween_property(splash_label, "modulate:a", 1.0, SPLASH_FADE_IN)
	_splash_tween.tween_interval(SPLASH_HOLD)
	_splash_tween.tween_property(splash_label, "modulate:a", 0.0, SPLASH_FADE_OUT)
	_splash_tween.finished.connect(_show_boot_page.bind(true))


func _input(event: InputEvent) -> void:
	if not _is_button_press(event):
		return
	match _phase:
		Phase.SPLASH:
			get_viewport().set_input_as_handled()
			_skip_splash()
		Phase.WAITING:
			get_viewport().set_input_as_handled()
			_run_boot()


## A key, mouse button or gamepad button going down. Held keys and mouse movement do not count.
func _is_button_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	if event is InputEventMouseButton or event is InputEventJoypadButton:
		return event.pressed
	return false


## Skipping removes the intro at once, with no fade, to show the boot menu.
func _skip_splash() -> void:
	_splash_tween.kill()
	_show_boot_page(false)


## Removes the intro, which sits above the boot menu, and starts the boot menu. It fades in
## after the intro ran its course, and is simply there after a skip.
func _show_boot_page(fade_in: bool) -> void:
	_phase = Phase.TO_BOOT
	if is_instance_valid(intro):
		intro.queue_free()
	boot_page.show()
	if fade_in:
		var tween := create_tween()
		tween.tween_property(boot_page, "modulate:a", 1.0, PAGE_FADE_TIME)
		await tween.finished
	else:
		boot_page.modulate.a = 1.0
	_phase = Phase.WAITING
	_start_prompt_pulse()


func _start_prompt_pulse() -> void:
	prompt_label.modulate.a = 1.0
	_prompt_tween = create_tween().set_loops()
	_prompt_tween.tween_property(prompt_label, "modulate:a", 0.25, PROMPT_PULSE_TIME) \
			.set_trans(Tween.TRANS_SINE)
	_prompt_tween.tween_property(prompt_label, "modulate:a", 1.0, PROMPT_PULSE_TIME) \
			.set_trans(Tween.TRANS_SINE)


func _stop_prompt_pulse() -> void:
	if _prompt_tween != null:
		_prompt_tween.kill()
	var tween := create_tween()
	tween.tween_property(prompt_label, "modulate:a", 0.0, 0.25)


func _run_boot() -> void:
	_phase = Phase.BOOTING
	_stop_prompt_pulse()
	_status_lines.clear()
	status_label.text = ""
	# The menu loads in the background while Steam and the lobby are set up.
	ResourceLoader.load_threaded_request(MAIN_MENU_SCENE)

	await _run_step("CONNECTING TO STEAM", _connect_steam)
	await _run_step("JOINING LOBBY", _join_lobby)
	await _run_step("LOADING MENU", _load_menu)

	if _menu_scene == null:
		# Steam and the lobby are optional; a menu that will not load is not.
		prompt_label.text = "PRESS ANY BUTTON TO TRY AGAIN"
		prompt_label.modulate.a = 1.0
		_phase = Phase.WAITING
		return

	await get_tree().create_timer(HANDOFF_PAUSE).timeout
	var tween := create_tween()
	tween.tween_property(boot_page, "modulate:a", 0.0, HANDOFF_FADE_TIME)
	await tween.finished
	get_tree().change_scene_to_packed(_menu_scene)


## Shows [param working_text], runs [param work] and replaces the line with the result.
## [param work] returns [code]{"text": String}[/code].
func _run_step(working_text: String, work: Callable) -> void:
	_status_lines.append(working_text + " ...")
	_refresh_status()
	var started := Time.get_ticks_msec()
	var result: Dictionary = await work.call()
	var remaining := STEP_MIN_TIME - (Time.get_ticks_msec() - started) / 1000.0
	if remaining > 0.0:
		await get_tree().create_timer(remaining).timeout
	_status_lines[_status_lines.size() - 1] = result["text"]
	_refresh_status()


func _refresh_status() -> void:
	status_label.text = "\n".join(_status_lines)


func _connect_steam() -> Dictionary:
	# Steam is started by the SteamNetwork autoload before any scene exists, so this
	# only reports how that went.
	if SteamNetwork.is_active:
		return {"text": "STEAM: CONNECTED AS %s" % SteamNetwork.persona_name}
	return {"text": "STEAM: OFFLINE - MULTIPLAYER IS UNAVAILABLE"}


func _join_lobby() -> Dictionary:
	if not SteamLobby.is_available():
		return {"text": "LOBBY: SKIPPED"}
	if await SteamLobby.create_lobby():
		return {"text": "LOBBY: READY"}
	return {"text": "LOBBY: UNAVAILABLE - CONTINUING WITHOUT ONE"}


func _load_menu() -> Dictionary:
	var status := ResourceLoader.load_threaded_get_status(MAIN_MENU_SCENE)
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
		status = ResourceLoader.load_threaded_get_status(MAIN_MENU_SCENE)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_menu_scene = ResourceLoader.load_threaded_get(MAIN_MENU_SCENE) as PackedScene
	if _menu_scene == null:
		return {"text": "MENU: FAILED TO LOAD"}
	return {"text": "MENU: READY"}
