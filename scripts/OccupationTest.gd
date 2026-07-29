extends Node
## Teste do MUNDO VIVO Bloco C — conquista com consequência.
## Godot_console.exe --headless --path . res://scenes/OccupationTest.tscn

func _ready() -> void:
	await get_tree().process_frame
	var E = GameEngine
	E.settings["mundo_vivo"] = true   # a atualização Mundo Vivo precisa estar LIGADA p/ estes testes
	E.player_nation = E.nations["BR"]
	E.game_state = "PLAYING"
	print("\n=== TESTE DE OCUPAÇÃO & PÁRIA (Mundo Vivo C) ===")
	var tally := [0, 0]
	var _t = func(desc, ok):
		if ok: tally[0] += 1
		else: tally[1] += 1
		print(("  ✓ " if ok else "  ✗ ") + desc)

	# pega uma província da Argentina (core AR) e transfere pro BR (ocupação)
	var ar_provs: Array = E.provinces_of.get("AR", [])
	var pid: String = ""
	for pp in ar_provs:
		if not bool(E.provinces.get(pp, {}).get("is_capital", false)):
			pid = pp; break
	if pid != "":
		E.provinces[pid]["unrest"] = 0.0
		E.transfer_province(pid, "BR", "conquista")
		# 1. conquistar território de outro core semeia unrest
		_t.call("ocupação semeia unrest (>0)", float(E.provinces[pid].get("unrest", 0)) > 0.0)
		_t.call("owner != core após ocupação", E.province_owner(pid) != E.provinces[pid].get("core_iso"))

		# 2. _process_occupation faz o unrest CRESCER
		E.nations["BR"].estabilidade_politica = 40.0  # ocupante instável → unrest sobe mais
		var u0: float = float(E.provinces[pid].get("unrest", 0))
		var tes0: float = E.nations["BR"].tesouro
		E._process_occupation()
		var u1: float = float(E.provinces[pid].get("unrest", 0))
		_t.call("unrest cresce ao ocupar (%.0f→%.0f)" % [u0, u1], u1 > u0)
		_t.call("ocupação cobra guarnição (tesouro cai)", E.nations["BR"].tesouro <= tes0)

		# 3. ao cruzar 100, a província RACHA de volta ao core
		E.provinces[pid]["unrest"] = 99.0
		# garante que o BR tem >1 província (guard)
		var owner_before: String = E.province_owner(pid)
		var core: String = String(E.provinces[pid].get("core_iso"))
		E._process_occupation()
		var owner_after: String = E.province_owner(pid)
		_t.call("província REVOLTA e volta ao core (%s→%s)" % [owner_before, owner_after], owner_after == core)
	else:
		_t.call("achou província da AR pra ocupar", false)

	# 4. reconquistar SEU PRÓPRIO core NÃO gera unrest (irredentismo legítimo)
	var br_provs: Array = E.provinces_of.get("BR", [])
	if br_provs.size() > 0:
		var own_pid: String = ""
		for pp in br_provs:
			if String(E.provinces[pp].get("core_iso")) == "BR":
				own_pid = pp; break
		if own_pid != "":
			# simula: AR toma e BR reconquista
			E.transfer_province(own_pid, "AR", "conquista")
			E.provinces[own_pid]["unrest"] = 0.0
			E.transfer_province(own_pid, "BR", "conquista")  # BR reconquista seu core
			_t.call("reconquistar próprio core NÃO gera unrest", float(E.provinces[own_pid].get("unrest", 0)) == 0.0)

	# 5. reputação alta (agressor pária) ATIVA a coalizão mesmo sem ser hegemon
	E.current_turn = 120  # janela da coalizão (>=120, %6==0)
	E._containment_active = false
	E.player_reputation = 70.0  # pária
	# BR NÃO é hegemon (rebaixa pra garantir)
	E.nations["BR"].pib_bilhoes_usd = 800.0
	# precisa de >=3 grandes potências
	E._process_containment_coalition()
	_t.call("agressor pária (rep 70) ativa a coalizão sem ser hegemon", E._containment_active)

	print("\n║  RESULTADO: %d PASS / %d FAIL" % [tally[0], tally[1]])
	get_tree().quit(0 if tally[1] == 0 else 1)
