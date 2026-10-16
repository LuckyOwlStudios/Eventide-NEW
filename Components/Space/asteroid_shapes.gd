class_name AsteroidShapes
extends RefCounted
## The few asteroid shapes a system is built from. A system holds thousands of asteroids but only
## [constant DEFAULT_MODEL_COUNT] of these: each asteroid is one of the models, turned and sized
## its own way, so the meshes and collision shapes are built once per jump and shared by every
## asteroid, and building a chunk never has to build a mesh.
##
## A model is a sphere roughed up with noise, stretched along each axis and dented with a few
## craters, all from the system's seed, so the same seed gives the same rocks. It is built at a
## size of one: the point farthest from the middle is exactly 1 m away, so an asteroid scaled by
## its radius reaches exactly that far, and a chunk can tell how much room one needs.
##
## [b]Kinds.[/b] Every model is one kind of [Asteroid]. How the models are shared out between the kinds a system has
## comes from its [AsteroidMix]. A kind's look is made by [AsteroidMaterials]. Whatever grows out of a kind (its
## [member Asteroid.decorators]: ice crystals, purple crystals) is part of the model: the decorator scenes' meshes are
## baked onto the rock, in surfaces of their own with their own materials, and into the collision shape when they
## collide. So they are part of the asteroid and not on top of it, and cost nothing extra for each asteroid that has them.
## The materials are made for each system, so one system's glow does not leak into the next.

## One shape. [member mesh] and [member collision] are shared by every asteroid that uses it.
class Model:
	extends RefCounted
	## The body is surface 0 and each material the decorations use gets a surface after it.
	var mesh: ArrayMesh
	var collision: ConcavePolygonShape3D
	## The kind of asteroid it is.
	var asteroid: Asteroid
	## The body's surface, kept as plain numbers: a point on the model's skin and which way it faces. They
	## stand in for the mesh where it cannot be read back (a headless run draws nothing) and are what
	## to look up for anything that must sit on an asteroid, such as a spot to mine.
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	## How many pieces (crystals and so on) grow out of it, and the corners of all of them.
	var decoration_count := 0
	var decoration_vertices := PackedVector3Array()
	## The point farthest from the middle, decorations included: exactly 1.
	var extent := 1.0

const DEFAULT_MODEL_COUNT := 10
## How many times the starting 20-sided shape is cut up. 3 gives 1280 triangles, 4 gives 5120.
const DEFAULT_DETAIL := 3
## Triangles smaller than this are left out of decorations: a cone's tip is a ring of corners in one place.
const MINIMUM_TRIANGLE_AREA := 0.0000001

## The kinds this system has and how common each is.
var mix: AsteroidMix
var models: Array[Model] = []

var _materials: Dictionary[Asteroid, Array] = {}

static var _base_vertices := PackedVector3Array()
static var _base_triangles := PackedInt32Array()
static var _base_detail := -1


## Builds [param count] models from [param system_seed], of the kinds in [param mix_to_use] (a comfortable system's
## when empty). [param detail] is how finely the sphere is cut up.
static func build(system_seed: int, count: int = DEFAULT_MODEL_COUNT, detail: int = DEFAULT_DETAIL, mix_to_use: AsteroidMix = null) -> AsteroidShapes:
	var shapes := AsteroidShapes.new()
	shapes.mix = mix_to_use if mix_to_use != null else AsteroidMix.make(0.0, [], 0)
	_ensure_base(detail)
	shapes._make_materials()
	var kinds := shapes.mix.allocate(maxi(count, 1))
	for index in kinds.size():
		shapes.models.append(shapes._make_model(SpaceRandom.combine(system_seed, index + 0x726F636B), shapes.mix.asteroids[kinds[index]]))
	return shapes


## Builds the models of [param system], of the kinds its asteroid mix says.
static func for_system(system: StarSystem, count: int = DEFAULT_MODEL_COUNT, detail: int = DEFAULT_DETAIL) -> AsteroidShapes:
	return build(system.system_seed, count, detail, system.asteroid_mix)


func get_model(index: int) -> Model:
	return models[posmod(index, models.size())]


## The material shared by every asteroid of [param asteroid] in this system (the first, for a kind that has several
## strengths of glow).
func get_material(asteroid: Asteroid) -> Material:
	var made: Array = _materials[asteroid]
	return made[0]


## Every material made for [param asteroid] in this system.
func get_materials(asteroid: Asteroid) -> Array[StandardMaterial3D]:
	var found: Array[StandardMaterial3D] = []
	found.assign(_materials.get(asteroid, []))
	return found


## Makes the glowing cracks of the kinds that have them breathe a little. Call it every frame with the time in seconds.
func tick(seconds: float) -> void:
	for asteroid in _materials:
		if asteroid.has_cracks():
			var made: Array[StandardMaterial3D] = []
			made.assign(_materials[asteroid])
			AsteroidMaterials.tick(asteroid, made, seconds)


## The sphere every model starts as: [code]vertices[/code] (all a meter from the middle) and
## [code]triangles[/code], three corner indexes each, wound counter-clockwise seen from outside.
static func get_base(detail: int = DEFAULT_DETAIL) -> Dictionary:
	_ensure_base(detail)
	return {"vertices": _base_vertices, "triangles": _base_triangles}


# --- Materials -----------------------------------------------------------------------------------------

func _make_materials() -> void:
	_materials.clear()
	for asteroid in mix.asteroids:
		_materials[asteroid] = AsteroidMaterials.make(asteroid)


func _pick_material(asteroid: Asteroid, rng: SpaceRandom) -> Material:
	var made: Array = _materials[asteroid]
	# One of the strengths of glow, for a kind that has several.
	return made[rng.range_int(0, made.size() - 1)]


# --- Models --------------------------------------------------------------------------------------------

func _make_model(model_seed: int, asteroid: Asteroid) -> Model:
	var rng := SpaceRandom.new(model_seed)
	var model := Model.new()
	model.asteroid = asteroid

	var noise := FastNoiseLite.new()
	noise.seed = rng.next_int() & 0x7FFFFFFF
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.fractal_lacunarity = 2.1
	noise.fractal_gain = 0.5
	noise.frequency = 1.0
	var bumpiness := rng.range_float(0.16, 0.38)
	var roughness_scale := rng.range_float(0.9, 1.6)
	var stretch := Vector3(rng.range_float(0.72, 1.2), rng.range_float(0.68, 1.1), rng.range_float(0.72, 1.2))

	# A few bowl-shaped craters: where, how wide (as an angle) and how deep.
	var crater_directions: Array[Vector3] = []
	var crater_widths := PackedFloat32Array()
	var crater_depths := PackedFloat32Array()
	for _crater in rng.range_int(0, 3):
		crater_directions.append(rng.unit_vector())
		crater_widths.append(rng.range_float(0.25, 0.55))
		crater_depths.append(rng.range_float(0.08, 0.2))

	var vertex_count := _base_vertices.size()
	var positions := PackedVector3Array()
	positions.resize(vertex_count)
	for index in vertex_count:
		var direction := _base_vertices[index]
		var radius := 1.0 + bumpiness * noise.get_noise_3d(
			direction.x * roughness_scale, direction.y * roughness_scale, direction.z * roughness_scale)
		for crater in crater_directions.size():
			var angle := acos(clampf(direction.dot(crater_directions[crater]), -1.0, 1.0))
			if angle < crater_widths[crater]:
				var across := angle / crater_widths[crater]
				var bowl := 1.0 - across * across
				radius -= crater_depths[crater] * bowl * bowl
		positions[index] = direction * radius * stretch

	# Smooth normals: every triangle adds its (area weighted) normal to its three corners. (Their
	# directions do not depend on the size, so this can be done before the model is scaled to one.)
	var normals := PackedVector3Array()
	normals.resize(vertex_count)
	for corner in range(0, _base_triangles.size(), 3):
		var a := _base_triangles[corner]
		var b := _base_triangles[corner + 1]
		var c := _base_triangles[corner + 2]
		var face := (positions[b] - positions[a]).cross(positions[c] - positions[a])
		normals[a] += face
		normals[b] += face
		normals[c] += face
	for index in vertex_count:
		normals[index] = normals[index].normalized()

	# Mottled color from a second noise, so the rocks are not one flat shade.
	var color_noise := FastNoiseLite.new()
	color_noise.seed = rng.next_int() & 0x7FFFFFFF
	color_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	color_noise.frequency = 2.6

	# Whatever grows out of it is part of the shape and so of how big it is.
	var decoration := _decorate(rng, asteroid, positions, normals)
	model.decoration_count = decoration.count

	# Scale it so the farthest point, the tip of a crystal if it has any, is a meter from the middle.
	var farthest := 0.001
	for point in positions:
		farthest = maxf(farthest, point.length())
	for point in decoration.vertices:
		farthest = maxf(farthest, point.length())
	var shrink := 1.0 / farthest
	for index in vertex_count:
		positions[index] *= shrink
	decoration.scale(shrink)

	var mottling := asteroid.mottling
	var colors := PackedColorArray()
	colors.resize(vertex_count)
	for index in vertex_count:
		var p := positions[index]
		var shade := clampf(1.0 - 0.22 * mottling / 0.32 + mottling * color_noise.get_noise_3d(p.x, p.y, p.z), 0.0, 1.0)
		colors[index] = Color(shade, shade, shade)

	# Godot draws triangles wound clockwise, so the corners go out in the other order.
	var indices := PackedInt32Array()
	indices.resize(_base_triangles.size())
	var faces := PackedVector3Array()
	faces.resize(_base_triangles.size())
	for corner in range(0, _base_triangles.size(), 3):
		indices[corner] = _base_triangles[corner]
		indices[corner + 1] = _base_triangles[corner + 2]
		indices[corner + 2] = _base_triangles[corner + 1]
	for corner in indices.size():
		faces[corner] = positions[indices[corner]]

	model.positions = positions
	model.normals = normals
	model.decoration_vertices = decoration.vertices
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	model.mesh = ArrayMesh.new()
	model.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	model.mesh.surface_set_material(0, _pick_material(asteroid, rng))
	for surface in decoration.surfaces:
		var surface_arrays: Array = []
		surface_arrays.resize(Mesh.ARRAY_MAX)
		surface_arrays[Mesh.ARRAY_VERTEX] = surface.vertices
		surface_arrays[Mesh.ARRAY_NORMAL] = surface.normals
		surface_arrays[Mesh.ARRAY_TEX_UV] = surface.uvs
		model.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_arrays)
		model.mesh.surface_set_material(model.mesh.get_surface_count() - 1, surface.material)
	faces.append_array(decoration.faces)

	model.collision = ConcavePolygonShape3D.new()
	model.collision.backface_collision = true
	model.collision.set_faces(faces)
	return model


# --- Decorations ---------------------------------------------------------------------------------------

## The mesh of one material of the decorations of a model.
class DecorationSurface:
	extends RefCounted
	var material: Material
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()


## Everything that grows out of a model, baked: one surface for each material, the triangles the collision shape
## gets, and every corner (for working out how far the model reaches).
class Decoration:
	extends RefCounted
	var surfaces: Array[DecorationSurface] = []
	var faces := PackedVector3Array()
	var vertices := PackedVector3Array()
	var count := 0

	func get_surface(material: Material) -> DecorationSurface:
		for surface in surfaces:
			if surface.material == material:
				return surface
		var made := DecorationSurface.new()
		made.material = material
		surfaces.append(made)
		return made

	## Makes everything [param factor] times its size.
	func scale(factor: float) -> void:
		for index in vertices.size():
			vertices[index] *= factor
		for index in faces.size():
			faces[index] *= factor
		for surface in surfaces:
			for index in surface.vertices.size():
				surface.vertices[index] *= factor


## Grows the decorators of [param asteroid] out of the body (given as [param positions] and [param normals]): clusters of
## pieces from the points of its surface and along their normals, leaning every which way.
func _decorate(rng: SpaceRandom, asteroid: Asteroid, positions: PackedVector3Array, normals: PackedVector3Array) -> Decoration:
	var decoration := Decoration.new()
	for decorator in asteroid.decorators:
		if decorator == null or not decorator.has_parts():
			continue
		var clusters := rng.range_int(mini(decorator.clusters_min, decorator.clusters_max), maxi(decorator.clusters_min, decorator.clusters_max))
		for _cluster in clusters:
			var anchor := rng.range_int(0, positions.size() - 1)
			var pieces := rng.range_int(mini(decorator.pieces_min, decorator.pieces_max), maxi(decorator.pieces_min, decorator.pieces_max))
			for piece in pieces:
				_add_piece(rng, decorator, positions[anchor], normals[anchor], piece, decoration)
	return decoration


## One piece of [param decorator], growing from [param point] of the body, whose surface faces [param normal] there.
## [param piece] is how many are already growing from this spot: the later ones lean further and are smaller.
func _add_piece(rng: SpaceRandom, decorator: AsteroidDecorator, point: Vector3, normal: Vector3, piece: int, out: Decoration) -> void:
	var lean := decorator.lean + 0.35 * piece
	var axis := (normal + rng.unit_vector() * lean).normalized()
	if axis.dot(normal) < 0.2:
		axis = normal
	var height := rng.range_float(minf(decorator.size_min, decorator.size_max), maxf(decorator.size_min, decorator.size_max)) * (1.0 - 0.15 * piece)
	var girth := height * (1.0 + rng.range_float(-decorator.thickness_variation, decorator.thickness_variation))
	var jitter := rng.unit_vector() * 0.05
	var twist := rng.next_float() * TAU

	# Turned so its up is the axis, then spun about it, then sized.
	var helper := Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT
	var across := axis.cross(helper).normalized()
	var turned := Basis(across, axis, across.cross(axis)).rotated(axis, twist)
	var placed := Transform3D(turned * Basis.from_scale(Vector3(girth, height, girth)), point + jitter - axis * (decorator.sink * height))

	for part in decorator.get_parts():
		var full := placed * part.transform
		var normal_basis := full.basis.inverse().transposed()
		var surface := out.get_surface(part.material)
		for corner in range(0, part.vertices.size(), 3):
			var a := full * part.vertices[corner]
			var b := full * part.vertices[corner + 1]
			var c := full * part.vertices[corner + 2]
			var face := (b - a).cross(c - a)
			if face.length() < MINIMUM_TRIANGLE_AREA * 2.0:
				continue
			# Drawn clockwise, so the face's own cross product points into the rock.
			var flat_normal := (-face).normalized()
			var corners: Array[Vector3] = [a, b, c]
			for index in 3:
				var smooth_normal: Vector3 = (normal_basis * part.normals[corner + index]).normalized()
				surface.vertices.append(corners[index])
				surface.normals.append(flat_normal if decorator.flat_shaded else smooth_normal)
				surface.uvs.append(part.uvs[corner + index])
			out.vertices.append_array(PackedVector3Array([a, b, c]))
			if decorator.collide:
				out.faces.append_array(PackedVector3Array([a, b, c]))
	out.count += 1


# --- The starting sphere -----------------------------------------------------------------------------------

static func _ensure_base(detail: int) -> void:
	if _base_detail == detail:
		return
	var t := (1.0 + sqrt(5.0)) * 0.5
	var vertices := PackedVector3Array([
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	])
	for index in vertices.size():
		vertices[index] = vertices[index].normalized()
	var triangles := PackedInt32Array([
		0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
		1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
		4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1,
	])
	for _step in detail:
		# Each triangle becomes four: one in every corner and one in the middle.
		var midpoints: Dictionary[int, int] = {}
		var refined := PackedInt32Array()
		for corner in range(0, triangles.size(), 3):
			var a := triangles[corner]
			var b := triangles[corner + 1]
			var c := triangles[corner + 2]
			var ab := _midpoint(vertices, midpoints, a, b)
			var bc := _midpoint(vertices, midpoints, b, c)
			var ca := _midpoint(vertices, midpoints, c, a)
			refined.append_array(PackedInt32Array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca]))
		triangles = refined
	_base_vertices = vertices
	_base_triangles = triangles
	_base_detail = detail


## The vertex halfway between [param a] and [param b], made once however many triangles share the edge.
static func _midpoint(vertices: PackedVector3Array, cache: Dictionary[int, int], a: int, b: int) -> int:
	var key := (mini(a, b) << 24) | maxi(a, b)
	if cache.has(key):
		return cache[key]
	var index := vertices.size()
	vertices.append(((vertices[a] + vertices[b]) * 0.5).normalized())
	cache[key] = index
	return index
