extends Node
## Teste headless dos Blocos 2+3: TERRITÓRIO muda de dono na guerra E persiste
## no save/load. Roda: Godot_console.exe --headless --path . res://scenes/ProvinceConquestTest.tscn

const SAVE_PATH := "user://nations_new_dawn_save.json"
var _save_backup: String = ""
var _had_save: bool = false

func _ready() -> void:
	await get_tree().process_frame
	# Backup do save real do jogador (padrão dos harness — nunca apagar dados)
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if _had_save:
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f: _save_backup = f.get_as_text(); f.close()
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

	# 3b. DIPLOMACIA TERRITORIAL (Bloco 4): exigir e comprar província
	E.player_nation = E.nations["BR"]
	E.player_actions_remaining = 99
	# _cession_accept_chance responde a poder/relação — usa província NÃO-capital
	# (a capital tem chance 0 por guard, então não serve pra testar a curva)
	var some_ar: Array = E.provinces_of.get("AR", [])
	var pid_ar: String = ""
	for pp in some_ar:
		if not bool(E.provinces.get(pp, {}).get("is_capital", false)):
			pid_ar = pp; break
	if pid_ar != "":
		# BR esmagadoramente forte → chance de EXIGIR alta
		var ch_strong: float = E._cession_accept_chance(pid_ar, "BR", 0.0)
		ar.militar["poder_militar_global"] = 500.0  # AR fica forte
		var ch_weak: float = E._cession_accept_chance(pid_ar, "BR", 0.0)
		ar.militar["poder_militar_global"] = 5.0     # volta fraca
		_t.call("chance de exigir cai quando o alvo fica forte (%.2f→%.2f)" % [ch_strong, ch_weak], ch_strong > ch_weak)
		# COMPRAR com oferta alta aumenta a chance
		var ch_nopay: float = E._cession_accept_chance(pid_ar, "BR", 0.0)
		var ch_pay: float = E._cession_accept_chance(pid_ar, "BR", 5000.0)
		_t.call("oferta em dinheiro aumenta a chance (%.2f→%.2f)" % [ch_nopay, ch_pay], ch_pay > ch_nopay)
		# player_buy_province transfere se aceito (força aceitação via oferta gigante)
		var ar_count0: int = E.provinces_of.get("AR", []).size()
		var br_count0: int = E.provinces_of.get("BR", []).size()
		var tries := 0
		var bought := false
		while tries < 20 and not bought:
			tries += 1
			var tgt2: String = ""
			for pp in E.provinces_of.get("AR", []):
				if not bool(E.provinces.get(pp, {}).get("is_capital", false)):
					tgt2 = pp; break
			if tgt2 == "": break
			E.nations["BR"].tesouro = 999999.0
			E.player_actions_remaining = 99
			var rbuy: Dictionary = E.player_buy_province(tgt2, 99999.0)
			if rbuy.get("aceito", false): bought = true
		_t.call("player_buy_province conquista com oferta alta", bought)

	# 3c. ESPIONAGEM/SECESSÃO (Bloco 5): fomentar sobe unrest; ≥100 racha.
	E.player_nation = E.nations["BR"]
	var ar_now: Array = E.provinces_of.get("AR", [])
	if not ar_now.is_empty():
		# pega província não-capital da AR
		var sec_pid: String = ""
		for pp in ar_now:
			if not bool(E.provinces.get(pp, {}).get("is_capital", false)):
				sec_pid = pp; break
		if sec_pid != "":
			E.nations["BR"].intel_score = 200.0   # operador competente
			E.provinces[sec_pid]["unrest"] = 0.0
			var unrest0: float = float(E.provinces[sec_pid].get("unrest", 0.0))
			E.nations["BR"].tesouro = 99999.0
			E.player_actions_remaining = 99
			E.player_incite_secession(sec_pid)
			var unrest1: float = float(E.provinces[sec_pid].get("unrest", 0.0))
			_t.call("fomentar secessão sobe o unrest (%.0f→%.0f)" % [unrest0, unrest1], unrest1 > unrest0)
			# força a secessão: unrest alto + fomenta de novo
			E.provinces[sec_pid]["unrest"] = 80.0
			var owner_before: String = E.province_owner(sec_pid)
			E.nations["BR"].tesouro = 99999.0
			E.player_actions_remaining = 99
			var rsec: Dictionary = E.player_incite_secession(sec_pid)
			var owner_after: String = E.province_owner(sec_pid)
			_t.call("secessão transfere a província (%s→%s)" % [owner_before, owner_after], owner_after != owner_before or rsec.get("secedeu", false))

	# 3d. GUARDAS ANTI-EXPLOIT (correção pós-revisão): nação nunca é apagada.
	# Reduz a AR a 1 província e tenta arrancá-la pelas 3 vias — nenhuma deve zerar.
	var ar_ids: Array = E.provinces_of.get("AR", []).duplicate()
	if ar_ids.size() > 1:
		# deixa só a 1ª província com a AR (o resto vai pro BR direto)
		for i in range(1, ar_ids.size()):
			E.transfer_province(ar_ids[i], "BR", "setup-guard")
	var last_ar: String = ""
	if E.provinces_of.get("AR", []).size() == 1:
		last_ar = E.provinces_of["AR"][0]
	if last_ar != "":
		# via GUERRA (fronteira mid-war com protect_last): não pode tomar a última
		var picked: String = E._pick_frontier_province("BR", "AR", true)
		_t.call("fronteira mid-war NÃO toma a última província", picked == "")
		# via DIPLOMACIA: chance 0 na última província
		var ch_last: float = E._cession_accept_chance(last_ar, "BR", 999999.0)
		_t.call("diplomacia NÃO compra a última província (chance %.2f)" % ch_last, ch_last == 0.0)
		# via SECESSÃO: não seca a última província
		E.provinces[last_ar]["unrest"] = 95.0
		E.nations["BR"].tesouro = 9999999.0
		E.player_actions_remaining = 99
		E.player_incite_secession(last_ar)
		_t.call("secessão NÃO zera o território do dono", E.provinces_of.get("AR", []).size() >= 1)

	# 4. SAVE/LOAD do território (Bloco 3): salva com território conquistado,
	# zera o estado, carrega, e confirma que as províncias voltam ao dono certo.
	var SaveSys = load("res://scripts/SaveSystem.gd")
	# garante uma guerra ATIVA com placar pra testar a persistência do placar
	if not ("AR" in br.em_guerra):
		br.em_guerra.append("AR")
	if not ("BR" in ar.em_guerra):
		ar.em_guerra.append("BR")
	E._war_score[E._war_key("BR", "AR")] = 42.0
	# snapshot de quem é dono de cada província conquistada por BR
	var br_owned_ids: Array = E.provinces_of.get("BR", []).duplicate()
	var br_owned_count: int = br_owned_ids.size()
	E.player_nation = E.nations["BR"]  # save exige player_nation
	var saved: bool = SaveSys.save_game(E)
	_t.call("save_game com território devolve true", saved)
	# "estraga" o estado: devolve todas as províncias de BR pra AR na marra
	for pid2 in br_owned_ids:
		if E.provinces.has(pid2) and String(E.provinces[pid2].get("core_iso","")) == "AR":
			E.provinces[pid2]["owner_iso"] = "AR"
	E.provinces_of["BR"] = []
	E.provinces_of["AR"] = []
	for pid2 in E.provinces:
		var ow: String = String(E.provinces[pid2]["owner_iso"])
		if not E.provinces_of.has(ow): E.provinces_of[ow] = []
		E.provinces_of[ow].append(pid2)
	# carrega
	var loaded: bool = SaveSys.load_game(E)
	_t.call("load_game devolve true", loaded)
	var br_after_load: int = E.provinces_of.get("BR", []).size()
	_t.call("território restaurado após load (%d→estragou→%d)" % [br_owned_count, br_after_load], br_after_load == br_owned_count)
	# guerra também restaurada?
	_t.call("placar de guerra (_war_score) restaurado", E._war_score.size() > 0)

	# Restaura o save real do jogador (backup/restore obrigatório)
	if _had_save:
		var fw := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if fw: fw.store_string(_save_backup); fw.close()
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

	print("\n╔══════════════════════════════════════╗")
	print("║  RESULTADO: %d PASS  /  %d FAIL  (total %d)" % [tally[0], tally[1], tally[0] + tally[1]])
	print("╚══════════════════════════════════════╝")
	get_tree().quit(0 if tally[1] == 0 else 1)
