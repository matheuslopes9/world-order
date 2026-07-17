// FUNDO CINEMATOGRÁFICO DO MENU — nébula quente em deriva lenta sobre carvão.
// Paleta dourada discreta (casa com o logo do brasão). 1 quad → custo ~zero.
shader_type canvas_item;

uniform vec3 base_color : source_color = vec3(0.010, 0.011, 0.015);
uniform vec3 nebula_a : source_color = vec3(0.070, 0.058, 0.032);
uniform vec3 nebula_b : source_color = vec3(0.240, 0.185, 0.085);
uniform float intensity : hint_range(0.0, 1.0) = 0.42;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.07;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	// Nébula dourada em deriva diagonal muito lenta
	float n = fbm(uv * vec2(2.4, 3.2) + vec2(TIME * 0.016, -TIME * 0.010));
	float band = smoothstep(0.42, 0.85, n);
	vec3 nebula = mix(nebula_a, nebula_b, band);
	vec3 col = base_color + nebula * band * intensity;
	// Poeira de estrelas fixa, quente e fraca
	float star = step(0.9986, hash(floor(uv * vec2(220.0, 130.0))));
	col += vec3(0.85, 0.75, 0.55) * star * 0.09;
	// Vinheta: foco no centro, onde vive o card
	float vig = smoothstep(1.18, 0.32, distance(uv, vec2(0.5)));
	col *= mix(0.62, 1.06, vig);
	COLOR = vec4(col, 1.0);
}
