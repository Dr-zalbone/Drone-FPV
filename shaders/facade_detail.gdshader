shader_type spatial;
// Procedural facade detail for low-resolution city scans (Manhattan source:
// ~0.12 texture px per metre). Keeps the original photo texture as the colour
// base and draws a world-space window grid on vertical walls up close,
// fading back to the plain texture with distance (no moire / shimmer in VR).
render_mode cull_disabled, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float floor_height = 3.6;      // metres per storey
uniform float bay_width = 3.2;         // metres per window bay
uniform vec2 window_size = vec2(0.6, 0.55); // fraction of a bay / storey
uniform vec3 glass_color : source_color = vec3(0.09, 0.12, 0.16);
uniform float glass_tint_from_base = 0.3;
uniform float frame_brighten = 1.18;
uniform float lit_window_chance = 0.02;
uniform float detail_fade_start = 120.0; // metres
uniform float detail_fade_end = 450.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 1 inside a centred rectangle of `size` in a 0..1 cell, anti-aliased.
float window_mask(vec2 f, vec2 size) {
	vec2 d = abs(f - 0.5) - size * 0.5;
	vec2 w = max(fwidth(f), vec2(1e-4));
	vec2 m = 1.0 - smoothstep(-w, w, d);
	return m.x * m.y;
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb;
	vec3 n = normalize(world_normal);
	float wall = 1.0 - smoothstep(0.25, 0.45, abs(n.y));
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float fade = 1.0 - smoothstep(detail_fade_start, detail_fade_end, dist);
	vec3 col = base;
	float rough = 0.85;
	float amount = wall * fade;
	if (amount > 0.001) {
		vec2 h = normalize(n.xz + vec2(1e-5));
		// Horizontal coordinate along the wall, vertical = world height.
		float u = dot(world_pos.xz, vec2(-h.y, h.x));
		vec2 cell = vec2(u / bay_width, world_pos.y / floor_height);
		vec2 id = floor(cell);
		vec2 f = fract(cell);
		// Facade orientation varies the pattern between buildings.
		float facade = hash(floor(h * 8.0) + floor(world_pos.xz / 40.0));
		vec2 size = window_size * vec2(0.85 + 0.3 * facade, 0.9 + 0.2 * hash(vec2(facade, 3.0)));
		float win = window_mask(f, size);
		float rnd = hash(id + facade * 17.0);
		vec3 glass = glass_color * (0.7 + 0.6 * rnd) + base * glass_tint_from_base;
		float lit = step(1.0 - lit_window_chance, hash(id * 1.37 + 3.1));
		glass = mix(glass, vec3(1.0, 0.86, 0.6), lit * 0.55);
		vec3 frame = base * frame_brighten;
		col = mix(base, mix(frame, glass, win), amount);
		rough = mix(0.85, 0.25, win * amount);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = 0.0;
}
