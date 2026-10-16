class_name GraphicsPreset
extends Resource
## What one Graphics Quality level allows. An [AdvEnvironment] holds one per level.
##
## Presets only take things away: glow and shadows stay off wherever the scene itself
## turned them off, whatever the quality.

## Allows glow where the environment has it on.
@export var glow := true
## Allows shadows from the lights that have them on.
@export var shadows := true
## How much of the screen resolution the 3D world is drawn at. The interface always draws
## at full resolution. This is the biggest saving on weaker graphics cards.
@export_range(0.25, 1.0, 0.05) var render_scale := 1.0
@export var msaa: Viewport.MSAA = Viewport.MSAA_DISABLED
## Detail of the shadows from spot and omni lights.
@export_range(256, 8192, 256) var positional_shadow_atlas_size := 2048
## Draws lens flares around the stars (see [StarFlares]). Off, there are none and no rays.
@export var lens_flares := true
## The most samples the god rays of the stars may take for each point of their quarter-size picture. More is smoother
## and costs more; 0 has no rays, only flares. The stars' own setting is the upper limit.
@export_range(0, 128, 1) var god_ray_samples := 48


static func create(
	allow_glow: bool,
	allow_shadows: bool,
	scale: float,
	antialiasing: Viewport.MSAA,
	atlas_size: int,
	allow_lens_flares := true,
	ray_samples := 48,
) -> GraphicsPreset:
	var preset := GraphicsPreset.new()
	preset.glow = allow_glow
	preset.shadows = allow_shadows
	preset.render_scale = scale
	preset.msaa = antialiasing
	preset.positional_shadow_atlas_size = atlas_size
	preset.lens_flares = allow_lens_flares
	preset.god_ray_samples = ray_samples
	return preset
