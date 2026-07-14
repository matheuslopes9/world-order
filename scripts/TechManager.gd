class_name TechManager
extends RefCounted
## Sistema de pesquisa tecnológica.
## Carrega tech.json, gerencia pesquisa em progresso, aplica efeitos quando concluída.

var engine
var tech_index: Dictionary = {}    # id → tech dict
var by_category: Dictionary = {}   # category → [techs]
var unlock_count: Dictionary = {}  # id → nº de techs que têm esta como pré-requisito

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
	# Conta quantas techs cada tech destrava (é pré-requisito de) — guia o bot
	# a pesquisar o que ABRE a árvore, não só o mais barato.
	for t in techs:
		for pre in t.get("pre_requisitos", []):
			unlock_count[pre] = int(unlock_count.get(pre, 0)) + 1

# ─────────────────────────────────────────────────────────────────
# CONSULTA
# ─────────────────────────────────────────────────────────────────

func get_categories() -> Array:
	return by_category.keys()

func get_techs_by_category(cat: String) -> Array:
	return by_category.get(cat, [])

func get_tech(id: String) -> Dictionary:
	return tech_index.get(id, {})

# Lista techs que a nação pode pesquisar AGORA (todos os checks de can_research OK).
# Ministério dono de uma tech. Usa o mapa por tech-id (trilhas equilibradas);
# cai no mapa por categoria se a tech não estiver listada (robustez).
func ministry_of(tech: Dictionary) -> String:
	var tid: String = String(tech.get("id", ""))
	if engine.MINISTRY_OF_TECH.has(tid):
		return engine.MINISTRY_OF_TECH[tid]
	var cat: String = String(tech.get("categoria", ""))
	return engine.MINISTRY_OF_CATEGORY.get(cat, "educacao")

# Techs disponíveis. Se `pasta` != "", filtra pelo ministério dono.
func get_available_techs(nation, pasta: String = "") -> Array:
	var out: Array = []
	for id in tech_index:
		if pasta != "" and ministry_of(tech_index[id]) != pasta:
			continue
		if can_research(nation, id).get("ok", false):
			out.append(tech_index[id])
	return out

# Verifica se uma nação pode pesquisar uma tech
func can_research(nation, tech_id: String) -> Dictionary:
	var tech: Dictionary = tech_index.get(tech_id, {})
	if tech.is_empty():
		return {"ok": false, "reason": "Tech não encontrada"}
	if tech_id in nation.tecnologias_concluidas:
		return {"ok": false, "reason": "Já concluída"}
	# A trilha DESTE ministério já está ocupada?
	var pasta: String = ministry_of(tech)
	if nation.pesquisa_por_ministerio.has(pasta):
		return {"ok": false, "reason": "%s já pesquisa outra tecnologia" % pasta}
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
	# GATE DE NÍVEL: tech tier 3+ exige o ministério dono no nível ≥ (tier-1)
	var tier: int = int(tech.get("tier", 1))
	if tier >= 3 and nation.has_method("ministry_level"):
		var nv_req: int = tier - 1
		if nation.ministry_level(pasta) < nv_req:
			return {"ok": false, "reason": "%s precisa nível %d (está %d)" % [pasta, nv_req, nation.ministry_level(pasta)]}
	# Custo (efetivo: economia de escala científica)
	var cost: float = get_effective_cost(nation, tech)
	if nation.tesouro < cost:
		return {"ok": false, "reason": "Custo: $%dB (você tem $%dB)" % [int(cost), int(nation.tesouro)]}
	return {"ok": true}

# Economia de escala científica: cada tech concluída barateia as próximas
# em 1.5% (cap -50%). Sem isto, o fim da árvore era inalcançável mesmo em
# 100 anos (máx observado: 35/57 em 1300 campanhas simuladas).
func get_effective_cost(nation, tech: Dictionary) -> float:
	var base: float = float(tech.get("custo", 0))
	var decay: float = clamp(1.0 - nation.tecnologias_concluidas.size() * 0.015, 0.5, 1.0)
	return round(base * decay)

# Inicia pesquisa na trilha do ministério dono da tech
func start_research(nation, tech_id: String) -> bool:
	var check: Dictionary = can_research(nation, tech_id)
	if not check.get("ok", false):
		return false
	var tech: Dictionary = tech_index[tech_id]
	var pasta: String = ministry_of(tech)
	nation.tesouro -= get_effective_cost(nation, tech)
	nation.pesquisa_por_ministerio[pasta] = {
		"id": tech_id,
		"progresso": 0.0,
		"tempo_total": float(tech.get("tempo_turnos", 5)),
	}
	# Mantém pesquisa_atual apontando p/ a trilha da Educação (retrocompat de UI legada)
	if pasta == "educacao":
		nation.pesquisa_atual = nation.pesquisa_por_ministerio[pasta]
	return true

# Cancela a pesquisa de uma trilha (sem reembolso). Sem pasta = todas.
func cancel_research(nation, pasta: String = "") -> void:
	if pasta == "":
		nation.pesquisa_por_ministerio.clear()
		nation.pesquisa_atual = null
	else:
		nation.pesquisa_por_ministerio.erase(pasta)
		if pasta == "educacao":
			nation.pesquisa_atual = null

# ─────────────────────────────────────────────────────────────────
# PROCESSAMENTO POR TURNO
# ─────────────────────────────────────────────────────────────────

func process_turn() -> void:
	for code in engine.nations:
		var n = engine.nations[code]
		_process_research(n)

func _process_research(nation) -> void:
	if nation.pesquisa_por_ministerio == null or nation.pesquisa_por_ministerio.is_empty():
		return
	# Conhecimento composto: cada tech concluída acelera as próximas em 2%
	# (cap +80%). Trilhas paralelas: só as N primeiras (research_slots) avançam,
	# então focar/espalhar vira decisão real (slots = 1 + nível Casa Civil).
	var momentum: float = clamp(1.0 + nation.tecnologias_concluidas.size() * 0.02, 1.0, 1.8)
	var slots: int = nation.research_slots() if nation.has_method("research_slots") else 6
	var concluidas: Array = []
	var ativa: int = 0
	for pasta in nation.pesquisa_por_ministerio.keys():
		ativa += 1
		if ativa > slots:
			break  # sem slot disponível — trilha espera este turno
		var pa: Dictionary = nation.pesquisa_por_ministerio[pasta]
		# Velocidade da trilha escala com o nível do ministério dono (nv1=1.0 … nv5≈1.6)
		var lvl_mult: float = nation.ministry_action_mult(pasta) if nation.has_method("ministry_action_mult") else 1.0
		pa["progresso"] = float(pa["progresso"]) + nation.velocidade_pesquisa * momentum * lvl_mult
		if pa["progresso"] >= float(pa["tempo_total"]):
			concluidas.append([pasta, pa["id"]])
	for c in concluidas:
		_complete_research(nation, c[1])
		nation.pesquisa_por_ministerio.erase(c[0])
		if c[0] == "educacao":
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
# Progresso de UMA trilha (por pasta) ou, sem pasta, a primeira ativa (retrocompat).
func get_research_progress(nation, pasta: String = "") -> Dictionary:
	var trilhas: Dictionary = nation.pesquisa_por_ministerio
	if trilhas == null or trilhas.is_empty():
		return {}
	var pa
	if pasta != "":
		if not trilhas.has(pasta):
			return {}
		pa = trilhas[pasta]
	else:
		pa = trilhas[trilhas.keys()[0]]
	var tech: Dictionary = tech_index.get(pa["id"], {})
	return {
		"id": pa["id"],
		"name": tech.get("nome", pa["id"]),
		"progress": float(pa["progresso"]),
		"total": float(pa["tempo_total"]),
		"pct": clamp(float(pa["progresso"]) / float(pa["tempo_total"]) * 100.0, 0, 100),
		"category": tech.get("categoria", ""),
	}

# Todas as trilhas ativas: pasta -> {progresso de UI}. Para o painel Gabinete.
func get_all_research_progress(nation) -> Dictionary:
	var out: Dictionary = {}
	if nation.pesquisa_por_ministerio == null:
		return out
	for pasta in nation.pesquisa_por_ministerio.keys():
		out[pasta] = get_research_progress(nation, pasta)
	return out
