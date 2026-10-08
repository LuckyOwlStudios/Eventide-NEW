extends Node
var failures := 0


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + message)


func _ready() -> void:
	await get_tree().process_frame
	for tx in range(-1, 6):
		for rx in range(-1, 6):
			check(VoiceChannels.matches(tx, rx) == (tx >= 0 and tx <= 4 and rx >= 0 and rx <= 4 and (tx == 0 or tx == rx)), "channel matrix")
	var frames := PackedVector2Array()
	frames.resize(480)
	frames.fill(Vector2(0.25, -0.25))
	var roundtrip := VoiceChannels.decode_pcm(VoiceChannels.encode_pcm(frames))
	check(roundtrip.size() == frames.size() and absf(roundtrip[0].x - 0.25) < 0.001, "PCM roundtrip")
	check(VoiceChannels.resample(frames, 48000).size() == 240, "sample rate conversion")
	var camera := Camera3D.new()
	add_child(camera)
	camera.make_current()
	var voice := SteamVoiceChat3D.new()
	voice.start_enabled = false
	voice.set_multiplayer_authority(2)
	add_child(voice)
	voice.start_voice_chat()
	check(is_zero_approx(voice.radio_gain_for_listener()), "nearby radio suppression")
	voice.position.x = 100.0
	check(is_equal_approx(voice.radio_gain_for_listener(), 1.0), "distant radio audibility")
	var speaker := ChannelSpeaker3D.new()
	add_child(speaker)
	VoiceChannels.publish_voice(voice, frames, 24000, 2)
	check(speaker._outputs.is_empty(), "wrong channel rejection")
	VoiceChannels.publish_voice(voice, frames, 24000, 0)
	check(speaker._outputs.size() == 1, "global broadcast reception")
	speaker.channel = 2
	check(speaker._outputs.is_empty(), "channel change clears queued audio")
	VoiceChannels.publish_voice(voice, frames, 24000, 2)
	check(speaker._outputs.size() == 1, "matching channel reception")
	voice.set_voice_muted(true)
	speaker._process(0.0)
	check(speaker._outputs.values()[0].player.volume_db < -80.0, "muting also silences radio")
	voice.set_voice_muted(false)
	var radio := WalkieTalkie3D.new()
	radio.voice_source = voice
	radio.use_input = false
	add_child(radio)
	radio.set_multiplayer_authority(2)
	radio.set_transmitting(true)
	check(not radio.transmitting, "remote radio ignores local input")
	radio.set_multiplayer_authority(1)
	voice.set_multiplayer_authority(1)
	radio.set_transmitting(true)
	check(voice.radio_transmitting, "radio transmission enables microphone request")
	radio.enabled = false
	radio._process(0.0)
	check(not voice.radio_transmitting, "disabled radio ends transmission")
	speaker.clear_audio()
	voice.position = Vector3.ZERO
	VoiceChannels.publish_voice(voice, frames, 24000, 2)
	check(speaker._outputs.is_empty(), "own voice stays off by default")
	speaker.hear_own_voice = true
	VoiceChannels.publish_voice(voice, frames, 24000, 1)
	check(speaker._outputs.is_empty(), "own voice still requires matching channel")
	VoiceChannels.publish_voice(voice, frames, 24000, 2)
	check(speaker._outputs.size() == 1, "own Beta transmission reaches opted-in speaker")
	if not speaker._outputs.is_empty():
		check(is_equal_approx(speaker._outputs.values()[0].player.volume_db, speaker.volume_db), "own voice bypasses proximity suppression")
	speaker.hear_own_voice = false
	check(speaker._outputs.is_empty(), "disabling own voice clears queued audio")
	voice.position.x = 100.0
	var recorder := PARecorder3D.new()
	recorder.save_path = "res://Components/VoiceChat/Testing/test_recording.wav"
	add_child(recorder)
	recorder.start_recording()
	await get_tree().create_timer(0.03).timeout
	VoiceChannels.publish_voice(voice, frames, 24000, -1)
	check(recorder._source_cursors.is_empty(), "recorder excludes out-of-range voices")
	voice.position = Vector3.ZERO
	VoiceChannels.publish_voice(voice, frames, 24000, -1)
	check(recorder._source_cursors.size() == 1, "recorder captures proximity-only voices")
	var saved := recorder.stop_recording()
	check(saved != null and saved.data.size() > 0, "recording creation")
	check(FileAccess.file_exists(recorder.save_path), "WAV saved on disk")
	var decoded := VoiceChannels.decode_pcm(saved.data)
	var peak := 0.0
	for frame in decoded:
		peak = maxf(peak, absf(frame.x))
	check(peak > 0.2, "recording contains audible PCM")
	speaker.channel = 4
	recorder.play_recording(0)
	recorder._process(0.025)
	check(speaker._outputs.has(recorder.get_instance_id()), "PA global reaches Delta")
	recorder.stop_playback()
	check(not speaker._outputs.has(recorder.get_instance_id()), "PA stop clears queued channel audio")
	var local := AudioStreamPlayer3D.new()
	add_child(local)
	recorder.local_speakers.append(local)
	recorder.play_recording(-1)
	recorder._process(0.025)
	check(recorder._local_outputs.size() == 1, "PA local playback")
	check(local.stream == null, "local playback preserves configured stream")
	recorder.stop_playback()
	# Ordinary world sound is captured without using the listener's audio bus.
	var sound := AudioStreamPlayer3D.new()
	var sound_frames := PackedVector2Array()
	sound_frames.resize(24000)
	sound_frames.fill(Vector2(0.2, 0.2))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 24000
	wav.data = VoiceChannels.encode_pcm(sound_frames)
	sound.stream = wav
	add_child(sound)
	sound.play()
	recorder.start_recording()
	await get_tree().create_timer(0.08).timeout
	var world_recording := recorder.stop_recording()
	var world_peak := 0.0
	for frame in VoiceChannels.decode_pcm(world_recording.data):
		world_peak = maxf(world_peak, frame.x)
	check(world_peak > 0.1, "PA captures nearby WAV world sound")
	sound.stop()
	recorder.max_recording_seconds = 1.0
	recorder.start_recording()
	await get_tree().create_timer(1.1).timeout
	check(not recorder.is_recording, "recording automatically stops at duration limit")
	check(recorder.recording.get_length() <= 1.001, "recording duration is bounded")
	DirAccess.remove_absolute(recorder.save_path)
	voice.stop_voice_chat()
	speaker.clear_audio()
	radio.clear_audio()
	await get_tree().create_timer(0.1).timeout
	print("COMMUNICATIONS TESTS: ", "PASS" if failures == 0 else "FAIL (%s)" % failures)
	get_tree().quit(0 if failures == 0 else 1)



