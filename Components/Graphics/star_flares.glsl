#[compute]
#version 450
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// Lens flares and god rays for up to three stars at once. A compositor effect (see star_flare_effect.gd):
// the full-resolution pass, over the finished color image, before glow and tonemapping. It only ever adds light.
//
// The stars are only directions in the world, so this works out where each one lands on the screen from the
// scene's own camera (the same way the star shader does), which keeps the glare stuck to the disc even while the
// camera turns fast. What it adds for each star: a glare around the disc, an anamorphic streak, ghosts along the
// line through the middle of the screen, and the god rays that star_rays.glsl worked out at a quarter of the size
// (colored here, smoothed, and kept off anything solid, so rocks stay dark against the haze). All of it needs the star
// to be in view: it dims the more of the disc something covers, fades as the star leaves the screen, and is gone when
// the star is behind the camera.
//
// Every star gets the same flare, whatever size its disc is drawn: what a lens makes of a bright point does not depend
// on how big the point is (a bigger, hotter star is stronger, not wider), and the star shader draws the disc and its
// corona for itself.
//
// The ideas follow the lens_effects addon by ARez (MIT) and the Shadertoy shaders it credits
// (https://www.shadertoy.com/view/XdfXRX).
//
// Distances are in screen heights (the screen is 1 high and `aspect` wide), so a shape keeps its size when the
// window changes shape. Sky is depth 0 (Godot's depth is reversed): anything above that blocks a star.

#define MAX_VIEWS 2
#include "godot/scene_data_inc.glsl"

layout(set = 0, binding = 0, std140) uniform SceneDataBlock {
	SceneData data;
	SceneData prev_data;
} scene;

layout(rgba16f, set = 0, binding = 1) uniform image2D color_image;
layout(set = 0, binding = 2) uniform sampler2D depth_sampler;
layout(set = 0, binding = 3) uniform sampler2D rays_sampler;

layout(set = 1, binding = 0, std140) uniform StarBlock {
	// xyz: the way to the star in the world, w: the tangent of half the angle across its disc.
	vec4 star_direction[3];
	// rgb: the color of its glare, a: how strong it is.
	vec4 star_color[3];
	// x: how many stars, y: glare, z: streak, w: ghosts (strengths).
	vec4 params_a;
	// x: ray strength, y: ray samples (0 for none), z: streak length, w: how hard the shadows of the rays are.
	vec4 params_b;
} stars;

const int MAX_STARS = 3;
const int VISIBILITY_SAMPLES = 16;
// How far from the middle of a star, in pixels, a covered patch still counts as covering it: how much of the star is
// seen is judged by looking around its middle, not across its whole disc.
const float VISIBILITY_RADIUS = 3.0;
// The hot core of the glare, a bright spot a few pixels across at the middle of the star, as a distance in screen heights.
const float CORE_RADIUS = 0.002;
// How far the veil of the glare reaches, and how thick the streak is, in screen heights.
const float VEIL_REACH = 0.1;
const float STREAK_THICKNESS = 0.0016;

shared vec3 s_star[MAX_STARS]; // xy: where on the screen (0..1), z: how much of it is in view (0 behind the camera)
shared float s_hits[MAX_STARS * VISIBILITY_SAMPLES];
shared float s_open[MAX_STARS]; // how much of the star can be seen, 0..1
shared float s_in_view; // how much of the most visible star is in view, 0 when there is none

const int GHOST_COUNT = 5;
// Where each ghost sits on the line from the star through the middle of the screen (1 is the middle itself).
const float GHOST_AT[GHOST_COUNT] = float[](0.4, 0.75, 1.3, 1.75, 2.4);
const float GHOST_SIZE[GHOST_COUNT] = float[](0.05, 0.1, 0.035, 0.13, 0.07);
const float GHOST_POWER[GHOST_COUNT] = float[](0.7, 0.5, 1.0, 0.35, 0.6);
const vec3 GHOST_TINT[GHOST_COUNT] = vec3[](
	vec3(1.0, 0.55, 0.3), vec3(0.35, 0.7, 1.0), vec3(0.55, 1.0, 0.5), vec3(0.9, 0.4, 0.95), vec3(1.0, 0.8, 0.4));

bool is_sky(vec2 pixel, vec2 size) {
	if (pixel.x < 0.0 || pixel.y < 0.0 || pixel.x >= size.x || pixel.y >= size.y) {
		return true; // off the screen, so assume the sky
	}
	return texelFetch(depth_sampler, ivec2(pixel), 0).r <= 0.0;
}

vec3 project_star(int index, vec2 size, float aspect) {
	if (float(index) >= stars.params_a.x) {
		return vec3(0.0);
	}
	// (The scene data of a compute pass names its matrices the other way round from a spatial shader: it is
	// inv_view_matrix that takes a world direction into the camera's frame. Checked against the star shader.)
	vec3 view_direction = mat3(scene.data.inv_view_matrix) * normalize(stars.star_direction[index].xyz);
	float ahead = -view_direction.z;
	if (ahead <= 0.02) {
		return vec3(0.0);
	}
	vec4 clip = scene.data.projection_matrix * vec4(view_direction, 1.0);
	vec2 uv = (clip.xy / clip.w) * 0.5 + 0.5;
	// A star well off to the side or behind has nothing to show; one just off the screen still glares into it.
	vec2 outside = max(abs(uv - 0.5) - 0.5, vec2(0.0)) * vec2(aspect, 1.0);
	float visible = smoothstep(0.02, 0.2, ahead) * (1.0 - smoothstep(0.0, 0.7, length(outside)));
	return vec3(uv, visible);
}

void main() {
	uint local = gl_LocalInvocationIndex;
	vec2 size = scene.data.viewport_size;
	float aspect = size.x / size.y;

	// Once per group: where the stars are, and how much of each can be seen.
	if (local < uint(MAX_STARS)) {
		s_star[local] = project_star(int(local), size, aspect);
	}
	memoryBarrierShared();
	barrier();
	if (local < uint(MAX_STARS * VISIBILITY_SAMPLES)) {
		uint index = local / uint(VISIBILITY_SAMPLES);
		uint sample_index = local % uint(VISIBILITY_SAMPLES);
		vec3 star = s_star[index];
		float seen = 0.0;
		if (star.z > 0.0) {
			float angle = float(sample_index) * 2.399963;
			float reach = VISIBILITY_RADIUS * sqrt((float(sample_index) + 0.5) / float(VISIBILITY_SAMPLES));
			vec2 pixel = star.xy * size + vec2(cos(angle), sin(angle)) * reach;
			seen = is_sky(pixel, size) ? 1.0 : 0.0;
		}
		s_hits[local] = seen;
	}
	memoryBarrierShared();
	barrier();
	if (local < uint(MAX_STARS)) {
		float total = 0.0;
		for (int i = 0; i < VISIBILITY_SAMPLES; i++) {
			total += s_hits[int(local) * VISIBILITY_SAMPLES + i];
		}
		s_open[local] = total / float(VISIBILITY_SAMPLES);
	}
	if (local == 0u) {
		s_in_view = max(s_star[0].z, max(s_star[1].z, s_star[2].z));
	}
	memoryBarrierShared();
	barrier();

	ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
	if (coord.x >= int(size.x) || coord.y >= int(size.y)) {
		return;
	}
	vec2 pixel = vec2(coord) + 0.5;
	vec2 uv = pixel / size;
	float glare_strength = stars.params_a.y;
	float streak_strength = stars.params_a.z;
	float ghost_strength = stars.params_a.w;
	float ray_strength = stars.params_b.x;
	float streak_length = stars.params_b.z;
	// (With no star in view there is no haze either, so there is nothing to look up.)
	bool rays_on = ray_strength > 0.0 && stars.params_b.y >= 1.0 && s_in_view > 0.0;

	// The haze the other pass made, kept off anything solid.
	vec3 haze = vec3(0.0);
	if (rays_on && is_sky(pixel, size)) {
		// Five looks, one in the middle and four a little way off, which smooth the grain left by the way the
		// other pass spreads its samples.
		vec2 texel = 1.0 / vec2(textureSize(rays_sampler, 0));
		haze = textureLod(rays_sampler, uv, 0.0).rgb * 0.2;
		haze += textureLod(rays_sampler, uv + vec2(0.8, 0.8) * texel, 0.0).rgb * 0.2;
		haze += textureLod(rays_sampler, uv + vec2(-0.8, 0.8) * texel, 0.0).rgb * 0.2;
		haze += textureLod(rays_sampler, uv + vec2(0.8, -0.8) * texel, 0.0).rgb * 0.2;
		haze += textureLod(rays_sampler, uv + vec2(-0.8, -0.8) * texel, 0.0).rgb * 0.2;
	}

	vec3 light = vec3(0.0);
	for (int i = 0; i < MAX_STARS; i++) {
		vec3 star = s_star[i];
		float shown = star.z * s_open[i];
		if (shown <= 0.0) {
			continue;
		}
		vec3 tint = stars.star_color[i].rgb;
		float power = stars.star_color[i].a * shown;

		vec2 offset = vec2((uv.x - star.x) * aspect, uv.y - star.y);
		float distance_from_star = length(offset);

		// Glare: a hot core at the middle of the star and a long faint veil around it.
		float outer = max(distance_from_star / CORE_RADIUS - 1.0, 0.0);
		float core = 0.55 / pow(1.0 + outer * outer * 0.8, 1.2);
		float veil = 0.05 / (1.0 + pow(distance_from_star / VEIL_REACH, 2.0));
		light += tint * (core + veil) * glare_strength * power;

		// The anamorphic streak: a thin line through the star, straight across the screen.
		float streak = exp(-abs(offset.y) / STREAK_THICKNESS) * exp(-abs(offset.x) / streak_length);
		vec3 streak_tint = mix(tint, vec3(0.55, 0.72, 1.0), 0.4);
		light += streak_tint * streak * streak_strength * power * 0.6;

		// Ghosts: reflections inside the lens, lined up with the middle of the screen.
		if (ghost_strength > 0.0) {
			vec2 toward_middle = vec2(0.5) - star.xy;
			float near_middle = 1.0 - 0.5 * smoothstep(0.0, 0.6, length(toward_middle * vec2(aspect, 1.0)));
			for (int g = 0; g < GHOST_COUNT; g++) {
				vec2 center = star.xy + toward_middle * GHOST_AT[g];
				vec2 from_ghost = vec2((uv.x - center.x) * aspect, uv.y - center.y);
				float across = length(from_ghost) / GHOST_SIZE[g];
				if (across < 1.2) {
					float ring = exp(-pow((across - 0.8) * 3.4, 2.0)) * 0.8;
					float fill = (1.0 - smoothstep(0.0, 1.0, across)) * 0.25;
					vec3 ghost_tint = mix(tint, GHOST_TINT[g], 0.6);
					light += ghost_tint * (ring + fill) * GHOST_POWER[g] * ghost_strength * power * near_middle * 0.12;
				}
			}
		}

		// God rays: the haze, shadowed wherever something is in the way of the star.
		light += tint * haze[i] * ray_strength * power;
	}

	// Reading and writing the whole picture is the main cost of this pass, so leave alone what gets no light (all of it,
	// when the star is out of view).
	if (light.r > 0.0 || light.g > 0.0 || light.b > 0.0) {
		vec4 base = imageLoad(color_image, coord);
		imageStore(color_image, coord, vec4(base.rgb + light, base.a));
	}
}
