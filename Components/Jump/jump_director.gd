class_name JumpDirector
extends InGameSystem
## Runs the game's loop. The crew arrives in a system, where the Cosmic Presence (see [CosmicPresence]) starts
## to close in on them, and has until it catches up to gather resources and repair what they can; then the
## ship jumps to the next system, which is harder, and leaves the presence behind. This node keeps the count,
## the seed and the presence's bar, and carries out each jump:
##
## [codeblock]
## IN_SYSTEM    the Cosmic Presence's bar creeps up.
## CHARGING     the last seconds before it fills (or from the moment a jump is asked for). A countdown
##              tells everyone to get back to the ship.
## WARPING_OUT  a bubble of warp energy forms around the ship, and hides the space outside it.
## SWITCHING    hidden by the bubble: everything outside the ship is deleted (see JumpPurge), the jump
##              count goes up, the presence is left behind (part of its bar is taken off), a new seed is
##              made, anyone left outside is brought aboard, and the new system's stars and asteroids
##              are built (see StarField and ChunkStreamer). The bubble stays until that is done.
## WARPING_IN   the bubble burns away and the ship is in a new system. The presence starts closing in again.
## [/codeblock]
##
## The jump count is how many jumps the ship has made, and the seed of each system comes from the world's
## seed and that count (see [StarSystem]), so the same world always has the same systems in the same order.
## The count and the bar are saved with the world after every jump; loading a world puts the ship at the
## beginning of the system its count points to, with the bar where that jump left it.
##
## [b]Multiplayer.[/b] The host (or a single player) runs all of this. Guests are told each change of phase,
## and the count, seed and arrival point to build the new system from, and build the same space themselves:
## asteroids and stars are never sent, only the numbers they are made from. The bar is sent as where it
## stands and how fast it is going, a second apart, and each guest moves it itself in between.
##
## [b]Testing.[/b] [member debug_fill_time] speeds the presence up in every system, J jumps at once in a
## debug build and K doubles the presence's speed (and back).

## The phase changed. [param phase] is the new one.
signal phase_changed(phase: Phase)
## A jump is about to start (the bubble begins to form). [param target_jump_count] is where it ends up.
signal jump_started(target_jump_count: int)
## A new system was made, hidden by the bubble: the count, the seed and the asteroids all changed.
signal system_changed(system: StarSystem)
## The jump is over: the bubble is gone and the presence is closing in again in the new system. Also sent when
## the world first starts, when the ship arrives in its first system.
signal jump_completed(jump_count: int)
## The jump drive has [param seconds_left] whole seconds left to charge: 10, 9, 8 and so on down to 1.
signal warning(seconds_left: int)

enum Phase {
	IN_SYSTEM,
	CHARGING,
	WARPING_OUT,
	SWITCHING,
	WARPING_IN,
}

## The group the director is in, so anything in the world can find it.
const GROUP: StringName = &"jump_director"
## Put a vehicle in this group to make it the ship that jumps, when [member ship] is not set.
const MAIN_SHIP_GROUP: StringName = &"main_ship"
## A debug build jumps at once when this key is pressed...
const DEBUG_JUMP_KEY := KEY_J
## ...and doubles the Cosmic Presence's speed, or puts it back, when this one is.
const DEBUG_PRESENCE_KEY := KEY_K
## The id of the speed modifier the debug key adds.
const DEBUG_PRESENCE_MODIFIER := "debug_key"
## A guest that has not heard from the host asks again this often.
const SYNC_RETRY_TIME := 3.0
## The host tells guests where the Cosmic Presence's bar is this often.
const PRESENCE_SYNC_TIME := 1.0

@export_group("Setup")
## The ship that jumps, and everything inside it with it. The first vehicle in the [code]main_ship[/code]
## group when left empty.
@export var ship: Vehicle3D
## Builds the asteroids. The child named ChunkStreamer when left empty.
@export var streamer: ChunkStreamer
## The Cosmic Presence. The child named CosmicPresence when left empty.
@export var presence: CosmicPresence
## Builds the stars and their light. The child named StarField when left empty.
@export var star_field: StarField
## How systems get harder, and which kind of system the first one is. The defaults when left empty.
@export var tuning: SystemTuning
## What a jump deletes. The level (the scene in the group gameplay_scene) when left empty.
@export var world_root: Node

@export_group("Sequence")
## How long the jump drive charges, in which everyone is told to get back aboard. It starts when the presence
## is this many seconds from filling the bar, or when a jump is asked for.
@export_range(1.0, 120.0, 0.5, "suffix:s") var charge_time := 10.0
## How long the bubble takes to form around the ship.
@export_range(0.5, 20.0, 0.1, "suffix:s") var warp_out_time := 2.4
## At least this long is spent hidden in the bubble, so the effect is seen whatever the machine.
@export_range(0.0, 20.0, 0.1, "suffix:s") var minimum_hold_time := 1.4
## How long the bubble takes to burn away.
@export_range(0.5, 20.0, 0.1, "suffix:s") var warp_in_time := 2.6
## Building the new system is never waited for longer than this.
@export_range(1.0, 120.0, 1.0, "suffix:s") var generation_timeout := 20.0
## The world begins as if the ship had just arrived: hidden by the bubble while the first system builds.
@export var arrive_at_start := true

@export_group("Space")
## Positions lose precision far from the world's origin (a few millimeters 40 km out, a centimeter or two
## 200 km out), which shows as things shaking. A jump that would leave the ship farther out than this puts
## it back at the origin instead, hidden by the bubble, and everything inside comes along. The ship stays
## where it is otherwise. Zero never moves it.
@export_range(0.0, 200000.0, 100.0, "or_greater", "suffix:m") var recenter_distance := 5000.0

@export_group("Debugging")
## Replaces the time the presence takes to cross the whole bar in every system, to try the loop without
## waiting. Zero uses the real times.
@export_range(0.0, 3600.0, 1.0, "suffix:s") var debug_fill_time := 0.0
## The seed of a world that is not in a save slot (one started straight from the editor). Zero is random.
@export var debug_seed := 0
## Makes every system, the first included, this kind of system, to see how a template turns out without waiting for
## the odds. Empty uses the real odds.
@export var debug_template: SystemTemplate
## Lets J start a jump, and K double the presence's speed, in a debug build.
@export var debug_keys := true

## How many jumps the ship has made. The system it is in is this one.
var jump_count := 0
## What every system of this world is built from.
var world_seed := 0
## The system the ship is in, or null before the first is built.
var system: StarSystem
var phase := Phase.IN_SYSTEM

var _bubble: WarpBubble3D
## The system's own scene, if its template has one (see [member SystemTemplate.scene]).
var _special: Node
var _level_root: Node
var _phase_time := 0.0
var _started := false
var _first_arrival := false
var _awaiting_sync := false
var _sync_wait := 0.0
var _presence_sync_wait := 0.0
var _generation_wait := 0.0
var _charge_second := 0


func _ready() -> void:
	super._ready()
	add_to_group(GROUP)
	if tuning == null:
		tuning = SystemTuning.new()
	_resolve_references()
	presence.running = false
	presence.aggression_start = tuning.aggression_start
	presence.speed_changed.connect(_on_presence_speed_changed)
	_bubble = WarpBubble3D.new()
	_bubble.name = "WarpBubble"
	get_tree().node_added.connect(_on_node_added)
	multiplayer.peer_connected.connect(_on_peer_connected)
	# Everything in the level is ready after this frame, so it can be built around and measured.
	_start.call_deferred()


func _exit_tree() -> void:
	if is_instance_valid(_bubble):
		_bubble.queue_free()
	_clear_special()


func _process(delta: float) -> void:
	if not _started:
		return
	if _awaiting_sync:
		_sync_wait += delta
		if _sync_wait >= SYNC_RETRY_TIME:
			_sync_wait = 0.0
			_ask_for_state()
		return
	# The presence closes in while the crew is in the system, and holds still while the ship jumps.
	presence.running = phase == Phase.IN_SYSTEM or phase == Phase.CHARGING
	match phase:
		Phase.IN_SYSTEM:
			if _is_authority() and presence.get_time_to_full() <= charge_time:
				_enter_phase(Phase.CHARGING)
		Phase.CHARGING:
			_phase_time += delta
			_announce_countdown()
			if _phase_time >= charge_time and _is_authority():
				_enter_phase(Phase.WARPING_OUT)
		Phase.WARPING_OUT:
			_phase_time += delta
			if _phase_time >= warp_out_time and _is_authority():
				_enter_phase(Phase.SWITCHING)
		Phase.SWITCHING:
			_phase_time += delta
			_generation_wait += delta
			if _is_authority() and _phase_time >= minimum_hold_time and _is_built():
				_enter_phase(Phase.WARPING_IN)
		Phase.WARPING_IN:
			_phase_time += delta
			if _phase_time >= warp_in_time and _is_authority():
				_enter_phase(Phase.IN_SYSTEM)
	_sync_presence(delta)
	_update_bubble()


func _unhandled_key_input(event: InputEvent) -> void:
	if not debug_keys or not OS.is_debug_build():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == DEBUG_JUMP_KEY:
		request_jump()
	elif key.keycode == DEBUG_PRESENCE_KEY and _is_authority() and is_instance_valid(presence):
		if presence.has_speed_modifier(DEBUG_PRESENCE_MODIFIER):
			presence.remove_speed_modifier(DEBUG_PRESENCE_MODIFIER)
		else:
			presence.add_speed_modifier(DEBUG_PRESENCE_MODIFIER, 100.0)


# --- Asking about it -----------------------------------------------------------------

## True while the ship could be told to jump now.
func can_jump() -> bool:
	return _started and phase == Phase.IN_SYSTEM and is_instance_valid(ship) and not _awaiting_sync


## True from the moment the last countdown begins until the new system is there.
func is_jumping() -> bool:
	return phase != Phase.IN_SYSTEM


## True while the world has only just begun and the ship is arriving in its first system, which it did
## not jump to.
func is_first_arrival() -> bool:
	return _first_arrival


## Whether the bubble is whole right now, which is when the world behind it is being changed.
func is_hidden_by_bubble() -> bool:
	return is_instance_valid(_bubble) and _bubble.progress >= 0.999


## How far through the current phase it is, from 0 to 1. IN_SYSTEM is how full the Cosmic Presence's bar is,
## and CHARGING runs from 0 to 1 over the countdown.
func get_phase_progress() -> float:
	match phase:
		Phase.IN_SYSTEM:
			return presence.progress
		Phase.CHARGING:
			return clampf(_phase_time / maxf(charge_time, 0.001), 0.0, 1.0)
		Phase.WARPING_OUT:
			return clampf(_phase_time / maxf(warp_out_time, 0.001), 0.0, 1.0)
		Phase.WARPING_IN:
			return clampf(_phase_time / maxf(warp_in_time, 0.001), 0.0, 1.0)
	return 1.0


## Seconds left to charge while the jump drive is charging, and 0 the rest of the time.
func get_charge_left() -> float:
	if phase != Phase.CHARGING:
		return 0.0
	return maxf(charge_time - _phase_time, 0.0)


## Seconds until the Cosmic Presence fills its bar at the speed it is going now.
func get_time_to_full() -> float:
	return presence.get_time_to_full()


## How long the presence takes to cross the whole bar in the current system at normal speed, in seconds.
func get_fill_time() -> float:
	if system == null:
		return 0.0
	return debug_fill_time if debug_fill_time > 0.0 else system.presence_fill_time


func get_bubble() -> WarpBubble3D:
	return _bubble


## Everything about where the loop is, for tests and a debug overlay.
func get_snapshot() -> Dictionary:
	return {
		"phase": phase,
		"jump_count": jump_count,
		"world_seed": world_seed,
		"system_seed": system.system_seed if system != null else 0,
		"presence": presence.progress,
		"presence_rate": presence.get_rate(),
		"bubble": _bubble.progress if is_instance_valid(_bubble) else 0.0,
	}


# --- Telling it what to do ---------------------------------------------------------------

## Starts the jump now: the drive begins to charge, which is then run through as usual (the Cosmic Presence's
## bar is left where it is until the jump takes some off). A guest asks the host. Returns whether the request was made.
func request_jump() -> bool:
	if not can_jump():
		return false
	if _is_authority():
		_enter_phase(Phase.CHARGING)
		return true
	_net_request_jump.rpc_id(NetworkSession.SERVER_PEER_ID)
	return true


## Sets the bar, for tests and debugging. Only the host (or a single player) has a bar to set.
func set_presence(progress: float) -> void:
	if _is_authority() and phase == Phase.IN_SYSTEM:
		presence.progress = progress


# --- Starting ----------------------------------------------------------------------------

func _start() -> void:
	if _started:
		return
	if not is_instance_valid(streamer) or not is_instance_valid(ship):
		push_warning("%s needs a ship and a ChunkStreamer to run the jump loop." % get_path())
		return
	_bubble.attach_to(ship)
	_track_everything()
	_started = true
	if _is_authority():
		_load_world_state()
		_make_system(jump_count, ship.global_position)
		if arrive_at_start:
			# The ship drops out of warp: the bubble is up while the first system builds, then burns away.
			streamer.request_fast_load()
			_first_arrival = true
			_set_phase(Phase.SWITCHING)
			_bubble.set_state(1.0)
		else:
			streamer.load_all_now()
			_set_phase(Phase.IN_SYSTEM)
	else:
		# A guest knows nothing until the host says what the world is like.
		_awaiting_sync = true
		_set_phase(Phase.SWITCHING)
		_bubble.set_state(1.0)
		_ask_for_state()


func _ask_for_state() -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_net_request_state.rpc_id(NetworkSession.SERVER_PEER_ID)


## The count, seed and presence of a saved world, or fresh ones for a world that is not saved.
func _load_world_state() -> void:
	var slot := WorldSaves.active_slot
	if slot > 0:
		var info := WorldSaves.read_slot(slot)
		if info["exists"] and not info["corrupt"]:
			jump_count = info["jump_count"]
			world_seed = WorldSaves.ensure_world_seed(slot)
			presence.progress = info["presence"] if info["presence"] >= 0.0 else tuning.starting_presence
			return
	jump_count = 0
	world_seed = debug_seed if debug_seed != 0 else WorldSaves.new_world_seed()
	presence.progress = tuning.starting_presence


func _resolve_references() -> void:
	if not is_instance_valid(streamer):
		streamer = get_node_or_null("ChunkStreamer") as ChunkStreamer
		if streamer == null:
			for child in get_children():
				if child is ChunkStreamer:
					streamer = child as ChunkStreamer
					break
	if not is_instance_valid(presence):
		presence = get_node_or_null("CosmicPresence") as CosmicPresence
		if presence == null:
			for child in get_children():
				if child is CosmicPresence:
					presence = child as CosmicPresence
					break
		if presence == null:
			# A director made in code, or a scene saved without one, still has a presence to run the loop by.
			presence = CosmicPresence.new()
			presence.name = "CosmicPresence"
			add_child(presence)
	if not is_instance_valid(star_field):
		star_field = get_node_or_null("StarField") as StarField
		if star_field == null:
			for child in get_children():
				if child is StarField:
					star_field = child as StarField
					break
	if not is_instance_valid(ship):
		for node in get_tree().get_nodes_in_group(MAIN_SHIP_GROUP):
			if node is Vehicle3D:
				ship = node as Vehicle3D
				break
	var node := get_parent()
	while node != null and not node.is_in_group(InGameUIHandler.GAMEPLAY_SCENE_GROUP):
		node = node.get_parent()
	_level_root = node if node != null else get_parent()
	if not is_instance_valid(world_root):
		world_root = _level_root


func _track_everything() -> void:
	streamer.track(ship)
	for player in JumpPurge.find_players(_level_root):
		streamer.track(player)


func _on_node_added(node: Node) -> void:
	if node is Player and is_instance_valid(streamer):
		streamer.track.call_deferred(node as Player)


# --- The phases ---------------------------------------------------------------------------------

## Sends [signal warning] for every whole second left while the drive charges.
func _announce_countdown() -> void:
	var second := ceili(maxf(charge_time - _phase_time, 0.0))
	if second != _charge_second:
		_charge_second = second
		if second > 0:
			warning.emit(second)


## Moves to [param new_phase] and, as the host, does what that phase starts with and tells the guests.
func _enter_phase(new_phase: Phase) -> void:
	var was := phase
	_set_phase(new_phase)
	if new_phase == Phase.SWITCHING:
		_switch_system(jump_count + 1)
	_announce_phase(was, new_phase)
	_broadcast_phase()


## Changes the phase on this machine, whoever decided on it.
func _set_phase(new_phase: Phase) -> void:
	phase = new_phase
	_phase_time = 0.0
	_generation_wait = 0.0
	_charge_second = ceili(charge_time) + 1
	if new_phase == Phase.WARPING_OUT:
		# The ship may have grown or shrunk since the bubble was last sized.
		_bubble.fit_to(ship)
	phase_changed.emit(new_phase)


## Says what a change of phase means to the game: a jump is starting, or has ended. Every machine does,
## whether it ran the change itself or was told of it.
func _announce_phase(was: Phase, now: Phase) -> void:
	if now == Phase.WARPING_OUT:
		jump_started.emit(jump_count + 1)
	elif now == Phase.IN_SYSTEM and was == Phase.WARPING_IN:
		_first_arrival = false
		jump_completed.emit(jump_count)


## Whether the new system is built, or has been waited for long enough.
func _is_built() -> bool:
	return streamer.is_settled() or _generation_wait >= generation_timeout


## Throws away everything outside the ship and builds the system for jump [param target], from the same
## seed, leaving the Cosmic Presence behind. Runs hidden behind the bubble. The first system of a world was
## already being built.
func _switch_system(target: int) -> void:
	JumpPurge.purge(world_root, ship, streamer)
	# Anyone outside is brought aboard first, where the ship is, so that if the ship is then moved (see
	# [member recenter_distance]) the interior carries them with everyone else, once.
	JumpPurge.recall_players(_level_root, ship)
	_stop_ship()
	var arrival := _get_arrival_point()
	_move_ship_to(arrival)
	_make_system(target, arrival)
	presence.relieve(tuning.jump_relief)
	if WorldSaves.active_slot > 0:
		WorldSaves.record_jump(WorldSaves.active_slot, jump_count, presence.progress)
	streamer.request_fast_load()


func _stop_ship() -> void:
	ship.linear_velocity = Vector3.ZERO
	ship.angular_velocity = Vector3.ZERO


## Where the ship arrives: where it is, or the origin when it has drifted too far for positions to stay precise.
func _get_arrival_point() -> Vector3:
	if recenter_distance > 0.0 and ship.global_position.length() > recenter_distance:
		return Vector3.ZERO
	return ship.global_position


## Puts the ship at [param point], turned as it was. Everyone and everything inside comes along, carried
## by the ship's interior as it carries them when the ship flies (see [VehicleInterior3D]).
func _move_ship_to(point: Vector3) -> void:
	if ship.global_position.is_equal_approx(point):
		return
	var moved := ship.global_transform
	moved.origin = point
	ship.global_transform = moved
	# It was not flying there, so it must not be drawn sliding in from where it was.
	ship.reset_physics_interpolation()


## Makes the system for jump [param target] and starts building it around the ship, which is at
## [param arrival]. Nothing is built in the area kept clear around that point.
func _make_system(target: int, arrival: Vector3) -> void:
	jump_count = target
	system = StarSystem.create(world_seed, jump_count, tuning, arrival, debug_template)
	presence.base_speed = 1.0 / maxf(get_fill_time(), 1.0)
	streamer.begin_system(system)
	if is_instance_valid(star_field):
		star_field.show_system(system)
	var temperature_handler := InGameHandler.get_temperature_handler_or_null()
	if temperature_handler != null:
		temperature_handler.set_system_temperature(system.temperature)
	_spawn_special(system)
	system_changed.emit(system)


## Puts the system's own scene (see [member SystemTemplate.scene]) into the world in place of the last system's, if its
## template has one. It is made on every machine from the system alone.
func _spawn_special(for_system: StarSystem) -> void:
	_clear_special()
	if for_system.template == null or for_system.template.scene == null:
		return
	var made := for_system.template.scene.instantiate()
	if made == null:
		return
	if made.has_method(&"setup"):
		made.call(&"setup", for_system)
	add_child(made)
	_special = made


func _clear_special() -> void:
	if is_instance_valid(_special):
		var parent := _special.get_parent()
		if parent != null:
			parent.remove_child(_special)
		_special.queue_free()
	_special = null


## The scene of the system's own that is in the world now, or null.
func get_special_scene() -> Node:
	return _special if is_instance_valid(_special) else null


func _update_bubble() -> void:
	match phase:
		Phase.WARPING_OUT:
			_bubble.set_state(get_phase_progress())
		Phase.SWITCHING:
			_bubble.set_state(1.0)
		Phase.WARPING_IN:
			var leaving := get_phase_progress()
			_bubble.set_state(1.0 - leaving, leaving)
		_:
			_bubble.set_state(0.0)


# --- Multiplayer ----------------------------------------------------------------------------------

## The host, or a single player (who is both): the one that keeps the bar.
func _is_authority() -> bool:
	return not NetworkSession.is_client()


func _has_guests() -> bool:
	return multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer and not multiplayer.get_peers().is_empty()


func _broadcast_phase() -> void:
	if _has_guests():
		_net_phase.rpc(phase, jump_count, world_seed, presence.progress, presence.get_rate(), system.arrival_position, _phase_time)


## The host tells its guests where the bar is every so often, and straight away when its speed changes.
func _sync_presence(delta: float) -> void:
	if not _is_authority():
		return
	_presence_sync_wait += delta
	if _presence_sync_wait >= PRESENCE_SYNC_TIME:
		_presence_sync_wait = 0.0
		if _has_guests():
			_net_presence.rpc(presence.progress, presence.get_rate())


func _on_presence_speed_changed(_multiplier: float) -> void:
	if _started and _is_authority() and _has_guests() and not _awaiting_sync:
		_presence_sync_wait = 0.0
		_net_presence.rpc(presence.progress, presence.get_rate())


func _on_peer_connected(peer_id: int) -> void:
	if _started and _is_authority() and not _awaiting_sync:
		_net_phase.rpc_id(peer_id, phase, jump_count, world_seed, presence.progress, presence.get_rate(), system.arrival_position, _phase_time)


## A guest asks where the loop is.
@rpc("any_peer", "call_remote", "reliable")
func _net_request_state() -> void:
	if not _is_authority() or not _started or system == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0:
		_net_phase.rpc_id(sender, phase, jump_count, world_seed, presence.progress, presence.get_rate(), system.arrival_position, _phase_time)


## A guest asks for a jump now.
@rpc("any_peer", "call_remote", "reliable")
func _net_request_jump() -> void:
	if _is_authority():
		request_jump()


## The host says the loop is in [param new_phase], [param in_phase] seconds into it, at [param count] jumps in a
## world with [param seed_value], with the Cosmic Presence's bar at [param bar] and moving [param rate] of it a
## second, and that the ship arrived at [param arrival].
@rpc("authority", "call_remote", "reliable")
func _net_phase(new_phase: int, count: int, seed_value: int, bar: float, rate: float, arrival: Vector3, in_phase: float) -> void:
	if not _started or NetworkSession.is_server():
		return
	var first_message := _awaiting_sync
	_awaiting_sync = false
	world_seed = seed_value
	if system == null or count != jump_count or system.arrival_position != arrival:
		# The jump the host just made, or the system a guest joined in the middle of. After a jump the ship
		# is where the host's arrived, whatever the host's ship has been doing since (the ships are not
		# kept in step yet), and a guest who joins has no way to know where the ship is now.
		if not first_message:
			JumpPurge.purge(world_root, ship, streamer)
			_move_ship_to(arrival)
		_make_system(count, arrival)
		streamer.request_fast_load()
	presence.follow(bar, rate)
	if new_phase != phase or first_message:
		var was := phase
		_set_phase(new_phase as Phase)
		_phase_time = in_phase
		_announce_phase(was, new_phase as Phase)
	if first_message and new_phase == Phase.IN_SYSTEM:
		streamer.load_all_now()


## The host says where the Cosmic Presence's bar is, and how fast it is going.
@rpc("authority", "call_remote", "unreliable_ordered")
func _net_presence(bar: float, rate: float) -> void:
	if not _started or NetworkSession.is_server() or _awaiting_sync:
		return
	presence.follow(bar, rate)
