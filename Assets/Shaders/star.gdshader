shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled;

// A star in the sky: a glowing disc wrapped in your star texture, and a corona around it. It is drawn
// at the end of the sky, never at a place in the world, so it cannot be flown to and does not move when
// the ship does, only when the camera turns. Everything in the world is in front of it.
//
// The mesh is a quad two meters across that can be anywhere: the vertex shader ignores where it is, and
// puts each corner on the ray from the camera toward the star (spread out enough to hold the corona),
// at the far end of the depth buffer. The fragment shader then works out, for each pixel, how far it is
// from the middle of the star in angle, and draws the disc, the surface texture or the corona.

uniform vec3 direction = vec3(0.0, 0.0, -1.0);
// Half the angle across the disc, in radians.
uniform float angular_radius = 0.1;
// How many disc radii out the quad reaches for a star of about six degrees, which is how far the corona can spread.
// Bigger stars have a corona that is smaller next to them, so a very close star does not fill the sky with haze.
uniform float quad_radius = 7.0;
uniform vec4 star_color : source_color = vec4(1.0, 0.96, 0.9, 1.0);
// How much stronger the disc's color is than the light's, which is kept pale.
uniform float color_boost = 1.7;
// How bright the disc is. Above 1 its hot patches bloom, if the world has glow.
uniform float disc_energy = 1.0;
uniform float corona_energy = 0.6;
uniform float spin_phase = 0.0;
uniform float spin_speed = 0.02;
uniform float tilt = 0.0;
uniform sampler2D star_texture : source_color, filter_linear_mipmap, repeat_enable;

varying vec3 ray;
varying vec3 axis_right;
varying vec3 axis_up;

// How much shorter the corona is, in disc radii, for a star bigger than about six degrees (and longer for a smaller one).
float corona_scale() {
	return pow(max(angular_radius, 0.001) / 0.1, 0.35);
}

void vertex() {
	vec3 n = normalize(direction);
	vec3 helper = abs(n.y) > 0.99 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
	axis_right = normalize(cross(helper, n));
	axis_up = cross(n, axis_right);
	// The quad lies flat across the star, so a point at an angle of `a` from its middle is `tan(a)` out.
	float reach = min(tan(min(angular_radius * quad_radius / corona_scale(), 1.3)), 4.0);
	ray = n + (axis_right * VERTEX.x + axis_up * VERTEX.y) * reach;
	// Any distance along the ray will do; only the way it points matters. Then to the far end of the depth
	// range (depth 0 is the far plane: Godot's depth is reversed), so everything in the world hides it.
	vec4 clip = PROJECTION_MATRIX * vec4(mat3(VIEW_MATRIX) * ray * 100.0, 1.0);
	POSITION = vec4(clip.xy, clip.w * 0.000001, clip.w);
}

void fragment() {
	vec3 n = normalize(direction);
	vec3 d = normalize(ray);
	float angle = atan(length(cross(d, n)), dot(d, n));
	float r = angle / angular_radius;
	float scale = corona_scale();
	if (r > quad_radius / scale) {
		discard;
	}

	float aa = max(fwidth(r), 0.0001);
	float disc = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, r);

	// The point on the star's surface that this pixel sees: across the disc, and how much it faces us.
	vec3 across_ray = d - n * dot(d, n);
	float across_length = length(across_ray);
	vec2 across = across_length > 0.000001 ? vec2(dot(across_ray, axis_right), dot(across_ray, axis_up)) / across_length * min(r, 1.0) : vec2(0.0);
	float facing = sqrt(max(1.0 - dot(across, across), 0.0));
	vec3 p = vec3(across, facing);

	// Lean the star's axis, then spin it about that axis; a second, slower layer turns the other way so the surface seethes.
	float lean_cos = cos(tilt);
	float lean_sin = sin(tilt);
	p = vec3(p.x, p.y * lean_cos - p.z * lean_sin, p.y * lean_sin + p.z * lean_cos);
	float turn = spin_phase + TIME * spin_speed;
	vec3 p1 = vec3(p.x * cos(turn) + p.z * sin(turn), p.y, -p.x * sin(turn) + p.z * cos(turn));
	float turn2 = 1.7 - TIME * spin_speed * 0.6;
	vec3 p2 = vec3(p.x * cos(turn2) + p.z * sin(turn2), p.y * 0.9, -p.x * sin(turn2) + p.z * cos(turn2));

	// The texture is a world map: longitude around, latitude down. Its seam is hidden by using the gradient
	// of whichever way of writing the longitude does not jump there.
	vec2 uv1 = vec2(atan(p1.x, p1.z) / TAU + 0.5, acos(clamp(p1.y, -1.0, 1.0)) / PI);
	vec2 uv1_b = vec2(fract(uv1.x + 0.5) - 0.5, uv1.y);
	vec2 dx1 = dFdx(uv1);
	vec2 dy1 = dFdy(uv1);
	vec2 dx1_b = dFdx(uv1_b);
	vec2 dy1_b = dFdy(uv1_b);
	if (dot(dx1_b, dx1_b) + dot(dy1_b, dy1_b) < dot(dx1, dx1) + dot(dy1, dy1)) {
		dx1 = dx1_b;
		dy1 = dy1_b;
	}
	float surface_a = textureGrad(star_texture, uv1, dx1, dy1).r;
	vec2 uv2 = vec2(atan(p2.x, p2.z) / TAU + 0.5, acos(clamp(p2.y, -1.0, 1.0)) / PI);
	vec2 uv2_b = vec2(fract(uv2.x + 0.5) - 0.5, uv2.y);
	vec2 dx2 = dFdx(uv2);
	vec2 dy2 = dFdy(uv2);
	vec2 dx2_b = dFdx(uv2_b);
	vec2 dy2_b = dFdy(uv2_b);
	if (dot(dx2_b, dx2_b) + dot(dy2_b, dy2_b) < dot(dx2, dx2) + dot(dy2, dy2)) {
		dx2 = dx2_b;
		dy2 = dy2_b;
	}
	float surface_b = textureGrad(star_texture, uv2, dx2, dy2).r;
	float heat = mix(surface_a, surface_b, 0.35);

	// Darker and redder toward the edge, as a star is, brighter and whiter in its hot patches.
	float limb = 0.4 + 0.6 * pow(facing, 0.5);
	vec3 hue = clamp(mix(vec3(1.0), star_color.rgb, color_boost), vec3(0.0), vec3(1.0));
	vec3 surface = hue * (0.3 + 0.95 * heat);
	surface = mix(surface, vec3(1.0), smoothstep(0.75, 1.0, heat) * 0.3);
	surface = mix(hue * vec3(1.0, 0.55, 0.3) * 0.7, surface, limb) * disc_energy * limb;

	// The corona: bright at the edge of the disc, thinning slowly outward, gone before the quad ends.
	float outer = max(r - 1.0, 0.0) * scale;
	float corona = 1.0 / (1.0 + 5.0 * outer + 10.0 * outer * outer);
	corona *= 1.0 - smoothstep(quad_radius * 0.55, quad_radius, outer);
	vec3 glow = hue * corona_energy * corona;

	ALBEDO = glow * (1.0 - 0.5 * disc) + surface * disc;
	ALPHA = disc;
}
