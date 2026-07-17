// OCEANO DO MAPA-MÚNDI — correntes sutis animadas + profundidade + grade + vinheta.
// Roda em 1 quad (o ColorRect "Ocean") → custo GPU desprezível em Vulkan.
// Filosofia: "satisfação ao olhar o mapa" sem poluição — tudo em baixa amplitude.
shader_type canvas_item;

uniform vec3 deep_color : source_color = vec3(0.012, 0.028, 0.050);
uniform vec3 shallow_color : source_color = vec3(0.032, 0.075, 0.118);
uniform float wave_strength : hint_range(0.0, 1.0) = 0.35;
uniform float grid_alpha : hint_range(0.0, 0.2) = 0.040;

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

// 3 oitavas bastam — mais que isso não aparece na amplitude usada
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.55;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	// Correntes marítimas: dois campos fbm derivando devagar em direções opostas
	float n1 = fbm(uv * vec2(14.0, 9.0) + vec2(TIME * 0.015, TIME * 0.008));
	float n2 = fbm(uv * vec2(30.0, 20.0) - vec2(TIME * 0.010, 0.0));
	float water = n1 * 0.75 + n2 * 0.25;
	vec3 col = mix(deep_color, shallow_color, water * wave_strength + 0.18);
	// Polos mais escuros (profundidade/latitude)
	float lat = abs(uv.y - 0.5) * 2.0;
	col *= 1.0 - lat * 0.22;
	// Grade lat/long fantasma (identidade "comando estratégico")
	vec2 g = fract(uv * vec2(36.0, 18.0));
	float grid = step(g.x, 0.010) + step(g.y, 0.020);
	col += vec3(0.0, 0.55, 0.85) * grid * grid_alpha;
	// Vinheta suave nas bordas do mundo
	float vig = smoothstep(1.05, 0.45, distance(uv, vec2(0.5)));
	col *= mix(0.80, 1.0, vig);
	COLOR = vec4(col, 1.0);
}
