// TERRENO REALISTA v3 — GEOGRAFIA REAL, não só bandas de ruído.
// Desertos onde os desertos EXISTEM (Saara, Arábia, Gobi, Atacama, Austrália…),
// florestas reais (Amazônia, Congo, Indonésia), cordilheiras reais com neve
// (Andes, Himalaia, Rochosas, Alpes), Groenlândia/Antártida geladas.
// Projeção: lon = wpos.x×0.18 − 180  ·  lat = 90 − wpos.y×0.18
// Máscaras elípticas suaves + ruído nas bordas = transições orgânicas.
// UM material compartilhado pelos ~3000 Polygon2D (batching preservado);
// a cor política tinge via self_modulate por multiplicação.
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

// Máscara elíptica suave em (lon, lat): 1 no centro, 0 fora — borda orgânica
float ell(vec2 ll, vec2 c, vec2 r) {
	vec2 d = (ll - c) / r;
	return 1.0 - smoothstep(0.72, 1.12, length(d));
}

void fragment() {
	float lon = wpos.x * 0.18 - 180.0;
	float lat = 90.0 - wpos.y * 0.18;
	float alat = abs(lat);
	// Distorção orgânica das bordas das regiões (±2.5°)
	vec2 jit = vec2(fbm(wpos * 0.012) - 0.5, fbm(wpos * 0.012 + vec2(533.7, 91.1)) - 0.5) * 5.0;
	vec2 ll = vec2(lon, lat) + jit;

	// ── DESERTOS REAIS (máscaras de seca) ──
	float dry = 0.0;
	dry += ell(ll, vec2(10.0, 22.0), vec2(28.0, 9.0));    // Saara
	dry += ell(ll, vec2(48.0, 24.0), vec2(12.0, 8.0));    // Arábia
	dry += ell(ll, vec2(62.0, 28.0), vec2(12.0, 7.0));    // Irã/Thar
	dry += ell(ll, vec2(103.0, 42.0), vec2(14.0, 6.0));   // Gobi
	dry += ell(ll, vec2(82.0, 39.0), vec2(8.0, 4.0));     // Taklamakan
	dry += ell(ll, vec2(132.0, -25.0), vec2(16.0, 9.0));  // Outback australiano
	dry += ell(ll, vec2(20.0, -25.0), vec2(9.0, 7.0));    // Kalahari/Namíbia
	dry += ell(ll, vec2(-69.5, -23.0), vec2(3.5, 8.0));   // Atacama
	dry += ell(ll, vec2(-112.0, 30.0), vec2(8.0, 6.0));   // Sonora/Mojave
	dry += ell(ll, vec2(-69.0, -44.0), vec2(5.0, 9.0));   // Estepe patagônica
	dry = clamp(dry, 0.0, 1.0);

	// ── FLORESTAS TROPICAIS REAIS (máscaras de umidade) ──
	float wet = 0.0;
	wet += ell(ll, vec2(-62.0, -4.0), vec2(15.0, 9.0));   // Amazônia
	wet += ell(ll, vec2(20.0, 0.0), vec2(12.0, 7.0));     // Congo
	wet += ell(ll, vec2(115.0, 2.0), vec2(22.0, 10.0));   // Indonésia/Sudeste Asiático
	wet = clamp(wet, 0.0, 1.0);

	// ── CORDILHEIRAS REAIS (boost de elevação) ──
	float range_m = 0.0;
	// Andes em 3 segmentos (a cordilheira CURVA — uma elipse reta vazava
	// neve para o oeste da Amazônia na fronteira Peru-Brasil)
	range_m += ell(ll, vec2(-70.0, -38.0), vec2(3.0, 16.0));  // Andes sul (Chile/Arg)
	range_m += ell(ll, vec2(-68.5, -17.0), vec2(3.5, 9.0));   // Andes central (Bolívia)
	range_m += ell(ll, vec2(-77.5, -2.0), vec2(2.6, 9.0));    // Andes norte (Peru/Equador/Col)
	range_m += ell(ll, vec2(-113.0, 45.0), vec2(7.0, 14.0));  // Rochosas
	range_m += ell(ll, vec2(85.0, 32.0), vec2(15.0, 6.0));    // Himalaia/Tibete
	range_m += ell(ll, vec2(10.0, 46.0), vec2(6.0, 2.5));     // Alpes
	range_m += ell(ll, vec2(45.0, 37.0), vec2(9.0, 4.0));     // Cáucaso/Zagros
	range_m += ell(ll, vec2(9.0, 63.0), vec2(4.0, 8.0));      // Escandinávia
	range_m = clamp(range_m, 0.0, 1.0);

	// ── GELO REAL ──
	float ice_m = ell(ll, vec2(-42.0, 74.0), vec2(15.0, 11.0));  // Groenlândia
	ice_m = max(ice_m, smoothstep(-58.0, -66.0, lat));           // Antártida
	ice_m = max(ice_m, smoothstep(72.0, 79.0, lat));             // Ártico extremo
	ice_m = clamp(ice_m, 0.0, 1.0);

	// ── CAMPOS BASE (ruído para variação natural dentro das regiões) ──
	float elev = clamp(fbm(wpos * 0.0065) * 0.80 + range_m * 0.55, 0.0, 1.0);
	float moist = clamp(fbm(wpos * 0.0042 + vec2(917.3, 411.7)) * 0.85 + wet * 0.55 - dry * 0.65, 0.0, 1.0);
	float band = alat + (moist - 0.5) * 14.0;

	// ── PALETA DE BIOMAS ──
	vec3 tropical = vec3(0.145, 0.335, 0.170);
	vec3 savanna  = vec3(0.470, 0.450, 0.260);
	vec3 desert   = vec3(0.780, 0.670, 0.450);
	vec3 temperate= vec3(0.270, 0.410, 0.235);
	vec3 boreal   = vec3(0.195, 0.300, 0.215);
	vec3 tundra   = vec3(0.520, 0.520, 0.470);
	vec3 ice      = vec3(0.880, 0.900, 0.925);

	// Bandas climáticas (base)
	vec3 col = mix(tropical, savanna, smoothstep(0.55, 0.32, moist));
	col = mix(col, temperate, smoothstep(26.0, 40.0, band));
	col = mix(col, boreal, smoothstep(46.0, 55.0, band));
	col = mix(col, tundra, smoothstep(56.0, 64.0, band));
	col = mix(col, ice, smoothstep(64.0, 70.0, band));

	// GEOGRAFIA REAL por cima das bandas:
	// Desertos reais (Gobi fica em lat 42 — fora do cinturão clássico)
	float local_dry = smoothstep(0.55, 0.30, fbm(wpos * 0.010));
	col = mix(col, desert, dry * (0.55 + 0.45 * local_dry) * (1.0 - ice_m));
	// Florestas tropicais reais
	col = mix(col, tropical, wet * smoothstep(28.0, 12.0, alat) * 0.85);
	// Gelo real (Groenlândia/Antártida/Ártico)
	col = mix(col, ice, ice_m);

	// ── MONTANHAS: rocha + NEVE nos picos ──
	float mtn = smoothstep(0.58, 0.74, elev);
	col = mix(col, vec3(0.400, 0.370, 0.330), mtn * 0.75 * (1.0 - ice_m));
	// Neve exige elevação real — floresta tropical úmida NUNCA neva
	// (matava a manchinha branca que o ruído criava no Acre/oeste amazônico)
	float snowcap = smoothstep(0.72, 0.84, elev + alat * 0.0035) * (1.0 - wet * 0.95);
	col = mix(col, vec3(0.905, 0.918, 0.938), snowcap);

	// ── RELEVO: sombreamento por encosta (luz do norte) + grão ──
	float elev_n = clamp(fbm((wpos + vec2(0.0, -18.0)) * 0.0065) * 0.80 + range_m * 0.55, 0.0, 1.0);
	float slope = (elev_n - elev) * 9.0;
	col *= 1.0 + clamp(slope, -1.0, 1.0) * light_amp;
	col *= 1.0 + (vnoise(wpos * 0.075) - 0.5) * relief_amp * 0.6;

	// Tinta política (neutro ≈ branco → terreno puro)
	COLOR.rgb = col * COLOR.rgb;
}
