extends Node

var _failures := 0


func _ready() -> void:
	var manager := RadioManager.new()
	manager.default_frequency_code = 1000
	add_child(manager)

	var handheld_a := _make_radio("Handheld A", Vector3.ZERO, 100.0, false, 1000)
	var handheld_b := _make_radio("Handheld B", Vector3(75.0, 0.0, 0.0), 100.0, false, 1000)
	var distant_radio := _make_radio("Distant", Vector3(150.0, 0.0, 0.0), 100.0, false, 1000)
	var wrong_channel := _make_radio("Wrong Channel", Vector3(25.0, 0.0, 0.0), 100.0, false, 2000)
	var ship_radio := _make_radio("Ship", Vector3(10000.0, 0.0, 0.0), 0.0, true, 1000)
	await get_tree().process_frame

	_check(manager._radio_can_receive(handheld_a, handheld_b), "matching handheld in range")
	_check(not manager._radio_can_receive(handheld_a, distant_radio), "matching handheld out of range")
	_check(not manager._radio_can_receive(handheld_a, wrong_channel), "wrong frequency rejected")
	_check(manager._radio_can_receive(ship_radio, handheld_a), "infinite ship transmitter reaches distant radio")
	_check(not manager._radio_can_receive(handheld_a, ship_radio), "finite handheld cannot reach distant ship")

	manager.refresh_runtime_diagnostics()
	_check("5 radio(s)" in manager.runtime_radio_registry, "manager runtime registry count")
	_check("OUT OF RANGE" in handheld_a.runtime_matching_radios, "per-radio distance diagnostics")
	_check("INFINITE" in ship_radio.runtime_status, "infinite range diagnostics")

	var speaker := handheld_b.receiver_speaker
	speaker._get_or_create_source_output(&"talker_a")
	speaker._get_or_create_source_output(&"talker_b")
	_check(speaker._source_outputs.size() == 2, "simultaneous talkers have separate outputs")

	print("RADIO SYSTEM TESTS: ", "PASS" if _failures == 0 else "FAIL (%s)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _make_radio(
	label: String,
	position: Vector3,
	range_meters: float,
	infinite: bool,
	frequency: int
) -> Radio:
	var radio := Radio.new()
	radio.name = label.replace(" ", "")
	radio.device_label = label
	radio.position = position
	radio.transmit_range_meters = range_meters
	radio.infinite_transmit_range = infinite
	radio.frequency_code = frequency
	radio.can_transmit = false
	add_child(radio)
	return radio


func _check(value: bool, message: String) -> void:
	if value:
		return
	_failures += 1
	push_error("RADIO TEST FAILED: " + message)
