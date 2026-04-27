class_name TechManager
extends RefCounted
## Sistema de pesquisa tecnológica.
## Carrega tech.json, gerencia pesquisa em progresso, aplica efeitos quando concluída.

var engine
var tech_index: Dictionary = {}    # id → tech dict
var by_category: Dictionary = {}   # category → [techs]

func _init(eng) -> void:
	engine = eng
	_index_tech_data()

func _index_tech_data() -> void:
	if engine.tech_data == null: return
	var techs: Array = engine.tech_data.get("tecnologias", [])
	for t in techs:
		var id: String = t.get("id", "")
		if id == "": continue
		tech_index[id] = t
		var cat: String = t.get("categoria", "?")
		if not by_category.has(cat):
			by_category[cat] = []
		by_category[cat].append(t)

# ─────────────────────────────────────────────────────────────────
# CONSULTA
# ─────────────────────────────────────────────────────────────────

func get_categories() -> Array:
	return by_category.keys()

func get_techs_by_category(cat: String) -> Array:
	return by_category.get(cat, [])

func get_tech(id: String) -> Dictionary:
	return tech_index.get(id, {})

# Verifica se uma nação pode pesquisar uma tech
func can_research(nation, tech_id: String) -> Dictionary:
	var tech: Dictionary = tech_index.get(tech_id, {})
	if tech.is_empty():
		return {"ok": false, "reason": "Tech não encontrada"}
	if tech_id in nation.tecnologias_concluidas:
		return {"ok": false, "reason": "Já concluída"}
	if nation.pesquisa_atual != null:
		return {"ok": false, "reason": "Já há pesquisa em andamento"}
	# Pré-requisitos
	var prereqs: Array = tech.get("pre_requisitos", [])
	for p in prereqs:
		if not (p in nation.tecnologias_concluidas):
			var p_name: String = tech_index[p].get("nome", p) if tech_index.has(p) else p
			return {"ok": false, "reason": "Pré-requisito faltando: " + p_name}
	# Requisitos numéricos
	var pib_req: float = float(tech.get("requisito_pib_minimo", 0))
	if nation.pib_bilhoes_usd < pib_req:
		return {"ok": false, "reason": "PIB mínimo: $%dB" % int(pib_req)}
	var stab_req: float = float(tech.get("requisito_estabilidade", 0))
	if nation.estabilidade_politica < stab_req:
		return {"ok": false, "reason": "Estabilidade mínima: %d%%" % int(stab_req)}
	# Custo
	var cost: float = float(tech.get("custo", 0))
	if nation.tesouro < cost:
		return {"ok": false, "reason": "Custo: $%dB (você tem $%dB)" % [int(cost), int(nation.tesouro)]}
	return {"ok": true}

# Inicia pesquisa
func start_research(nation, tech_id: String) -> bool:
	var check: Dictionary = can_research(nation, tech_id)
	if not check.get("ok", false):
		return false
	var tech: Dictionary = tech_index[tech_id]
	nation.tesouro -= float(tech.get("custo", 0))
	nation.pesquisa_atual = {
		"id": tech_id,
		"progresso": 0.0,
		"tempo_total": float(tech.get("tempo_turnos", 5)),
	}
	return true

# Cancela pesquisa em andamento (sem reembolso)
func cancel_research(nation) -> void:
	nation.pesquisa_atual = null

# ─────────────────────────────────────────────────────────────────
# PROCESSAMENTO POR TURNO
# ─────────────────────────────────────────────────────────────────

func process_turn() -> void:
	for code in engine.nations:
		var n = engine.nations[code]
		_process_research(n)

func _process_research(nation) -> void:
	if nation.pesquisa_atual == null:
		return
	var pa: Dictionary = nation.pesquisa_atual
	pa["progresso"] = float(pa["progresso"]) + nation.velocidade_pesquisa
	if pa["progresso"] >= float(pa["tempo_total"]):
		# Conclui!
		_complete_research(nation, pa["id"])
		nation.pesquisa_atual = null

func _complete_research(nation, tech_id: String) -> void:
	if tech_id in nation.tecnologias_concluidas: return
	nation.tecnologias_concluidas.append(tech_id)
	var tech: Dictionary = tech_index.get(tech_id, {})
	var efeitos: Dictionary = tech.get("efeitos", {})
	# Aplica efeitos
	if efeitos.has("bonus_pib_pct"):
		nation.apply_pib_multiplier(1.0 + float(efeitos["bonus_pib_pct"]) / 100.0)
	if efeitos.has("estabilidade_fator"):
		nation.estabilidade_politica = clamp(nation.estabilidade_politica + float(efeitos["estabilidade_fator"]), 0, 100)
	if efeitos.has("populacao_fator"):
		nation.populacao = int(nation.populacao * float(efeitos["populacao_fator"]))
	if efeitos.has("bonus_intel"):
		nation.intel_score += float(efeitos["bonus_intel"])
	if efeitos.has("bonus_ciencia"):
		nation.velocidade_pesquisa = min(3.0, nation.velocidade_pesquisa + float(efeitos["bonus_ciencia"]))
	if efeitos.has("poder_militar_bonus"):
		var mil: Dictionary = nation.militar
		mil["poder_militar_global"] = float(mil.get("poder_militar_global", 0)) + float(efeitos["poder_militar_bonus"])
	# Notifica se for o jogador
	if engine.player_nation and nation.codigo_iso == engine.player_nation.codigo_iso:
		engine.recent_events.append({
			"type": "tech_concluida",
			"headline": "🔬 Pesquisa concluída: " + tech.get("nome", tech_id),
			"body": "Categoria: %s • Tier %d" % [tech.get("categoria", ""), int(tech.get("tier", 1))],
			"involves_player": true,
		})

# Helpers de UI
func get_research_progress(nation) -> Dictionary:
	if nation.pesquisa_atual == null:
		return {}
	var pa: Dictionary = nation.pesquisa_atual
	var tech: Dictionary = tech_index.get(pa["id"], {})
	return {
		"id": pa["id"],
		"name": tech.get("nome", pa["id"]),
		"progress": float(pa["progresso"]),
		"total": float(pa["tempo_total"]),
		"pct": clamp(float(pa["progresso"]) / float(pa["tempo_total"]) * 100.0, 0, 100),
		"category": tech.get("categoria", ""),
	}
