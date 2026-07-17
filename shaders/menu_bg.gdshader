// FUNDO CINEMATOGRÁFICO DO MENU — aurora azul-petróleo em deriva lenta + vinheta.
// 1 quad full-screen → custo desprezível. Amplitude baixa: o card continua o herói.
shader_type canvas_item;

uniform vec3 base_color : source_color = vec3(0.010, 0.022, 0.042);
uniform vec3 aurora_a : source_color = vec3(0.0, 0.10, 0.19);
uniform vec3 aurora_b : source_color = vec3(0.0, 0.38, 0.55);
uniform float intensity : hint_range(0.0, 1.0) = 0.34;

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
	// Aurora: banda de fbm que deriva lentamente na diagonal
	float n = fbm(uv * vec2(2.6, 3.4) + vec2(TIME * 0.020, -TIME * 0.012));
	float band = smoothstep(0.38, 0.80, n);
	vec3 aurora = mix(aurora_a, aurora_b, band);
	vec3 col = base_color + aurora * band * intensity;
	// Estrelas fixas bem fracas (pontos de hash)
	float star = step(0.9985, hash(floor(uv * vec2(220.0, 130.0))));
	col += vec3(0.55, 0.75, 0.9) * star * 0.10;
	// Vinheta: foco no centro, onde vive o card
	float vig = smoothstep(1.15, 0.35, distance(uv, vec2(0.5)));
	col *= mix(0.70, 1.05, vig);
	COLOR = vec4(col, 1.0);
}
