extends CanvasLayer
## Small test panel for the existing sandbox scene.
@export var radio: WalkieTalkie3D
@onready var recorder: PARecorder3D = $"../PARecorder3D"
var _status: Label

func _ready() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "VOICE / RADIO / PA"
	box.add_child(title)
	var help := Label.new()
	help.text = "Hold V: proximity voice    Hold B: radio\nGlobal broadcasts to every channel."
	box.add_child(help)
	var channel_select := OptionButton.new()
	for label in ["Global", "Alpha", "Beta", "Charlie", "Delta"]:
		channel_select.add_item(label)
	channel_select.select(radio.channel)
	channel_select.item_selected.connect(func(index: int): radio.channel = index)
	box.add_child(channel_select)
	var targets := OptionButton.new()
	for label in ["PA: Local speakers", "PA: Global", "PA: Alpha", "PA: Beta", "PA: Charlie", "PA: Delta"]:
		targets.add_item(label)
	@warning_ignore("int_as_enum_without_cast")
	targets.item_selected.connect(func(index: int): recorder.destination = index - 1)
	box.add_child(targets)
	var record_button := Button.new()
	record_button.text = "Start / stop PA recording"
	record_button.pressed.connect(func():
		if recorder.is_recording:
			recorder.stop_recording()
		else:
			recorder.start_recording()
	)
	box.add_child(record_button)
	var play_button := Button.new()
	play_button.text = "Play saved recording"
	play_button.pressed.connect(func(): recorder.play_recording())
	box.add_child(play_button)
	var stop_button := Button.new()
	stop_button.text = "Stop playback"
	stop_button.pressed.connect(recorder.stop_playback)
	box.add_child(stop_button)
	_status = Label.new()
	box.add_child(_status)


func _process(_delta: float) -> void:
	if _status == null:
		return
	var state := "Recording nearby voices..." if recorder.is_recording else "PA ready"
	if recorder.recording != null and not recorder.is_recording:
		state = "Recording saved (%.1f seconds)" % recorder.recording.get_length()
	_status.text = "%s | Radio: %s" % [state, "transmitting" if radio.transmitting else "listening"]
