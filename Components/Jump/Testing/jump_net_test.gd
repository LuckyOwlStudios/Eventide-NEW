extends Node
## Two-process check that a guest follows the host through jumps: run one server and one client.
##
## godot --headless --path . res://Components/Jump/Testing/JumpNetTest.tscn -- server
## godot --headless --path . res://Components/Jump/Testing/JumpNetTest.tscn -- client
##
## Each process builds the same small world (the real Mule, a jump director) and prints lines the runner
## script compares. The host starts a jump; the guest asks for the next one, which tests the request going
## the other way. The guest's ship is not where the host's is, to show the new system is built around where
## the HOST says the ship arrived. Items lying outside the guest's ship must be deleted by the guest's own
## purge, since nothing about them is sent.
##
## Run it with run_jump_net_test.ps1 (from a copy of the project while the editor is open).

const MULE_SCENE := preload("res://Scenes/Vehicles/Mule/Mule.tscn")
const DIRECTOR_SCENE := preload("res://Components/Jump/JumpDirector.tscn")
const PORT := 27056

var role := "server"
var _world: Node3D
var _mule: Mule
var _director: JumpDirector
var _crate_outside: RigidBody3D
var _events: Array[String] = []
var _bubble_seen := false
var _asked := false
var _joined_at := 0.0
var _finished := false
var _started_at := 0.0
var _failures := 0
var _phases_seen: Array[int] = []
var _started_jumps: Array[int] = []
var _completed_jumps: Array[int] = []
var _first_jump_signature := ""
var _first_jump_system_seed := 0
var _reporting := false
var _first_bar := -1.0


func _ready() -> void:
	InGameUIHandler.is_ui_open = false
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		role = args[0]
	_started_at = Time.get_ticks_msec() / 1000.0
	WorldSaves.active_slot = 0
	if role == "server":
		_start_server()
	else:
		_start_client()


func _process(_delta: float) -> void:
	if _finished:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _started_at > 70.0:
		print("RESULT %s timeout" % role)
		_finish()
		return
	if not is_instance_valid(_director) or _director.system == null:
		return
	if is_instance_valid(_director.get_bubble()) and _director.get_bubble().progress > 0.99 and _director.phase == JumpDirector.Phase.SWITCHING:
		_bubble_seen = true
	if _director.jump_count == 1 and _director.phase == JumpDirector.Phase.IN_SYSTEM and _first_jump_signature.is_empty():
		_first_jump_signature = _signature()
		_first_jump_system_seed = _director.system.system_seed
		_first_bar = _director.presence.progress
		print("INFO %s has jump 1 (%d), the presence at %.3f" % [role, _director.system.system_seed, _first_bar])
	if role == "server":
		# Once the guest is there, the host starts the first jump.
		if _joined_at > 0.0 and not _asked and now - _joined_at > 3.0 and _director.can_jump():
			_asked = true
			print("INFO server starts jump 1")
			_director.request_jump()
	else:
		# The guest asks for the second jump once the first is over.
		if not _first_jump_signature.is_empty() and not _asked:
			_asked = true
			print("INFO client asks for jump 2")
			_director.request_jump()
	if _director.jump_count >= 2 and _director.phase == JumpDirector.Phase.IN_SYSTEM and _director.presence.running and not _reporting:
		_reporting = true
		if role == "server":
			# The crew does something that draws the presence on: it must reach the guest too.
			_director.presence.add_speed_modifier("net_test", 100.0)
		await get_tree().create_timer(1.5).timeout
		_report()


func _report() -> void:
	if _finished:
		return
	var crate_gone := not is_instance_valid(_crate_outside)
	var presence := _director.presence
	print("RESULT %s count=%d seed=%d system=%d arrival=%s field=%d phase=%d first_system=%d first_field=%s crate_outside_gone=%s bubble_seen=%s started=%s completed=%s ship=%s bar=%.4f rate=%.7f multiplier=%.3f first_bar=%.4f stars=%d heat=%.4f" % [
		role, _director.jump_count, _director.world_seed, _director.system.system_seed, str(_director.system.arrival_position),
		_signature().hash(), _director.phase, _first_jump_system_seed, str(_first_jump_signature.hash()), str(crate_gone), str(_bubble_seen), str(_started_jumps).replace(" ", ""), str(_completed_jumps).replace(" ", ""), str(_mule.global_position.snapped(Vector3.ONE * 0.5)).replace(" ", ""),
		presence.progress, presence.get_rate(), presence.get_speed_multiplier(), _first_bar, _director.system.get_star_count(), _director.system.heat,
	])
	print("PHASES %s %s" % [role, str(_phases_seen)])
	_finish()


func _finish() -> void:
	_finished = true
	get_tree().quit()


## Where every asteroid within 1200 m of the arrival point is, to the centimeter, as one string. (Each machine
## loads the space around its own ship, which is a few meters from the other's, so only what both
## have loaded is compared.)
func _signature() -> String:
	var parts: PackedStringArray = []
	var streamer := _director.streamer
	var arrival := _director.system.arrival_position
	var coords := streamer.get_loaded_coords()
	coords.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.x < b.x or (a.x == b.x and (a.y < b.y or (a.y == b.y and a.z < b.z))))
	for coord in coords:
		var chunk := streamer.get_chunk(coord)
		if chunk != null:
			for child in chunk.get_children():
				var position := (child as Node3D).global_position
				if position.distance_to(arrival) < 1200.0:
					parts.append("%.2f,%.2f,%.2f" % [position.x, position.y, position.z])
	return ";".join(parts)


func _build_world() -> void:
	_world = Node3D.new()
	_world.name = "World"
	_world.add_to_group(InGameUIHandler.GAMEPLAY_SCENE_GROUP)
	add_child(_world)
	_mule = MULE_SCENE.instantiate() as Mule
	_mule.name = "Mule"
	_world.add_child(_mule)
	_director = DIRECTOR_SCENE.instantiate() as JumpDirector
	_director.name = "JumpDirector"
	_director.ship = _mule
	var tuning := SystemTuning.new()
	# The bar starts half full and a jump takes only a little off, so there is plenty of it left to compare.
	tuning.starting_presence = 0.5
	tuning.jump_relief = 0.05
	_director.tuning = tuning
	_director.debug_fill_time = 60.0
	_director.charge_time = 2.0
	_director.warp_out_time = 0.5
	_director.minimum_hold_time = 0.3
	_director.warp_in_time = 0.5
	_director.arrive_at_start = false
	_director.debug_seed = 987654321
	_director.phase_changed.connect(func(phase: JumpDirector.Phase) -> void:
		_phases_seen.append(phase)
		print("EVENT %s phase %d count %d" % [role, phase, _director.jump_count])
	)
	_director.jump_started.connect(func(count: int) -> void: _started_jumps.append(count))
	_director.jump_completed.connect(func(count: int) -> void: _completed_jumps.append(count))
	_world.add_child(_director)
	# Something lying outside the ship, on this machine only.
	_crate_outside = RigidBody3D.new()
	_crate_outside.collision_layer = PhysicsLayers.ITEMS
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.6, 0.6)
	shape.shape = box
	_crate_outside.add_child(shape)
	_world.add_child(_crate_outside)
	_crate_outside.global_position = Vector3(300.0, 0.0, 50.0)
	if role == "client":
		# The guest's ship is not where the host's is.
		_mule.global_position = Vector3(7.0, 0.0, -3.0)


func _start_server() -> void:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, 4)
	if error != OK:
		print("ERROR could not host: ", error)
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(func(id: int) -> void:
		print("INFO server: peer %d joined" % id)
		_joined_at = Time.get_ticks_msec() / 1000.0
	)
	_build_world()
	print("INFO server listening")


func _start_client() -> void:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client("127.0.0.1", PORT)
	if error != OK:
		print("ERROR could not connect: ", error)
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	# The world is loaded once connected, as in the game.
	multiplayer.connected_to_server.connect(func() -> void:
		print("INFO client: connected as %d" % multiplayer.get_unique_id())
		_build_world()
	)
