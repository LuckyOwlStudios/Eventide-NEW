extends Node
## Transport-independent information about the active Godot multiplayer session.
## Steam SDK initialization remains the responsibility of SteamNetwork.

## Emitted when another peer joins the current multiplayer session.
## [param peer_id] is that peer's unique Godot multiplayer ID.
signal peer_joined(peer_id: int)
## Emitted after another peer leaves the current multiplayer session.
## [param peer_id] is the ID formerly assigned to that peer.
signal peer_left(peer_id: int)
## Emitted on a client after it successfully connects to the server.
signal connected_to_server
## Emitted on a client when its attempt to connect to the server fails.
signal connection_failed
## Emitted on a client after its connection to the server is lost.
signal server_disconnected

## Godot's reserved multiplayer ID for the authoritative server peer.
const SERVER_PEER_ID := 1


## Connects the global session signals to Godot's active [MultiplayerAPI].
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## True while Godot has a peer whose transport has reached CONNECTED state.
## This can be true for a host even before another player joins.
func is_network_connected() -> bool:
	var peer := multiplayer.multiplayer_peer
	return (
		peer != null
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	)


## True only when at least one other multiplayer peer is currently present.
## Unlike [method is_network_connected], a host waiting alone returns [code]false[/code].
func has_remote_peers() -> bool:
	return is_network_connected() and not multiplayer.get_peers().is_empty()


## Returns whether this process is participating with at least one remote peer.
## Use [method is_network_connected] when a listening host should also count.
func is_multiplayer_session_active() -> bool:
	return has_remote_peers()


## Returns this process's unique Godot multiplayer peer ID.
## Offline play normally uses [constant SERVER_PEER_ID].
func get_local_peer_id() -> int:
	return multiplayer.get_unique_id()


## Returns the IDs of every currently connected remote peer.
## Returns an empty array while offline or while a host is waiting alone.
func get_remote_peer_ids() -> PackedInt32Array:
	return multiplayer.get_peers() if is_network_connected() else PackedInt32Array()


## Returns the number of currently connected remote peers.
func get_remote_peer_count() -> int:
	return get_remote_peer_ids().size()


## Offline mode is not considered a server session.
## Returns [code]true[/code] only for a connected authoritative server or host.
func is_server() -> bool:
	return is_network_connected() and multiplayer.is_server()


## Returns [code]true[/code] when connected as a client rather than the server.
func is_client() -> bool:
	return is_network_connected() and not multiplayer.is_server()


## Offline actors are always locally controlled. During a session, Godot's
## authority assigned to that node decides whether this machine owns it.
## Invalid nodes always return [code]false[/code].
func is_local_authority(node: Node) -> bool:
	return is_instance_valid(node) and (
		not is_network_connected() or node.is_multiplayer_authority()
	)


## Returns whether [param peer_id] represents this process.
## Returns [code]true[/code] in offline play because all input is local there.
func is_local_peer(peer_id: int) -> bool:
	return not is_network_connected() or peer_id == get_local_peer_id()


## Forwards Godot's peer-connected event through [signal peer_joined].
func _on_peer_connected(peer_id: int) -> void:
	peer_joined.emit(peer_id)


## Forwards Godot's peer-disconnected event through [signal peer_left].
func _on_peer_disconnected(peer_id: int) -> void:
	peer_left.emit(peer_id)


## Forwards a successful client connection through [signal connected_to_server].
func _on_connected_to_server() -> void:
	connected_to_server.emit()


## Forwards a failed client connection through [signal connection_failed].
func _on_connection_failed() -> void:
	connection_failed.emit()


## Forwards a lost server connection through [signal server_disconnected].
func _on_server_disconnected() -> void:
	server_disconnected.emit()
