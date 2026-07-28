extends Node
## Teste headless do Bloco 2: confirma que TERRITÓRIO muda de dono na guerra.
## Roda: Godot_console.exe --headless --path . res://scenes/ProvinceConquestTest.tscn

func _ready() -> void:
	await get_tree().process_frame
	var E = GameEngine
	print("\n=== TESTE DE CONQUISTA TERRITORIAL (Bloco 2) ===")
	print("Províncias carregadas: %d | nações com província: %d" % [E.provinces.size(), E.provinces_of.size()])

	var tally: Array = [0, 0]  # [pass, fail] — array p/ mutação dentro do lambda
	var _t = func(desc: String, ok: bool):
		if ok: tally[0] += 1
		else: tally[1] += 1
		print(("  ✓ " if ok else "  ✗ ") + desc)

	# 1. transfer_province move o dono e a fatia econômica
	var br_provs: Array = E.provinces_of.get("BR", [])
	var ar_provs0: int = E.provinces_of.get("AR", []).size()
	_t.call("BR tem províncias (%d)" % br_provs.size(), br_provs.size() > 1)
	if br_provs.size() > 0:
		var pid: String = br_provs[0]
		var ar = E.nations["AR"]
		var pop_ar0: int = ar.populacao
		var ok_transfer: bool = E.transfer_province(pid, "AR", "teste")
		_t.call("transfer_province devolve true", ok_transfer)
		_t.call("província agora é da AR", E.province_owner(pid) == "AR")
		_t.call("AR ganhou 1 província (%d→%d)" % [ar_provs0, E.provinces_of.get("AR", []).size()], E.provinces_of.get("AR", []).size() == ar_provs0 + 1)
		_t.call("BR perdeu a província", not (pid in E.provinces_of.get("BR", [])))
		_t.call("população migrou para AR (%d→%d)" % [pop_ar0, ar.populacao], ar.populacao >= pop_ar0)
		# devolve pra não sujar
		E.transfer_province(pid, "BR", "teste-reverter")

	# 2. _pick_frontier_province acha alvo válido
	var tgt: String = E._pick_frontier_province("AR", "BR")
	_t.call("_pick_frontier_province(AR,BR) acha alvo", tgt != "" and E.province_owner(tgt) == "BR")
	if tgt != "":
		_t.call("alvo prioriza não-capital", not bool(E.provinces.get(tgt, {}).get("is_capital", false)) or E.provinces_of.get("BR",[]).size() == 1)

	# 3. GUERRA que anda: força BR vs AR, dá vantagem esmagadora a BR, avança turnos
	var conquered: Array = []
	E.province_conquered.connect(func(pid2, oldo, newo): conquered.append([pid2, oldo, newo]))
	var br = E.nations["BR"]
	var ar = E.nations["AR"]
	# BR poderosa, AR fraca
	br.militar["poder_militar_global"] = 200.0
	br.pib_bilhoes_usd = 3000.0
	ar.militar["poder_militar_global"] = 5.0
	if not ("AR" in br.em_guerra):
		br.em_guerra.append("AR")
	if not ("BR" in ar.em_guerra):
		ar.em_guerra.append("BR")
	var br_before: int = E.provinces_of.get("BR", []).size()
	# roda a resolução de guerra várias vezes (simula turnos)
	for i in 40:
		E._process_war_resolution()
	var br_after: int = E.provinces_of.get("BR", []).size()
	_t.call("BR conquistou território de AR na guerra (%d→%d províncias)" % [br_before, br_after], br_after > br_before)
	_t.call("sinal province_conquered disparou (%d vezes)" % conquered.size(), conquered.size() > 0)

	print("\n╔══════════════════════════════════════╗")
	print("║  RESULTADO: %d PASS  /  %d FAIL  (total %d)" % [tally[0], tally[1], tally[0] + tally[1]])
	print("╚══════════════════════════════════════╝")
	get_tree().quit(0 if tally[1] == 0 else 1)
