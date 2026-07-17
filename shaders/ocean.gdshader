// OCEANO v5 — satélite NASA no modo realista; CHAPADO escuro no modo dados.
// Fora do mundo [0,2000]×[0,1000]: azul profundo LISO imediato (zero blur —
// nada de amostrar/esticar a borda da textura). O mundo é fechado por uma
// moldura desenhada pelo WorldMap.
shader_type canvas_item;

uniform sampler2D earth_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 border_deep : source_color = vec3(0.016, 0.030, 0.058);
uniform vec3 data_ocean : source_color = vec3(0.028, 0.045, 0.080);
uniform float data_mode : hint_range(0.0, 1.0) = 0.0;  // 1 = filtro de dados
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
	bool inside = uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
	vec3 col;
	if (!inside) {
		// FORA DO MUNDO: cor lisa, SEM textura — zero blur/smear
		col = border_deep;
	} else if (data_mode > 0.5) {
		// MODO DADOS (filtros): oceano chapado escuro — o mapa vira um
		// painel de dados limpo, países em escala de cor por cima
		col = data_ocean;
		// Grade discreta mantém a leitura cartográfica
		vec2 g = abs(fract(wpos / grid_step) - 0.5);
		float dline = min(g.x, g.y) * grid_step;
		float grid = 1.0 - smoothstep(0.0, 1.3, dline);
		col += vec3(0.30, 0.42, 0.58) * grid * (grid_alpha * 1.6);
	} else {
		// MODO REALISTA: mar REAL da NASA (batimetria) + vida animada
		col = texture(earth_tex, uv).rgb;
		float grey = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(vec3(grey), col, 1.15) * 1.30 + vec3(0.010, 0.022, 0.045);
		float n = fbm(wpos * 0.006 + vec2(TIME * 0.020, TIME * 0.011));
		col *= 1.0 + (n - 0.5) * wave_strength;
		float glint = smoothstep(0.82, 0.95, vnoise(wpos * 0.0065 + vec2(TIME * 0.05, -TIME * 0.03)));
		col += vec3(0.10, 0.13, 0.15) * glint * 0.35;
		vec2 g = abs(fract(wpos / grid_step) - 0.5);
		float dline = min(g.x, g.y) * grid_step;
		float grid = 1.0 - smoothstep(0.0, 1.3, dline);
		col += vec3(0.45, 0.60, 0.75) * grid * grid_alpha;
	}
	COLOR = vec4(col, 1.0);
}
