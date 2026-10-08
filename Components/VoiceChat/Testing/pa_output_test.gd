extends Node3D

func _ready() -> void:
	var camera := Camera3D.new()
	add_child(camera)
	camera.make_current()
	AudioServer.add_bus()
	var bus_index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_index, "PATest")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 2.0
	AudioServer.add_bus_effect(bus_index, capture)
	var speaker := AudioStreamPlayer3D.new()
	speaker.bus = &"PATest"
	speaker.position = Vector3(0, 0, -2)
	add_child(speaker)
	var recorder := PARecorder3D.new()
	recorder.save_path = ""
	recorder.local_speakers.append(speaker)
	add_child(recorder)
	var frames := PackedVector2Array()
	frames.resize(12000)
	for i in frames.size():
		var value := sin(TAU * 440.0 * i / 24000.0) * 0.4
		frames[i] = Vector2(value, value)
	recorder.recording = AudioStreamWAV.new()
	recorder.recording.format = AudioStreamWAV.FORMAT_16_BITS
	recorder.recording.stereo = true
	recorder.recording.mix_rate = 24000
	recorder.recording.data = VoiceChannels.encode_pcm(frames)
	recorder.play_recording(-1)
	await get_tree().create_timer(0.8).timeout
	var output := capture.get_buffer(capture.get_frames_available())
	var peak := 0.0
	for frame in output:
		peak = maxf(peak, absf(frame.x))
	print("PA AUDIO OUTPUT: frames=", output.size(), " peak=", peak)
	recorder.stop_playback()
	await get_tree().create_timer(0.1).timeout
	AudioServer.remove_bus(bus_index)
	get_tree().quit(0 if peak > 0.01 else 1)
