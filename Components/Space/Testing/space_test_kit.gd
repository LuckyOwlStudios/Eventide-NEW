extends RefCounted
## Things the space tests build over and over: templates, stars and asteroid kinds made in code, so a test depends on
## what it builds and not on what is in the registry folders (apart from the tests that are about those).
##
## Used as [code]const Kit := preload("res://Components/Space/Testing/space_test_kit.gd")[/code].


## One star, [param distance] away, that always looks the same.
static func star(distance := 0.42, variation := 0.0, color := Color.NAVAJO_WHITE) -> Star:
	var made := Star.new()
	made.distance = distance
	made.distance_variation = variation
	made.color = color
	made.color_variation = 0.0
	return made


## A template whose systems all have temperature [param temperature] and density [param density], with
## [param star_count] steady stars at distance 0.42.
static func flat_template(temperature := 0.0, density := 0.5, star_count := 1) -> SystemTemplate:
	var template := SystemTemplate.new()
	template.display_name = "Flat"
	template.temperature_min = temperature
	template.temperature_max = temperature
	template.density_min = density
	template.density_max = density
	for _index in star_count:
		template.stars.append(star())
	return template


## A kind of asteroid that turns up from [param low] to [param high], most at [param peak].
static func kind(display_name: String, low: float, peak: float, high: float, weight := 1.0) -> Asteroid:
	var made := Asteroid.new()
	made.display_name = display_name
	made.temperature_min = low
	made.temperature_peak = peak
	made.temperature_max = high
	made.weight = weight
	return made


## The asteroid kinds of the game, as the registry finds them, by display name.
static func registry_kinds() -> Dictionary[String, Asteroid]:
	var found: Dictionary[String, Asteroid] = {}
	for asteroid in AsteroidRegistry.get_asteroids():
		found[asteroid.get_display_name()] = asteroid
	return found


## The system templates of the game, by display name.
static func registry_templates() -> Dictionary[String, SystemTemplate]:
	var found: Dictionary[String, SystemTemplate] = {}
	for template in SystemRegistry.get_templates():
		found[template.get_display_name()] = template
	return found


## A decorator scene with a single [param height]-tall cone and nothing else, made in code (no file needed), for
## decorations that depend on nothing in the registry.
static func cone_scene(height := 1.0, radius := 0.2) -> PackedScene:
	var root := Node3D.new()
	root.name = "Cone"
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = radius
	cone.height = height
	cone.radial_segments = 6
	cone.rings = 0
	cone.cap_top = false
	cone.cap_bottom = false
	var material := StandardMaterial3D.new()
	material.resource_name = "ConeMaterial"
	cone.material = material
	mesh_instance.mesh = cone
	mesh_instance.position = Vector3(0.0, height * 0.5, 0.0)
	root.add_child(mesh_instance)
	mesh_instance.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	return scene


## A decorator that grows [param count] cones from each of [param clusters] spots on every rock.
static func cone_decorator(clusters := 8, collide := true) -> AsteroidDecorator:
	var decorator := AsteroidDecorator.new()
	decorator.scene = cone_scene()
	decorator.clusters_min = clusters
	decorator.clusters_max = clusters
	decorator.pieces_min = 1
	decorator.pieces_max = 1
	decorator.size_min = 0.3
	decorator.size_max = 0.3
	decorator.collide = collide
	decorator.flat_shaded = true
	return decorator

