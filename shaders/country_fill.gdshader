// TERRENO DOS PAÍSES — textura procedural de relevo sobre a cor política.
// Aplicado como UM ShaderMaterial compartilhado por todos os Polygon2D:
// a cor por-país continua vindo do self_modulate (COLOR), o shader só
// adiciona relevo/grão em cima. Coordenadas em WORLD SPACE para a textura
// ser contínua entre países e estável em qualquer zoom.
shader_type canvas_item;

uniform float relief_amp : hint_range(0.0, 0.4) = 0.16;   // força do relevo
uniform float grain_amp : hint_range(0.0, 0.2) = 0.05;    // grão fino
uniform float light_amp : hint_range(0.0, 0.3) = 0.10;    // luz N→S

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
	// Relevo macro (cadeias/planaltos ~120px mundo) + grão fino (~15px)
	float macro = fbm(wpos * 0.008);
	float fine = vnoise(wpos * 0.065);
	float shade = (macro - 0.5) * 2.0 * relief_amp + (fine - 0.5) * 2.0 * grain_amp;
	// Falsa iluminação: encostas viradas ao norte clareiam (derivada do relevo)
	float macro_n = fbm((wpos + vec2(0.0, -22.0)) * 0.008);
	float slope = (macro_n - macro) * 10.0;
	shade += clamp(slope, -1.0, 1.0) * light_amp;
	COLOR.rgb *= 1.0 + shade;
}
