// TERRENO v4 — SATÉLITE REAL (NASA Blue Marble, domínio público).
// A textura equiretangular casa 1:1 com a projeção do mapa:
//   u = wpos.x / 2000   ·   v = wpos.y / 1000
// Amazônia, Saara, Himalaia, gelo — a TERRA DE VERDADE. Por cima:
// grão sutil + a tinta política via self_modulate (jogador/inimigo/filtros).
// UM material compartilhado pelos ~3000 Polygon2D (batching preservado).
shader_type canvas_item;

uniform sampler2D earth_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float saturation : hint_range(0.5, 1.8) = 1.24;
uniform float brightness : hint_range(0.6, 2.0) = 1.38;
uniform float grain_amp : hint_range(0.0, 0.2) = 0.045;

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

void fragment() {
	vec2 uv = vec2(wpos.x / 2000.0, wpos.y / 1000.0);
	vec3 col = texture(earth_tex, clamp(uv, vec2(0.001), vec2(0.999))).rgb;
	// Realce leve: satélite cru fica lavado em tela — vida sem exagero
	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(grey), col, saturation) * brightness;
	// Grão fino (quebra o "liso" do JPEG em zoom alto)
	col *= 1.0 + (vnoise(wpos * 0.08) - 0.5) * grain_amp;
	// Tinta política por multiplicação (neutro ≈ branco → satélite puro)
	COLOR.rgb = col * COLOR.rgb;
}
