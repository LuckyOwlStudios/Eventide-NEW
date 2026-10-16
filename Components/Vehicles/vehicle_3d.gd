@tool
@icon("uid://b41c6dwvtv4qm")
class_name Vehicle3D
extends RigidBody3D
## Base for anything a player can pilot: a physical body with weight and velocity that one
## [VehicleController] at a time can take control of.
##
## A vehicle starts out on the Vehicles collision layer with no damping, so it keeps its
## velocity until something pushes back. Anything a scene set to something other than Godot's
## stock values is left alone. Set [member RigidBody3D.mass] in the scene.

signal control_started(controller: VehicleController)
signal control_ended(controller: VehicleController)

## The engines ran or stopped.
signal engine_state_changed(running: bool)
## The electronics got power or lost it.
signal power_state_changed(powered: bool)
## The headlights were switched on or off with the lights key (they stay dark without power).
signal light_state_changed(on: bool)

## Hold this to start the engines (the same key as jumping, so no extra key is needed). It does
## nothing else while the engines are off, since a ship that is off cannot take off.
const START_ENGINE := &"jump"
## Hold this to shut the engines down. Held, not tapped, so it cannot happen by accident.
const STOP_ENGINE := &"engine_off"
## Press this in the pilot's seat to switch the headlights ([member lights]) on or off.
const TOGGLE_LIGHTS := &"light"
## Press this in the pilot's seat to open or close the [member exterior_doors].
const TOGGLE_EXTERIOR_DOORS := &"exterior_doors"

## True when the engines run: the vehicle can be driven and holds itself up against gravity, which
## is what lets a ship hover or a car drive. With them off it cannot move under its own power.
## Starting them takes power; see [member power_state].
@export var engine_state := false:
	set(value):
		if value == engine_state:
			return
		engine_state = value
		engine_state_changed.emit(engine_state)
## True when the electronics have power: lights, hydraulic doors and the like work. It does not
## depend on the engines, so a parked ship can keep its lights on. Losing power stops the engines.
@export var power_state := false:
	set(value):
		if value == power_state:
			return
		power_state = value
		_apply_power_nodes()
		power_state_changed.emit(power_state)
		if not power_state:
			engine_state = false

@export_group("Engine Controls")
## How long the start key is held to start the engines.
@export_range(0.2, 10.0, 0.1, "suffix:s") var engine_start_hold_seconds := 3.0
## How long the stop key is held to shut them down.
@export_range(0.2, 10.0, 0.1, "suffix:s") var engine_stop_hold_seconds := 1.0

@export_group("")

@export var vehicle_camera: Camera3D
## Turn this on for a vehicle people walk around inside, like a ship with a cargo bay. Its
## body then sits on the Hulls layer, which characters and items ignore, so it does not fill the
## inside; they stand on the walls and floors on the Vehicle Interiors layer instead. Leave it off
## for a vehicle that is solid, such as a car.
@export var walkable_interior := false

@export_group("Power, Lights and Doors")
## Nodes that are shown only while the vehicle has power: indicator lights, glowing panels, interior
## lamps. They are hidden when the power goes out.
@export var power_on_nodes: Array[Node3D]
## The headlights. They toggle with the lights key (F) from the pilot's seat, and are dark without
## power. A node in here and in [member power_on_nodes] follows the headlights.
@export var lights: Array[Node3D]
## Whether the headlights are switched on. They only shine while there is power as well.
@export var light_state := true:
	set(value):
		if value == light_state:
			return
		light_state = value
		_apply_power_nodes()
		light_state_changed.emit(light_state)
## The doors of the outside of the vehicle, such as a cargo bay door. The doors key (H) from the pilot's
## seat opens them all, or closes them all if any is open. It takes power. Doors between rooms and the
## hatch on the roof do not belong here.
@export var exterior_doors: Array[HingedDoor3D]

@export_group("")

var controller: VehicleController
## 0 to 1: how far the held start or stop key has got. A HUD can show this.
var engine_hold_progress := 0.0

var _start_hold := 0.0
var _stop_hold := 0.0
## Set once the engines start, until the key is let go, so the start key does not also launch it.
var _start_key_used := false


func _enter_tree() -> void:
	# Defaults are for the running game. In the editor they would be saved into the scene.
	if Engine.is_editor_hint():
		return
	if collision_layer == 1:
		collision_layer = PhysicsLayers.HULLS if walkable_interior else PhysicsLayers.VEHICLES
	if collision_mask == 1:
		collision_mask = PhysicsLayers.HULL_MASK if walkable_interior else PhysicsLayers.VEHICLE_MASK
	if linear_damp_mode == RigidBody3D.DAMP_MODE_COMBINE and is_zero_approx(linear_damp):
		linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	if angular_damp_mode == RigidBody3D.DAMP_MODE_COMBINE and is_zero_approx(angular_damp):
		angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	# A ship can outrun a thin wall in one physics tick.
	continuous_cd = true


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if walkable_interior:
		_keep_walls_off_the_hull()
	if is_instance_valid(vehicle_camera):
		vehicle_camera.current = false
	_ensure_action(TOGGLE_LIGHTS, KEY_F, JOY_BUTTON_INVALID)
	_ensure_action(TOGGLE_EXTERIOR_DOORS, KEY_H, JOY_BUTTON_DPAD_UP)
	_apply_power_nodes()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_engine_controls(delta)
	_update_pilot_keys()


## Switches the headlights. They shine only while there is power, so with the power out this changes
## what they do when it comes back.
func toggle_lights() -> void:
	light_state = not light_state


## True while the headlights are actually shining: switched on, and there is power.
func are_lights_shining() -> bool:
	return power_state and light_state


## Opens or closes every exterior door.
func set_exterior_doors_open(open: bool) -> void:
	for door in exterior_doors:
		if is_instance_valid(door):
			door.set_open(open)


## True when any exterior door has been told to be open.
func are_exterior_doors_open() -> bool:
	for door in exterior_doors:
		if is_instance_valid(door) and door.open_requested:
			return true
	return false


## Opens the exterior doors, or closes them all if any is open. Needs power, like the doors' hydraulics.
## Returns whether it did anything.
func toggle_exterior_doors() -> bool:
	if not power_state or exterior_doors.is_empty():
		return false
	set_exterior_doors_open(not are_exterior_doors_open())
	return true


func can_be_controlled_by(candidate: VehicleController) -> bool:
	return is_instance_valid(candidate) and not is_instance_valid(controller)


func claim_control(candidate: VehicleController) -> bool:
	if not can_be_controlled_by(candidate):
		return false
	controller = candidate
	_on_control_started(candidate)
	control_started.emit(candidate)
	return true


func release_control(candidate: VehicleController) -> bool:
	if not is_instance_valid(controller) or controller != candidate:
		return false
	var previous := controller
	controller = null
	_on_control_ended(previous)
	control_ended.emit(previous)
	return true


func has_local_control() -> bool:
	return is_instance_valid(controller) and controller.is_local_controller()


func _on_control_started(_controller: VehicleController) -> void:
	pass


func _on_control_ended(_controller: VehicleController) -> void:
	pass


## The walls of a walkable vehicle are part of the vehicle. If one is on a layer the vehicle's
## body scans (an editor re-save can leave a wall on World), the body fights its own wall and
## throws the ship around. Move such walls to Vehicle Interiors and say so.
func _keep_walls_off_the_hull() -> void:
	for node in find_children("*", "CSGShape3D", true, false):
		var wall := node as CSGShape3D
		if wall.use_collision and wall.collision_layer & collision_mask != 0:
			push_warning("%s collides with its own vehicle (layer %d); moved it to Vehicle Interiors. Fix its collision layer in the scene." % [wall.get_path(), wall.collision_layer])
			wall.collision_layer = PhysicsLayers.VEHICLE_INTERIORS
			wall.collision_mask = 0

## Whether someone is flying this vehicle right now. A subclass can say more.
func _is_piloted() -> bool:
	return has_local_control()


## True while the start key is still held after it started the engines. A ship should not read
## it as "go up" until the key has been let go.
func is_start_key_in_use() -> bool:
	return _start_key_used


## What the power state and the headlight switch show: [member power_on_nodes] are visible with power,
## and [member lights] with power and the switch on. Only while the game runs, so the editor does not
## save a hidden lamp into the scene.
func _apply_power_nodes() -> void:
	if Engine.is_editor_hint() or not is_node_ready():
		return
	for node in power_on_nodes:
		if is_instance_valid(node):
			node.visible = power_state
	for node in lights:
		if is_instance_valid(node):
			node.visible = power_state and light_state


## The pilot's keys for the headlights and the exterior doors.
func _update_pilot_keys() -> void:
	if not _is_piloted() or InGameUIHandler.is_ui_open:
		return
	if power_state and Input.is_action_just_pressed(TOGGLE_LIGHTS):
		toggle_lights()
	if Input.is_action_just_pressed(TOGGLE_EXTERIOR_DOORS):
		toggle_exterior_doors()


## Adds a key to the Input Map if the project does not have the action (the project settings are the
## place to rebind it).
static func _ensure_action(action: StringName, key: Key, button: JoyButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var key_event := InputEventKey.new()
	key_event.physical_keycode = key
	InputMap.action_add_event(action, key_event)
	if button != JOY_BUTTON_INVALID:
		var button_event := InputEventJoypadButton.new()
		button_event.button_index = button
		InputMap.action_add_event(action, button_event)


## Hold the start key to start the engines (needs power), hold the stop key to shut them down.
func _update_engine_controls(delta: float) -> void:
	var allowed := _is_piloted() and not InGameUIHandler.is_ui_open
	if not Input.is_action_pressed(START_ENGINE):
		_start_key_used = false
	var starting := allowed and not engine_state and power_state and not _start_key_used and Input.is_action_pressed(START_ENGINE)
	_start_hold = _start_hold + delta if starting else 0.0
	if _start_hold >= engine_start_hold_seconds:
		_start_hold = 0.0
		_start_key_used = true
		engine_state = true

	var stopping := allowed and engine_state and Input.is_action_pressed(STOP_ENGINE)
	_stop_hold = _stop_hold + delta if stopping else 0.0
	if _stop_hold >= engine_stop_hold_seconds:
		_stop_hold = 0.0
		engine_state = false

	engine_hold_progress = maxf(_start_hold / engine_start_hold_seconds, _stop_hold / engine_stop_hold_seconds)
