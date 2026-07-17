// TERRENO REALISTA DOS PAÍSES — biomas procedurais por latitude + umidade.
// Projeção do mapa: y = (90 − lat) × (1000/180)  →  lat = 90 − wpos.y × 0.18
// Gelo polar, tundra, taiga, temperado, deserto, savana, tropical, montanhas
// com neve — tudo em UM material compartilhado (batching preservado).
// A cor política (jogador/inimigo/filtros) chega via self_modulate e TINTA
// o terreno por multiplicação (neutros são quase-brancos → terreno puro).
shader_type canvas_item;

uniform float relief_amp : hint_range(0.0, 0.4) = 0.14;
uniform float light_amp : hint_range(0.0, 0.3) = 0.12;

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
		p *= 2.11;
		a *= 0.52;
	}
	return v;
}

void fragment() {
	// Latitude real deste fragmento (90=polo norte, 0=equador, -90=sul)
	float lat = 90.0 - wpos.y * 0.18;
	float alat = abs(lat);
	// Campos procedurais: elevação (montanhas) e umidade (desertos/florestas)
	float elev = fbm(wpos * 0.0065);
	float moist = fbm(wpos * 0.0042 + vec2(917.3, 411.7));
	// Bandas de bioma distorcidas pela umidade (fronteiras orgânicas, não retas)
	float band = alat + (moist - 0.5) * 16.0;

	// ── PALETA DE BIOMAS (do equador aos polos) ──
	vec3 tropical = vec3(0.145, 0.335, 0.170);   // floresta equatorial
	vec3 savanna  = vec3(0.470, 0.450, 0.260);   // savana/cerrado
	vec3 desert   = vec3(0.760, 0.650, 0.435);   // areia
	vec3 temperate= vec3(0.270, 0.410, 0.235);   // temperado verde
	vec3 boreal   = vec3(0.195, 0.300, 0.215);   // taiga
	vec3 tundra   = vec3(0.520, 0.520, 0.470);   // tundra
	vec3 ice      = vec3(0.870, 0.895, 0.920);   // calota polar

	// Trópicos (0-15°): floresta tropical; seca → savana
	vec3 col = mix(tropical, savanna, smoothstep(0.55, 0.30, moist));
	// Cinturão desértico (15-32°): umidade baixa vira deserto de verdade
	float desert_zone = smoothstep(13.0, 20.0, band) * (1.0 - smoothstep(30.0, 38.0, band));
	float dryness = smoothstep(0.52, 0.34, moist);
	col = mix(col, desert, desert_zone * dryness);
	// Temperado (28-48°)
	col = mix(col, temperate, smoothstep(28.0, 40.0, band));
	// Taiga (48-58°)
	col = mix(col, boreal, smoothstep(46.0, 55.0, band));
	// Tundra (58-66°)
	col = mix(col, tundra, smoothstep(56.0, 64.0, band));
	// Gelo polar (66°+) — Groenlândia/Antártida brancas
	col = mix(col, ice, smoothstep(64.0, 70.0, band));

	// ── MONTANHAS: elevação alta escurece/acinzenta; muito alta = neve ──
	float mtn = smoothstep(0.60, 0.76, elev);
	col = mix(col, vec3(0.400, 0.370, 0.330), mtn * 0.75);
	float snowcap = smoothstep(0.76, 0.86, elev + alat * 0.0035);
	col = mix(col, vec3(0.900, 0.915, 0.935), snowcap);

	// ── RELEVO: sombreamento por encosta (luz vinda do norte) ──
	float elev_n = fbm((wpos + vec2(0.0, -18.0)) * 0.0065);
	float slope = (elev_n - elev) * 9.0;
	col *= 1.0 + clamp(slope, -1.0, 1.0) * light_amp;
	// Grão fino de terreno
	col *= 1.0 + (vnoise(wpos * 0.075) - 0.5) * relief_amp * 0.6;

	// Tinta política por cima (neutro ≈ branco → terreno puro;
	// jogador/inimigo/filtros tingem mantendo a textura visível)
	COLOR.rgb = col * COLOR.rgb;
}
