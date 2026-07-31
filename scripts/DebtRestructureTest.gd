extends Node
## Teste da REESTRUTURAÇÃO SOBERANA (calote realista) — a espiral de dívida tem freio.
## Godot_console.exe --headless --path . res://scenes/DebtRestructureTest.tscn

func _ready() -> void:
	await get_tree().process_frame
	var E = GameEngine
	print("\n=== TESTE DE REESTRUTURAÇÃO SOBERANA (freio da dívida) ===")
	var tally := [0, 0]
	var _t = func(desc, ok):
		if ok: tally[0] += 1
		else: tally[1] += 1
		print(("  ✓ " if ok else "  ✗ ") + desc)

	var n = E.nations["AR"]

	# 1. dívida insustentável (>10× PIB) dispara o calote (haircut de 60%)
	n.pib_bilhoes_usd = 100.0
	n.divida_publica = 2000.0          # 20× o PIB — insustentável
	n.tesouro = 50.0
	n._reestruturacao_cooldown = 0
	var defaults0: int = n.defaults_no_historico
	var estab0: float = n.estabilidade_politica
	var divida0: float = n.divida_publica
	n.process_turn_finances()
	_t.call("calote CORTA a dívida p/ ~1,5× PIB (%.0f→%.0f)" % [divida0, n.divida_publica], n.divida_publica <= n.pib_bilhoes_usd * 2.0)
	_t.call("calote registra no histórico (rating cai)", n.defaults_no_historico == defaults0 + 1)
	_t.call("calote custa estabilidade", n.estabilidade_politica < estab0)
	_t.call("cooldown ativado após o calote", n._reestruturacao_cooldown > 0)

	# 2. durante o cooldown o CALOTE (haircut p/ 1,5×) não dispara — mas o teto
	#    duro (8× PIB) ainda vale. Dívida a 6× PIB não deve ser cortada p/ 1,5×.
	n.pib_bilhoes_usd = 100.0
	n.divida_publica = 600.0           # 6× PIB: acima do gatilho de calote (5×), abaixo do teto (8×)
	n._reestruturacao_cooldown = 10    # em cooldown
	var defaults_pre: int = n.defaults_no_historico
	n.tesouro = 50.0
	n.process_turn_finances()
	_t.call("cooldown BLOQUEIA novo calote (sem haircut p/ 1,5×)", n.defaults_no_historico == defaults_pre and n.divida_publica > n.pib_bilhoes_usd * 2.0)

	# 3. dívida saudável NÃO dispara calote
	var m = E.nations["CL"]
	m.pib_bilhoes_usd = 500.0
	m.divida_publica = 300.0           # 0,6× PIB — saudável
	m.tesouro = 100.0
	m._reestruturacao_cooldown = 0
	var d0: int = m.defaults_no_historico
	m.process_turn_finances()
	_t.call("dívida saudável NÃO gera calote", m.defaults_no_historico == d0)

	# 4. O FREIO DE VERDADE: rodando muitos turnos em espiral, a dívida NÃO
	#    explode ao infinito — fica limitada por calotes periódicos.
	var s = E.nations["PE"]
	s.pib_bilhoes_usd = 100.0
	s.divida_publica = 500.0
	s.tesouro = 0.0
	s._reestruturacao_cooldown = 0
	# força déficit permanente: gasto militar altíssimo, receita mínima
	s.militar["orcamento_militar_bilhoes"] = 2000.0
	var pico: float = 0.0
	for i in 400:
		s.process_turn_finances()
		pico = max(pico, s.divida_publica)
	# sem o freio, a 18% a.a. por 400 turnos a dívida passaria de milhões de % do PIB.
	# com o freio, o pico fica num múltiplo FINITO e razoável do PIB.
	var pico_ratio: float = pico / max(1.0, s.pib_bilhoes_usd)
	print("    pico de dívida em 400 turnos: %.0f%% do PIB" % (pico_ratio * 100.0))
	_t.call("espiral CONTIDA (pico < 20× PIB, não milhões)", pico_ratio < 20.0)

	print("\n║  RESULTADO: %d PASS / %d FAIL" % [tally[0], tally[1]])
	get_tree().quit(0 if tally[1] == 0 else 1)
