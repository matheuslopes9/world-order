extends Node
## Teste da EVOLUÇÃO DO LOOP POR ERA: ações que destravam por década/tech.
## O loop de 2060 ≠ o de 2005. Godot_console.exe --headless res://scenes/EraActionsTest.tscn

func _ready() -> void:
	await get_tree().process_frame
	var E = GameEngine
	print("\n=== TESTE DE AÇÕES POR ERA (loop evolui) ===")
	var tally := [0, 0]
	var _t = func(desc, ok):
		if ok: tally[0] += 1
		else: tally[1] += 1
		print(("  ✓ " if ok else "  ✗ ") + desc)

	E.player_nation = E.nations["BR"]
	E.game_state = "PLAYING"
	var n = E.nations["BR"]

	# helper: a lista de ações de um painel contém um id?
	var _tem = func(panel, id):
		for a in E.get_panel_actions(panel):
			if a.get("id") == id: return true
		return false
	# helper: gera N techs fake (GDScript não tem list comprehension)
	var _techs = func(qtd):
		var arr: Array = []
		for i in qtd: arr.append("t%d" % i)
		return arr

	# 1. Em 2000, as ações de era FUTURA não aparecem
	E.date_year = 2000
	n.tecnologias_concluidas = []
	_t.call("2000: 'economia_digital' (unlock 2015) NÃO aparece", not _tem.call("economia", "economia_digital"))
	_t.call("2000: 'programa_espacial' (unlock 2040) NÃO aparece", not _tem.call("seguranca", "programa_espacial"))
	# mas as ações base SIM
	_t.call("2000: ação base 'estimulo_fiscal' aparece", _tem.call("economia", "estimulo_fiscal"))

	# 2. Em 2016, economia_digital (só ano 2015) já aparece
	E.date_year = 2016
	_t.call("2016: 'economia_digital' destravada (ano)", _tem.call("economia", "economia_digital"))

	# 3. Ação com gate de TECH: transicao_energetica (ano 2030 + 8 techs)
	E.date_year = 2035
	n.tecnologias_concluidas = ["t1", "t2"]  # só 2 techs < 8
	_t.call("2035 c/ 2 techs: 'transicao_energetica' AINDA bloqueada (falta tech)", not _tem.call("economia", "transicao_energetica"))
	n.tecnologias_concluidas = _techs.call(10)  # 10 techs >= 8
	_t.call("2035 c/ 10 techs: 'transicao_energetica' destravada", _tem.call("economia", "transicao_energetica"))

	# 4. Em 2060 o leque de ações é MAIOR que em 2000 (loop evoluiu)
	E.date_year = 2000
	n.tecnologias_concluidas = []
	var n2000: int = 0
	for p in ["economia","governo","saude","educacao","seguranca"]:
		n2000 += E.get_panel_actions(p).size()
	E.date_year = 2060
	n.tecnologias_concluidas = _techs.call(20)
	var n2060: int = 0
	for p in ["economia","governo","saude","educacao","seguranca"]:
		n2060 += E.get_panel_actions(p).size()
	_t.call("2060 tem MAIS ações que 2000 (%d > %d)" % [n2060, n2000], n2060 > n2000)

	# 5. player_panel_action REJEITA ação bloqueada (defesa dupla — bot não burla)
	E.date_year = 2000
	n.tecnologias_concluidas = []
	n.tesouro = 500.0
	var res: Dictionary = E.player_panel_action("programa_espacial")
	_t.call("executar ação bloqueada é rejeitado (%s)" % String(res.get("reason","")), not res.get("ok", false))

	# 6. a MESMA ação executa quando destravada e aplica efeito
	E.date_year = 2045
	n.tecnologias_concluidas = _techs.call(20)
	n.tesouro = 500.0
	var poder0: float = float(n.militar.get("poder_militar_global", 0))
	var res2: Dictionary = E.player_panel_action("programa_espacial")
	_t.call("ação destravada executa (ok)", res2.get("ok", false))
	_t.call("efeito aplicado (poder militar subiu)", float(n.militar.get("poder_militar_global", 0)) > poder0)

	print("\n║  RESULTADO: %d PASS / %d FAIL" % [tally[0], tally[1]])
	get_tree().quit(0 if tally[1] == 0 else 1)
