// OCEANO v4 — BATIMETRIA REAL da NASA Blue Marble + vida animada.
// Dentro dos bounds do mundo [0,2000]×[0,1000] sampleia o mar REAL da
// textura (dorsais, fossas, plataformas continentais). Fora, extrapola o
// azul profundo. Ondas fbm e glint solar entram como MODULAÇÃO leve.
shader_type canvas_item;

uniform sampler2D earth_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 border_deep : source_color = vec3(0.020, 0.050, 0.105);
uniform float wave_strength : hint_range(0.0, 0.5) = 0.14;
uniform float grid_alpha : hint_range(0.0, 0.3) = 0.020;
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
	vec2 uv = vec2(wpos.x / 2000.0, wpos.y / 1000.0);
	vec3 col;
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		// MAR REAL da NASA (batimetria) — leve realce de contraste
		col = texture(earth_tex, uv).rgb;
		float grey = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(vec3(grey), col, 1.15) * 1.30 + vec3(0.010, 0.022, 0.045);
	} else {
		// Fora do mundo: azul profundo LISO com transição curtíssima (60px).
		// (Antes: esticava a última coluna de pixels → borrão horizontal feio)
		vec2 d = max(vec2(0.0) - uv, uv - vec2(1.0));
		float dist = length(max(d, vec2(0.0)));
		vec3 edge = texture(earth_tex, clamp(uv, vec2(0.002), vec2(0.998))).rgb;
		float grey_e = dot(edge, vec3(0.299, 0.587, 0.114));
		edge = mix(vec3(grey_e), edge, 1.15) * 1.30 + vec3(0.010, 0.022, 0.045);
		col = mix(edge, border_deep, smoothstep(0.0, 0.03, dist));
	}
	// Ondulação viva (modulação sutil — o mar respira sem virar ruído)
	float n = fbm(wpos * 0.006 + vec2(TIME * 0.020, TIME * 0.011));
	col *= 1.0 + (n - 0.5) * wave_strength;
	// Glint solar itinerante
	float glint = smoothstep(0.82, 0.95, vnoise(wpos * 0.0065 + vec2(TIME * 0.05, -TIME * 0.03)));
	col += vec3(0.10, 0.13, 0.15) * glint * 0.35;
	// Grade náutica fantasma (identidade estratégica, bem discreta)
	vec2 g = abs(fract(wpos / grid_step) - 0.5);
	float dline = min(g.x, g.y) * grid_step;
	float grid = 1.0 - smoothstep(0.0, 1.3, dline);
	col += vec3(0.45, 0.60, 0.75) * grid * grid_alpha;
	COLOR = vec4(col, 1.0);
}
