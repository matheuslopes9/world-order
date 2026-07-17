extends Control
## Spinner de arco clássico: trilho fantasma + arco CURTO girando.
## Comprimento constante — indica atividade, não progresso.

var _t: float = 0.0

func _process(delta: float) -> void:
	# Avanço limitado por frame: mesmo se um frame demorar (lote de países
	# montando), o arco não "teleporta" — giro sempre fluido ao olho.
	_t += minf(delta, 0.05) * 4.2
	queue_redraw()

func _draw() -> void:
	var c := size / 2.0
	var r: float = minf(size.x, size.y) * 0.40
	if r <= 2.0:
		return
	# Trilho completo bem fraco
	draw_arc(c, r, 0.0, TAU, 48, Color(0.90, 0.74, 0.36, 0.13), 4.0, true)
	# Arco curto girando (28% do círculo — leitura de "carregando")
	draw_arc(c, r, _t, _t + TAU * 0.28, 24, Color(0.95, 0.79, 0.40, 0.95), 4.0, true)
