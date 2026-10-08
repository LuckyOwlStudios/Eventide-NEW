extends SceneTree


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var health := Health.new()
	root.add_child(health)

	var bar_scene: PackedScene = load("res://Components/Attributes/UI/LerpingAttributeBar.tscn")
	assert(bar_scene != null)
	var bar := bar_scene.instantiate() as LerpingAttributeBar
	bar.attribute_node = health
	root.add_child(bar)
	bar._sync_immediately()
	assert(is_equal_approx(bar.main_ratio, 1.0))
	assert(is_equal_approx(bar.secondary_ratio, 1.0))

	# Decreases move the main bar immediately and leave a trailing secondary bar.
	health.decrease(50.0)
	assert(is_equal_approx(bar.main_ratio, 0.5))
	assert(is_equal_approx(bar.secondary_ratio, 1.0))

	# Increases preview on the secondary bar before the main bar follows.
	health.increase(25.0)
	assert(is_equal_approx(bar.main_ratio, 0.5))
	assert(is_equal_approx(bar.secondary_ratio, 0.75))

	# The same bar accepts any AttributeNode implementation.
	var stamina := Stamina.new()
	root.add_child(stamina)
	bar.attribute_node = stamina
	assert(is_equal_approx(bar.main_ratio, 1.0))
	stamina.consume(20.0)
	assert(is_equal_approx(bar.main_ratio, 0.8))

	bar.free()
	health.free()
	stamina.free()
	print("Lerping attribute bar tests passed.")
	quit()
