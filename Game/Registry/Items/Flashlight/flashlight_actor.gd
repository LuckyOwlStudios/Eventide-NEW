## A flashlight. Flashlight.tscn is its one scene: this script runs on the ground, in the holder's hand,
## in another player's, and on a player's body when it is in a pocket, and the state it works from lives
## in the [FlashlightInstance]. Only its beam is made for carrying (it is in item_always), so a lit
## flashlight in a pocket shines from the player's shoulder and no model of it exists there.
##
## In hand it is switched by the primary action. Carried in a container that listens (the player's lamp
## slot), it is switched by [constant TOGGLE_ACTION] instead, and only that one: a flashlight in the
## hotbar that is not in hand ignores the key, so a player with several does not light them all.
class_name FlashlightActor
extends ItemActor

signal toggled(enabled: bool)

## The Input Map action that switches a carried flashlight.
const TOGGLE_ACTION: StringName = &"toggle_flashlight"

@export_range(0.0, 100.0, 0.1, "or_greater") var power_drain_per_second := 1.0

@onready var light: SpotLight3D = get_node_or_null("%Light")
@onready var lens: MeshInstance3D = get_node_or_null("%Lightmesh")

var flashlight_instance: FlashlightInstance
var is_on: bool:
	get:
		return flashlight_instance != null and flashlight_instance.is_on

var _shown_on := false


## Only called while a player holds the flashlight and looks through their own eyes, with no menu open.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"primary_action"):
		toggle()


## Only called while the flashlight is on a player's body, in a container that listens to the key.
func _carried_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_ACTION):
		get_viewport().set_input_as_handled()
		toggle()


## Runs only while the light is on, wherever the flashlight is.
func _process(delta: float) -> void:
	# The shadow of a flashlight in the player's own hand is not a second battery drain.
	if flashlight_instance != null and not is_shadow_only():
		flashlight_instance.power_level -= power_drain_per_second * delta


## The flashlight on the ground has a "toggle" option (see Flashlight.tscn).
func _on_world_option(option_id: StringName, _interactor: Node3D) -> bool:
	if option_id != &"toggle" or flashlight_instance == null:
		return false
	toggle()
	return true


func toggle() -> void:
	if flashlight_instance != null:
		flashlight_instance.toggle()


func _on_item_instance_changed() -> void:
	if flashlight_instance != null and flashlight_instance.switched.is_connected(_apply_state):
		flashlight_instance.switched.disconnect(_apply_state)
	flashlight_instance = item_instance as FlashlightInstance
	if item_instance != null and flashlight_instance == null:
		push_warning("[FlashlightActor] Expected a FlashlightInstance.")
	if flashlight_instance != null:
		flashlight_instance.switched.connect(_apply_state)
	_apply_state()

## In a bag it is covered and its battery is not worn by it: it goes out. (In a pocket that carries items
## it stays as it is, and shines from the holder's shoulder.)
func _on_packed_away() -> void:
	if flashlight_instance != null:
		flashlight_instance.is_on = false


## Makes the light and the lens match the instance, so it looks the same on the ground, in the holder's
## hand and on anyone else's screen.
func _apply_state(_instance_is_on: bool = false) -> void:
	var lit := is_on
	if is_instance_valid(light):
		light.visible = lit
	if is_instance_valid(lens):
		lens.visible = lit
	set_process(lit and not is_shadow_only())
	if lit != _shown_on:
		_shown_on = lit
		toggled.emit(lit)
