extends SceneTree


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var health := Health.new()
	health.starting_max_health = 100.0
	health.starting_health_change_rate = 10.0
	health.low_health_percentage = 0.25
	root.add_child(health)

	var entered_count := [0]
	var exited_count := [0]
	health.injured_state_entered.connect(func(): entered_count[0] += 1)
	health.injured_state_exited.connect(func(): exited_count[0] += 1)

	health.decrease(80.0)
	assert(is_equal_approx(health.health, 20.0))
	assert(health.is_injured)
	assert(entered_count[0] == 1)

	health.increase(10.0)
	assert(is_equal_approx(health.health, 30.0))
	assert(not health.is_injured)
	assert(exited_count[0] == 1)

	health.decrease(20.0)
	health._process(1.0)
	assert(is_equal_approx(health.health, 20.0))
	assert(health.is_injured)
	health._process(1.0)
	assert(is_equal_approx(health.health, 30.0))
	assert(not health.is_injured)

	var healing_bonus := AttributeModifier.new()
	healing_bonus.amount = 5.0
	health.health_change_rate.add_attribute_modifier("test_healing_bonus", healing_bonus)
	assert(is_equal_approx(health.health_change_rate.value, 15.0))

	var poison := AttributeModifier.new()
	poison.amount = -20.0
	health.health_change_rate.add_attribute_modifier("test_poison", poison)
	assert(is_equal_approx(health.health_change_rate.value, -5.0))
	health.set_health(50.0)
	health._process(2.0)
	assert(is_equal_approx(health.health, 40.0))

	# Passive positive rates do not revive a depleted player.
	health.health_change_rate.remove_attribute_modifier("test_poison")
	health.set_health(0.0)
	health._process(1.0)
	assert(is_zero_approx(health.health))

	health.free()
	print("Health attribute tests passed.")
	quit()
