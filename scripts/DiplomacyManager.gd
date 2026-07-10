class_name DiplomacyManager
extends RefCounted
## Sistema de tratados internacionais.
## Tipos de tratado, propostas, aceitação automática pela IA, efeitos por turno, violações.

const TIPOS_TRATADO := {
	"alianca_militar": {
		"nome": "Aliança Militar",
		"descricao": "Defesa mútua: ataque a um é ataque a todos.",
		"duracao_min": 20, "duracao_max": 50,
		"efeitos": {"bonus_militar": 0.10, "rel_bonus": 30, "compartilha_intel": true},
		"penalidade_quebra": -50,
	},
	"pacto_nao_agressao": {
		"nome": "Pacto de Não-Agressão",
		"descricao": "Compromisso de não declarar guerra mútua.",
		"duracao_min": 15, "duracao_max": 30,
		"efeitos": {"rel_bonus": 15},
		"penalidade_quebra": -40,
	},
	"livre_comercio": {
		"nome": "Livre Comércio",
		"descricao": "Tarifas zero entre signatários — PIB cresce 0.3%/turno.",
		"duracao_min": 10, "duracao_max": 30,
		"efeitos": {"bonus_pib_pct": 0.003, "rel_bonus": 10},
		"penalidade_quebra": -20,
	},
	"parceria_tecnologica": {
		"nome": "Parceria Tecnológica",
		"descricao": "Pesquisa compartilhada acelera ciência.",
		"duracao_min": 15, "duracao_max": 30,
		"efeitos": {"velocidade_pesquisa_bonus": 0.10, "rel_bonus": 12},
		"penalidade_quebra": -25,
	},
	"desarmamento": {
		"nome": "Desarmamento Mútuo",
		"descricao": "Reduz orçamentos militares e armamento.",
		"duracao_min": 20, "duracao_max": 40,
		"efeitos": {"reducao_militar": 0.05, "rel_bonus": 8},
		"penalidade_quebra": -35,
	},
	"acordo_climatico": {
		"nome": "Acordo Climático",
		"descricao": "Investimento conjunto em sustentabilidade.",
		"duracao_min": 15, "duracao_max": 30,
		"efeitos": {"felicidade_bonus": 0.5, "rel_bonus": 10},
		"penalidade_quebra": -15,
	},
}

var engine  # GameEngine
var treaties: Array = []      # tratados ativos
var proposals: Array = []     # propostas pendentes (pra player ou IA)

func _init(eng) -> void:
	engine = eng

# ─────────────────────────────────────────────────────────────────
# PROPOR TRATADO
# ─────────────────────────────────────────────────────────────────

func propose(proposer_code: String, target_code: String, treaty_type: String) -> Dictionary:
	if not TIPOS_TRATADO.has(treaty_type):
		return {}
	if not engine.nations.has(proposer_code) or not engine.nations.has(target_code):
		return {}
	if proposer_code == target_code:
		return {}
	# Não propor se já existe tratado ativo do mesmo tipo
	for t in treaties:
		if t["type"] == treaty_type and proposer_code in t["signatories"] and target_code in t["signatories"]:
			return {}
	var prop := {
		"id": "p_%d_%d" % [Time.get_ticks_msec(), randi() % 1000],
		"proposer": proposer_code,
		"target": target_code,
		"type": treaty_type,
		"turn_proposed": engine.current_turn,
	}
	proposals.append(prop)
	return prop

# IA decide automaticamente sobre propostas que recebeu
func process_pending_proposals() -> void:
	var remaining := []
	for prop in proposals:
		var target_code: String = prop["target"]
		var is_player_target: bool = engine.player_nation != null and target_code == engine.player_nation.codigo_iso
		if is_player_target:
			# Mantém proposta pendente — UI do jogador decide
			remaining.append(prop)
			continue
		# IA decide
		var accepted := _ai_evaluate_proposal(prop)
		if accepted:
			_create_treaty(prop)
		# Se rejeitou ou aceitou, remove da fila
	proposals = remaining

func _ai_evaluate_proposal(prop: Dictionary) -> bool:
	var target = engine.nations.get(prop["target"])
	if target == null: return false
	var rel: float = float(target.relacoes.get(prop["proposer"], 0))
	var personality_aggro: float = engine._get_aggression(target) if engine.has_method("_get_aggression") else 0.5
	# Tratados defensivos: aceita mais facilmente quando relação ok ou quando é fraco
	var threshold: float = 30.0
	match prop["type"]:
		"alianca_militar":
			threshold = 40.0
		"pacto_nao_agressao":
			threshold = 0.0
		"livre_comercio", "parceria_tecnologica":
			threshold = 10.0
		"desarmamento":
			threshold = 20.0 + personality_aggro * 30.0
		"acordo_climatico":
			threshold = -10.0
	# Adiciona variação por personalidade
	threshold -= (1.0 - personality_aggro) * 20.0  # pacífica aceita mais
	return rel >= threshold

# Player aceita/rejeita proposta direcionada a ele
func player_accept(proposal_id: String) -> bool:
	for i in proposals.size():
		var p = proposals[i]
		if p["id"] == proposal_id:
			_create_treaty(p)
			proposals.remove_at(i)
			return true
	return false

func player_reject(proposal_id: String) -> bool:
	for i in proposals.size():
		var p = proposals[i]
		if p["id"] == proposal_id:
			# Pequena penalidade de relação
			var proposer = engine.nations.get(p["proposer"])
			var target = engine.nations.get(p["target"])
			if proposer and target:
				proposer.relacoes[p["target"]] = clamp(float(proposer.relacoes.get(p["target"], 0)) - 5, -100, 100)
				target.relacoes[p["proposer"]] = clamp(float(target.relacoes.get(p["proposer"], 0)) - 5, -100, 100)
			proposals.remove_at(i)
			return true
	return false

func _create_treaty(prop: Dictionary) -> void:
	var meta: Dictionary = TIPOS_TRATADO[prop["type"]]
	var duration: int = randi_range(int(meta["duracao_min"]), int(meta["duracao_max"]))
	var treaty := {
		"id": "t_%d_%d" % [Time.get_ticks_msec(), randi() % 1000],
		"type": prop["type"],
		"signatories": [prop["proposer"], prop["target"]],
		"created_turn": engine.current_turn,
		"expires_turn": engine.current_turn + duration,
	}
	treaties.append(treaty)
	# Bônus inicial de relação ao assinar
	var rel_bonus: int = int(meta["efeitos"].get("rel_bonus", 0))
	for code_a in treaty["signatories"]:
		for code_b in treaty["signatories"]:
			if code_a == code_b: continue
			var na = engine.nations.get(code_a)
			if na:
				na.relacoes[code_b] = clamp(float(na.relacoes.get(code_b, 0)) + rel_bonus, -100, 100)
	# Notifica
	var proposer_name: String = engine.nations[prop["proposer"]].nome
	var target_name: String = engine.nations[prop["target"]].nome
	var involves_player := false
	if engine.player_nation:
		involves_player = (prop["proposer"] == engine.player_nation.codigo_iso) or (prop["target"] == engine.player_nation.codigo_iso)
	engine.recent_events.append({
		"type": "tratado",
		"headline": "📜 %s assinado: %s ↔ %s" % [meta["nome"], proposer_name, target_name],
		"body": meta["descricao"],
		"involves_player": involves_player,
	})

# ─────────────────────────────────────────────────────────────────
# PROCESSAMENTO POR TURNO
# ─────────────────────────────────────────────────────────────────

func process_turn() -> void:
	# Aplica efeitos de tratados ativos
	for t in treaties:
		_apply_treaty_effects(t)
	# Remove tratados expirados
	var still_active: Array = []
	for t in treaties:
		if engine.current_turn < t["expires_turn"]:
			still_active.append(t)
		else:
			engine.recent_events.append({
				"type": "tratado_expirado",
				"headline": "⏰ Tratado de %s expirou: %s" % [TIPOS_TRATADO[t["type"]]["nome"], " ↔ ".join(t["signatories"])],
				"body": "Renove ou os benefícios cessam.",
				"involves_player": engine.player_nation != null and engine.player_nation.codigo_iso in t["signatories"],
			})
	treaties = still_active
	# Detecta violações: signatários em guerra
	_detect_violations()
	# IA propõe novos tratados ocasionalmente
	_ai_generate_proposals()
	# Processa propostas (IA decide as suas)
	process_pending_proposals()

func _apply_treaty_effects(t: Dictionary) -> void:
	var meta: Dictionary = TIPOS_TRATADO.get(t["type"], {})
	var efeitos: Dictionary = meta.get("efeitos", {})
	for code in t["signatories"]:
		var n = engine.nations.get(code)
		if n == null: continue
		if efeitos.has("bonus_pib_pct"):
			n.apply_pib_multiplier(1.0 + float(efeitos["bonus_pib_pct"]))
		if efeitos.has("velocidade_pesquisa_bonus"):
			n.velocidade_pesquisa = min(3.0, n.velocidade_pesquisa + float(efeitos["velocidade_pesquisa_bonus"]) / 100.0)
		if efeitos.has("felicidade_bonus"):
			n.felicidade = min(100.0, n.felicidade + float(efeitos["felicidade_bonus"]))
		if efeitos.has("compartilha_intel"):
			n.intel_score += 0.3

func _detect_violations() -> void:
	var to_remove: Array = []
	for i in treaties.size():
		var t = treaties[i]
		if t["type"] != "alianca_militar" and t["type"] != "pacto_nao_agressao":
			continue
		# Se signatários estão em guerra → tratado violado
		var sigs: Array = t["signatories"]
		var violated := false
		for a in sigs:
			var na = engine.nations.get(a)
			if na == null: continue
			for b in sigs:
				if a == b: continue
				if b in na.em_guerra:
					violated = true
					break
			if violated: break
		if violated:
			var meta = TIPOS_TRATADO.get(t["type"], {})
			var penalty: int = int(meta.get("penalidade_quebra", -30))
			for a in sigs:
				var na = engine.nations.get(a)
				if na:
					for b in sigs:
						if a == b: continue
						na.relacoes[b] = clamp(float(na.relacoes.get(b, 0)) + penalty, -100, 100)
			to_remove.append(i)
			engine.recent_events.append({
				"type": "tratado_violado",
				"headline": "⚠ %s VIOLADO: %s" % [meta.get("nome", "Tratado"), " ↔ ".join(sigs)],
				"body": "Penalidade de relação aplicada.",
				"involves_player": engine.player_nation != null and engine.player_nation.codigo_iso in sigs,
			})
	to_remove.reverse()
	for i in to_remove:
		treaties.remove_at(i)

func _ai_generate_proposals() -> void:
	# 5-10% das nações (NPC) tentam propor tratado a alguém por turno
	var codes: Array = engine.nations.keys()
	codes.shuffle()
	var max_proposals: int = 4
	var made: int = 0
	for code in codes:
		if engine.player_nation and code == engine.player_nation.codigo_iso: continue
		if randf() > 0.15: continue
		var proposer = engine.nations[code]
		# Escolhe um país com boa relação como alvo
		var best_target := ""
		var best_rel: float = -200.0
		for c in proposer.relacoes:
			var r: float = float(proposer.relacoes[c])
			if r > best_rel and engine.nations.has(c) and c != code:
				best_rel = r
				best_target = c
		# Fallback: vizinho regional aleatório
		if best_target == "" or best_rel < 0:
			for c in engine.nations:
				if c == code: continue
				if engine.nations[c].continente == proposer.continente:
					best_target = c
					best_rel = float(proposer.relacoes.get(c, 0))
					break
		if best_target == "": continue
		# Escolhe tipo de tratado
		var types := ["livre_comercio", "pacto_nao_agressao", "parceria_tecnologica", "acordo_climatico"]
		if best_rel >= 30: types.append("alianca_militar")
		var picked_type: String = types[randi() % types.size()]
		propose(code, best_target, picked_type)
		made += 1
		if made >= max_proposals: break

# Helpers para UI
func get_player_treaties() -> Array:
	var out: Array = []
	if engine.player_nation == null: return out
	var p_code: String = engine.player_nation.codigo_iso
	for t in treaties:
		if p_code in t["signatories"]:
			out.append(t)
	return out

func get_player_pending_proposals() -> Array:
	var out: Array = []
	if engine.player_nation == null: return out
	var p_code: String = engine.player_nation.codigo_iso
	for p in proposals:
		if p["target"] == p_code:
			out.append(p)
	return out
