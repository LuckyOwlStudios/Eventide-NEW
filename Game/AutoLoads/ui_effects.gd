extends CanvasLayer

## Shared screen-space effects. Requesters are reference-counted so one menu
## cannot hide the effects while another menu still needs them.

@onready var blur: BlurOverlay = %Blur
@onready var dimmer: Variant = %Dimmer

var _requesters: Dictionary[int, WeakRef] = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	blur.set_blur_immediate(0.0)
	dimmer.set_dim_immediate(0.0)

func show_effects(requester: Node, duration := -1.0) -> void:
	_prune_requesters()
	if is_instance_valid(requester):
		var requester_id := requester.get_instance_id()
		if not _requesters.has(requester_id):
			_requesters[requester_id] = weakref(requester)
			var exit_callback := _on_requester_exited.bind(requester_id)
			if not requester.tree_exited.is_connected(exit_callback):
				requester.tree_exited.connect(exit_callback, CONNECT_ONE_SHOT)
	blur.fade_in(blur.fade_duration if duration < 0.0 else duration)
	dimmer.fade_in(dimmer.fade_duration if duration < 0.0 else duration)

func hide_effects(requester: Node, duration := -1.0) -> void:
	if is_instance_valid(requester):
		_requesters.erase(requester.get_instance_id())
	_prune_requesters()
	if not _requesters.is_empty():
		return
	blur.fade_out(blur.fade_duration if duration < 0.0 else duration)
	dimmer.fade_out(dimmer.fade_duration if duration < 0.0 else duration)

func clear_effects(duration := 0.0) -> void:
	_requesters.clear()
	blur.fade_out(duration)
	dimmer.fade_out(duration)

func _on_requester_exited(requester_id: int) -> void:
	_requesters.erase(requester_id)
	if is_inside_tree() and _requesters.is_empty():
		blur.fade_out()
		dimmer.fade_out()

func _prune_requesters() -> void:
	for requester_id in _requesters.keys():
		var requester_ref: WeakRef = _requesters[requester_id]
		if requester_ref.get_ref() == null:
			_requesters.erase(requester_id)
