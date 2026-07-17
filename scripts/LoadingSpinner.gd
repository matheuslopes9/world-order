extends Control
## Spinner de arco clássico: trilho fantasma + arco dourado girando.
## Desenhado via _draw (suave em qualquer tamanho — nada de glyph rotacionado).

var _t: float = 0.0

func _process(delta: float) -> void:
	_t += delta * 3.0
	queue_redraw()

func _draw() -> void:
	var c := size / 2.0
	var r: float = minf(size.x, size.y) * 0.40
	if r <= 2.0:
		return
	# Trilho completo bem fraco
	draw_arc(c, r, 0.0, TAU, 48, Color(0.90, 0.74, 0.36, 0.14), 4.0, true)
	# Arco principal girando (72% do círculo, cauda com fade)
	draw_arc(c, r, _t, _t + TAU * 0.70, 40, Color(0.90, 0.74, 0.36, 0.95), 4.0, true)
	draw_arc(c, r, _t + TAU * 0.55, _t + TAU * 0.70, 12, Color(1.0, 0.88, 0.55, 1.0), 4.0, true)
