extends Node
## Two-process check for CharacterNetSync: run one server and one client.
##
## godot --headless --path . res://Components/Movement/Testing/NetSyncTest.tscn -- server <latency_ms> <loss_%> <seconds>
## godot --headless --path . res://Components/Movement/Testing/NetSyncTest.tscn -- client <latency_ms> <loss_%> <seconds>
##
## Only the server's world contains a wall, so the client's prediction walks
## straight through it and has to be corrected. Each process prints a line the
## runner script compares: where the player ended up on the server, on the client
## and as the other side sees the NPC.

const PORT := 27055
const SCRIPT_START_TICK := 90

var mode := "server"
var latency_ms := 0.0
var loss_percent := 0.0
var run_seconds := 14.0
var speed_hack := false

var _players: Node3D
var _my_player: CharacterBody3D
var _npc: CharacterBody3D
var _started_at := 0.0
var _finished := false
var _reconcile_count := 0
var _largest_error := 0.0
var _peer_joined := false
var _joined_at := 0.0
var _teleported := false


class ScriptedPlayer extends CharacterController:
	var tick := 0
	## Walks sideways forever, to measure how far the server lets a client get.
	var endless_strafe := false

	func poll_intent(_delta: float) -> MoveIntent:
		tick += 1
		var intent := MoveIntent.new()
		var t := tick - SCRIPT_START_TICK
		if t < 0:
			return intent
		if endless_strafe:
			intent.move = Vector2(1.0, 0.0)
			return intent
		if t < 120:
			intent.move = Vector2(0.0, -1.0)
		elif t == 120:
			intent.jump_pressed = true
		elif t >= 140 and t < 240:
			intent.move = Vector2(1.0, 0.0)
			intent.sprint = true
		elif t >= 240 and t < 330:
			intent.move = Vector2(-0.7, 0.7)
			intent.yaw = 0.6
		elif t >= 430 and t < 530:
			intent.move = Vector2(0.0, -1.0)
			intent.crouch = true
		return intent


class ScriptedNpc extends CharacterController:
	var tick := 0

	func poll_intent(_delta: float) -> MoveIntent:
		tick += 1
		var intent := MoveIntent.new()
		# Pace back and forth, then stand still for the last stretch.
		if tick < 600:
			intent.move = Vector2(0.0, -1.0)
			intent.yaw = PI if (tick / 150) % 2 == 1 else 0.0
		return intent


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = args[0]
	if args.size() > 1:
		latency_ms = float(args[1])
	if args.size() > 2:
		loss_percent = float(args[2])
	if args.size() > 3:
		run_seconds = float(args[3])
	if args.size() > 4:
		speed_hack = args[4] == "hack"
	_build_world()
	if mode == "server":
		_start_server()
	else:
		_start_client()


func _process(_delta: float) -> void:
	if _finished:
		return
	# TELEPORT=1: the server moves the remote player mid-run, which every peer must follow.
	if (
		mode == "server"
		and OS.has_environment("TELEPORT")
		and not _teleported
		and _joined_at > 0.0
		and Time.get_ticks_msec() / 1000.0 - _joined_at > 5.0
	):
		_teleported = true
		for child in _players.get_children():
			if child.name != "NPC":
				(child.get_node("Controller") as CharacterController).teleport(
					Transform3D(Basis.IDENTITY, Vector3(20.0, 0.05, 20.0))
				)
				print("INFO server teleported ", child.name)
	if mode == "client" and not _peer_joined:
		return
	if _started_at == 0.0:
		_started_at = Time.get_ticks_msec() / 1000.0
	if Time.get_ticks_msec() / 1000.0 - _started_at >= run_seconds:
		_finish()


func _finish() -> void:
	_finished = true
	if mode == "server":
		for child in _players.get_children():
			var body := child as CharacterBody3D
			print("RESULT server %s %.4f %.4f %.4f" % [body.name, body.global_position.x, body.global_position.y, body.global_position.z])
	else:
		for child in _players.get_children():
			var body := child as CharacterBody3D
			print("RESULT client %s %.4f %.4f %.4f" % [body.name, body.global_position.x, body.global_position.y, body.global_position.z])
		print("INFO reconciles=%d largest_error=%.3f" % [_reconcile_count, _largest_error])
	get_tree().quit()


func _build_world() -> void:
	var world := Node3D.new()
	world.name = "World"
	add_child(world)
	var field := DirectionalGravityField3D.new()
	var field_shape := CollisionShape3D.new()
	var field_box := BoxShape3D.new()
	field_box.size = Vector3(300.0, 200.0, 300.0)
	field_shape.shape = field_box
	field_shape.position = Vector3(0.0, 80.0, 0.0)
	field.add_child(field_shape)
	world.add_child(field)
	_add_box(world, Vector3(0.0, -0.5, 0.0), Vector3(200.0, 1.0, 200.0))
	if mode == "server":
		# The client's world has no such wall.
		_add_box(world, Vector3(0.0, 1.5, -6.0), Vector3(8.0, 3.0, 0.5))
	_players = Node3D.new()
	_players.name = "Players"
	add_child(_players)


func _add_box(parent: Node, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	parent.add_child(body)


func _start_server() -> void:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, 4)
	if error != OK:
		print("ERROR could not host: ", error)
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	_npc = _make_character("NPC", 1, ScriptedNpc.new(), Vector3(8.0, 0.05, 0.0))
	_players.add_child(_npc)
	multiplayer.peer_connected.connect(func(id: int) -> void:
		print("INFO server: peer %d joined" % id)
		_joined_at = Time.get_ticks_msec() / 1000.0
		_players.add_child(_make_character("P%d" % id, id, CharacterController.new(), Vector3(0.0, 0.05, 0.0)))
	)
	print("INFO server listening")


func _start_client() -> void:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client("127.0.0.1", PORT)
	if error != OK:
		print("ERROR could not connect: ", error)
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(func() -> void:
		var id := multiplayer.get_unique_id()
		print("INFO client: connected as %d" % id)
		var scripted := ScriptedPlayer.new()
		scripted.endless_strafe = speed_hack or OS.has_environment("ENDLESS")
		_my_player = _make_character("P%d" % id, id, scripted, Vector3(0.0, 0.05, 0.0))
		_players.add_child(_my_player)
		_npc = _make_character("NPC", 1, CharacterController.new(), Vector3(8.0, 0.05, 0.0))
		_players.add_child(_npc)
		var sync := _my_player.get_node("CharacterNetSync") as CharacterNetSync
		sync.reconciled.connect(func(error_distance: float, _replayed: int) -> void:
			_reconcile_count += 1
			_largest_error = maxf(_largest_error, error_distance)
		)
		if speed_hack:
			# Run the client twice as fast while its simulation still assumes 1/60 s a
			# step: it sends twice the commands it is entitled to.
			Engine.physics_ticks_per_second = 120
		_peer_joined = true
	)


func _make_character(
	node_name: String,
	authority: int,
	controller: CharacterController,
	position: Vector3,
) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.name = node_name
	body.collision_layer = PhysicsLayers.CREATURES if node_name == "NPC" else PhysicsLayers.PLAYERS
	body.collision_mask = PhysicsLayers.CREATURE_MASK if node_name == "NPC" else PhysicsLayers.PLAYER_MASK
	body.set_multiplayer_authority(authority)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.9, 0.0)
	body.add_child(shape)
	var stats := MovementAttribute.new()
	stats.name = "MovementAttribute"
	body.add_child(stats)
	var orientor := Orientator.new()
	orientor.name = "Orientor"
	body.add_child(orientor)
	controller.name = "Controller"
	body.add_child(controller)
	var sync := CharacterNetSync.new()
	sync.name = "CharacterNetSync"
	sync.simulated_latency_ms = latency_ms
	sync.simulated_packet_loss_percent = loss_percent
	body.add_child(sync)
	body.position = position
	return body
