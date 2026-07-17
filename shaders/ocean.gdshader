// OCEANO v3 — MAR AZUL REALISTA com profundidade, correntes e brilho solar.
// World-space; 1 quad → custo desprezível. Mais claro perto do equador,
// escuro e frio nos polos; ondulação fbm visível mas calma.
shader_type canvas_item;

uniform vec3 deep_color : source_color = vec3(0.040, 0.095, 0.185);
uniform vec3 shallow_color : source_color = vec3(0.095, 0.215, 0.360);
uniform float wave_strength : hint_range(0.0, 1.0) = 0.60;
uniform float grid_alpha : hint_range(0.0, 0.3) = 0.026;
uniform float grid_step = 250.0;

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
	// Ondulação/correntes em duas escalas, deriva lenta
	float n1 = fbm(wpos * 0.0038 + vec2(TIME * 0.022, TIME * 0.012));
	float n2 = fbm(wpos * 0.0125 - vec2(TIME * 0.015, 0.0));
	float water = n1 * 0.68 + n2 * 0.32;
	vec3 col = mix(deep_color, shallow_color, clamp(water * wave_strength + 0.25, 0.0, 1.0));
	// Latitude: mar equatorial mais claro/quente, polar mais escuro/frio
	float lat = 90.0 - wpos.y * 0.18;
	float alat = clamp(abs(lat) / 90.0, 0.0, 1.0);
	col *= 1.0 - alat * 0.34;
	col.b *= 1.0 + alat * 0.08;
	// Banheira de gelo polar: mar quase branco-azulado além de ~72°
	float polar_ice = smoothstep(0.80, 0.93, alat);
	col = mix(col, vec3(0.72, 0.78, 0.84), polar_ice * 0.85);
	// Grade náutica discreta
	vec2 g = abs(fract(wpos / grid_step) - 0.5);
	float dline = min(g.x, g.y) * grid_step;
	float grid = 1.0 - smoothstep(0.0, 1.3, dline);
	col += vec3(0.55, 0.70, 0.85) * grid * grid_alpha;
	// Glint solar itinerante (reflexo do sol no mar)
	float glint = smoothstep(0.80, 0.95, vnoise(wpos * 0.0065 + vec2(TIME * 0.05, -TIME * 0.03)));
	col += vec3(0.14, 0.18, 0.20) * glint * 0.45;
	COLOR = vec4(col, 1.0);
}
