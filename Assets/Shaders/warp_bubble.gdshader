shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// The skin of the warp bubble: an oval of warping energy around the ship that hides the world
// while it changes. Seen from inside it is a tunnel of light streaming past; from outside it is a
// glowing shell. The mesh is a sphere of radius one, stretched into the oval by the node.
//
// `progress` is how much of the skin exists. At 0 none of it is drawn; as it rises the skin burns
// in from scattered points, with a bright rim along the burning edge, until all of it is there.
// It is drawn opaque (cut away, never see-through), so nothing behind it ever shows.

uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform vec4 deep_color : source_color = vec4(0.02, 0.06, 0.28, 1.0);
uniform vec4 streak_color : source_color = vec4(0.2, 0.62, 1.0, 1.0);
uniform vec4 hot_color : source_color = vec4(0.85, 0.95, 1.0, 1.0);
// How bright the light is. Above 1 it blooms, if the world has glow.
uniform float energy : hint_range(0.0, 8.0) = 2.6;
// How fast the streaks run past.
uniform float speed : hint_range(0.0, 10.0) = 2.4;
// How much the streaks twist around the length of the oval.
uniform float twist : hint_range(0.0, 8.0) = 2.5;

varying vec3 local_direction;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Smooth noise that repeats every `period` cells across, so it has no seam where the angle wraps round.
float wrapped_noise(vec2 p, float period) {
	vec2 cell = floor(p);
	vec2 blend = fract(p);
	blend = blend * blend * (3.0 - 2.0 * blend);
	float left = mod(cell.x, period);
	float right = mod(cell.x + 1.0, period);
	return mix(
		mix(hash(vec2(left, cell.y)), hash(vec2(right, cell.y)), blend.x),
		mix(hash(vec2(left, cell.y + 1.0)), hash(vec2(right, cell.y + 1.0)), blend.x),
		blend.y);
}

float wrapped_fbm(vec2 p, float period) {
	float total = 0.0;
	float amount = 0.5;
	for (int octave = 0; octave < 4; octave++) {
		total += amount * wrapped_noise(p, period);
		p = vec2(p.x * 2.0, p.y * 2.0 + 7.3);
		period *= 2.0;
		amount *= 0.5;
	}
	return total;
}

void vertex() {
	local_direction = normalize(VERTEX);
}

void fragment() {
	vec3 direction = normalize(local_direction);
	// Around the length of the oval (-0.5 to 0.5), and along it (-1 at one end, 1 at the other).
	float around = atan(direction.y, direction.x) / 6.28318;
	float along = direction.z;

	// Burning in: every spot has a moment it appears, and progress sweeps past them all.
	float patch = wrapped_fbm(vec2(around * 7.0 + along * 2.0, along * 5.0), 7.0);
	float moment = smoothstep(0.22, 0.75, patch);
	float burning = progress * 1.12 - moment;
	if (burning <= 0.0) {
		discard;
	}
	float rim = 1.0 - smoothstep(0.0, 0.1, burning);

	// Streaks: noise stretched along the oval, twisting as it goes. They flow toward +z, the stern, from
	// inside and outside alike, which is how the world streams past a ship that is flying forward (-z).
	float twisted = around + along * twist * 0.15 + TIME * 0.05;
	float stream = along * 3.0 - TIME * speed;
	float lines = wrapped_fbm(vec2(twisted * 38.0, stream), 38.0);
	float fine = wrapped_fbm(vec2(twisted * 120.0, stream * 2.7 + 11.0), 120.0);
	float streak = smoothstep(0.38, 0.82, lines) * (0.55 + 0.75 * fine);

	// Brighter toward the ends, where the tunnel narrows to a point.
	float ends = pow(abs(along), 5.0);
	// Brighter at a grazing angle, which gives the shell from outside its glowing edge.
	float fresnel = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.2);

	vec3 color = mix(deep_color.rgb, streak_color.rgb, clamp(streak + 0.25 * fresnel, 0.0, 1.0));
	color = mix(color, hot_color.rgb, clamp(ends * 0.65 + rim * 0.9 + streak * streak * 0.35, 0.0, 1.0));
	float shimmer = 0.88 + 0.12 * sin(TIME * 7.0 + around * 40.0);
	if (!FRONT_FACING) {
		// Seen from outside: a denser, more solid looking shell.
		color = mix(color, streak_color.rgb, 0.35 * fresnel) + hot_color.rgb * fresnel * 0.5;
	}
	ALBEDO = color * energy * shimmer;
}
