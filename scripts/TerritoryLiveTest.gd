extends Node
## Teste: a conquista de território ACONTECE numa campanha real (bots em guerra)?
## Roda uma campanha 2000→2100 com o mundo ativo e conta transferências de província.
## Godot_console.exe --headless --path . res://scenes/TerritoryLiveTest.tscn

const SAVE_PATH := "user://nations_new_dawn_save.json"
var _save_backup := ""
var _had_save := false

func _ready() -> void:
	await get_tree().process_frame
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if _had_save:
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f: _save_backup = f.get_as_text(); f.close()

	var E = GameEngine
	# Brasil como jogador (14 províncias, vizinhos terrestres)
	E.player_nation = E.nations["BR"]
	E.game_state = "PLAYING"

	# conta transferências de província no MUNDO INTEIRO (bots incluídos)
	var transfers := [0]
	var by_motivo := {}
	E.province_conquered.connect(func(pid, oldo, newo):
		transfers[0] += 1)

	# snapshot inicial da distribuição de território
	var owners0 := {}
	for pid in E.provinces:
		var o: String = E.province_owner(pid)
		owners0[o] = int(owners0.get(o, 0)) + 1

	print("\n=== TESTE DE TERRITÓRIO EM CAMPANHA REAL ===")
	print("Rodando 100 anos (1200 turnos) com o mundo ativo...")
	var wars_seen := 0
	var t0 := Time.get_ticks_msec()
	for i in 1200:
		E.end_turn()
		# amostra: conta guerras ativas no mundo a cada 100 turnos
		if i % 100 == 0:
			var w := 0
			for c in E.nations:
				w += E.nations[c].em_guerra.size()
			wars_seen = max(wars_seen, w / 2)
	var ms := Time.get_ticks_msec() - t0

	# quantas nações mudaram de tamanho territorial?
	var changed := 0
	for o in owners0:
		var now: int = E.provinces_of.get(o, []).size() if E.provinces_of.has(o) else 0
		if now != int(owners0[o]):
			changed += 1

	print("Transferências de província no século: %d" % transfers[0])
	print("Pico de guerras simultâneas no mundo: ~%d" % wars_seen)
	print("Nações cujo território MUDOU de tamanho: %d" % changed)
	print("(processado em %d ms)" % ms)

	var tally := [0, 0]
	var _t = func(desc, ok):
		if ok: tally[0] += 1
		else: tally[1] += 1
		print(("  ✓ " if ok else "  ✗ ") + desc)
	_t.call("houve guerra no mundo (bots guerreiam)", wars_seen > 0)
	_t.call("território FOI conquistado em campanha real", transfers[0] > 0)
	_t.call("mapa mudou (nações trocaram território)", changed > 0)

	if _had_save:
		var fw := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if fw: fw.store_string(_save_backup); fw.close()

	print("\n║  RESULTADO: %d PASS / %d FAIL" % [tally[0], tally[1]])
	get_tree().quit(0 if tally[1] == 0 else 1)
