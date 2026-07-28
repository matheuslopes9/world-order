extends Node
## Teste do MEGAFONE DO DRAMA MUNDIAL: roda turnos completos e confirma que
## eventos-mundo (coalizão, novo rival, golpe, guerra entre potências) enfileiram
## drama para a UI destacar. Roda: --headless res://scenes/WorldDramaTest.tscn

const SAVE_PATH := "user://world_order_save.json"
var _save_backup := ""
var _had_save := false

func _ready() -> void:
	await get_tree().process_frame
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if _had_save:
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f: _save_backup = f.get_as_text(); f.close()

	var E = GameEngine
	E.player_nation = E.nations["BR"]
	E.game_state = "PLAYING"
	print("\n=== TESTE DO MEGAFONE (drama mundial) ===")

	var tally := [0, 0]
	var _t = func(desc, ok):
		if ok: tally[0] += 1
		else: tally[1] += 1
		print(("  ✓ " if ok else "  ✗ ") + desc)

	# 1. _flag_drama enfileira corretamente
	E.pending_drama.clear()
	E._flag_drama("TESTE", "corpo", "US", "presidente", 3)
	_t.call("_flag_drama enfileira um item", E.pending_drama.size() == 1)
	_t.call("item tem headline/iso/severity", E.pending_drama[0].get("iso") == "US" and int(E.pending_drama[0].get("severity")) == 3)
	E.pending_drama.clear()

	# 2. coalizão de contenção gera drama de severidade máxima
	# força o jogador a hegemon: BR gigante + rivais menores; turno elegível (>=120, %6==0)
	E.nations["BR"].pib_bilhoes_usd = 500000.0
	E.nations["BR"].militar["poder_militar_global"] = 5000.0
	# derruba TODAS as outras potências pra garantir BR #1 com folga (≥1.6× o #2)
	for c in E.nations:
		if c != "BR":
			E.nations[c].pib_bilhoes_usd = minf(E.nations[c].pib_bilhoes_usd, 2000.0)
	E.current_turn = 120
	E.player_power_rank_history = [1,1,1,1,1]
	E._containment_active = false
	E.pending_drama.clear()
	E._process_containment_coalition()
	var got_coalition := false
	for d in E.pending_drama:
		if "CONTRA VOCÊ" in String(d.get("headline","")) or "COALIZÃO" in String(d.get("headline","")).to_upper():
			got_coalition = true
	_t.call("coalizão de contenção gera drama (mundo contra você)", got_coalition)

	# 3. golpe/troca de liderança relevante gera drama — roda vários turnos completos
	#    e conta quantos itens de drama surgem no total (IA + liderança + guerra)
	E.pending_drama.clear()
	var drama_total := 0
	# desliga o modal de decisão histórica pra não travar headless
	E.date_year = 2001
	for i in 60:
		E.pending_drama.clear()
		E.end_turn()
		drama_total += E.pending_drama.size()
	_t.call("turnos completos geram drama mundial (%d itens em 60 turnos)" % drama_total, drama_total > 0)

	if _had_save:
		var fw := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if fw: fw.store_string(_save_backup); fw.close()

	print("\n║  RESULTADO: %d PASS / %d FAIL" % [tally[0], tally[1]])
	get_tree().quit(0 if tally[1] == 0 else 1)
