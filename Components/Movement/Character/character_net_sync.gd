@icon("uid://dfmh403n6k2ac")
class_name CharacterNetSync
extends Node
## Keeps a CharacterController's character in step across the network, with the server
## in charge.
##
## Clients never say where they are, only what they want to do: each physics tick
## the owner sends a numbered [MoveIntent]. The server simulates those intents
## with the same controller code at a fixed rate, so it alone decides positions, speed
## and what a jump or crouch is allowed to do, and tells everyone the result.
##
## The owning client does not wait for that. It simulates its own intents at once
## (prediction), remembers them, and when the server reports the state after
## command N it checks its own state after command N. If they agree nothing
## happens; if not, it rewinds to the server's state and replays every command
## the server has not yet seen (reconciliation). Small differences fade out of
## the camera instead of snapping. Everyone else's characters are shown a moment
## in the past, blended between the server's snapshots.

signal role_changed(new_role: Role)
## Emitted on the owning client after a misprediction was corrected.
signal reconciled(position_error: float, replayed_commands: int)

enum Role {
	## Offline play, or a character this process fully controls (the server's own
	## player, or an AI). Simulates straight from its controller.
	LOCAL,
	## This client owns the character: predict it and correct from the server.
	PREDICTED_CLIENT,
	## The server runs a remote player's character from the commands they send.
	SERVER_REMOTE,
	## Someone else's character on a client: show interpolated snapshots.
	PROXY,
}

const NETWORK_CHANNEL := 7
const COMMAND_BYTES := 4 + MoveIntent.ENCODED_SIZE
const MAX_COMMANDS_PER_PACKET := 4
## A sequence number this far below the last one means the sender restarted.
const SEQUENCE_RESTART_GAP := 300
const MAX_PROXY_SNAPSHOTS := 32

## The character controller this node drives. Found next to this node when left empty.
@export var controller: CharacterController
## The peer whose input drives this character. Zero means the body's multiplayer
## authority, the same rule the Rotator uses.
@export var input_peer_id := 0

@export_group("Server")
## How often the server tells everyone where the character is.
@export_range(0.01, 0.5, 0.01, "suffix:s") var snapshot_interval := 0.05
## Most commands the server holds for one player before throwing the oldest away.
@export_range(2, 64) var max_queued_commands := 16
## After a lag spike the server may run this many commands in one tick to catch up.
## It earns one command of credit per tick, so a client can never run faster than
## real time for long, however fast it sends.
@export_range(1, 16) var catch_up_allowance := 4

@export_group("Prediction")
## A disagreement under this distance is rounding, not a misprediction.
@export_range(0.001, 1.0, 0.001, "suffix:m") var position_tolerance := 0.03
@export_range(0.01, 5.0, 0.01, "suffix:m/s") var velocity_tolerance := 0.2
## Corrections bigger than this snap instead of gliding.
@export_range(0.1, 50.0, 0.1, "suffix:m") var snap_distance := 3.0
## How many unacknowledged commands a client remembers (60 is one second).
@export_range(8, 600) var max_pending_commands := 120

@export_group("Other Players")
## Other players are shown this far in the past so there are always two
## snapshots to blend between.
@export_range(0.0, 0.5, 0.01, "suffix:s") var interpolation_delay := 0.1
## How long a missing snapshot is covered by continuing the last velocity.
@export_range(0.0, 1.0, 0.01, "suffix:s") var max_extrapolation := 0.25

@export_group("Debug")
## Delays everything this node sends, to try lag in the editor.
@export_range(0.0, 1000.0, 1.0, "suffix:ms") var simulated_latency_ms := 0.0
## Randomly drops this share of everything this node sends.
@export_range(0.0, 100.0, 0.5, "suffix:%") var simulated_packet_loss_percent := 0.0

var role := Role.LOCAL

var _sequence := 0
var _history: Array[PendingCommand] = []
var _last_applied_ack := 0
var _pending_snapshot: Snapshot
var _epoch := 0

var _server_queue: Array[PendingCommand] = []
var _last_received_sequence := 0
var _last_processed_sequence := 0
var _snapshot_elapsed := 0.0
var _command_credit := 0.0

var _proxy_snapshots: Array[Snapshot] = []
var _delayed: Array[Dictionary] = []


class PendingCommand:
	var sequence := 0
	var intent: MoveIntent
	## The client's own state right after simulating this command.
	var state: MoveState


class Snapshot:
	var acknowledged_sequence := 0
	var epoch := 0
	var state: MoveState
	var received_at := 0.0


func _ready() -> void:
	if not is_instance_valid(controller):
		controller = _find_controller()
	if not is_instance_valid(controller):
		push_error("CharacterNetSync needs a CharacterController next to it.")
		set_physics_process(false)
		return
	controller.net_sync = self
	controller.set_physics_process(false)
	controller.teleported.connect(_on_controller_teleported)
	controller.movement_resumed.connect(_on_controller_resumed)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(controller):
		return
	_flush_delayed()
	var wanted_role := _resolve_role()
	if wanted_role != role:
		_set_role(wanted_role)
	if not controller.begin_tick():
		return
	match role:
		Role.LOCAL:
			_tick_local(delta)
		Role.PREDICTED_CLIENT:
			_tick_predicted_client()
		Role.SERVER_REMOTE:
			_tick_server_remote(delta)
		Role.PROXY:
			_tick_proxy()


## Commands the client has sent that the server has not yet confirmed.
func get_pending_command_count() -> int:
	return _history.size()


## Commands the server is holding for this player, waiting to be simulated.
func get_queued_command_count() -> int:
	return _server_queue.size()


func get_last_processed_sequence() -> int:
	return _last_processed_sequence


# --- Roles -------------------------------------------------------------------

func _resolve_role() -> Role:
	if not NetworkSession.is_network_connected():
		return Role.LOCAL
	var owner_peer := _get_input_peer_id()
	if NetworkSession.is_server():
		return Role.LOCAL if owner_peer == NetworkSession.SERVER_PEER_ID else Role.SERVER_REMOTE
	if owner_peer == NetworkSession.get_local_peer_id():
		return Role.PREDICTED_CLIENT
	return Role.PROXY


func _set_role(new_role: Role) -> void:
	role = new_role
	_reset_streams()
	role_changed.emit(role)


func _reset_streams() -> void:
	_sequence = 0
	_history.clear()
	_last_applied_ack = 0
	_pending_snapshot = null
	_server_queue.clear()
	_last_received_sequence = 0
	_last_processed_sequence = 0
	_snapshot_elapsed = 0.0
	_command_credit = 0.0
	_proxy_snapshots.clear()
	_delayed.clear()


func _get_input_peer_id() -> int:
	if input_peer_id > 0:
		return input_peer_id
	var body := controller.get_body()
	return body.get_multiplayer_authority() if is_instance_valid(body) else NetworkSession.SERVER_PEER_ID


# --- Local and server --------------------------------------------------------

func _tick_local(delta: float) -> void:
	controller.step(controller.prepare_intent(_poll_controller()))
	if NetworkSession.is_server():
		_broadcast_if_due(delta)


func _tick_server_remote(delta: float) -> void:
	# One tick of credit arrives per tick and each command costs one, so the rate is
	# capped at real time. Credit saved while nothing arrived pays for catching up.
	_command_credit = minf(_command_credit + 1.0, float(catch_up_allowance))
	while _command_credit >= 1.0 and not _server_queue.is_empty():
		_command_credit -= 1.0
		var command: PendingCommand = _server_queue.pop_front()
		# The server applies its own rules to the client's wishes.
		controller.step(controller.prepare_intent(command.intent))
		_last_processed_sequence = command.sequence
	_broadcast_if_due(delta)


func _broadcast_if_due(delta: float) -> void:
	_snapshot_elapsed += delta
	if _snapshot_elapsed < snapshot_interval:
		return
	_snapshot_elapsed = fmod(_snapshot_elapsed, snapshot_interval)
	_broadcast_snapshot()


func _broadcast_snapshot() -> void:
	if not NetworkSession.has_remote_peers():
		return
	var acknowledged := _last_processed_sequence
	var epoch := _epoch
	var bytes := controller.capture_state().encode()
	_dispatch(func() -> void:
		# A delayed packet can outlive the connection it was meant for.
		if NetworkSession.has_remote_peers():
			_client_receive_snapshot.rpc(acknowledged, epoch, bytes)
	)


@rpc("any_peer", "call_remote", "unreliable_ordered", NETWORK_CHANNEL)
func _server_receive_commands(packet: PackedByteArray) -> void:
	if not NetworkSession.is_server() or role != Role.SERVER_REMOTE:
		return
	if multiplayer.get_remote_sender_id() != _get_input_peer_id():
		return
	var size := packet.size()
	if size == 0 or size % COMMAND_BYTES != 0 or size > MAX_COMMANDS_PER_PACKET * COMMAND_BYTES:
		return

	@warning_ignore("integer_division")
	var count := size / COMMAND_BYTES
	if count > 0 and packet.decode_u32(0) + SEQUENCE_RESTART_GAP < _last_received_sequence:
		# The client started over, so forget the old stream.
		_last_received_sequence = 0
		_last_processed_sequence = 0
		_server_queue.clear()
	for index in count:
		var offset := index * COMMAND_BYTES
		var sequence := packet.decode_u32(offset)
		if sequence <= _last_received_sequence:
			continue
		var command := PendingCommand.new()
		command.sequence = sequence
		command.intent = MoveIntent.decode_from(packet, offset + 4)
		_server_queue.append(command)
		_last_received_sequence = sequence
	# A client that sends faster than the server ticks cannot move any faster:
	# the surplus is simply dropped, oldest first.
	while _server_queue.size() > max_queued_commands:
		_server_queue.pop_front()


# --- Predicting client -------------------------------------------------------

func _tick_predicted_client() -> void:
	_apply_pending_snapshot()
	var intent := controller.prepare_intent(_poll_controller())
	_sequence += 1
	controller.step(intent)

	var command := PendingCommand.new()
	command.sequence = _sequence
	command.intent = intent
	command.state = controller.capture_state()
	_history.append(command)
	while _history.size() > max_pending_commands:
		_history.pop_front()
	_send_commands()


func _send_commands() -> void:
	var count := mini(_history.size(), MAX_COMMANDS_PER_PACKET)
	if count == 0:
		return
	# Recent commands ride along again in case an earlier packet was lost.
	var packet := PackedByteArray()
	packet.resize(count * COMMAND_BYTES)
	for index in count:
		var command := _history[_history.size() - count + index]
		var offset := index * COMMAND_BYTES
		packet.encode_u32(offset, command.sequence)
		command.intent.encode_to(packet, offset + 4)
	_dispatch(func() -> void:
		if NetworkSession.is_client():
			_server_receive_commands.rpc_id(NetworkSession.SERVER_PEER_ID, packet)
	)


@rpc("any_peer", "call_remote", "unreliable_ordered", NETWORK_CHANNEL)
func _client_receive_snapshot(
	acknowledged_sequence: int,
	epoch: int,
	bytes: PackedByteArray,
) -> void:
	if multiplayer.get_remote_sender_id() != NetworkSession.SERVER_PEER_ID:
		return
	var state := MoveState.decode(bytes)
	if state == null:
		return
	var snapshot := Snapshot.new()
	snapshot.acknowledged_sequence = acknowledged_sequence
	snapshot.epoch = epoch
	snapshot.state = state
	snapshot.received_at = _now()
	match role:
		Role.PREDICTED_CLIENT:
			# Only the newest matters; the next tick checks it.
			if (
				_pending_snapshot == null
				or epoch != _pending_snapshot.epoch
				or acknowledged_sequence >= _pending_snapshot.acknowledged_sequence
			):
				_pending_snapshot = snapshot
		Role.PROXY:
			_proxy_snapshots.append(snapshot)
			while _proxy_snapshots.size() > MAX_PROXY_SNAPSHOTS:
				_proxy_snapshots.pop_front()


func _apply_pending_snapshot() -> void:
	if _pending_snapshot == null:
		return
	var snapshot := _pending_snapshot
	_pending_snapshot = null

	if snapshot.epoch != _epoch:
		# The server moved the character itself (a teleport): follow, don't predict.
		_epoch = snapshot.epoch
		_history.clear()
		_last_applied_ack = snapshot.acknowledged_sequence
		_sequence = maxi(_sequence, _last_applied_ack)
		controller.apply_state(snapshot.state)
		controller.get_body().reset_physics_interpolation()
		controller.get_body().clear_visual_offset()
		return

	var acknowledged := snapshot.acknowledged_sequence
	if acknowledged <= _last_applied_ack or acknowledged > _sequence:
		return
	_last_applied_ack = acknowledged

	# Forget everything the server has now seen, remembering what we predicted
	# for the last of it.
	var predicted: MoveState
	while not _history.is_empty() and _history[0].sequence <= acknowledged:
		var confirmed: PendingCommand = _history.pop_front()
		if confirmed.sequence == acknowledged:
			predicted = confirmed.state
	if predicted != null and not predicted.differs_from(
		snapshot.state, position_tolerance, velocity_tolerance
	):
		return
	_reconcile(snapshot.state)


## Rewinds to the server's state and replays the commands it has not seen yet.
func _reconcile(authoritative: MoveState) -> void:
	var body := controller.get_body()
	var before := body.global_position
	controller.apply_state(authoritative)
	for command in _history:
		controller.replay(command.intent)
		command.state = controller.capture_state()
	var error := before - body.global_position
	var distance := error.length()
	body.reset_physics_interpolation()
	if distance > snap_distance:
		controller.get_body().clear_visual_offset()
	else:
		controller.get_body().add_visual_offset(error)
	reconciled.emit(distance, _history.size())


# --- Other players -----------------------------------------------------------

func _tick_proxy() -> void:
	if _proxy_snapshots.is_empty():
		return
	var render_time := _now() - interpolation_delay
	var newest: Snapshot = _proxy_snapshots.back()
	if render_time >= newest.received_at:
		# Ran out of snapshots: carry on with the last velocity for a moment.
		var lead := minf(render_time - newest.received_at, max_extrapolation)
		var extrapolated := newest.state.duplicate()
		extrapolated.position += newest.state.velocity * lead
		controller.apply_proxy_state(extrapolated)
		return
	for index in range(_proxy_snapshots.size() - 1, -1, -1):
		var from := _proxy_snapshots[index]
		if from.received_at > render_time:
			continue
		if index == _proxy_snapshots.size() - 1:
			controller.apply_proxy_state(from.state)
			return
		var to := _proxy_snapshots[index + 1]
		var span := maxf(to.received_at - from.received_at, 0.0001)
		controller.apply_proxy_state(from.state.interpolated(to.state, (render_time - from.received_at) / span))
		return
	controller.apply_proxy_state(_proxy_snapshots[0].state)


# --- Plumbing ----------------------------------------------------------------

func _poll_controller() -> MoveIntent:
	return controller.poll_intent(controller.get_step_delta())


func _on_controller_teleported(_destination: Transform3D) -> void:
	# Only the side that is in charge of the character may move it.
	if role == Role.PREDICTED_CLIENT or role == Role.PROXY:
		return
	_epoch += 1
	_server_queue.clear()
	if NetworkSession.is_server():
		_broadcast_snapshot()


func _on_controller_resumed() -> void:
	# Whatever happened while locked is not part of the prediction stream.
	_history.clear()
	_pending_snapshot = null
	_server_queue.clear()


func _find_controller() -> CharacterController:
	var parent := get_parent()
	if parent == null:
		return null
	for child in parent.get_children():
		if child is CharacterController:
			return child as CharacterController
	return null


func _dispatch(send: Callable) -> void:
	if (
		simulated_packet_loss_percent > 0.0
		and randf() * 100.0 < simulated_packet_loss_percent
	):
		return
	if simulated_latency_ms <= 0.0:
		send.call()
		return
	_delayed.append({"release_at": _now() + simulated_latency_ms / 1000.0, "send": send})


func _flush_delayed() -> void:
	var now := _now()
	while not _delayed.is_empty() and float(_delayed[0]["release_at"]) <= now:
		var entry: Dictionary = _delayed.pop_front()
		(entry["send"] as Callable).call()


func _now() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0
