shader_type spatial;
// Cheap open-water surface for the area around a map: two scrolling samples
// of one tiling noise normal map, glossy, with a little extra brightness at
// grazing angles. One texture, no depth/screen reads (fine for Quest).

uniform vec4 water_color : source_color = vec4(0.13, 0.3, 0.38, 1.0);
uniform sampler2D wave_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wave_scale = 0.025;   // tiles per metre
uniform float wave_speed = 0.015;

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 uv = world_xz * wave_scale;
	vec3 n1 = texture(wave_normal, uv + vec2(TIME * wave_speed, 0.0)).xyz;
	vec3 n2 = texture(wave_normal, uv * 1.7 - vec2(0.0, TIME * wave_speed * 1.3)).xyz;
	NORMAL_MAP = normalize(n1 + n2 - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(water_color.rgb, vec3(0.55, 0.68, 0.78), fresnel * 0.5);
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
