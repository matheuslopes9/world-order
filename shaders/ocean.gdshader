// OCEANO DO MAPA-MÚNDI v2 — profundidade, correntes animadas e grade náutica.
// Coordenadas em WORLD SPACE (o v1 usava UV do rect de 8000px → tudo esticado
// e imperceptível). 1 quad → custo GPU desprezível em Vulkan.
shader_type canvas_item;

uniform vec3 deep_color : source_color = vec3(0.016, 0.028, 0.044);
uniform vec3 shallow_color : source_color = vec3(0.042, 0.075, 0.105);
uniform float wave_strength : hint_range(0.0, 1.0) = 0.55;
uniform float grid_alpha : hint_range(0.0, 0.3) = 0.085;
uniform float grid_step = 250.0;   // px de mundo entre linhas da grade

varying vec2 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

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
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.55;
	}
	return v;
}

void fragment() {
	// Correntes marítimas: 2 campos fbm em escalas de mundo diferentes,
	// derivando devagar em direções opostas (vivo, mas calmo)
	float n1 = fbm(wpos * 0.0035 + vec2(TIME * 0.020, TIME * 0.011));
	float n2 = fbm(wpos * 0.0110 - vec2(TIME * 0.014, 0.0));
	float water = n1 * 0.70 + n2 * 0.30;
	vec3 col = mix(deep_color, shallow_color, clamp(water * wave_strength + 0.22, 0.0, 1.0));
	// Faixas de profundidade por latitude (polos mais escuros e frios)
	float lat = clamp(abs(wpos.y - 500.0) / 2500.0, 0.0, 1.0);
	col *= 1.0 - lat * 0.28;
	// GRADE NÁUTICA em world space: linhas finas com anti-alias suave
	vec2 g = abs(fract(wpos / grid_step) - 0.5);
	float dline = min(g.x, g.y) * grid_step;         // distância em px à linha
	float grid = 1.0 - smoothstep(0.0, 1.4, dline);  // linha ~1.4px
	col += vec3(0.30, 0.42, 0.50) * grid * grid_alpha;
	// Brilho especular fraco itinerante (reflexo de luz sobre o mar)
	float glint = smoothstep(0.78, 0.95, vnoise(wpos * 0.006 + vec2(TIME * 0.05, -TIME * 0.03)));
	col += vec3(0.10, 0.14, 0.16) * glint * 0.35;
	COLOR = vec4(col, 1.0);
}
