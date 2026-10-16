class_name AsteroidMaterials
extends RefCounted
## Makes the materials a kind of asteroid is drawn with, from its look settings (see [Asteroid]).
##
## Every kind starts from a copy of its [member Asteroid.base_material] (the rock texture in
## [code]Assets/Materials/Asteroid.tres[/code] when it has none), so the material files themselves are never
## changed. The models have no flat map to wrap a texture around, so the copies are wrapped on from all sides
## (triplanar), painted by the model's own vertex colors (which is where the rock's mottling is) and drawn from the
## outside only, since the models are closed.
##
## [b]Cracks.[/b] A kind with [member Asteroid.cracks] gets a picture of cracks (bright lines along the edges
## between cells of stone, with a little glow around them) as its emission. The picture is [i]multiplied[/i] with the
## crack color, so it works as a mask; the default way to use an emission picture is to add it, which would light
## the whole rock. The picture is read as a color, so what it holds is the brightness it should have, brightened
## by the curve the engine undoes it with. It is the same pattern for every kind, with a width and a halo that
## depend on the kind, and is made once and kept.
## A cracked kind gets [constant CRACK_VARIANTS] materials with different strengths of glow, so its rocks are
## not all alike. [method tick] makes the glow breathe.

## The rock material that kinds without a base material of their own start from.
const BASE_MATERIAL_PATH := "res://Assets/Materials/Asteroid.tres"
## How much the rock texture is stretched over a model: repeats across its width.
const TEXTURE_SCALE := 1.0
## ...and the cracks, which want to be a little finer.
const CRACK_SCALE := 1.3
## The rock texture is dark, so a tint is multiplied by this to make white leave the rock looking as it should.
const TEXTURE_BOOST := 1.7
## How many strengths of glow a cracked kind gets.
const CRACK_VARIANTS := 3
const CRACK_TEXTURE_SIZE := 256
## The glow that every part of a cracked rock has, however far from a crack, so a rock too far to see its cracks
## still looks hot.
const CRACK_FLOOR := 0.035

static var _crack_edges := PackedByteArray()
static var _crack_variation := PackedByteArray()
static var _crack_textures: Dictionary[int, Texture2D] = {}


## The materials for [param asteroid]: one, or [constant CRACK_VARIANTS] with different glow for a cracked kind. The first
## is the one to show for the kind on its own.
static func make(asteroid: Asteroid) -> Array[StandardMaterial3D]:
	var made: Array[StandardMaterial3D] = []
	var variants := CRACK_VARIANTS if asteroid.has_cracks() else 1
	for variant in variants:
		made.append(_make_one(asteroid, variant, variants))
	return made


## The glow of a cracked material at [param seconds], so the cracks breathe a little. Call it every frame.
static func tick(asteroid: Asteroid, materials: Array[StandardMaterial3D], seconds: float) -> void:
	if not asteroid.has_cracks():
		return
	for index in materials.size():
		materials[index].emission_energy_multiplier = get_crack_energy(asteroid, index, materials.size(), seconds)


## How brightly variant [param variant] of [param count] of a cracked kind glows at [param seconds].
static func get_crack_energy(asteroid: Asteroid, variant: int, count: int, seconds: float) -> float:
	var strength := 0.75 + 0.25 * float(variant + 1) / maxf(float(count), 1.0)
	var swell := (1.0 - asteroid.crack_pulse) + asteroid.crack_pulse * sin(seconds * 0.9 + float(variant) * 2.1)
	return asteroid.crack_energy * strength * swell


static func _make_one(asteroid: Asteroid, variant: int, variants: int) -> StandardMaterial3D:
	var material := _load_base(asteroid)
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.uv1_triplanar = true
	material.uv1_triplanar_sharpness = 3.0
	material.uv1_scale = Vector3.ONE * (CRACK_SCALE if asteroid.has_cracks() else TEXTURE_SCALE)

	var textured := asteroid.use_texture and material.albedo_texture != null
	if not asteroid.use_texture:
		material.albedo_texture = null
	var boost := TEXTURE_BOOST if textured else 1.0
	material.albedo_color = Color(asteroid.tint.r * boost, asteroid.tint.g * boost, asteroid.tint.b * boost, asteroid.tint.a)
	material.roughness = asteroid.roughness
	material.metallic = asteroid.metallic
	material.metallic_specular = asteroid.specular
	if material.normal_texture != null:
		material.normal_scale = material.normal_scale * asteroid.normal_strength

	if asteroid.has_cracks():
		material.emission_enabled = true
		material.emission = asteroid.crack_color
		material.emission_texture = get_crack_texture(asteroid.crack_width, asteroid.crack_halo)
		# Multiplying makes the picture a mask. (The default adds it, which lights the whole rock.)
		material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		material.emission_energy_multiplier = get_crack_energy(asteroid, variant, variants, 0.0)
	elif asteroid.glow > 0.0:
		material.emission_enabled = true
		material.emission = asteroid.glow_color
		material.emission_texture = null
		material.emission_operator = BaseMaterial3D.EMISSION_OP_ADD
		material.emission_energy_multiplier = asteroid.glow
	else:
		material.emission_enabled = false
	return material


## A copy of the kind's base material, or of the rock material, or a plain gray one if that is missing.
static func _load_base(asteroid: Asteroid) -> StandardMaterial3D:
	var base := asteroid.base_material
	if base == null:
		base = load(BASE_MATERIAL_PATH) as StandardMaterial3D
	if base != null:
		return base.duplicate() as StandardMaterial3D
	push_warning("%s is missing, so asteroids are plain." % BASE_MATERIAL_PATH)
	var plain := StandardMaterial3D.new()
	plain.roughness = 0.9
	return plain


## A seamless picture of cracks for cracks that are [param width] wide (a share of the distance between two cracks) with
## a halo of glow [param halo] strong around them. Made once for each pair and kept.
static func get_crack_texture(width: float, halo: float) -> Texture2D:
	var width_steps := roundi(clampf(width, 0.01, 1.0) * 100.0)
	var halo_steps := roundi(clampf(halo, 0.0, 1.0) * 100.0)
	var key := width_steps * 1000 + halo_steps
	if _crack_textures.has(key):
		return _crack_textures[key]
	_make_crack_noise()
	var crack_width := width_steps / 100.0
	var crack_halo := halo_steps / 100.0
	var size := CRACK_TEXTURE_SIZE
	var pixels := PackedByteArray()
	pixels.resize(size * size * 3)
	for index in size * size:
		# Along an edge the distance to the nearest cell and the next one are the same, so the value is 0 there.
		var distance := _crack_edges[index] / 255.0
		var crack := 1.0 - smoothstep(0.0, crack_width, distance)
		# A soft glow around the cracks, and a dull one everywhere.
		var glow := crack_halo * pow(1.0 - distance, 3.0) + CRACK_FLOOR
		var level := clampf(maxf(crack, glow), 0.0, 1.0) * (0.35 + 0.65 * _crack_variation[index] / 255.0)
		var byte := int(pow(level, 1.0 / 2.2) * 255.0)
		pixels[index * 3] = byte
		pixels[index * 3 + 1] = byte
		pixels[index * 3 + 2] = byte
	var image := Image.create_from_data(size, size, false, Image.FORMAT_RGB8, pixels)
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_crack_textures[key] = texture
	return texture


## The two patterns every crack picture is made of: the edges between cells, and how the heat varies from place to place.
static func _make_crack_noise() -> void:
	if not _crack_edges.is_empty():
		return
	var size := CRACK_TEXTURE_SIZE
	var cells := FastNoiseLite.new()
	cells.seed = 4242
	cells.noise_type = FastNoiseLite.TYPE_CELLULAR
	cells.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	cells.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	cells.frequency = 0.035
	var edges := cells.get_seamless_image(size, size)
	edges.convert(Image.FORMAT_L8)
	var heat := FastNoiseLite.new()
	heat.seed = 777
	heat.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	heat.frequency = 0.012
	var variation := heat.get_seamless_image(size, size)
	variation.convert(Image.FORMAT_L8)
	_crack_edges = edges.get_data()
	_crack_variation = variation.get_data()
