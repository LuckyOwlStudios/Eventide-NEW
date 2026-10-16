#[compute]
#version 450
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// The god rays of up to three stars, first half (see star_flares.glsl for the second, and star_flare_effect.gd).
//
// Runs at a quarter of the screen's resolution, because it is the costly part: for every texel it looks along the
// line toward each star, a number of times, to see how much of the way is blocked by something in the depth buffer.
// What it writes is, per star, how much haze there is at that texel and how much of it gets through: the red,
// green and blue channels are the first, second and third star. The full-resolution pass colors and blurs it.
//
// The rays are only there while the star is in view: they fade as it leaves the screen and are gone when it is behind
// the camera.
//
// Distances are in screen heights (the screen is 1 high). Sky is depth 0 (Godot's depth is reversed).

#define MAX_VIEWS 2
#include "godot/scene_data_inc.glsl"

layout(set = 0, binding = 0, std140) uniform SceneDataBlock {
	SceneData data;
	SceneData prev_data;
} scene;

layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D rays_image;
layout(set = 0, binding = 2) uniform sampler2D depth_sampler;

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
// How far the haze reaches, in screen heights: thick within the first, and a long faint tail within the second. They
// are the same for every star, whatever size its disc is drawn (see star_flares.glsl).
const float NEAR_REACH = 0.07;
const float FAR_REACH = 0.3;

shared vec3 s_star[MAX_STARS]; // xy: where on the screen (0..1), z: how much of it is in view (0 behind the camera)

// Interleaved gradient noise: a cheap, even pattern, used to spread the samples so they blur instead of banding.
float gradient_noise(vec2 pixel) {
	return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}

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
	if (local < uint(MAX_STARS)) {
		s_star[local] = project_star(int(local), size, aspect);
	}
	memoryBarrierShared();
	barrier();

	ivec2 texel = ivec2(gl_GlobalInvocationID.xy);
	ivec2 rays_size = imageSize(rays_image);
	if (texel.x >= rays_size.x || texel.y >= rays_size.y) {
		return;
	}
	// Where on the full-size screen this texel is.
	vec2 pixel = (vec2(texel) + 0.5) * size / vec2(rays_size);
	vec2 uv = pixel / size;
	int samples = int(stars.params_b.y);
	float hardness = stars.params_b.w;

	vec3 haze_through = vec3(0.0);
	for (int i = 0; i < MAX_STARS; i++) {
		vec3 star = s_star[i];
		if (star.z <= 0.0) {
			continue;
		}
		vec2 offset = vec2((uv.x - star.x) * aspect, uv.y - star.y);
		float distance_from_star = length(offset);

		// Haze: thick close to the star and thinning out to a long faint tail.
		float haze = 0.85 * exp(-distance_from_star / NEAR_REACH) + 0.15 / (1.0 + pow(distance_from_star / FAR_REACH, 2.0));
		haze *= 1.0 - smoothstep(0.8, 1.6, distance_from_star);
		if (haze <= 0.002) {
			continue;
		}

		// How much of the way from here to the star is blocked.
		vec2 star_pixel = star.xy * size;
		vec2 to_star = star_pixel - pixel;
		float jitter = gradient_noise(vec2(texel) + float(i) * 17.0);
		float blocked = 0.0;
		for (int s = 0; s < samples; s++) {
			float along = (float(s) + jitter) / float(samples);
			blocked += is_sky(pixel + to_star * along, size) ? 0.0 : 1.0;
		}
		float clear = 1.0 - smoothstep(0.0, 1.0, blocked / float(samples) * hardness);
		haze_through[i] = haze * clear;
	}
	imageStore(rays_image, texel, vec4(haze_through, 0.0));
}
