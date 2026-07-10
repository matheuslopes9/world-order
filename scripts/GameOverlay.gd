extends Control
## HUD do jogador após Assumir Comando.
## Vive sobre o WorldMap.tscn — painel esquerdo com tabs dos 9 painéis temáticos.

# Resolvidos em _resolve_widgets() pra funcionar tanto na cena estática quanto
# quando o node é construído dinamicamente pelo WorldMap._build_legacy_nodes
var player_panel: PanelContainer = null
var nation_header: Label = null
var nation_tier: Label = null
var panel_tabs: HBoxContainer = null
var panel_content: VBoxContainer = null

var activated: bool = false
var current_panel: String = "governo"
var endgame_triggered: bool = false  # trava múltiplos modais de fim

const PANELS := [
	{"id": "governo",    "icon": "🏛", "label": "Governo"},
	{"id": "militar",    "icon": "⚔", "label": "Militar"},
	{"id": "economia",   "icon": "📊", "label": "Economia"},
	{"id": "diplomacia", "icon": "🤝", "label": "Diplo"},
	{"id": "tech",       "icon": "🔬", "label": "Tech"},
	{"id": "intel",      "icon": "🕵", "label": "Intel"},
	{"id": "situacao",   "icon": "🌐", "label": "Situação"},
	{"id": "historico",  "icon": "📋", "label": "Histórico"},
	{"id": "noticias",   "icon": "📡", "label": "News"},
]

func _ready() -> void:
	pass

func activate() -> void:
	if activated: return
	activated = true
	visible = true
	_resolve_widgets()
	if GameEngine.has_signal("turn_advanced"):
		GameEngine.turn_advanced.connect(_on_turn_advanced)
	if GameEngine.has_signal("player_event_triggered"):
		GameEngine.player_event_triggered.connect(_on_player_event)
	if GameEngine.has_signal("endgame_reached"):
		GameEngine.endgame_reached.connect(_on_endgame_reached)
	_build_tabs()
	_render_panel("governo")
	_refresh_header()

func _resolve_widgets() -> void:
	# find_child funciona tanto pra cena estática quanto pra árvore criada via script
	if player_panel == null: player_panel = find_child("PlayerPanel", true, false)
	if nation_header == null: nation_header = find_child("NationHeader", true, false)
	if nation_tier == null: nation_tier = find_child("NationTier", true, false)
	if panel_tabs == null: panel_tabs = find_child("PanelTabs", true, false)
	if panel_content == null: panel_content = find_child("PanelContent", true, false)

func _build_tabs() -> void:
	if panel_tabs == null: return
	for c in panel_tabs.get_children(): c.queue_free()
	for p in PANELS:
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_pressed = (p["id"] == current_panel)
		btn.set_meta("panel_id", p["id"])
		btn.text = p["icon"]
		btn.tooltip_text = p["label"]
		btn.custom_minimum_size = Vector2(0, 36)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 14)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_tab_pressed.bind(p["id"]))
		panel_tabs.add_child(btn)

func _on_tab_pressed(panel_id: String) -> void:
	current_panel = panel_id
	for child in panel_tabs.get_children():
		if child is Button:
			child.button_pressed = (child.get_meta("panel_id", "") == panel_id)
	_render_panel(panel_id)

func _refresh_header() -> void:
	var n = GameEngine.player_nation
	if n == null: return
	nation_header.text = n.nome
	var meta = GameEngine.get_difficulty_meta(n.tier_dificuldade)
	nation_tier.text = "%s %s — %s" % [meta["icon"], n.codigo_iso, meta["label"]]
	nation_tier.add_theme_color_override("font_color", meta["color"])

func _on_turn_advanced(_t: int) -> void:
	_refresh_header()
	_render_panel(current_panel)

func _on_player_event(event_data: Dictionary) -> void:
	_show_event_modal(event_data)

# ─────────────────────────────────────────────────────────────────
# RENDERIZAÇÃO DE PAINÉIS
# ─────────────────────────────────────────────────────────────────

func _render_panel(panel_id: String) -> void:
	if panel_content == null: return
	for c in panel_content.get_children(): c.queue_free()
	match panel_id:
		"governo":    _render_governo()
		"militar":    _render_militar()
		"economia":   _render_economia()
		"diplomacia": _render_diplomacia()
		"tech":       _render_tech()
		"intel":      _render_intel()
		"situacao":   _render_situacao()
		"historico":  _render_historico()
		"noticias":   _render_noticias()

# ─────────────────────────────────────────────────────────────────
# PAINEL: GOVERNO
# ─────────────────────────────────────────────────────────────────

func _render_governo() -> void:
	var n = GameEngine.player_nation
	if n == null: return
	_add_section_title("INDICADORES")
	_add_bar("Estabilidade", n.estabilidade_politica, true)
	_add_bar("Apoio popular", n.apoio_popular, true)
	_add_bar("Felicidade", n.felicidade, true)
	_add_bar("Corrupção", n.corrupcao, false)
	_add_bar("Inflação", min(100.0, n.inflacao * 2.0), false, "%.1f%%" % n.inflacao)
	_add_separator()
	_add_section_title("AÇÕES DE GOVERNO")
	for a in GameEngine.get_panel_actions("governo"):
		_add_action_button(a.id, a.label, a.cost, a.desc, _run_panel_action.bind(a.id, "governo", Color(0, 0.823, 1)))

# Executa ação via API central do GameEngine (catálogo único).
# Toda a lógica de custo/efeito vive em GameEngine.player_panel_action.
func _run_panel_action(action_id: String, panel_id: String, color: Color) -> void:
	var res: Dictionary = GameEngine.player_panel_action(action_id)
	if not res.get("ok", false):
		_log_global_news("⚠ AÇÃO INDISPONÍVEL", String(res.get("reason", "")), Color(1, 0.6, 0.4))
		return
	_log_global_news(action_id.replace("_", " ").to_upper(),
		String(res.get("msg", "")) + "  •  -$%dB" % int(res.get("cost", 0)), color)
	_render_panel(panel_id)
	_refresh_top_bar_external()

# ─────────────────────────────────────────────────────────────────
# PAINEL: MILITAR
# ─────────────────────────────────────────────────────────────────

func _render_militar() -> void:
	var n = GameEngine.player_nation
	if n == null: return
	_add_section_title("CAPACIDADE MILITAR")
	var m: Dictionary = n.militar
	var u: Dictionary = m.get("unidades", {})
	_add_data_row("Poder Militar", "%d" % int(m.get("poder_militar_global", 0)))
	_add_data_row("Orçamento Militar", "$%dB/ano" % int(m.get("orcamento_militar_bilhoes", 0)))
	_add_data_row("Armas Nucleares", "%d ogivas" % int(m.get("armas_nucleares", 0)))
	_add_data_row("Infantaria", _fmt_thousands(u.get("infantaria", 0)))
	_add_data_row("Tanques", _fmt_thousands(u.get("tanques", 0)))
	_add_data_row("Aviões", _fmt_thousands(u.get("avioes", 0)))
	_add_data_row("Navios", _fmt_thousands(u.get("navios", 0)))
	_add_separator()
	_add_section_title("OPERAÇÕES MILITARES")
	for a in GameEngine.get_panel_actions("militar"):
		_add_action_button(a.id, a.label, a.cost, a.desc, _run_panel_action.bind(a.id, "militar", Color(1, 0.5, 0.5)))

# ─────────────────────────────────────────────────────────────────
# PAINEL: ECONOMIA
# ─────────────────────────────────────────────────────────────────

func _render_economia() -> void:
	var n = GameEngine.player_nation
	if n == null: return
	_add_section_title("INDICADORES ECONÔMICOS")
	_add_data_row("PIB Anual", _money(n.pib_bilhoes_usd))
	_add_data_row("Tesouro", _money(n.tesouro))
	_add_data_row("Dívida Pública", _money(n.divida_publica))
	_add_data_row("Inflação", "%.1f%%" % n.inflacao)
	_add_data_row("População", _fmt_thousands(n.populacao))
	var receita: float = n.calc_receita() if n.has_method("calc_receita") else 0.0
	var despesas: float = n.calc_despesas() if n.has_method("calc_despesas") else 0.0
	_add_separator()
	_add_section_title("FINANÇAS (TRIMESTRE)")
	_add_data_row("Receita", "+%s" % _money(receita))
	_add_data_row("Despesas", "-%s" % _money(despesas))
	_add_data_row("Saldo", _money(receita - despesas))
	_add_separator()
	_add_section_title("RECURSOS NATURAIS")
	var rec: Dictionary = n.recursos
	for k in ["petroleo", "gas_natural", "minerios_raros", "uranio", "ferro", "terras_araveis"]:
		if rec.has(k):
			_add_bar(k.replace("_", " ").capitalize(), float(rec[k]), true)
	_add_separator()
	_add_section_title("AÇÕES ECONÔMICAS")
	for a in GameEngine.get_panel_actions("economia"):
		_add_action_button(a.id, a.label, a.cost, a.desc, _run_panel_action.bind(a.id, "economia", Color(0, 1, 0.5)))

# ─────────────────────────────────────────────────────────────────
# PAINEL: DIPLOMACIA
# ─────────────────────────────────────────────────────────────────

func _render_diplomacia() -> void:
	var n = GameEngine.player_nation
	if n == null: return

	# ── PROPOSTAS PENDENTES (alta prioridade visual) ──
	if GameEngine.diplomacy:
		var pending: Array = GameEngine.diplomacy.get_player_pending_proposals()
		if pending.size() > 0:
			_add_section_title("⚡ PROPOSTAS RECEBIDAS (%d)" % pending.size())
			for prop in pending:
				_render_proposal_card(prop)
			_add_separator()

	# ── TRATADOS ATIVOS ──
	_add_section_title("TRATADOS ATIVOS")
	var my_treaties: Array = GameEngine.diplomacy.get_player_treaties() if GameEngine.diplomacy else []
	if my_treaties.is_empty():
		_add_hint_label("Nenhum tratado ativo. Selecione um país no mapa para propor.")
	else:
		for t in my_treaties:
			var meta = GameEngine.diplomacy.TIPOS_TRATADO.get(t["type"], {})
			var other := ""
			for s in t["signatories"]:
				if s != n.codigo_iso:
					other = GameEngine.nations[s].nome if GameEngine.nations.has(s) else s
			var turns_left: int = int(t["expires_turn"]) - GameEngine.current_turn
			_add_data_row(meta.get("nome", t["type"]), "%s • %d turnos" % [other, turns_left], Color(0.4, 0.85, 1))
	_add_separator()

	# ── ALIANÇAS PRÉ-EXISTENTES ──
	_add_section_title("ALIANÇAS")
	var found_alliance := false
	for alliance in GameEngine.alliances_data:
		var members: Array = alliance.get("membros", [])
		if n.codigo_iso in members:
			_add_data_row(alliance.get("nome", "?"), "%d membros" % members.size(), Color(0.4, 0.85, 1))
			found_alliance = true
	if not found_alliance:
		_add_hint_label("Você não é membro de nenhuma aliança.")
	_add_separator()

	# ── RELAÇÕES (top 5 aliados / rivais) ──
	_add_section_title("RELAÇÕES BILATERAIS")
	var rels: Array = []
	for code in n.relacoes:
		rels.append({"code": code, "rel": float(n.relacoes[code])})
	rels.sort_custom(func(a, b): return a["rel"] > b["rel"])
	if rels.size() > 0:
		_add_subtitle("✅ Aliados")
		var aliados_count: int = 0
		for r in rels:
			if r["rel"] <= 0: break
			if aliados_count >= 5: break
			var nm: String = GameEngine.nations[r["code"]].nome if GameEngine.nations.has(r["code"]) else r["code"]
			_add_data_row(nm, "+%d" % int(r["rel"]), Color(0.4, 1, 0.6))
			aliados_count += 1
		_add_subtitle("⚠ Rivais")
		var rev = rels.duplicate()
		rev.reverse()
		var rivais_count: int = 0
		for r in rev:
			if r["rel"] >= 0: break
			if rivais_count >= 5: break
			var nm: String = GameEngine.nations[r["code"]].nome if GameEngine.nations.has(r["code"]) else r["code"]
			_add_data_row(nm, "%d" % int(r["rel"]), Color(1, 0.4, 0.4))
			rivais_count += 1
	else:
		_add_hint_label("Nenhuma relação registrada ainda.")
	_add_separator()
	_add_hint_label("💡 Selecione qualquer país no mapa para abrir ações diplomáticas (embaixada, sanções, propor tratados, declarar guerra, propor paz).")

func _render_proposal_card(prop: Dictionary) -> void:
	var meta = GameEngine.diplomacy.TIPOS_TRATADO.get(prop["type"], {})
	var proposer_name: String = GameEngine.nations[prop["proposer"]].nome if GameEngine.nations.has(prop["proposer"]) else prop["proposer"]
	var card := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var title := Label.new()
	title.text = "%s propõe: %s" % [proposer_name, meta.get("nome", prop["type"])]
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	title.add_theme_font_size_override("font_size", 12)
	v.add_child(title)
	var desc := Label.new()
	desc.text = meta.get("descricao", "")
	desc.add_theme_color_override("font_color", Color(0.7, 0.78, 0.88))
	desc.add_theme_font_size_override("font_size", 10)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc)
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	var btn_yes := Button.new()
	btn_yes.text = "✅ ACEITAR"
	btn_yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_yes.pressed.connect(func():
		GameEngine.player_accept_proposal(prop["id"])
		_render_panel(current_panel))
	btn_row.add_child(btn_yes)
	var btn_no := Button.new()
	btn_no.text = "❌ REJEITAR"
	btn_no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_no.pressed.connect(func():
		GameEngine.player_reject_proposal(prop["id"])
		_render_panel(current_panel))
	btn_row.add_child(btn_no)
	v.add_child(btn_row)
	panel_content.add_child(card)

func _add_hint_label(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(0.5, 0.65, 0.85))
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel_content.add_child(lbl)

# ─────────────────────────────────────────────────────────────────
# PAINEL: TECH
# ─────────────────────────────────────────────────────────────────

var _tech_filter: String = "ALL"

func _render_tech() -> void:
	var n = GameEngine.player_nation
	if n == null: return

	# 1) Pesquisa ativa
	_add_section_title("🔬 PESQUISA ATIVA")
	if GameEngine.tech and n.pesquisa_atual:
		var prog: Dictionary = GameEngine.tech.get_research_progress(n)
		_add_data_row("Tecnologia", str(prog.get("name", "—")), Color(0, 0.823, 1))
		_add_bar("Progresso", float(prog.get("pct", 0)), true, "%d/%d turnos" % [int(prog.get("progress", 0)), int(prog.get("total", 0))])
		var btn := Button.new()
		btn.text = "❌ CANCELAR PESQUISA"
		btn.custom_minimum_size = Vector2(0, 32)
		btn.pressed.connect(func():
			GameEngine.player_cancel_research()
			_render_panel("tech"))
		panel_content.add_child(btn)
	else:
		_add_hint_label("Nenhuma pesquisa em andamento.")
	_add_separator()

	# 2) Status compacto
	_add_section_title("📊 STATUS")
	_add_data_row("Concluídas", "%d techs" % n.tecnologias_concluidas.size())
	_add_data_row("Velocidade pesquisa", "%.1fx" % n.velocidade_pesquisa)
	_add_separator()

	# 3) Filtro de categoria
	_add_section_title("🗂 CATEGORIA")
	var cats: Array = ["ALL"]
	if GameEngine.tech:
		for c in GameEngine.tech.get_categories():
			cats.append(c)
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 4)
	for c in cats:
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_pressed = (c == _tech_filter)
		btn.text = "Todas" if c == "ALL" else str(c).substr(0, 5)
		btn.custom_minimum_size = Vector2(0, 28)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 10)
		btn.pressed.connect(func():
			_tech_filter = c
			_render_panel("tech"))
		filter_row.add_child(btn)
	panel_content.add_child(filter_row)
	_add_separator()

	# 4) Coleta techs filtradas
	var all_techs: Array = []
	if GameEngine.tech:
		if _tech_filter == "ALL":
			for c in GameEngine.tech.get_categories():
				for t in GameEngine.tech.get_techs_by_category(c):
					all_techs.append(t)
		else:
			all_techs = GameEngine.tech.get_techs_by_category(_tech_filter)

	# 5) Separa em 3 grupos: concluídas / disponíveis / bloqueadas
	var done: Array = []
	var available: Array = []
	var locked: Array = []
	for t in all_techs:
		if t["id"] in n.tecnologias_concluidas:
			done.append(t)
		else:
			var check: Dictionary = GameEngine.tech.can_research(n, t["id"])
			# Diferencia "pode pesquisar" de "bloqueada por pré-requisito/recurso"
			var reason: String = String(check.get("reason", ""))
			if check.get("ok", false):
				available.append(t)
			elif "Pré-requisito" in reason or "PIB mínimo" in reason or "Estabilidade" in reason:
				locked.append({"tech": t, "reason": reason})
			else:
				# "Custo" — disponível mas sem dinheiro agora
				available.append(t)
	# Ordena cada grupo por tier→custo
	var sort_fn := func(a, b):
		var ta = a["tech"] if a is Dictionary and a.has("tech") else a
		var tb = b["tech"] if b is Dictionary and b.has("tech") else b
		if int(ta.get("tier", 1)) != int(tb.get("tier", 1)):
			return int(ta.get("tier", 1)) < int(tb.get("tier", 1))
		return float(ta.get("custo", 0)) < float(tb.get("custo", 0))
	done.sort_custom(sort_fn)
	available.sort_custom(sort_fn)
	locked.sort_custom(sort_fn)

	# 6) Renderiza cada grupo

	# ✓ CONCLUÍDAS — bloco verde
	if done.size() > 0:
		_add_section_title("✓ CONCLUÍDAS (%d)" % done.size())
		for t in done.slice(0, 8):
			_render_tech_card_compact(t, "done")
		if done.size() > 8:
			_add_hint_label("  ...e mais %d técnica(s) já concluída(s)" % (done.size() - 8))
		_add_separator()

	# 🔬 DISPONÍVEIS PARA PESQUISA
	_add_section_title("🔬 DISPONÍVEIS (%d)" % available.size())
	if available.is_empty():
		_add_hint_label("Sem techs disponíveis nesta categoria. Cumpra pré-requisitos primeiro.")
	for t in available.slice(0, 12):
		_render_tech_card(n, t)

	# 🔒 BLOQUEADAS — só mostra top 6
	if locked.size() > 0:
		_add_separator()
		_add_section_title("🔒 BLOQUEADAS (%d)" % locked.size())
		for entry in locked.slice(0, 6):
			_render_tech_card_locked(entry["tech"], entry["reason"])
		if locked.size() > 6:
			_add_hint_label("  ...e mais %d bloqueada(s)" % (locked.size() - 6))

# Card compacto pra tech concluída ou bloqueada
func _render_tech_card_compact(tech: Dictionary, state: String) -> void:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	if state == "done":
		sb.bg_color = Color(0.05, 0.15, 0.10, 0.85)
		sb.border_color = Color(0.30, 0.85, 0.50, 0.7)
	else:
		sb.bg_color = Color(0.10, 0.10, 0.12, 0.85)
		sb.border_color = Color(0.4, 0.4, 0.45, 0.6)
	sb.set_border_width_all(1)
	sb.border_width_left = 3
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 10
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	card.add_child(v)
	var name_lbl := Label.new()
	name_lbl.text = "%s  •  T%d" % [tech.get("nome", "?"), int(tech.get("tier", 1))]
	name_lbl.add_theme_font_size_override("font_size", 11)
	if state == "done":
		name_lbl.add_theme_color_override("font_color", Color(0.4, 1, 0.55))
	else:
		name_lbl.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	v.add_child(name_lbl)
	panel_content.add_child(card)

# Card pra tech bloqueada (mostra motivo)
func _render_tech_card_locked(tech: Dictionary, reason: String) -> void:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.10, 0.85)
	sb.border_color = Color(0.4, 0.4, 0.45, 0.5)
	sb.set_border_width_all(1)
	sb.border_width_left = 3
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 10
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	card.add_child(v)
	var name_lbl := Label.new()
	name_lbl.text = "%s  •  T%d" % [tech.get("nome", "?"), int(tech.get("tier", 1))]
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	v.add_child(name_lbl)
	var reason_lbl := Label.new()
	reason_lbl.text = "🔒 " + reason
	reason_lbl.add_theme_font_size_override("font_size", 9)
	reason_lbl.add_theme_color_override("font_color", Color(0.85, 0.55, 0.45))
	reason_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(reason_lbl)
	panel_content.add_child(card)

func _render_tech_card(nation, tech: Dictionary) -> void:
	var card := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	card.add_child(v)
	# Nome + tier
	var head := HBoxContainer.new()
	var name_lbl := Label.new()
	name_lbl.text = tech.get("nome", "?")
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 12)
	var status_color := Color(1, 1, 1)
	if tech["id"] in nation.tecnologias_concluidas:
		status_color = Color(0.4, 1, 0.6)
	elif nation.pesquisa_atual and nation.pesquisa_atual.get("id", "") == tech["id"]:
		status_color = Color(1, 0.85, 0)
	name_lbl.add_theme_color_override("font_color", status_color)
	head.add_child(name_lbl)
	var tier_lbl := Label.new()
	tier_lbl.text = "T%d" % int(tech.get("tier", 1))
	tier_lbl.add_theme_color_override("font_color", Color(0.5, 0.65, 0.85))
	tier_lbl.add_theme_font_size_override("font_size", 10)
	head.add_child(tier_lbl)
	v.add_child(head)
	# Descrição curta
	var cat_lbl := Label.new()
	cat_lbl.text = "%s • $%dB • %d turnos" % [str(tech.get("categoria", "")), int(tech.get("custo", 0)), int(tech.get("tempo_turnos", 0))]
	cat_lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
	cat_lbl.add_theme_font_size_override("font_size", 10)
	v.add_child(cat_lbl)
	# Botão
	if tech["id"] in nation.tecnologias_concluidas:
		var done := Label.new()
		done.text = "✓ Concluída"
		done.add_theme_color_override("font_color", Color(0.4, 1, 0.6))
		done.add_theme_font_size_override("font_size", 10)
		v.add_child(done)
	else:
		var check: Dictionary = GameEngine.tech.can_research(nation, tech["id"])
		var btn := Button.new()
		if check.get("ok", false):
			btn.text = "🔬 PESQUISAR"
		else:
			btn.text = "🔒 " + check.get("reason", "Indisponível")
			btn.disabled = true
		btn.custom_minimum_size = Vector2(0, 28)
		btn.add_theme_font_size_override("font_size", 10)
		btn.pressed.connect(func():
			var res: Dictionary = GameEngine.player_start_research(tech["id"])
			if res.get("ok", false):
				_log_global_news("🔬 PESQUISA", "Iniciada: %s ($%dB)" % [tech.get("nome", ""), int(tech.get("custo", 0))], Color(0.7, 0.5, 1))
			_render_panel("tech")
			_refresh_top_bar_external())
		v.add_child(btn)
	panel_content.add_child(card)

# ─────────────────────────────────────────────────────────────────
# PAINEL: INTEL
# ─────────────────────────────────────────────────────────────────

func _render_intel() -> void:
	var n = GameEngine.player_nation
	if n == null: return
	_add_section_title("INTELIGÊNCIA")
	_add_data_row("Intel Score", "%.1f" % n.intel_score, Color(0, 0.823, 1))
	_add_data_row("Segurança Intel", "%.1f" % n.seguranca_intel, Color(0.4, 1, 0.6))
	_add_data_row("Operações realizadas", "%d" % n.spy_ops_log.size())
	_add_separator()
	_add_section_title("OPERAÇÕES DISPONÍVEIS")
	_add_hint_label("💡 Selecione um país no mapa primeiro, depois escolha a operação.")
	if GameEngine.espionage:
		for op_id in GameEngine.espionage.OPS:
			var op: Dictionary = GameEngine.espionage.OPS[op_id]
			var card := PanelContainer.new()
			var v := VBoxContainer.new()
			v.add_theme_constant_override("separation", 2)
			card.add_child(v)
			var head := Label.new()
			head.text = "%s %s — $%dB (%d%%)" % [op["icon"], op["nome"], int(op["custo"]), int(float(op["base_success"]) * 100)]
			head.add_theme_color_override("font_color", Color(0.85, 0.93, 1))
			head.add_theme_font_size_override("font_size", 11)
			v.add_child(head)
			var desc := Label.new()
			desc.text = op["descricao"]
			desc.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
			desc.add_theme_font_size_override("font_size", 10)
			desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(desc)
			panel_content.add_child(card)
	_add_separator()
	_add_section_title("ÚLTIMAS OPERAÇÕES")
	if n.spy_ops_log.is_empty():
		_add_hint_label("Nenhuma operação realizada ainda.")
	else:
		var recent: Array = n.spy_ops_log.slice(max(0, n.spy_ops_log.size() - 8))
		recent.reverse()
		for entry in recent:
			var icon := "✅" if entry.get("success", false) else "❌"
			var target_name: String = GameEngine.nations[entry["target"]].nome if GameEngine.nations.has(entry["target"]) else entry["target"]
			_add_data_row("T%d %s vs %s" % [int(entry["turn"]), entry["op"], target_name], icon)

# ─────────────────────────────────────────────────────────────────
# PAINEL: SITUAÇÃO
# ─────────────────────────────────────────────────────────────────

func _render_situacao() -> void:
	var n = GameEngine.player_nation
	if n == null: return
	_add_section_title("RANKINGS GLOBAIS")
	var by_pib: Array = []
	var by_mil: Array = []
	for code in GameEngine.nations:
		var nat = GameEngine.nations[code]
		by_pib.append({"code": code, "v": nat.pib_bilhoes_usd, "n": nat})
		by_mil.append({"code": code, "v": float(nat.militar.get("poder_militar_global", 0)), "n": nat})
	by_pib.sort_custom(func(a, b): return a["v"] > b["v"])
	by_mil.sort_custom(func(a, b): return a["v"] > b["v"])
	var pib_rank := 0
	var mil_rank := 0
	for i in by_pib.size():
		if by_pib[i]["code"] == n.codigo_iso: pib_rank = i + 1
	for i in by_mil.size():
		if by_mil[i]["code"] == n.codigo_iso: mil_rank = i + 1
	_add_data_row("Ranking PIB", "#%d / %d" % [pib_rank, by_pib.size()])
	_add_data_row("Ranking Militar", "#%d / %d" % [mil_rank, by_mil.size()])
	_add_separator()
	_add_section_title("TOP 5 ECONOMIAS")
	for i in range(min(5, by_pib.size())):
		var b = by_pib[i]
		var color := Color(1, 1, 1) if b["code"] != n.codigo_iso else Color(0, 1, 0.5)
		_add_data_row("#%d %s" % [i+1, b["n"].nome], _money(b["v"]), color)
	_add_separator()
	_add_section_title("TOP 5 PODERES MILITARES")
	for i in range(min(5, by_mil.size())):
		var b = by_mil[i]
		var color := Color(1, 1, 1) if b["code"] != n.codigo_iso else Color(0, 1, 0.5)
		_add_data_row("#%d %s" % [i+1, b["n"].nome], "%d" % int(b["v"]), color)

# ─────────────────────────────────────────────────────────────────
# PAINEL: HISTÓRICO
# ─────────────────────────────────────────────────────────────────

func _render_historico() -> void:
	var n = GameEngine.player_nation
	if n == null: return
	_add_section_title("LEGADO NACIONAL")
	var ach: Array = n.conquistas_historicas if n.conquistas_historicas else []
	if ach.is_empty():
		_add_hint_label("Nenhuma conquista histórica registrada.")
	else:
		for a in ach:
			var lbl := Label.new()
			lbl.text = "• " + str(a)
			lbl.add_theme_color_override("font_color", Color(0.85, 0.93, 1))
			lbl.add_theme_font_size_override("font_size", 11)
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			panel_content.add_child(lbl)
	_add_separator()
	var n_turns: int = n.historico["estabilidade"].size() if n.historico.has("estabilidade") else 0
	_add_section_title("HISTÓRICO DE INDICADORES (%d turnos)" % min(20, n_turns))
	for k in ["estabilidade", "apoio_popular", "felicidade", "corrupcao", "inflacao"]:
		if n.historico.has(k):
			var arr: Array = n.historico[k]
			if arr.size() > 0:
				_add_sparkline_row(k.capitalize(), arr, _color_for_metric(k))
	_add_separator()
	_add_section_title("ECONOMIA")
	for k in ["pib", "tesouro"]:
		if n.historico.has(k):
			var arr: Array = n.historico[k]
			if arr.size() > 0:
				_add_sparkline_row(k.capitalize(), arr, Color(0, 1, 0.5))

func _color_for_metric(k: String) -> Color:
	match k:
		"corrupcao", "inflacao": return Color(1, 0.4, 0.4)
		"estabilidade", "apoio_popular": return Color(0, 0.823, 1)
		"felicidade": return Color(0, 1, 0.5)
	return Color(0.7, 0.78, 0.88)

func _add_sparkline_row(label: String, values: Array, color: Color) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.custom_minimum_size = Vector2(110, 0)
	hbox.add_child(lbl)
	# Spark = Control que desenha
	var spark := SparklineWidget.new()
	spark.values = values
	spark.line_color = color
	spark.custom_minimum_size = Vector2(120, 28)
	spark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spark)
	# Valor atual
	var v_lbl := Label.new()
	v_lbl.text = "%.1f" % float(values[values.size() - 1])
	v_lbl.add_theme_color_override("font_color", color)
	v_lbl.add_theme_font_size_override("font_size", 11)
	v_lbl.custom_minimum_size = Vector2(40, 0)
	hbox.add_child(v_lbl)
	panel_content.add_child(hbox)

# Widget interno para sparkline
class SparklineWidget extends Control:
	var values: Array = []
	var line_color: Color = Color(0, 0.823, 1)
	func _draw() -> void:
		if values.size() < 2: return
		var w: float = size.x
		var h: float = size.y
		var min_v: float = 1e9
		var max_v: float = -1e9
		for v in values:
			var f: float = float(v)
			min_v = min(min_v, f)
			max_v = max(max_v, f)
		var range_v: float = max(0.001, max_v - min_v)
		var pts := PackedVector2Array()
		for i in values.size():
			var x: float = (float(i) / float(values.size() - 1)) * w
			var y: float = h - (float(values[i]) - min_v) / range_v * h
			pts.append(Vector2(x, y))
		# Linha de fundo (zero)
		draw_rect(Rect2(0, 0, w, h), Color(0.05, 0.07, 0.10), true)
		# Linha do gráfico
		for i in range(pts.size() - 1):
			draw_line(pts[i], pts[i + 1], line_color, 1.5, true)
		# Pontinho final
		draw_circle(pts[pts.size() - 1], 2.5, line_color)

# ─────────────────────────────────────────────────────────────────
# PAINEL: NOTÍCIAS
# ─────────────────────────────────────────────────────────────────

func _render_noticias() -> void:
	_add_section_title("FEED DE INTELIGÊNCIA")
	var lbl := Label.new()
	lbl.text = "Eventos do mundo aparecem no rodapé (ticker). Painel dedicado virá na próxima atualização com filtros por categoria."
	lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel_content.add_child(lbl)

# ─────────────────────────────────────────────────────────────────
# HELPERS DE UI
# ─────────────────────────────────────────────────────────────────

func _add_section_title(text: String) -> void:
	var lbl := Label.new()
	lbl.text = "■ " + text
	lbl.add_theme_color_override("font_color", Color(0, 0.823, 1))
	lbl.add_theme_font_size_override("font_size", 11)
	panel_content.add_child(lbl)

func _add_subtitle(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(0.5, 0.65, 0.85))
	lbl.add_theme_font_size_override("font_size", 10)
	panel_content.add_child(lbl)

func _add_separator() -> void:
	var sep := HSeparator.new()
	panel_content.add_child(sep)

func _add_data_row(key: String, value: String, color: Color = Color(1, 1, 1)) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	var k := Label.new()
	k.text = key
	k.add_theme_color_override("font_color", Color(0.5, 0.65, 0.85))
	k.add_theme_font_size_override("font_size", 11)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(k)
	var v := Label.new()
	v.text = value
	v.add_theme_color_override("font_color", color)
	v.add_theme_font_size_override("font_size", 11)
	hbox.add_child(v)
	panel_content.add_child(hbox)

func _add_bar(label: String, value: float, higher_is_better: bool, override_text: String = "") -> void:
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_color_override("font_color", Color(0.65, 0.74, 0.85))
	lbl.add_theme_font_size_override("font_size", 10)
	panel_content.add_child(lbl)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.max_value = 100.0
	bar.value = value
	if override_text != "":
		bar.show_percentage = false
	var col: Color
	if higher_is_better:
		if value >= 65:   col = Color(0.20, 0.95, 0.55)
		elif value >= 35: col = Color(1.0, 0.72, 0.18)
		else:              col = Color(1.0, 0.35, 0.35)
	else:
		if value >= 65:   col = Color(1.0, 0.35, 0.35)
		elif value >= 35: col = Color(1.0, 0.72, 0.18)
		else:              col = Color(0.20, 0.95, 0.55)
	# Background com cantos arredondados (combina com o tema)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.025, 0.045, 0.07, 1)
	bg.border_color = Color(0.10, 0.16, 0.22, 1)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(7)
	bar.add_theme_stylebox_override("background", bg)
	# Fill com glow proporcional à cor
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(7)
	fill.shadow_color = Color(col.r, col.g, col.b, 0.45)
	fill.shadow_size = 4
	bar.add_theme_stylebox_override("fill", fill)
	panel_content.add_child(bar)
	if override_text != "":
		var ot := Label.new()
		ot.text = override_text
		ot.add_theme_color_override("font_color", col)
		ot.add_theme_font_size_override("font_size", 10)
		ot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		panel_content.add_child(ot)

func _add_action_button(_action_id: String, label: String, cost: int, desc: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 56)
	btn.text = "%s   $%dB\n%s" % [label, cost, desc]
	btn.add_theme_font_size_override("font_size", 11)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.clip_text = true
	# Estilo: bordas/margens SIMÉTRICAS pra hitbox bater com visual
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.075, 0.115, 0.9)
	sb.border_color = Color(0.0, 0.55, 0.78, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	var sb_h := sb.duplicate() as StyleBoxFlat
	sb_h.bg_color = Color(0.0, 0.40, 0.60, 0.85)
	sb_h.border_color = Color(0.0, 0.95, 1, 1)
	var sb_p := sb.duplicate() as StyleBoxFlat
	sb_p.bg_color = Color(0.0, 0.30, 0.48, 0.95)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb_h)
	btn.add_theme_stylebox_override("pressed", sb_p)
	btn.add_theme_stylebox_override("focus", sb_h)
	btn.add_theme_color_override("font_color", Color(0.92, 0.96, 1))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	btn.pressed.connect(callback)
	panel_content.add_child(btn)

func _money(value: float) -> String:
	if abs(value) >= 1000.0:
		return "$%.2fT" % (value / 1000.0)
	return "$%dB" % int(value)

func _fmt_thousands(value) -> String:
	var n: int = int(value)
	if n >= 1_000_000_000:
		return "%.2fB" % (n / 1_000_000_000.0)
	if n >= 1_000_000:
		return "%.1fM" % (n / 1_000_000.0)
	if n >= 1_000:
		return "%.1fK" % (n / 1_000.0)
	return str(n)

func _refresh_top_bar_external() -> void:
	# Pede ao WorldMap (parent do parent) pra atualizar top bar
	var wm = get_node_or_null("/root/WorldMap")
	if wm and wm.has_method("_refresh_top_bar"):
		wm._refresh_top_bar()

func _log_global_news(title: String, body: String, color: Color = Color(0.7, 0.8, 1)) -> void:
	# Adiciona ao ticker do WorldMap
	var wm = get_node_or_null("/root/WorldMap")
	if wm and wm.has_method("_log_ticker"):
		wm._log_ticker(title, body, color)

# ─────────────────────────────────────────────────────────────────
# ENDGAME + MODAL DE EVENTO
# ─────────────────────────────────────────────────────────────────

# A lógica de vitória/derrota vive no GameEngine (evaluate_endgame).
# A UI apenas escuta o sinal e apresenta o modal.
func _on_endgame_reached(result: Dictionary) -> void:
	_show_endgame(String(result.get("title", "")), String(result.get("msg", "")), bool(result.get("victory", false)))

func _show_endgame(title: String, msg: String, victory: bool) -> void:
	if endgame_triggered: return
	if get_node_or_null("/root/EndgameOverlay") != null:
		return
	endgame_triggered = true
	# Pausa o jogo
	get_tree().paused = false  # reseta caso houvesse
	# Concede XP de meta-progressão (persiste entre saves)
	var xp_earned: int = 0
	if GameEngine.meta_progression:
		var n_ref = GameEngine.player_nation
		var stats_payload := {
			"victory": victory,
			"turns_played": GameEngine.current_turn,
			"tier": String(n_ref.tier_dificuldade) if n_ref and "tier_dificuldade" in n_ref else "NORMAL",
			"tech_count": n_ref.tecnologias_concluidas.size() if n_ref else 0,
			"decisions": GameEngine.timeline.decision_log.size() if GameEngine.timeline else 0,
		}
		xp_earned = GameEngine.meta_progression.award_end_game_xp(stats_payload)
	var modal := ColorRect.new()
	modal.name = "EndgameOverlay"
	modal.color = Color(0, 0, 0, 0.94)
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	get_tree().root.add_child(modal)
	# Fade-in cinematográfico — cor já está no ColorRect, modula sobre o card
	modal.modulate = Color(1, 1, 1, 0)
	var tw_fade := create_tween()
	tw_fade.tween_property(modal, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_CUBIC)
	# Card central com tema visual diferente pra vitória vs derrota
	var box := PanelContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(640, 480)
	box.position = Vector2(-320, -240)
	var sb := StyleBoxFlat.new()
	if victory:
		sb.bg_color = Color(0.05, 0.10, 0.05, 0.99)
		sb.border_color = Color(1, 0.85, 0.2, 1)  # dourado vitória
	else:
		sb.bg_color = Color(0.10, 0.04, 0.04, 0.99)
		sb.border_color = Color(1, 0.3, 0.3, 1)  # vermelho derrota
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 32
	sb.content_margin_right = 32
	sb.content_margin_top = 28
	sb.content_margin_bottom = 28
	box.add_theme_stylebox_override("panel", sb)
	modal.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	box.add_child(v)
	# Badge — vitória recebe título conferido pelo sumário da campanha
	var badge := Label.new()
	if victory:
		var n_b = GameEngine.player_nation
		var earned_title: String = _compute_legacy_title(n_b)
		badge.text = "★ %s ★" % earned_title
	else:
		badge.text = "✕ FIM DE GOVERNO"
	badge.add_theme_color_override("font_color", Color(1, 0.85, 0.2) if victory else Color(1, 0.4, 0.4))
	badge.add_theme_font_size_override("font_size", 13)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(badge)
	# Título grande
	var t := Label.new()
	t.text = title
	t.add_theme_color_override("font_color", Color(1, 1, 1))
	t.add_theme_font_size_override("font_size", 32)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	# Linha decorativa
	var deco := ColorRect.new()
	deco.color = Color(1, 0.85, 0.2, 0.6) if victory else Color(1, 0.4, 0.4, 0.6)
	deco.custom_minimum_size = Vector2(120, 2)
	deco.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(deco)
	# Mensagem
	var m := Label.new()
	m.text = msg
	m.add_theme_color_override("font_color", Color(0.85, 0.93, 1))
	m.add_theme_font_size_override("font_size", 13)
	m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(m)
	# Seção "Legado" — só pra vitória, com narrativa contextualizada
	if victory:
		v.add_child(HSeparator.new())
		var legacy_title := Label.new()
		legacy_title.text = "🏛 SEU LEGADO"
		legacy_title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
		legacy_title.add_theme_font_size_override("font_size", 11)
		legacy_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(legacy_title)
		var legacy_text := Label.new()
		legacy_text.text = _compute_legacy_narrative(GameEngine.player_nation)
		legacy_text.add_theme_color_override("font_color", Color(0.92, 0.95, 0.8))
		legacy_text.add_theme_font_size_override("font_size", 12)
		legacy_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		legacy_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(legacy_text)
	# Estatísticas finais
	v.add_child(HSeparator.new())
	var stats_title := Label.new()
	stats_title.text = "📊 SUMÁRIO DA CAMPANHA"
	stats_title.add_theme_color_override("font_color", Color(0.5, 0.7, 0.95))
	stats_title.add_theme_font_size_override("font_size", 11)
	stats_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(stats_title)
	var n = GameEngine.player_nation
	if n != null:
		var stats_grid := GridContainer.new()
		stats_grid.columns = 2
		stats_grid.add_theme_constant_override("h_separation", 24)
		stats_grid.add_theme_constant_override("v_separation", 4)
		stats_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var stats := [
			["Nação", n.nome],
			["Turnos jogados", "%d" % GameEngine.current_turn],
			["Período", "2000 - %d" % GameEngine.date_year],
			["PIB final", "$%dB" % int(n.pib_bilhoes_usd)],
			["Tesouro final", "$%dB" % int(n.tesouro)],
			["Apoio popular", "%d%%" % int(n.apoio_popular)],
			["Estabilidade", "%d%%" % int(n.estabilidade_politica)],
			["Tecnologias", "%d concluídas" % n.tecnologias_concluidas.size()],
		]
		var hist_count: int = 0
		if GameEngine.timeline:
			hist_count = GameEngine.timeline.decision_log.size()
		stats.append(["Decisões históricas", "%d" % hist_count])
		if xp_earned > 0:
			stats.append(["⭐ XP ganho", "+%d (total: %d)" % [xp_earned, GameEngine.meta_progression.total_xp if GameEngine.meta_progression else 0]])
		for pair in stats:
			var k := Label.new()
			k.text = String(pair[0])
			k.add_theme_color_override("font_color", Color(0.55, 0.65, 0.78))
			k.add_theme_font_size_override("font_size", 11)
			stats_grid.add_child(k)
			var val := Label.new()
			val.text = String(pair[1])
			val.add_theme_color_override("font_color", Color(0.95, 1, 1))
			val.add_theme_font_size_override("font_size", 12)
			val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			stats_grid.add_child(val)
		v.add_child(stats_grid)
	v.add_child(HSeparator.new())
	# Botões
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	v.add_child(btn_row)
	# Vitória oferece "Continuar Livre" + "Nova Campanha" (NG+ com XP acumulado)
	if victory:
		var btn_continue := Button.new()
		btn_continue.text = "▶ CONTINUAR LIVRE"
		btn_continue.custom_minimum_size = Vector2(200, 44)
		btn_continue.pressed.connect(func():
			modal.queue_free()
			endgame_triggered = false
			GameEngine.resume_after_endgame())
		btn_row.add_child(btn_continue)
		var btn_newgame := Button.new()
		btn_newgame.text = "🔄 NOVA CAMPANHA"
		btn_newgame.custom_minimum_size = Vector2(200, 44)
		btn_newgame.pressed.connect(func():
			SaveSystem.delete_save()
			_transition_to_scene(modal, "res://scenes/MainMenu.tscn"))
		btn_row.add_child(btn_newgame)
	var btn_menu := Button.new()
	btn_menu.text = "🏠 MENU PRINCIPAL"
	btn_menu.custom_minimum_size = Vector2(200, 44)
	btn_menu.pressed.connect(func():
		_transition_to_scene(modal, "res://scenes/MainMenu.tscn"))
	btn_row.add_child(btn_menu)

# Transição com fade-out do modal + change_scene
func _transition_to_scene(modal: Node, scene_path: String) -> void:
	if modal != null and is_instance_valid(modal):
		var tw := create_tween()
		tw.tween_property(modal, "modulate:a", 0.0, 0.18)
		tw.tween_callback(func():
			if is_instance_valid(modal): modal.queue_free()
			get_tree().change_scene_to_file(scene_path))
	else:
		get_tree().change_scene_to_file(scene_path)

# Título conferido na vitória, baseado em qual estatística mais se destacou.
# Usa thresholds escaláveis em vez de checagem fixa pra dar variedade.
func _compute_legacy_title(n) -> String:
	if n == null: return "VITÓRIA HISTÓRICA"
	var pib_base: float = float(n.pib_inicial) if n.pib_inicial > 0 else float(n.pib_bilhoes_usd)
	var pib_growth: float = float(n.pib_bilhoes_usd) / max(1.0, pib_base)
	var techs: int = n.tecnologias_concluidas.size() if n.tecnologias_concluidas else 0
	var apoio: float = float(n.apoio_popular)
	var corrupcao: float = float(n.corrupcao)
	var hist_decisions: int = GameEngine.timeline.decision_log.size() if GameEngine.timeline else 0
	var wars: int = n.em_guerra.size() if n.em_guerra else 0
	# Decide título por categoria dominante
	if pib_growth >= 3.0:
		return "ARQUITETO DA PROSPERIDADE"
	if techs >= 12:
		return "VISIONÁRIO TECNOLÓGICO"
	if apoio >= 75 and corrupcao <= 25:
		return "LÍDER QUERIDO DO POVO"
	if wars == 0 and hist_decisions >= 8:
		return "PACIFICADOR HISTÓRICO"
	if corrupcao <= 15:
		return "GUARDIÃO DA RES PUBLICA"
	if hist_decisions >= 12:
		return "ESTADISTA DECISIVO"
	return "VITÓRIA HISTÓRICA"

# Narrativa de 2-3 linhas que muda conforme perfil da partida
func _compute_legacy_narrative(n) -> String:
	if n == null: return ""
	var leader: String = String(n.get_meta("leader_name", "O líder"))
	var nome: String = n.nome
	var pib_base: float = float(n.pib_inicial) if n.pib_inicial > 0 else 1.0
	var pib_growth: float = float(n.pib_bilhoes_usd) / max(1.0, pib_base)
	var techs: int = n.tecnologias_concluidas.size() if n.tecnologias_concluidas else 0
	var hist_decisions: int = GameEngine.timeline.decision_log.size() if GameEngine.timeline else 0
	var lines: Array = []
	lines.append("%s liderou %s por %d turnos." % [leader, nome, GameEngine.current_turn])
	if pib_growth >= 2.0:
		lines.append("A economia cresceu %dx — uma transformação histórica." % int(pib_growth))
	elif pib_growth >= 1.3:
		lines.append("A economia se expandiu de forma sustentável.")
	if techs >= 8:
		lines.append("%d tecnologias-chave foram desbloqueadas, redefinindo a fronteira da inovação." % techs)
	if hist_decisions >= 5:
		lines.append("Em %d momentos críticos da história, suas decisões marcaram o século." % hist_decisions)
	lines.append("Os historiadores da Olimpia registrarão esta linha temporal.")
	return "\n".join(lines)

func _show_event_modal(event: Dictionary) -> void:
	var modal := ColorRect.new()
	modal.color = Color(0, 0, 0, 0.85)
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(modal)  # filho do GameOverlay (não da root → limpa em scene change)
	var box := PanelContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(560, 360)
	box.position = Vector2(-280, -180)
	modal.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	box.add_child(v)
	var cap := Label.new()
	cap.text = "⚡ EVENTO CRÍTICO"
	cap.add_theme_color_override("font_color", Color(0, 0.823, 1))
	cap.add_theme_font_size_override("font_size", 11)
	v.add_child(cap)
	var title := Label.new()
	title.text = event.get("nome", "Evento")
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	title.add_theme_font_size_override("font_size", 20)
	v.add_child(title)
	var desc := Label.new()
	desc.text = event.get("descricao", "")
	desc.add_theme_color_override("font_color", Color(0.78, 0.85, 0.95))
	desc.add_theme_font_size_override("font_size", 12)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc)
	v.add_child(HSeparator.new())
	var choices: Array = event.get("choices", [])
	for i in choices.size():
		var c: Dictionary = choices[i]
		var btn := Button.new()
		var label_text: String = c.get("label", c.get("texto", "Opção %d" % (i+1)))
		var efeitos: Dictionary = c.get("efeitos", {})
		var ef_str := ""
		for k in efeitos:
			var val = efeitos[k]
			var prefix := "+" if (typeof(val) == TYPE_INT or typeof(val) == TYPE_FLOAT) and float(val) > 0 else ""
			ef_str += "  •  %s: %s%s" % [k, prefix, str(val)]
		btn.text = "%s\n%s" % [label_text, ef_str]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 50)
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(func():
			GameEngine.apply_event_choice(event, i)
			modal.queue_free()
			_render_panel(current_panel))
		v.add_child(btn)
