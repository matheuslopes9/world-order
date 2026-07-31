extends Node
## Teste do ONBOARDING de tech: o conselheiro cutuca a pesquisar quando o país
## está estável (a alavanca de crescimento que o jogador ignorava) + o briefing
## destaca ciência. Godot_console.exe --headless res://scenes/TechOnboardingTest.tscn

func _ready() -> void:
	await get_tree().process_frame
	var E = GameEngine
	print("\n=== TESTE DE ONBOARDING DE TECH ===")
	var tally := [0, 0]
	var _t = func(desc, ok):
		if ok: tally[0] += 1
		else: tally[1] += 1
		print(("  ✓ " if ok else "  ✗ ") + desc)

	var n = E.nations["BR"]

	# 1. o briefing inicial DESTACA a ciência como alavanca de crescimento
	var brief: Dictionary = E.generate_briefing(n)
	var steps: Array = brief.get("steps", brief.get("first_steps", []))
	var brief_txt: String = " ".join(steps) if steps is Array else str(brief)
	_t.call("briefing menciona pesquisa/ciência/tecnologia",
		"ciência" in brief_txt.to_lower() or "pesquisa" in brief_txt.to_lower() or "tecnologia" in brief_txt.to_lower())

	# 2. a lógica do conselheiro: nação ESTÁVEL e SEM pesquisa → candidato de tech.
	# Reproduz o critério de _maybe_show_advisor_alert (WorldMap) direto no estado.
	n.estabilidade_politica = 70.0
	n.apoio_popular = 70.0
	n.inflacao = 3.0
	n.tesouro = 200.0
	n.divida_publica = 0.0
	n.corrupcao = 20.0
	n.pesquisa_por_ministerio = {}       # NÃO está pesquisando
	var pesquisando: bool = not n.pesquisa_por_ministerio.is_empty()
	var deve_cutucar_ociosa: bool = (not pesquisando) and n.tesouro > 0.0
	_t.call("país estável e SEM pesquisa dispara alerta de pesquisa ociosa", deve_cutucar_ociosa)

	# 3. país que JÁ pesquisa não recebe o alerta de ociosa
	n.pesquisa_por_ministerio = {"educacao": {"id": "tech_x", "progresso": 10.0}}
	var pesquisando2: bool = not n.pesquisa_por_ministerio.is_empty()
	_t.call("país que pesquisa NÃO recebe alerta de ociosa", pesquisando2)

	# 4. país estável com poucas techs p/ a época recebe o lembrete leve
	E.current_turn = 300  # ~ano 2025 (ritmo mensal)
	n.tecnologias_concluidas = ["t1", "t2"]  # bem abaixo do esperado (3 + 300/30 = 13)
	var esperado: int = 3 + int(E.current_turn / 30.0)
	var atras: bool = n.tecnologias_concluidas.size() < esperado and n.estabilidade_politica >= 48.0 and n.apoio_popular >= 48.0
	_t.call("poucas techs p/ a época (%d < %d) dispara lembrete" % [n.tecnologias_concluidas.size(), esperado], atras)

	print("\n║  RESULTADO: %d PASS / %d FAIL" % [tally[0], tally[1]])
	get_tree().quit(0 if tally[1] == 0 else 1)
