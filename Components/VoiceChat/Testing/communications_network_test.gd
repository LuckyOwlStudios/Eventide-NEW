extends Node
var _server := false
var _received := 0
var _complete := false
var _recorder: PARecorder3D

func _ready() -> void:
	_server = "--server" in OS.get_cmdline_user_args()
	var peer := ENetMultiplayerPeer.new()
	var error: Error
	if _server:
		error = peer.create_server(28734, 2, 3)
	else:
		error = peer.create_client("127.0.0.1", 28734, 3)
	if error != OK:
		push_error("ENet setup failed: %s" % error)
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	_recorder = PARecorder3D.new()
	_recorder.name = "Recorder"
	_recorder.save_path = ""
	add_child(_recorder)
	if not _server:
		VoiceChannels.broadcast_frames.connect(_on_frames)
		multiplayer.connected_to_server.connect(func(): _request_play.rpc_id(1))
	get_tree().create_timer(10.0).timeout.connect(func():
		if not _complete:
			push_error("NETWORK TEST TIMEOUT")
			get_tree().quit(1)
	)


@rpc("any_peer", "call_remote", "reliable", 2)
func _request_play() -> void:
	if not _server or multiplayer.get_remote_sender_id() == 0:
		return
	var frames := PackedVector2Array()
	frames.resize(1440)
	frames.fill(Vector2(0.25, 0.25))
	_recorder.recording = AudioStreamWAV.new()
	_recorder.recording.format = AudioStreamWAV.FORMAT_16_BITS
	_recorder.recording.mix_rate = VoiceChannels.SAMPLE_RATE
	_recorder.recording.stereo = true
	_recorder.recording.data = VoiceChannels.encode_pcm(frames)
	_recorder.play_recording(0)


func _on_frames(source: Node3D, frames: PackedVector2Array, channel: int) -> void:
	if source != _recorder or channel != 0 or absf(frames[0].x - 0.25) > 0.001:
		push_error("NETWORK TEST: unexpected payload")
		get_tree().quit(1)
		return
	_received += frames.size()
	if _received >= 1440:
		_complete = true
		_ack.rpc_id(1)
		print("NETWORK CLIENT: PASS (1440 PCM frames received)")
		await get_tree().create_timer(0.2).timeout
		get_tree().quit()


@rpc("any_peer", "call_remote", "reliable", 2)
func _ack() -> void:
	if _server:
		_complete = true
		print("NETWORK SERVER: PASS (client acknowledged playback)")
		get_tree().quit()
