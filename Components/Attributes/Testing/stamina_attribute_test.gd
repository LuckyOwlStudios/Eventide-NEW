extends SceneTree


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var stamina := Stamina.new()
	stamina.starting_max_stamina = 100.0
	stamina.starting_regen_cooldown = 2.0
	stamina.starting_stamina_change_rate = 10.0
	root.add_child(stamina)

	assert(stamina.consume(20.0))
	assert(is_equal_approx(stamina.stamina, 80.0))
	assert(not stamina.consume(100.0))
	assert(is_equal_approx(stamina.stamina, 80.0))
	assert(is_equal_approx(stamina.get_regen_cooldown_remaining(), 2.0))

	stamina._process(1.0)
	assert(is_equal_approx(stamina.stamina, 80.0))
	stamina._process(1.0)
	assert(is_equal_approx(stamina.stamina, 80.0))
	stamina._process(1.0)
	assert(is_equal_approx(stamina.stamina, 90.0))

	# A negative net rate consumes stamina over time, including while full.
	stamina.increase(100.0)
	var drain := AttributeModifier.new()
	drain.amount = -25.0
	stamina.stamina_change_rate.add_attribute_modifier("test_drain", drain)
	assert(is_equal_approx(stamina.stamina_change_rate.value, -15.0))
	stamina._process(2.0)
	assert(is_equal_approx(stamina.stamina, 70.0))

	# Regeneration waits for the cooldown after an overtime drain ends.
	stamina.stamina_change_rate.remove_attribute_modifier("test_drain")
	stamina._process(2.0)
	assert(is_equal_approx(stamina.stamina, 70.0))
	stamina._process(1.0)
	assert(is_equal_approx(stamina.stamina, 80.0))

	# Cooldown itself is modifier-driven.
	var shorter_cooldown := AttributeModifier.new()
	shorter_cooldown.amount = -50.0
	shorter_cooldown.operation = AttributeModifier.Operation.ADD_MULTIPLIED_BASE
	stamina.regen_cooldown.add_attribute_modifier("test_shorter_cooldown", shorter_cooldown)
	assert(is_equal_approx(stamina.regen_cooldown.value, 1.0))

	stamina.free()
	print("Stamina attribute tests passed.")
	quit()
