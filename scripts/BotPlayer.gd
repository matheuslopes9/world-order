class_name BotPlayer
extends RefCounted
## Bot de IA que joga como o jogador humano em tempo real.
## Usa árvore de decisão ponderada: avalia todas as ações possíveis,
## pontua cada uma por impacto esperado nos indicadores vitais,
## escolhe a melhor e a executa. Repete até esgotar as ações do turno,
## depois avança o turno automaticamente.
##
## As ações de painel passam por GameEngine.player_panel_action — a MESMA
## API usada pelos botões da UI (catálogo único, custos/efeitos idênticos).
##
## O raciocínio é exposto em tempo real via signal "thinking" pra UI
## mostrar num painel "O que o bot está pensando".

# ── Signals ──────────────────────────────────────────────────────
signal thinking(message: String)        # linha de raciocínio (mostra na UI)
signal action_taken(action: Dictionary) # ação escolhida { type, target, reason, score }
signal turn_starting(turn: int)
signal game_over_detected()

# ── Configuração ─────────────────────────────────────────────────
var speed_delay: float = 2.0   # segundos entre ações (jogador vê acontecer)
var turn_delay: float  = 1.5   # segundos antes de avançar turno
var enabled: bool      = false
var verbose: bool      = true  # false = sem prints no console (usado pelo BalanceSim)

# ── Estado ───────────────────────────────────────────────────────
var _engine              # referência ao GameEngine (autoload)
var _tree: SceneTree     # pra criar timers
var _running: bool = false

# ── Personalidade do bot (pesos pra scoring de ação) ─────────────
# Muda o estilo de jogo: "balanced", "economic", "military", "diplomat"
var personality: String = "balanced"

const PERSONALITIES := {
	"balanced":  {"economia": 1.0, "military": 0.8, "diplomacy": 0.8, "tech": 0.9, "social": 0.9},
	# economic rebalanceada (1000 jogos: 48% de vitória vs 83-90% das outras —
	# o peso 1.6 em economia sufocava a pesquisa, e tech domina o longo prazo)
	"economic":  {"economia": 1.4, "military": 0.4, "diplomacy": 0.7, "tech": 1.2, "social": 0.8},
	"military":  {"economia": 0.7, "military": 1.8, "diplomacy": 0.5, "tech": 0.7, "social": 0.6},
	"diplomat":  {"economia": 0.8, "military": 0.3, "diplomacy": 1.8, "tech": 0.8, "social": 1.2},
}

func _init(engine, tree: SceneTree, persona: String = "balanced") -> void:
	_engine = engine
	_tree = tree
	personality = persona

# ── Entrada pública ───────────────────────────────────────────────
func start() -> void:
	if _running: return
	enabled = true
	_running = true
	_run_loop()

func stop() -> void:
	enabled = false
	_running = false

# ── Loop principal ────────────────────────────────────────────────
func _run_loop() -> void:
	while enabled and _engine != null and _engine.game_state == "PLAYING":
		emit_signal("turn_starting", _engine.current_turn)
		_think("=== Turno %d — Analisando situação... ===" % _engine.current_turn)
		# Ajusta a verba de P&D dos ministérios conforme a persona (não custa ação)
		_manage_ministry_budgets()
		await _delay(turn_delay * 0.5)

		# Executa ações até esgotar o orçamento do turno
		var actions_this_turn: int = 0
		var failed_streak: int = 0
		while _engine.player_actions_remaining > 0 and enabled:
			var best := _choose_best_action()
			if best.is_empty():
				_think("Sem ações rentáveis disponíveis. Poupando ações.")
				break
			await _delay(speed_delay)
			if _execute_action(best):
				actions_this_turn += 1
				failed_streak = 0
			else:
				# Falha sem consumir ação → evita loop infinito na mesma escolha
				failed_streak += 1
				if failed_streak >= 2:
					_think("Ações falhando em sequência — encerrando turno.")
					break
			await _delay(0.3)

		# Aceita propostas diplomáticas pendentes (grátis)
		_handle_pending_proposals()
		# Resgate do FMI: bot aceita (sobreviver > orgulho)
		if not _engine.bailout_pending.is_empty():
			_engine.accept_bailout()
			_think("🏦 Resgate do FMI aceito — austeridade, mas sobrevivemos.")

		_think("Ações usadas: %d. Avançando turno..." % actions_this_turn)
		await _delay(turn_delay)

		if not enabled: break
		# Avança o turno pelo GameEngine diretamente
		_engine.end_turn()
		await _delay(0.5)

	_running = false
	if not enabled:
		_think("Bot pausado.")
	else:
		emit_signal("game_over_detected")
		_think("Fim de jogo detectado.")

# ── Motor de decisão ──────────────────────────────────────────────
# Gera todas as ações possíveis, pontua cada uma, retorna a melhor.
func _choose_best_action() -> Dictionary:
	var n = _engine.player_nation
	if n == null: return {}

	var candidates: Array = []
	candidates.append_array(_generate_economy_actions(n))
	candidates.append_array(_generate_social_actions(n))
	candidates.append_array(_generate_tech_actions(n))
	candidates.append_array(_generate_diplomacy_actions(n))
	candidates.append_array(_generate_military_actions(n))
	candidates.append_array(_generate_trade_actions(n))
	candidates.append_array(_generate_era_actions(n))

	if candidates.is_empty(): return {}

	# Aplica pesos de personalidade
	var weights: Dictionary = PERSONALITIES.get(personality, PERSONALITIES["balanced"])
	for c in candidates:
		var cat: String = String(c.get("category", "economia"))
		var w: float = float(weights.get(cat, 1.0))
		c["score"] = float(c.get("score", 0)) * w

	# Ordena por score decrescente
	candidates.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))

	# Log top 3 opções consideradas
	var top_n: int = mini(3, candidates.size())
	var top_str: String = ""
	for i in top_n:
		top_str += "\n  [%.1f] %s" % [float(candidates[i]["score"]), String(candidates[i]["reason"])]
	_think("Top opções:%s" % top_str)

	return candidates[0]

# ── Geração de candidatos ─────────────────────────────────────────
# IDs de ação = catálogo GameEngine.PANEL_ACTIONS (custos reais do jogo).

# Ações de ERA (economia_digital, programa_espacial, etc.) — só as JÁ destravadas
# aparecem em get_panel_actions (o gate de década/tech filtra). Assim o MUNDO
# evolui junto com o jogador: os bots modernizam quando a época chega.
func _generate_era_actions(n) -> Array:
	var out: Array = []
	var tesouro: float = float(n.tesouro)
	var ERA_IDS := {
		"economia_digital": 44.0, "transicao_energetica": 40.0, "renda_basica": 38.0,
		"telemedicina": 36.0, "ensino_imersivo": 42.0, "drones_autonomos": 40.0,
		"programa_espacial": 46.0,
	}
	for panel in ["economia", "governo", "saude", "educacao", "seguranca"]:
		for a in _engine.get_panel_actions(panel):
			var aid: String = String(a.get("id", ""))
			if not ERA_IDS.has(aid):
				continue
			if tesouro < float(a.get("cost", 0)) * 1.4:  # só com folga (não estoura o caixa)
				continue
			out.append({
				"type": "panel_action", "action": aid,
				"score": ERA_IDS[aid], "category": "era",
				"reason": "Modernização: %s" % String(a.get("label", aid))
			})
	return out

func _generate_economy_actions(n) -> Array:
	var out: Array = []
	var inflacao: float = float(n.inflacao)
	var tesouro: float = float(n.tesouro)

	# Inflação alta — aperto monetário URGENTE (nova ferramenta anti-inflação)
	if inflacao > 30 and tesouro >= 40:
		out.append({
			"type": "panel_action", "action": "aperto_monetario",
			"score": 55.0 + (inflacao - 30.0) * 1.8, "category": "economia",
			"reason": "URGENTE: Aperto monetário — inflação=%.0f%%" % inflacao
		})

	# Estímulo fiscal (+2% PIB, custo 80)
	if tesouro >= 110:
		var score: float = 40.0
		if inflacao > 25: score -= 15.0          # economia superaquecida
		if float(n.corrupcao) > 60: score -= 10.0
		out.append({
			"type": "panel_action", "action": "estimulo_fiscal",
			"score": score, "category": "economia",
			"reason": "Estímulo fiscal (+2%% PIB) — tesouro=$%.0fB" % tesouro
		})

	# Infraestrutura básica (+1% PIB, custo 50)
	if tesouro >= 80:
		out.append({
			"type": "panel_action", "action": "infra_basica",
			"score": 35.0, "category": "economia",
			"reason": "Infraestrutura (+1%% PIB)"
		})

	# Megaprojeto (+2.5% PIB, custo 100) — só quando rico e estável
	if tesouro >= 200 and float(n.estabilidade_politica) >= 55:
		out.append({
			"type": "panel_action", "action": "infra_megaprojeto",
			"score": 38.0, "category": "economia",
			"reason": "Megaprojeto (+2.5%% PIB, Estab -2)"
		})

	# Explorar recurso mais escasso (custo 20)
	if tesouro >= 40 and not n.recursos.is_empty():
		var min_res: float = 100.0
		for v in n.recursos.values():
			min_res = minf(min_res, float(v))
		if min_res < 60:
			out.append({
				"type": "panel_action", "action": "explorar_recurso",
				"score": 28.0 + (60.0 - min_res) * 0.3, "category": "economia",
				"reason": "Explorar recursos — recurso mín=%.0f" % min_res
			})

	# Upgrade industrial (custo 70): industrializar quando o país exporta commodity
	# BRUTA e tem baixa complexidade (rico em recursos, pouca manufatura = Brasil).
	# Score sobe com a volatilidade (dependência de commodity bruta) e cai com ECS alto.
	if tesouro >= 90:
		var vol: float = n.commodity_volatilidade()
		var ecs: float = n.complexidade_economica
		# só se há setor de commodity exportável ainda pouco processado
		var tem_alvo: bool = false
		for s in n.COMMODITY_SECTORS:
			if n._setor_oferta(s) >= 60.0 and n._grau_proc(s) < 0.9:
				tem_alvo = true
				break
		if tem_alvo and vol >= 0.25:
			out.append({
				"type": "panel_action", "action": "upgrade_industrial",
				"score": 30.0 + vol * 35.0 + maxf(0.0, 55.0 - ecs) * 0.4, "category": "economia",
				"reason": "Industrializar — commodity bruta (vol=%.2f, ECS=%.0f)" % [vol, ecs]
			})

	return out

func _generate_social_actions(n) -> Array:
	var out: Array = []
	var apoio: float = float(n.apoio_popular)
	var felicidade: float = float(n.felicidade)
	var stab: float = float(n.estabilidade_politica)
	var corrupcao: float = float(n.corrupcao)
	var tesouro: float = float(n.tesouro)

	# Disciplina fiscal: investimentos que criam GASTO PERMANENTE
	# (saúde/educação/previdência) só com saldo trimestral positivo —
	# sem isto o bot cavava déficit eterno em países ricos
	var saldo_ok: bool = n.calc_saldo() > 0.0

	# Saúde pública — felicidade e apoio (custo 20)
	if (felicidade < 65 or apoio < 65) and tesouro >= 30 and saldo_ok:
		var score: float = 50.0 + (65.0 - felicidade) * 0.8 + (65.0 - apoio) * 0.5
		out.append({
			"type": "panel_action", "action": "investir_saude",
			"score": score, "category": "social",
			"reason": "Saúde pública — felicidade=%.0f%%, apoio=%.0f%%" % [felicidade, apoio]
		})

	# Combate à corrupção — urgente se > 40 (custo 20)
	if corrupcao > 40 and tesouro >= 30:
		var score: float = 35.0 + (corrupcao - 40) * 1.2
		out.append({
			"type": "panel_action", "action": "combater_corrupcao",
			"score": score, "category": "social",
			"reason": "Anti-corrupção — corrupção=%.0f%%" % corrupcao
		})

	# Estabilidade crítica — reforma política (custo 30)
	if stab < 50 and tesouro >= 40:
		var score: float = 60.0 + (50.0 - stab) * 1.5
		out.append({
			"type": "panel_action", "action": "reforma_politica",
			"score": score, "category": "social",
			"reason": "URGENTE: Reforma política — estab=%.0f%%" % stab
		})

	# Apoio crítico — propaganda é a ação mais forte de apoio (custo 10)
	if apoio < 35 and tesouro >= 15:
		out.append({
			"type": "panel_action", "action": "propaganda",
			"score": 80.0 + (35.0 - apoio) * 2.0, "category": "social",
			"reason": "CRÍTICO: Apoio popular em %.0f%% — risco revolução!" % apoio
		})
	# Apoio moderadamente baixo — previdência (custo 20, gasto permanente)
	elif apoio < 55 and tesouro >= 30 and saldo_ok:
		out.append({
			"type": "panel_action", "action": "investir_previdencia",
			"score": 25.0 + (55.0 - apoio) * 0.5, "category": "social",
			"reason": "Previdência — apoio=%.0f%%" % apoio
		})

	return out

func _generate_tech_actions(n) -> Array:
	var out: Array = []
	if _engine.tech == null: return out
	# Trilhas paralelas: só busca nova tech se ainda houver slot (trilha ociosa)
	var slots: int = n.research_slots() if n.has_method("research_slots") else 2
	if n.pesquisa_por_ministerio.size() >= slots:
		return out

	var available: Array = _engine.tech.get_available_techs(n)
	if available.is_empty(): return out

	# Não repete pasta já ocupada (uma trilha por ministério)
	var pastas_ocupadas: Dictionary = {}
	for p in n.pesquisa_por_ministerio:
		pastas_ocupadas[p] = true

	# Escolhe a MELHOR tech para uma pasta LIVRE. O RANKING interno valoriza
	# techs que destravam a árvore (unlock_count) + tier; o custo desempata.
	var prio := {"MILITAR": 0.9, "DIGITAL": 1.2, "ENERGIA": 1.1, "SOCIAL": 1.0, "ESPACIAL": 0.9}
	var best_tech: Dictionary = {}
	var best_rank: float = -1.0
	for t in available:
		var pasta: String = _engine.tech.ministry_of(t)
		if pastas_ocupadas.has(pasta):
			continue  # essa trilha já está pesquisando
		var cat: String = String(t.get("categoria", "")).to_upper()
		var custo: float = float(t.get("custo", 50))
		var unlocks: int = int(_engine.tech.unlock_count.get(String(t.get("id", "")), 0))
		var tier: int = int(t.get("tier", 1))
		# destravar a árvore domina; tier dá profundidade; custo desempata
		var rank: float = (1.0 + unlocks * 3.0 + tier * 1.5) * float(prio.get(cat, 1.0))
		rank += 30.0 / max(1.0, custo)
		if rank > best_rank:
			best_rank = rank
			best_tech = t

	if best_tech.is_empty(): return out
	# Score de PRIORIDADE contra as outras ações do bot (faixa 15-80): pesquisar é
	# quase sempre a jogada dominante (tech-rush), então entra ALTO — como antes das
	# trilhas paralelas. Sem isto o bot larga a pesquisa e a árvore trava (~8 techs).
	var trilhas_ativas: int = n.pesquisa_por_ministerio.size()
	var priority: float = 82.0 - trilhas_ativas * 6.0  # 1ª trilha domina; extras ainda competem
	out.append({
		"type": "research", "tech_id": String(best_tech.get("id", "")),
		"score": priority, "category": "tech",
		"reason": "Pesquisar '%s' (cat: %s, destrava %d)" % [String(best_tech.get("nome", "?")), String(best_tech.get("categoria", "?")), int(_engine.tech.unlock_count.get(String(best_tech.get("id", "")), 0))]
	})
	return out

func _generate_diplomacy_actions(n) -> Array:
	var out: Array = []
	if _engine.diplomacy == null: return out
	var tesouro: float = float(n.tesouro)
	var p_code: String = n.codigo_iso

	# Propor tratado ao melhor aliado potencial (relação > 20, sem tratado)
	var best_partner: String = ""
	var best_rel: float = 20.0
	var existing_partners: Array = []
	for t in _engine.diplomacy.get_player_treaties():
		for s in t.get("signatories", []):
			if s != p_code: existing_partners.append(s)

	for code in n.relacoes:
		if code == p_code: continue
		var rel: float = float(n.relacoes[code])
		if rel > best_rel and not (code in existing_partners) and not (code in n.em_guerra):
			best_rel = rel
			best_partner = code

	if best_partner != "" and tesouro >= 10:
		var treaty_type: String = "livre_comercio" if best_rel < 60 else "parceria_tecnologica"
		out.append({
			"type": "treaty", "target": best_partner, "treaty_type": treaty_type,
			"score": 20.0 + best_rel * 0.4, "category": "diplomacy",
			"reason": "Propor %s a %s (rel=%.0f)" % [treaty_type, _engine.nations[best_partner].nome if _engine.nations.has(best_partner) else best_partner, best_rel]
		})

	# Embaixada — melhora relações com vizinho frio (custo 15)
	if tesouro >= 25:
		var emb_target: String = ""
		var emb_rel: float = 999.0
		for code in n.relacoes:
			if code == p_code or code in n.em_guerra:
				continue
			var rel2: float = float(n.relacoes[code])
			if rel2 >= -30.0 and rel2 <= 30.0 and rel2 < emb_rel:
				emb_rel = rel2
				emb_target = code
		if emb_target != "":
			out.append({
				"type": "embassy", "target": emb_target,
				"score": 18.0 + (30.0 - emb_rel) * 0.3, "category": "diplomacy",
				"reason": "Embaixada em %s (rel=%.0f → +15)" % [_engine.nations[emb_target].nome if _engine.nations.has(emb_target) else emb_target, emb_rel]
			})

	# Educação — acelera pesquisa (custo 20, gasto permanente)
	if tesouro >= 30 and n.velocidade_pesquisa < 2.0 and n.calc_saldo() > 0.0:
		out.append({
			"type": "panel_action", "action": "investir_educacao",
			"score": 22.0, "category": "tech",
			"reason": "Investir em educação (+5%% pesquisa)"
		})

	# CONQUISTA TERRITORIAL PACÍFICA (Bloco 5 — IA territorial): com caixa
	# sobrando, o bot COMPRA uma província de um vizinho de continente com quem
	# tem relação ok (evita guerra). Expande sem sangue — o mundo fica dinâmico.
	if _engine.has_method("player_buy_province") and tesouro >= 300 and not _engine.provinces_of.is_empty():
		var best_pid: String = ""
		var best_prov_score: float = 0.0
		for code in _engine.nations:
			if code == p_code or code in n.em_guerra:
				continue
			var other = _engine.nations[code]
			if other.continente != n.continente:
				continue
			var rel3: float = float(n.relacoes.get(code, 0))
			if rel3 < -20.0:  # relação muito ruim → não vende
				continue
			for pid in _engine.provinces_of.get(code, []):
				var pinf: Dictionary = _engine.provinces.get(pid, {})
				if bool(pinf.get("is_capital", false)):
					continue  # capital não se compra
				var ch: float = _engine._cession_accept_chance(pid, p_code, tesouro * 0.15)
				var sc: float = ch * 100.0 + rel3 * 0.3
				if sc > best_prov_score and ch > 0.4:
					best_prov_score = sc
					best_pid = pid
		if best_pid != "":
			out.append({
				"type": "buy_province", "prov_id": best_pid, "oferta": tesouro * 0.15,
				"score": 26.0 + minf(best_prov_score * 0.15, 20.0), "category": "diplomacy",
				"reason": "Comprar província (expansão pacífica)"
			})

	return out

func _generate_military_actions(n) -> Array:
	var out: Array = []
	var tesouro: float = float(n.tesouro)
	var em_guerra: bool = not n.em_guerra.is_empty()

	# Em guerra: propor paz se estabilidade baixa ou tesouro baixo
	if em_guerra:
		var stab: float = float(n.estabilidade_politica)
		if stab < 45 or tesouro < 40:
			var enemy: String = String(n.em_guerra[0])
			out.append({
				"type": "peace", "target": enemy,
				"score": 70.0 + (45.0 - stab) * 1.5, "category": "military",
				"reason": "Propor paz — stab=%.0f%%, tesouro=%.0fB" % [stab, tesouro]
			})
		else:
			# PILOTAR A FRENTE: com fôlego (estab/tesouro ok), empurra o placar.
			# Ofensiva quando forte; cerco quando quer economizar; fortificar se apoio baixo.
			var enemy: String = String(n.em_guerra[0])
			var st: Dictionary = _engine.war_front_status(enemy) if _engine.has_method("war_front_status") else {}
			var lead: String = String(st.get("lead", "empate"))
			var war_id: String = "war_cerco"
			var reason: String = "Cerco — desgastar %s barato" % enemy
			if float(n.apoio_popular) < 40.0:
				war_id = "war_fortificar"
				reason = "Fortificar — recompor apoio (%.0f%%)" % n.apoio_popular
			elif lead == "vencendo" or (tesouro >= 120 and personality == "military"):
				war_id = "war_ofensiva"
				reason = "Ofensiva total — pressionar a vitória sobre %s" % enemy
			out.append({
				"type": "war_action", "target": enemy, "war_id": war_id,
				"score": 55.0 if lead == "vencendo" else 38.0, "category": "military",
				"reason": reason
			})

	# GUERRA OFENSIVA — oportunismo territorial. Antes era só persona 'military'
	# com ratio 2.5x E rel<=-50 (raríssimo → wars=0 nas sims). Agora:
	#  • 'military' ataca com vantagem 1.6x rival (rel<=-30) ou 2.2x qualquer vizinho fraco;
	#  • 'balanced' ataca rival muito fraco (2.0x, rel<=-40);
	#  • 'diplomat'/'economic' evitam guerra (mantêm o perfil).
	# Vencer toma território/espólios — guerra virou investimento com o placar pilotável.
	var war_capable: bool = personality == "military" or personality == "balanced"
	if war_capable and n.em_guerra.is_empty() and tesouro >= 120:
		var my_power: float = n.get_military_power()
		var min_ratio: float = 1.6 if personality == "military" else 2.0
		var rel_gate: float = -30.0 if personality == "military" else -40.0
		var same_cont_only: bool = personality != "military"  # balanced só ataca vizinho de continente
		var best_target: String = ""
		var best_sc: float = 0.0
		for code in _engine.nations:
			if code == n.codigo_iso:
				continue
			var t = _engine.nations[code]
			if same_cont_only and t.continente != n.continente:
				continue
			var rel: float = float(n.relacoes.get(code, 0))
			var ratio: float = my_power / max(1.0, t.get_military_power())
			# Casus belli: ou é rival (rel baixa) OU é uma presa fácil (vantagem esmagadora)
			var is_rival: bool = rel <= rel_gate
			var is_prey: bool = ratio >= min_ratio + 0.6
			if not (is_rival or is_prey):
				continue
			if ratio < min_ratio:
				continue
			var sc: float = ratio * 8.0 - rel * 0.15
			if sc > best_sc:
				best_sc = sc
				best_target = code
		if best_target != "":
			out.append({
				"type": "war", "target": best_target,
				"score": 24.0 + minf(best_sc * 0.3, 30.0), "category": "military",
				"reason": "GUERRA: conquistar %s (vantagem %.1fx)" % [(_engine.nations[best_target].nome if _engine.nations.has(best_target) else best_target), my_power / max(1.0, _engine.nations[best_target].get_military_power())]
			})

	# Construir base se poder militar baixo e tem dinheiro (custo 40)
	var poder: float = float(n.militar.get("poder_militar_global", 0)) if n.militar else 0.0
	if poder < 40 and tesouro >= 60:
		out.append({
			"type": "panel_action", "action": "construir_base",
			"score": 18.0 + (40.0 - poder) * 0.5, "category": "military",
			"reason": "Construir base militar — poder=%.0f" % poder
		})

	return out

func _generate_trade_actions(n) -> Array:
	var out: Array = []
	if n.recursos.is_empty(): return out

	# Encontra melhor recurso pra exportar (>= 60 de valor)
	var best_res: String = ""
	var best_val: float = 60.0
	for k in n.recursos:
		var v: float = float(n.recursos[k])
		if v > best_val:
			best_val = v
			best_res = k
	if best_res == "": return out

	# Encontra melhor parceiro comercial (boa relação, sem guerra, sem sanção)
	var best_target: String = ""
	var best_rel: float = -100.0
	for code in _engine.nations:
		if code == n.codigo_iso: continue
		if code in n.em_guerra: continue
		var rel: float = float(n.relacoes.get(code, 0))
		if rel > best_rel:
			best_rel = rel
			best_target = code

	if best_target == "": return out
	out.append({
		"type": "trade", "target": best_target, "resource": best_res,
		"score": 15.0 + best_val * 0.2 + best_rel * 0.1, "category": "economia",
		"reason": "Exportar %s→%s (recurso=%.0f, rel=%.0f)" % [
			best_res,
			_engine.nations[best_target].nome if _engine.nations.has(best_target) else best_target,
			best_val, best_rel
		]
	})
	return out

# ── Executor de ações ─────────────────────────────────────────────
# Retorna true se a ação foi executada (consumiu ação do turno).
func _execute_action(action: Dictionary) -> bool:
	var atype: String = String(action.get("type", ""))
	var reason: String = String(action.get("reason", ""))
	_think("▶ EXECUTANDO: %s" % reason)
	emit_signal("action_taken", action)

	match atype:
		"panel_action":
			return _do_panel_action(String(action.get("action", "")))
		"research":
			var res: Dictionary = _engine.player_start_research(String(action.get("tech_id", "")))
			if not bool(res.get("ok", false)):
				_think("  ✗ Pesquisa falhou: %s" % String(res.get("reason", "")))
				return false
			return true
		"treaty":
			# player_propose_treaty devolve o dict da proposta em sucesso
			# (sem chave "ok") ou {"ok": false, reason} em falha de validação
			var res: Dictionary = _engine.player_propose_treaty(String(action.get("target", "")), String(action.get("treaty_type", "livre_comercio")))
			if res.is_empty() or res.get("ok", true) == false:
				_think("  ✗ Tratado falhou: %s" % String(res.get("reason", "proposta inválida")))
				return false
			return true
		"peace":
			if not _engine.player_propose_peace(String(action.get("target", ""))):
				_think("  ✗ Paz falhou")
				return false
			return true
		"trade":
			var res: Dictionary = _engine.player_export_resource(String(action.get("target", "")), String(action.get("resource", "")))
			if not bool(res.get("ok", false)):
				_think("  ✗ Comércio falhou: %s" % String(res.get("reason", "")))
				return false
			return true
		"war":
			if not _engine.player_declare_war(String(action.get("target", ""))):
				_think("  ✗ Declaração de guerra falhou")
				return false
			return true
		"war_action":
			# Pilotar uma frente ativa (Ofensiva/Cerco/Fortificar) — mesma API do jogador
			var wres: Dictionary = _engine.player_war_action(String(action.get("war_id", "war_cerco")), String(action.get("target", "")))
			if not bool(wres.get("ok", false)):
				_think("  ✗ Ação de guerra falhou: %s" % String(wres.get("reason", "")))
				return false
			return true
		"embassy":
			var res: Dictionary = _engine.player_open_embassy(String(action.get("target", "")))
			if not bool(res.get("ok", false)):
				_think("  ✗ Embaixada falhou: %s" % String(res.get("reason", "")))
				return false
			return true
		"buy_province":
			var bres: Dictionary = _engine.player_buy_province(String(action.get("prov_id", "")), float(action.get("oferta", 0.0)))
			if not bool(bres.get("ok", false)):
				_think("  ✗ Compra de província falhou: %s" % String(bres.get("reason", "")))
				return false
			return true
	return false

# Executa ação de painel via API central — a MESMA usada pelos botões da UI.
# (antes: efeitos duplicados aqui com custos divergentes e bug de multiplicador)
# Aloca verba de P&D aos ministérios conforme a persona — dá progressão de
# gabinete + trilhas de pesquisa paralelas à IA (mesmo sistema do jogador).
func _manage_ministry_budgets() -> void:
	var n = _engine.player_nation
	if n == null or n.ministerios == null or n.tesouro < 100.0:
		return
	# Prioridade de pasta por persona (pesos)
	var prio: Dictionary
	match personality:
		"military":
			prio = {"seguranca": 3.0, "casa_civil": 1.5, "educacao": 1.0, "fazenda": 1.0, "saude": 0.5, "exterior": 0.5}
		"economic":
			prio = {"fazenda": 3.0, "educacao": 1.5, "casa_civil": 1.5, "saude": 1.0, "seguranca": 0.8, "exterior": 0.8}
		"diplomat":
			prio = {"exterior": 3.0, "casa_civil": 1.5, "educacao": 1.5, "saude": 1.0, "fazenda": 1.0, "seguranca": 0.5}
		_:  # balanced
			prio = {"casa_civil": 1.5, "educacao": 1.5, "fazenda": 1.2, "saude": 1.2, "seguranca": 1.2, "exterior": 1.0}
	# Orçamento total de P&D = ~1.5% do PIB, dividido pelos pesos
	var total_rd: float = n.pib_bilhoes_usd * 0.015
	var soma_peso: float = 0.0
	for w in prio.values():
		soma_peso += float(w)
	for pasta in prio:
		var verba: float = total_rd * float(prio[pasta]) / max(soma_peso, 0.01)
		_engine.player_alloc_rd(pasta, verba)
	_manage_debt(n)

# Alavancagem estratégica: capta empréstimo quando o crédito é BOM e o tesouro
# está baixo (investir cedo), e amortiza quando sobra caixa e a dívida é grande.
func _manage_debt(n) -> void:
	if not n.has_method("rating_credito"):
		return
	var rating: float = n.rating_credito()
	var limite: float = n.limite_emprestimo()
	var tesouro_baixo: bool = n.tesouro < n.pib_bilhoes_usd * 0.08
	if rating >= 60.0 and tesouro_baixo and limite > 50.0 and n.estabilidade_politica >= 55.0:
		var alvo: float = n.pib_bilhoes_usd * (0.15 if personality == "economic" else 0.08)
		var valor: float = minf(alvo, limite)
		if valor >= 20.0:
			_engine.player_take_loan(valor)
			return
	if n.divida_publica > n.pib_bilhoes_usd * 0.8 and n.tesouro > n.pib_bilhoes_usd * 0.15:
		_engine.player_repay_debt(minf(n.tesouro * 0.4, n.divida_publica * 0.3))
	# Tesouro OCIOSO (sem dívida cara e com caixa gordo) → aplica parte na bolsa.
	# Complementar: só o excedente, nunca all-in. Economic é mais ativo.
	if n.divida_publica < n.pib_bilhoes_usd * 0.3 and n.tesouro > n.pib_bilhoes_usd * 0.18:
		var ocioso: float = n.tesouro - n.pib_bilhoes_usd * 0.15
		var frac: float = 0.5 if personality == "economic" else 0.3
		if ocioso > 20.0:
			_engine.player_invest_stocks(ocioso * frac)
			# Cripto: só a persona economic, e só uma FATIA PEQUENA (alto risco).
			# Compra no bull OU quando está barata (fundo), evita comprar no topo.
			if personality == "economic" and n.tesouro > n.pib_bilhoes_usd * 0.16:
				var barata: bool = _engine.crypto_price < 800.0 + _engine.current_turn * 1.333
				if _engine.crypto_cycle > -0.2 or barata:
					_engine.player_buy_crypto((n.tesouro - n.pib_bilhoes_usd * 0.15) * 0.2)

func _do_panel_action(action_id: String) -> bool:
	var res: Dictionary = _engine.player_panel_action(action_id)
	if not res.get("ok", false):
		_think("  ✗ %s" % String(res.get("reason", "ação falhou")))
		return false
	var n = _engine.player_nation
	_engine._log_news({
		"type": "bot_action",
		"headline": "🤖 BOT: %s — %s" % [action_id.replace("_", " ").capitalize(), String(res.get("msg", ""))],
		"body": "",
		"color": Color(0.4, 0.85, 1),
	}, [n.codigo_iso] if n != null else [], n.continente if n != null else "")
	return true

# ── Propostas diplomáticas ────────────────────────────────────────
func _handle_pending_proposals() -> void:
	if _engine.diplomacy == null: return
	var pending: Array = _engine.diplomacy.get_player_pending_proposals()
	for prop in pending:
		# Aceita se relação for positiva, rejeita se negativa
		var proposer: String = String(prop.get("proposer", ""))
		var rel: float = float(_engine.player_nation.relacoes.get(proposer, 0)) if _engine.player_nation else 0.0
		if rel >= 0:
			_engine.player_accept_proposal(String(prop.get("id", "")))
			_think("✅ Aceita proposta de %s (rel=%.0f)" % [proposer, rel])
		else:
			_engine.player_reject_proposal(String(prop.get("id", "")))
			_think("❌ Rejeita proposta de %s (rel=%.0f)" % [proposer, rel])

# ── Helpers ───────────────────────────────────────────────────────
func _think(msg: String) -> void:
	emit_signal("thinking", msg)
	if verbose:
		print("[BOT] %s" % msg)

func _delay(seconds: float) -> Signal:
	return _tree.create_timer(seconds).timeout
