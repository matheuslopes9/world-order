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
		"gabinete":   _render_gabinete()
		"governo":    _render_governo()
		"militar":    _render_militar()
		"seguranca":  _render_militar()   # Justiça & Segurança usa o painel militar (defesa+segurança)
		"economia":   _render_economia()
		"saude":      _render_saude()
		"educacao":   _render_educacao()
		"diplomacia": _render_diplomacia()
		"tech":       _render_tech()
		"intel":      _render_intel()
		"situacao":   _render_situacao()
		"historico":  _render_historico()
		"noticias":   _render_noticias()

# ─────────────────────────────────────────────────────────────────
# PAINEL: GOVERNO
# ─────────────────────────────────────────────────────────────────

## PAINEL GABINETE — hub central: os 6 ministros com nível, XP e pesquisa.
func _render_gabinete() -> void:
	var n = GameEngine.player_nation
	if n == null: return
	var snap: Array = GameEngine.get_cabinet_snapshot()
	_add_advisor_header("presidente", "GABINETE PRESIDENCIAL",
		"Seu governo, Presidente. Cada ministério cresce com investimento — e mais ministérios pesquisam em paralelo.",
		"neutro", Color(0.4, 0.8, 1))
	_add_section_title("MINISTÉRIOS (%d trilhas de pesquisa simultâneas)" % n.research_slots())
	for m in snap:
		_add_minister_card(m)
	_add_separator()
	_add_hint_label("💡 Clique num ministério na barra inferior para agir nele. Suba o nível da Casa Civil para liberar mais trilhas de pesquisa paralelas.")

## Card de um ministro no hub: retrato + nível + barra XP + pesquisa ativa.
func _add_minister_card(m: Dictionary) -> void:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.12, 0.17, 0.92)
	sb.border_width_left = 3
	sb.border_color = Color(0.3, 0.6, 0.85)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8; sb.content_margin_right = 8
	sb.content_margin_top = 7; sb.content_margin_bottom = 7
	box.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var pv := PortraitView.make(GameEngine.player_nation.codigo_iso, String(m["role"]), "neutro", 52.0)
	pv.custom_minimum_size = Vector2(52, 62)
	pv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pv)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var title := Label.new()
	title.text = "%s %s" % [m["icon"], m["nome"]]
	title.add_theme_color_override("font_color", Color(0.9, 0.95, 1))
	title.add_theme_font_size_override("font_size", 12)
	col.add_child(title)
	# nível + estrelas
	var nv: int = int(m["nivel"])
	var stars := "★".repeat(nv) + "☆".repeat(5 - nv)
	var lvl := Label.new()
	lvl.text = "Nível %d  %s" % [nv, stars]
	lvl.add_theme_color_override("font_color", Color(1, 0.82, 0.3))
	lvl.add_theme_font_size_override("font_size", 10)
	col.add_child(lvl)
	# barra de XP
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 8)
	bar.max_value = 100.0
	bar.value = float(m["xp_pct"])
	bar.show_percentage = false
	col.add_child(bar)
	# trilha de pesquisa ativa (se houver)
	var pesq: Dictionary = m.get("pesquisa", {})
	var info := Label.new()
	if not pesq.is_empty():
		info.text = "🔬 %s (%d%%)" % [pesq.get("name", "?"), int(pesq.get("pct", 0))]
		info.add_theme_color_override("font_color", Color(0.5, 0.85, 1))
	else:
		var vb: float = float(m.get("verba", 0.0))
		info.text = "P&D: $%dB/ano" % int(vb) if vb > 0 else "sem pesquisa ativa"
		info.add_theme_color_override("font_color", Color(0.6, 0.7, 0.82))
	info.add_theme_font_size_override("font_size", 10)
	col.add_child(info)
	panel_content.add_child(box)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 5)
	panel_content.add_child(sp)

## PAINEL SAÚDE — Ministro reage à felicidade/população.
func _render_saude() -> void:
	var n = GameEngine.player_nation
	if n == null: return
	var lvl: int = n.ministry_level("saude")
	var fala: String
	var expr: String
	if n.felicidade < 40.0:
		fala = "A população sofre, Presidente. Precisamos de hospitais e vacinas já."
		expr = "preocupado"
	else:
		fala = "O SUS vai bem. Com mais verba, alcançamos cada cidadão."
		expr = "feliz" if n.felicidade > 65.0 else "neutro"
	_add_advisor_header("saude", "MIN. DA SAÚDE  ·  Nível %d" % lvl, fala, expr, Color(0.5, 0.85, 0.9))
	_add_section_title("INDICADORES DE SAÚDE")
	_add_bar("Felicidade", n.felicidade, true)
	_add_data_row("População", _fmt_thousands(n.populacao))
	_add_data_row("Gasto em saúde", "$%dB" % int(n.gasto_social.get("saude", 0)))
	_add_ministry_rd_controls("saude")
	_add_separator()
	_add_section_title("AÇÕES DE SAÚDE")
	for a in GameEngine.get_panel_actions("saude"):
		_add_action_button(a.id, a.label, a.cost, a.desc, _run_panel_action.bind(a.id, "saude", Color(0.5, 0.9, 0.8)))

## PAINEL EDUCAÇÃO — Ministro puxa a ciência.
func _render_educacao() -> void:
	var n = GameEngine.player_nation
	if n == null: return
	var lvl: int = n.ministry_level("educacao")
	var fala: String = "Educação é o motor da nação, Presidente. Cada real investido volta em ciência."
	var expr: String = "feliz" if n.velocidade_pesquisa > 1.3 else "neutro"
	_add_advisor_header("educacao", "MIN. DA EDUCAÇÃO  ·  Nível %d" % lvl, fala, expr, Color(0.5, 0.65, 0.95))
	_add_section_title("INDICADORES DE ENSINO")
	_add_data_row("Velocidade de pesquisa", "%.2f×" % n.velocidade_pesquisa, Color(0.5, 0.85, 1))
	_add_data_row("Techs concluídas", "%d de %d" % [n.tecnologias_concluidas.size(), GameEngine.tech.tech_index.size() if GameEngine.tech else 0])
	_add_data_row("Gasto em educação", "$%dB" % int(n.gasto_social.get("educacao", 0)))
	_add_ministry_rd_controls("educacao")
	_add_separator()
	_add_section_title("AÇÕES DE EDUCAÇÃO")
	for a in GameEngine.get_panel_actions("educacao"):
		_add_action_button(a.id, a.label, a.cost, a.desc, _run_panel_action.bind(a.id, "educacao", Color(0.5, 0.7, 1)))
	_add_separator()
	_add_hint_label("🔬 A pesquisa científica de cada ministério é gerida na aba Tech — cada pasta pesquisa a sua trilha em paralelo.")

## Controle de verba de P&D de um ministério (+/- ajusta a alocação anual).
func _add_ministry_rd_controls(pasta: String) -> void:
	var n = GameEngine.player_nation
	var atual: float = float(n.ministerios.get(pasta, {}).get("verba", 0.0))
	var step: float = max(5.0, n.pib_bilhoes_usd * 0.003)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = "Verba de P&D: $%dB/ano" % int(atual)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1))
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var minus := Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(34, 28)
	minus.pressed.connect(func():
		GameEngine.player_alloc_rd(pasta, maxf(0.0, atual - step))
		_render_panel(_current_panel_for(pasta)))
	row.add_child(minus)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(34, 28)
	plus.pressed.connect(func():
		GameEngine.player_alloc_rd(pasta, atual + step)
		_render_panel(_current_panel_for(pasta)))
	row.add_child(plus)
	panel_content.add_child(row)

func _current_panel_for(pasta: String) -> String:
	match pasta:
		"saude": return "saude"
		"educacao": return "educacao"
		"fazenda": return "economia"
		"seguranca": return "seguranca"
		_: return "gabinete"

func _render_governo() -> void:
	var n = GameEngine.player_nation
	if n == null: return
	# Casa Civil coordena — o "chefe de gabinete"
	_add_advisor_header("casa_civil", "MIN. CHEFE DA CASA CIVIL  ·  Nível %d" % n.ministry_level("casa_civil"),
		"Coordeno o governo, Presidente. Mais investimento aqui libera trilhas de pesquisa em paralelo.",
		"neutro", Color(0.6, 0.7, 0.85))
	_add_ministry_rd_controls("casa_civil")
	_add_separator()
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
		_spawn_action_floater("✕ " + String(res.get("reason", "indisponível")), Color(1, 0.55, 0.45))
		return
	_log_global_news(action_id.replace("_", " ").to_upper(),
		String(res.get("msg", "")) + "  •  -$%dB" % int(res.get("cost", 0)), color)
	var fb: String = String(res.get("msg", ""))
	if fb.length() > 42:
		fb = "Executado"
	_spawn_action_floater("✓ %s  −$%dB" % [fb, int(res.get("cost", 0))], color)
	_render_panel(panel_id)
	_refresh_top_bar_external()

# Feedback visual leve: label flutuante que sobe do ponto do clique e some.
# 1 Label + 1 tween one-shot — sem partículas pesadas, sem poluição.
func _spawn_action_floater(text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.z_index = 300
	lbl.top_level = true  # posição global, ignora o layout do painel
	add_child(lbl)
	lbl.global_position = get_global_mouse_position() + Vector2(14, -8)
	var tw := lbl.create_tween().set_parallel()
	tw.tween_property(lbl, "global_position:y", lbl.global_position.y - 44.0, 0.9) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.9) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(lbl.queue_free)

# ─────────────────────────────────────────────────────────────────
# PAINEL: MILITAR
# ─────────────────────────────────────────────────────────────────

func _render_militar() -> void:
	var n = GameEngine.player_nation
	if n == null: return
	var lvl: int = n.ministry_level("seguranca")
	# Min. da Justiça & Segurança comanda defesa + segurança interna + intel
	var em_guerra: bool = n.em_guerra.size() > 0
	var g_fala: String
	var g_expr: String
	if em_guerra:
		g_fala = "Estamos em %d frente(s), Presidente. Preciso de orçamento para vencer." % n.em_guerra.size()
		g_expr = "bravo"
	elif n.corrupcao > 50.0:
		g_fala = "A corrupção mina a nação por dentro. Reforma judicial, urgente."
		g_expr = "preocupado"
	elif int(n.militar.get("poder_militar_global", 0)) < 80:
		g_fala = "Nossas forças estão defasadas. Investir agora evita humilhação depois."
		g_expr = "preocupado"
	else:
		g_fala = "Ordem interna e forças prontas, Presidente. Aguardo suas ordens."
		g_expr = "neutro"
	_add_advisor_header("seguranca", "MIN. DA JUSTIÇA & SEGURANÇA  ·  Nível %d" % lvl, g_fala, g_expr, Color(0.55, 0.62, 0.72))
	_add_section_title("SEGURANÇA INTERNA")
	_add_bar("Estabilidade", n.estabilidade_politica, true)
	_add_bar("Corrupção", n.corrupcao, false)
	_add_data_row("Intel Score", "%.0f" % n.intel_score, Color(0, 0.823, 1))
	_add_data_row("Segurança Intel", "%.0f" % n.seguranca_intel, Color(0.4, 1, 0.6))
	_add_separator()
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
	_add_section_title("AÇÕES DE JUSTIÇA & SEGURANÇA")
	for a in GameEngine.get_panel_actions("seguranca"):
		_add_action_button(a.id, a.label, a.cost, a.desc, _run_panel_action.bind(a.id, "seguranca", Color(0.6, 0.7, 0.9)))
	_add_separator()
	_add_hint_label("🕵 Operações de espionagem ficam na aba Intel — o mesmo ministério as comanda.")

# ─────────────────────────────────────────────────────────────────
# PAINEL: ECONOMIA
# ─────────────────────────────────────────────────────────────────

# Nomes amigáveis dos setores de comércio.
const SETOR_NOMES := {"energia": "energia", "alimentos": "alimentos", "industriais": "industriais", "materias_primas": "matérias-primas"}
func _setor_nome(setor: String) -> String:
	return SETOR_NOMES.get(setor, setor)

# Top setores de um dict de comércio (ordenados por valor), nomes amigáveis.
func _top_setores(d: Dictionary, limite: int = 3) -> Array:
	var pares: Array = []
	for k in d:
		pares.append([k, float(d[k])])
	pares.sort_custom(func(a, b): return a[1] > b[1])
	var out: Array = []
	for i in min(limite, pares.size()):
		if pares[i][1] > 0.1:
			out.append(_setor_nome(String(pares[i][0])))
	return out

func _render_economia() -> void:
	var n = GameEngine.player_nation
	if n == null: return
	# Ministra(o) da Economia reage à saúde fiscal
	var m_fala: String
	var m_expr: String
	if n.tesouro <= 0.0:
		m_fala = "O cofre está vazio, Presidente. Sem receita nova, o FMI vai bater à porta."
		m_expr = "urgente"
	elif n.inflacao > 25.0:
		m_fala = "A inflação em %.0f%% corrói o poder de compra. Aperto monetário, urgente." % n.inflacao
		m_expr = "preocupado"
	elif not GameEngine.active_shock.is_empty():
		m_fala = "A crise global pressiona os mercados. Vamos navegar com cautela."
		m_expr = "preocupado"
	else:
		m_fala = "As contas fecham, Presidente. Podemos pensar em investir no futuro."
		m_expr = "feliz" if n.tesouro > n.pib_bilhoes_usd * 0.1 else "neutro"
	_add_advisor_header("economia", "MIN. DA FAZENDA  ·  Nível %d" % n.ministry_level("fazenda"), m_fala, m_expr, Color(0.9, 0.55, 0.65))
	_add_ministry_rd_controls("fazenda")
	_add_separator()
	_add_section_title("INDICADORES ECONÔMICOS")
	_add_data_row("PIB Anual", _money(n.pib_bilhoes_usd))
	_add_data_row("Tesouro", _money(n.tesouro))
	_add_data_row("Dívida Pública", _money(n.divida_publica))
	_add_data_row("Inflação", "%.1f%%" % n.inflacao)
	_add_data_row("População", _fmt_thousands(n.populacao))
	# Confiança do investidor / IED — o elo corrupção → empresas → PIB
	var conf: float = n.confianca_investidor
	var conf_cor := Color(0.4, 1, 0.6) if conf >= 55.0 else (Color(1, 0.5, 0.4) if conf < 35.0 else Color(1, 0.82, 0.3))
	var conf_tag := "atrai capital ↗" if conf >= 55.0 else ("ÊXODO de empresas ↘" if conf < 35.0 else "estável")
	_add_data_row("🏢 Confiança do Investidor", "%d%%  (%s)" % [int(conf), conf_tag], conf_cor)
	if n.empresas_sairam > 0:
		_add_data_row("  └ empresas que deixaram o país", "%d" % n.empresas_sairam, Color(1, 0.55, 0.4))
	if n.tesouro_desviado_total > 0.5:
		_add_data_row("  └ 💸 desviado pela corrupção", _money(n.tesouro_desviado_total), Color(1, 0.45, 0.4))
	if n.corrupcao >= 50.0:
		_add_hint_label("⚠ Corrupção em %d%%: parte do tesouro é desviada todo turno e empresas fogem. Combata-a na Casa Civil ou com Reforma Judicial." % int(n.corrupcao))
	var receita: float = n.calc_receita() if n.has_method("calc_receita") else 0.0
	var despesas: float = n.calc_despesas() if n.has_method("calc_despesas") else 0.0
	var exportacao: float = n.calc_receita_exportacao() if n.has_method("calc_receita_exportacao") else 0.0
	# Choque global ativo: banner de alerta com contagem regressiva
	if not GameEngine.active_shock.is_empty():
		var sh: Dictionary = GameEngine.active_shock
		_add_data_row("%s CHOQUE GLOBAL" % sh.get("icon", "⚠"),
			"%s — %d turnos restantes" % [sh.get("nome", "?"), int(sh.get("turns_remaining", 0))],
			Color(1, 0.4, 0.3))
		if n.commodity_multiplier > 1.0:
			_add_hint_label("🛢 Suas commodities valem %.0f×: exportações rendem o dobro durante a crise!" % n.commodity_multiplier)
		_add_separator()
	_add_separator()
	_add_section_title("FINANÇAS (TRIMESTRE)")
	_add_data_row("Receita", "+%s" % _money(receita))
	_add_data_row("Despesas", "-%s" % _money(despesas))
	_add_data_row("Saldo", _money(receita - despesas), Color(0.4, 1, 0.6) if receita >= despesas else Color(1, 0.5, 0.4))
	_add_separator()
	# ── BALANÇA COMERCIAL ──
	_add_section_title("BALANÇA COMERCIAL (ano)")
	var saldo_com: float = n.calc_balanca_comercial() * 12.0  # anualiza
	var exp_setores: Array = _top_setores(n.exportacoes)
	var imp_setores: Array = _top_setores(n.importacoes)
	var exp_total: float = 0.0
	for v in n.exportacoes.values(): exp_total += float(v)
	var imp_total: float = 0.0
	for v in n.importacoes.values(): imp_total += float(v)
	_add_data_row("Exportações", "+%s%s" % [_money(exp_total * 4.0), "  " + ", ".join(exp_setores) if not exp_setores.is_empty() else ""], Color(0.5, 0.9, 0.7))
	_add_data_row("Importações", "-%s%s" % [_money(imp_total * 4.0), "  " + ", ".join(imp_setores) if not imp_setores.is_empty() else ""], Color(1, 0.7, 0.5))
	var saldo_tag := "▲ superávit" if saldo_com >= 0 else "▼ déficit"
	_add_data_row("Saldo comercial", "%s  %s" % [_money(saldo_com), saldo_tag], Color(0.4, 1, 0.6) if saldo_com >= 0 else Color(1, 0.5, 0.4))
	if n.commodity_multiplier != 1.0:
		_add_hint_label("🛢 Choque energético: preços de energia ×%.1f (afeta export E import)" % n.commodity_multiplier)
	# Dependência crítica de importação (vulnerabilidade a choques)
	for setor in n.import_dependencia:
		var dep: float = float(n.import_dependencia[setor])
		if dep >= 0.5:
			_add_data_row("  ⚠ dependência de %s" % _setor_nome(setor), "%d%% importado" % int(dep * 100), Color(1, 0.6, 0.4))
	_add_separator()
	# ── CRÉDITO & DÍVIDA ──
	_add_section_title("CRÉDITO & DÍVIDA")
	_render_complexidade_economica(n)
	var rating: float = n.rating_credito()
	var letra: String = n.rating_letra()
	var rating_cor := Color(0.4, 1, 0.6) if rating >= 66.0 else (Color(1, 0.5, 0.4) if rating < 42.0 else Color(1, 0.82, 0.3))
	_add_data_row("Rating de crédito", "%s  (%d/100)" % [letra, int(rating)], rating_cor)
	_add_data_row("Juros de novos empréstimos", "%.1f%%/ano" % (n.juros_emprestimo() * 100.0))
	var limite: float = n.limite_emprestimo()
	_add_data_row("Crédito disponível", _money(limite), Color(0.5, 0.8, 1))
	# Botões: captar empréstimo / amortizar (passo de 5% do PIB)
	var passo: float = maxf(20.0, n.pib_bilhoes_usd * 0.05)
	var loan_row := HBoxContainer.new()
	loan_row.add_theme_constant_override("separation", 8)
	var btn_loan := Button.new()
	btn_loan.text = "🏦 Captar %s" % _money(minf(passo, limite))
	btn_loan.custom_minimum_size = Vector2(0, 30)
	btn_loan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_loan.disabled = limite < 1.0
	btn_loan.pressed.connect(func():
		var r: Dictionary = GameEngine.player_take_loan(minf(passo, GameEngine.player_nation.limite_emprestimo()))
		if r.get("ok", false):
			_log_global_news("🏦 EMPRÉSTIMO", "Captado %s a %.1f%%/ano" % [_money(r.get("valor", 0)), float(r.get("juros", 0)) * 100.0], Color(0.5, 0.8, 1))
		else:
			_log_global_news("⚠ CRÉDITO", String(r.get("reason", "")), Color(1, 0.6, 0.4))
		_render_panel("economia")
		_refresh_top_bar_external())
	loan_row.add_child(btn_loan)
	if n.divida_publica > 1.0 and n.tesouro > 1.0:
		var btn_pay := Button.new()
		btn_pay.text = "💳 Amortizar %s" % _money(minf(passo, n.divida_publica))
		btn_pay.custom_minimum_size = Vector2(0, 30)
		btn_pay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_pay.pressed.connect(func():
			GameEngine.player_repay_debt(minf(passo, GameEngine.player_nation.divida_publica))
			_render_panel("economia")
			_refresh_top_bar_external())
		loan_row.add_child(btn_pay)
	panel_content.add_child(loan_row)
	_add_hint_label("💡 Empréstimo bem investido (infra, tech) acelera; mal usado, afunda em juros. Rating melhor = juro mais barato.")
	_add_separator()
	# ── MERCADO DE AÇÕES ──
	_add_section_title("MERCADO DE AÇÕES")
	var idx: float = GameEngine.market_index
	# Tendência: compara com o valor de alguns turnos atrás
	var trend := "→"
	var trend_cor := Color(0.8, 0.85, 0.9)
	var hist: Array = GameEngine.market_history
	if hist.size() >= 3:
		var antes: float = float(hist[max(0, hist.size() - 4)])
		if idx > antes * 1.005: trend = "▲"; trend_cor = Color(0.4, 1, 0.6)
		elif idx < antes * 0.995: trend = "▼"; trend_cor = Color(1, 0.5, 0.4)
	_add_data_row("🌐 Índice Global de Ações", "%d  %s" % [int(idx), trend], trend_cor)
	var pos: float = GameEngine.player_stocks_value()
	if pos > 1.0:
		var lucro: float = pos - GameEngine.player_stocks_invested
		var lucro_cor := Color(0.4, 1, 0.6) if lucro >= 0 else Color(1, 0.5, 0.4)
		_add_data_row("Sua posição", "%s  (%s%s)" % [_money(pos), "+" if lucro >= 0 else "", _money(lucro)], lucro_cor)
	# Botões: investir / resgatar (passo de 5% do PIB)
	var passo_b: float = maxf(20.0, n.pib_bilhoes_usd * 0.05)
	var stock_row := HBoxContainer.new()
	stock_row.add_theme_constant_override("separation", 8)
	var btn_buy := Button.new()
	btn_buy.text = "📈 Investir %s" % _money(minf(passo_b, n.tesouro))
	btn_buy.custom_minimum_size = Vector2(0, 30)
	btn_buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_buy.disabled = n.tesouro < 1.0
	btn_buy.pressed.connect(func():
		var r: Dictionary = GameEngine.player_invest_stocks(minf(passo_b, GameEngine.player_nation.tesouro))
		if not r.get("ok", false):
			_log_global_news("⚠ BOLSA", String(r.get("reason", "")), Color(1, 0.6, 0.4))
		_render_panel("economia")
		_refresh_top_bar_external())
	stock_row.add_child(btn_buy)
	if pos > 1.0:
		var btn_sell := Button.new()
		btn_sell.text = "📉 Resgatar %s" % _money(minf(passo_b, pos))
		btn_sell.custom_minimum_size = Vector2(0, 30)
		btn_sell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_sell.pressed.connect(func():
			GameEngine.player_sell_stocks(minf(passo_b, GameEngine.player_stocks_value()))
			_render_panel("economia")
			_refresh_top_bar_external())
		stock_row.add_child(btn_sell)
	panel_content.add_child(stock_row)
	_add_hint_label("💡 A bolsa sobe com prosperidade e paz, cai em crises e guerras. Bom para render tesouro ocioso — mas governar bem rende mais.")
	_add_separator()
	# ── CRIPTOMOEDA (WorldCoin) ──
	_add_section_title("₿ CRIPTOMOEDA — WorldCoin")
	var cp: float = GameEngine.crypto_price
	var ctrend := "→"
	var ctrend_cor := Color(0.8, 0.85, 0.9)
	var chist: Array = GameEngine.crypto_history
	if chist.size() >= 3:
		var cantes: float = float(chist[max(0, chist.size() - 3)])
		if cp > cantes * 1.02: ctrend = "▲"; ctrend_cor = Color(0.4, 1, 0.6)
		elif cp < cantes * 0.98: ctrend = "▼"; ctrend_cor = Color(1, 0.5, 0.4)
	var ciclo := "🐂 bull" if GameEngine.crypto_cycle > 0.2 else ("🐻 bear" if GameEngine.crypto_cycle < -0.2 else "lateral")
	_add_data_row("Cotação WorldCoin", "%d  %s  (%s)" % [int(cp), ctrend, ciclo], ctrend_cor)
	var cpos: float = GameEngine.player_crypto_value()
	if cpos > 1.0:
		var clucro: float = cpos - GameEngine.player_crypto_invested
		var clucro_cor := Color(0.4, 1, 0.6) if clucro >= 0 else Color(1, 0.5, 0.4)
		_add_data_row("Sua posição", "%s  (%s%s)" % [_money(cpos), "+" if clucro >= 0 else "", _money(clucro)], clucro_cor)
	# Botões: comprar / vender
	var passo_c: float = maxf(10.0, n.pib_bilhoes_usd * 0.03)
	var crypto_row := HBoxContainer.new()
	crypto_row.add_theme_constant_override("separation", 8)
	var btn_cbuy := Button.new()
	btn_cbuy.text = "₿ Comprar %s" % _money(minf(passo_c, n.tesouro))
	btn_cbuy.custom_minimum_size = Vector2(0, 30)
	btn_cbuy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_cbuy.disabled = n.tesouro < 1.0
	btn_cbuy.pressed.connect(func():
		var r: Dictionary = GameEngine.player_buy_crypto(minf(passo_c, GameEngine.player_nation.tesouro))
		if not r.get("ok", false):
			_log_global_news("⚠ CRIPTO", String(r.get("reason", "")), Color(1, 0.6, 0.4))
		_render_panel("economia")
		_refresh_top_bar_external())
	crypto_row.add_child(btn_cbuy)
	if cpos > 1.0:
		var btn_csell := Button.new()
		btn_csell.text = "💵 Vender %s" % _money(minf(passo_c, cpos))
		btn_csell.custom_minimum_size = Vector2(0, 30)
		btn_csell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_csell.pressed.connect(func():
			GameEngine.player_sell_crypto(minf(passo_c, GameEngine.player_crypto_value()))
			_render_panel("economia")
			_refresh_top_bar_external())
		crypto_row.add_child(btn_csell)
	panel_content.add_child(crypto_row)
	# Adoção como moeda legal
	var btn_legal := Button.new()
	btn_legal.text = "🏛 Revogar curso legal da WorldCoin" if GameEngine.crypto_legal_tender else "🏛 Adotar WorldCoin como moeda legal"
	btn_legal.custom_minimum_size = Vector2(0, 30)
	btn_legal.pressed.connect(func():
		GameEngine.player_toggle_legal_tender()
		_render_panel("economia"))
	panel_content.add_child(btn_legal)
	if GameEngine.crypto_legal_tender:
		_add_hint_label("⚠ WorldCoin é moeda legal: atrai capital de inovação e dribla sanções, mas colapsos abalam a estabilidade.")
	else:
		_add_hint_label("₿ Alto risco/retorno: sobe e desce muito mais que a bolsa, com risco de COLAPSO súbito. Aposte só o que pode perder.")
	_add_separator()
	_add_section_title("RECURSOS NATURAIS")
	var rec: Dictionary = n.recursos
	for k in ["petroleo", "gas_natural", "minerios_raros", "uranio", "ferro", "terras_araveis"]:
		if rec.has(k):
			_add_resource_row(k, float(rec[k]))
	_add_separator()
	_add_section_title("AÇÕES ECONÔMICAS")
	for a in GameEngine.get_panel_actions("economia"):
		_add_action_button(a.id, a.label, a.cost, a.desc, _run_panel_action.bind(a.id, "economia", Color(0, 1, 0.5)))

# Seção "Complexidade Econômica" do painel de economia: ECS + grau de
# processamento por setor (raw vs manufaturado) + aviso de volatilidade.
func _render_complexidade_economica(n) -> void:
	_add_section_title("COMPLEXIDADE ECONOMICA")
	var ecs: float = n.complexidade_economica
	var ecs_cor := Color(0.4, 1, 0.6) if ecs >= 62.0 else (Color(1, 0.5, 0.4) if ecs < 40.0 else Color(1, 0.82, 0.3))
	_add_data_row("Indice (ECS)", "%s  (%d/100)" % [n.complexidade_letra(), int(ecs)], ecs_cor)
	var setores_nome := {"energia": "Energia", "alimentos": "Alimentos", "materias_primas": "Materias-primas"}
	for s in n.COMMODITY_SECTORS:
		if n._setor_oferta(s) >= 60.0:  # so setores que o pais realmente exporta
			var proc: float = n._grau_proc(s) * 100.0
			var tag := "manufaturado" if proc >= 60.0 else ("semi-processado" if proc >= 30.0 else "bruto (raw)")
			var pcor := Color(0.4, 1, 0.6) if proc >= 60.0 else (Color(1, 0.6, 0.4) if proc < 30.0 else Color(1, 0.82, 0.3))
			_add_data_row("  %s" % setores_nome.get(s, s), "%d%% processado - %s" % [int(proc), tag], pcor)
	var vol: float = n.commodity_volatilidade()
	if vol >= 0.35:
		_add_hint_label("Economia dependente de commodities brutas: receita e inflacao mais volateis. Use Upgrade Industrial para agregar valor.")
	elif ecs >= 62.0:
		_add_hint_label("Economia sofisticada: crescimento estavel e menos exposto a choques de preco.")
	_add_separator()

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

	# ── BLOCOS GEOPOLÍTICOS (#11) — membro (sair) + elegíveis (aderir) ──
	_add_section_title("BLOCOS GEOPOLÍTICOS")
	var found_alliance := false
	for alliance in GameEngine.alliances_data:
		var members: Array = alliance.get("membros", [])
		if n.codigo_iso in members:
			found_alliance = true
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var lbl := Label.new()
			lbl.text = "🛡 %s · %d membros" % [alliance.get("nome", "?"), members.size()]
			lbl.add_theme_color_override("font_color", Color(0.4, 0.85, 1))
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lbl)
			var bid: String = String(alliance.get("id", ""))
			var btn_out := Button.new()
			btn_out.text = "🚪 Sair"
			btn_out.tooltip_text = "Sair do bloco (custa relações com os membros)"
			btn_out.pressed.connect(func():
				GameEngine.player_leave_bloc(bid)
				_render_panel("diplomacia"))
			row.add_child(btn_out)
			panel_content.add_child(row)
	if not found_alliance:
		_add_hint_label("Você não é membro de nenhum bloco.")
	# Blocos elegíveis para aderir (bem-quisto pelos membros)
	var eligibles: Array = GameEngine.player_eligible_blocs()
	if not eligibles.is_empty():
		_add_hint_label("Blocos abertos a você (boas relações com os membros):")
		for alliance in eligibles:
			var row2 := HBoxContainer.new()
			row2.add_theme_constant_override("separation", 8)
			var lbl2 := Label.new()
			lbl2.text = "  %s · %d membros" % [alliance.get("nome", "?"), alliance.get("membros", []).size()]
			lbl2.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
			lbl2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row2.add_child(lbl2)
			var bid2: String = String(alliance.get("id", ""))
			var btn_in := Button.new()
			btn_in.text = "🤝 Aderir"
			btn_in.tooltip_text = "Entrar no bloco (consome 1 ação; +relações com os membros)"
			btn_in.pressed.connect(func():
				GameEngine.player_join_bloc(bid2)
				_render_panel("diplomacia"))
			row2.add_child(btn_in)
			panel_content.add_child(row2)
	_add_separator()

	# ── RELAÇÕES (top 5 aliados / rivais) ──
	_add_section_title("RELAÇÕES BILATERAIS")
	_add_hint_label("🛡 Boas relações são ESCUDO real: nos playtests, nações diplomáticas sofrem metade das guerras de quem ignora a diplomacia.")
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

# True se a tech está em pesquisa em QUALQUER trilha ministerial.
func _is_researching(nation, tech_id: String) -> bool:
	if nation.pesquisa_por_ministerio == null:
		return false
	for pasta in nation.pesquisa_por_ministerio:
		if String(nation.pesquisa_por_ministerio[pasta].get("id", "")) == tech_id:
			return true
	return false

func _render_tech() -> void:
	var n = GameEngine.player_nation
	if n == null: return

	# 1) Trilhas de pesquisa PARALELAS (uma por ministério com foco definido)
	var slots: int = n.research_slots() if n.has_method("research_slots") else 2
	_add_section_title("🔬 PESQUISA PARALELA (%d/%d trilhas)" % [n.pesquisa_por_ministerio.size(), slots])
	var trilhas: Dictionary = GameEngine.tech.get_all_research_progress(n) if GameEngine.tech else {}
	if trilhas.is_empty():
		_add_hint_label("Nenhuma trilha ativa. Escolha techs abaixo — cada ministério pesquisa a sua em paralelo.")
	else:
		for pasta in trilhas:
			var prog: Dictionary = trilhas[pasta]
			var mm: Dictionary = GameEngine.MINISTRY_META.get(pasta, {})
			_add_data_row("%s %s" % [mm.get("icon", "•"), mm.get("nome", pasta)], str(prog.get("name", "—")), Color(0, 0.823, 1))
			_add_bar("", float(prog.get("pct", 0)), true, "%d/%d turnos" % [int(prog.get("progress", 0)), int(prog.get("total", 0))])
			var btn := Button.new()
			btn.text = "❌ cancelar %s" % mm.get("nome", pasta)
			btn.custom_minimum_size = Vector2(0, 26)
			btn.add_theme_font_size_override("font_size", 10)
			var p_bind: String = pasta
			btn.pressed.connect(func():
				GameEngine.player_cancel_research(p_bind)
				_render_panel("tech"))
			panel_content.add_child(btn)
	_add_separator()

	# 2) Status compacto
	_add_section_title("📊 STATUS")
	_add_data_row("Concluídas", "%d techs" % n.tecnologias_concluidas.size())
	_add_data_row("Velocidade pesquisa", "%.1fx" % n.velocidade_pesquisa)
	_add_data_row("Trilhas simultâneas", "%d (nível Casa Civil %d)" % [slots, n.ministry_level("casa_civil")])
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
	elif _is_researching(nation, String(tech["id"])):
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
	# Chefe de Inteligência — sempre reservado, tom de sombra
	var i_fala: String
	if n.seguranca_intel < 40.0:
		i_fala = "Nossa contra-espionagem está frágil. Rivais podem estar nos observando agora."
	elif n.spy_ops_log.size() > 0:
		i_fala = "%d operações no histórico, Presidente. Escolha o alvo — o resto é comigo." % n.spy_ops_log.size()
	else:
		i_fala = "Aguardo suas ordens nas sombras. Aponte o alvo no mapa."
	_add_advisor_header("seguranca", "MIN. DA JUSTIÇA & SEGURANÇA · Inteligência", i_fala, "neutro", Color(0.55, 0.6, 0.7))
	_add_section_title("INTELIGÊNCIA")
	_add_data_row("Intel Score", "%.1f" % n.intel_score, Color(0, 0.823, 1))
	_add_data_row("Segurança Intel", "%.1f" % n.seguranca_intel, Color(0.4, 1, 0.6))
	_add_data_row("Operações realizadas", "%d" % n.spy_ops_log.size())
	_add_separator()
	_add_section_title("OPERAÇÕES DISPONÍVEIS")
	var wm0 = get_node_or_null("/root/WorldMap")
	var alvo: String = String(wm0.preview_code) if wm0 != null and wm0.get("preview_code") != null else ""
	if alvo != "" and GameEngine.player_nation != null and alvo != GameEngine.player_nation.codigo_iso and GameEngine.nations.has(alvo):
		_add_hint_label("🎯 Alvo atual: %s — clique numa operação para executá-la." % GameEngine.nations[alvo].nome)
	else:
		_add_hint_label("💡 Clique num país do mapa para definir o ALVO, depois escolha a operação aqui.")
	if GameEngine.espionage:
		for op_id in GameEngine.espionage.OPS:
			var op: Dictionary = GameEngine.espionage.OPS[op_id]
			var btn := Button.new()
			btn.text = "%s %s — $%dB (%d%%)\n%s" % [op["icon"], op["nome"], int(op["custo"]), int(float(op["base_success"]) * 100), op["descricao"]]
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.custom_minimum_size = Vector2(0, 52)
			btn.add_theme_font_size_override("font_size", 11)
			btn.clip_text = true
			btn.pressed.connect(_on_intel_op_pressed)
			panel_content.add_child(btn)
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

# Clique numa operação do painel Intel: abre o picker de espionagem
# (com % real de êxito por alvo) no país atualmente selecionado no mapa
func _on_intel_op_pressed() -> void:
	var wm = get_node_or_null("/root/WorldMap")
	if wm == null: return
	var alvo: String = String(wm.preview_code) if wm.get("preview_code") != null else ""
	if alvo == "" or GameEngine.player_nation == null or alvo == GameEngine.player_nation.codigo_iso or not GameEngine.nations.has(alvo):
		_log_global_news("🕵 INTEL", "Selecione um país-alvo no mapa primeiro (clique no país).", Color(1, 0.7, 0.4))
		return
	if wm.has_method("_show_spy_picker_modal"):
		wm._show_spy_picker_modal(alvo)

# ─────────────────────────────────────────────────────────────────
# PAINEL: SITUAÇÃO
# ─────────────────────────────────────────────────────────────────

func _render_situacao() -> void:
	var n = GameEngine.player_nation
	if n == null: return

	# ══ PODER GLOBAL — a métrica que define a vitória ══
	GameEngine._refresh_world_maxima()
	var my_rank: int = GameEngine.get_power_rank(n.codigo_iso)
	var bd: Dictionary = GameEngine.get_power_breakdown(n)
	_add_section_title("PODER GLOBAL — MÉTRICA DE VITÓRIA")

	# Headline: posição com cor por faixa
	var rank_color: Color
	if my_rank == 1: rank_color = Color(1, 0.85, 0.2)        # ouro: líder
	elif my_rank <= 5: rank_color = Color(0.4, 1, 0.6)       # verde: top-5 (Potência do Século)
	elif my_rank <= 20: rank_color = Color(0, 0.823, 1)      # ciano: relevante
	else: rank_color = Color(0.9, 0.95, 1)
	var head := Label.new()
	head.text = "🌍 #%d POTÊNCIA MUNDIAL  —  %.1f pts" % [my_rank, bd["total"]]
	head.add_theme_color_override("font_color", rank_color)
	head.add_theme_font_size_override("font_size", 19)
	panel_content.add_child(head)

	# Tendência (compara com ~2 anos atrás)
	var hist: Array = GameEngine.player_power_rank_history
	if hist.size() >= 2:
		var lookback: int = mini(8, hist.size() - 1)
		var delta: int = int(hist[hist.size() - 1 - lookback]) - my_rank
		var tr := Label.new()
		if delta > 0:
			tr.text = "▲ subiu %d posiç%s nos últimos %d turnos" % [delta, "ão" if delta == 1 else "ões", lookback]
			tr.add_theme_color_override("font_color", Color(0.4, 1, 0.6))
		elif delta < 0:
			tr.text = "▼ caiu %d posiç%s nos últimos %d turnos" % [-delta, "ão" if delta == -1 else "ões", lookback]
			tr.add_theme_color_override("font_color", Color(1, 0.45, 0.4))
		else:
			tr.text = "• posição estável nos últimos %d turnos" % lookback
			tr.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
		tr.add_theme_font_size_override("font_size", 10)
		panel_content.add_child(tr)

	# Trajetória (sparkline invertida: linha subindo = ranking melhorando)
	if hist.size() >= 2:
		var inv: Array = []
		for r in hist:
			inv.append(-float(r))
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		var lbl := Label.new()
		lbl.text = "Trajetória"
		lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.custom_minimum_size = Vector2(110, 0)
		hbox.add_child(lbl)
		var spark := SparklineWidget.new()
		spark.values = inv
		spark.line_color = rank_color
		spark.custom_minimum_size = Vector2(120, 28)
		spark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(spark)
		var v_lbl := Label.new()
		v_lbl.text = "#%d" % my_rank
		v_lbl.add_theme_color_override("font_color", rank_color)
		v_lbl.add_theme_font_size_override("font_size", 11)
		v_lbl.custom_minimum_size = Vector2(40, 0)
		hbox.add_child(v_lbl)
		panel_content.add_child(hbox)

	# Composição do poder — mostra ONDE investir pra subir
	_add_bar("Economia (40%)",   bd["economia"] / 40.0 * 100.0,   true, "%.1f/40" % bd["economia"])
	_add_bar("Militar (25%)",    bd["militar"] / 25.0 * 100.0,    true, "%.1f/25" % bd["militar"])
	_add_bar("Tecnologia (20%)", bd["tecnologia"] / 20.0 * 100.0, true, "%.1f/20" % bd["tecnologia"])
	_add_bar("Diplomacia (15%)", bd["diplomacia"] / 15.0 * 100.0, true, "%.1f/15" % bd["diplomacia"])
	_add_separator()

	# ══ OBJETIVOS DE VITÓRIA ══
	_add_section_title("OBJETIVOS DE VITÓRIA")
	# Objetivo temático do cenário (Década Crítica, Guerra Fria 2.0…)
	var cenario_obj: String = String(GameEngine.active_scenario.get("objetivo", "")) if not GameEngine.active_scenario.is_empty() else ""
	if cenario_obj != "":
		_add_data_row("🎯 %s" % GameEngine.active_scenario.get("name", "Cenário"), "", Color(0.5, 0.9, 1))
		_add_hint_label(cenario_obj)
	if GameEngine.victory_achieved:
		_add_data_row("🏆 Hegemonia Global", "CONQUISTADA — modo livre", Color(1, 0.85, 0.2))
	else:
		var streak: int = int(n.get_meta("hegemony_streak", 0))
		if my_rank == 1:
			_add_data_row("🏆 Hegemonia Global", "líder há %d/16 turnos" % streak, Color(1, 0.85, 0.2))
			var faltando: Array = []
			if n.apoio_popular < 55.0: faltando.append("apoio ≥ 55")
			if n.estabilidade_politica < 55.0: faltando.append("estabilidade ≥ 55")
			if n.pib_bilhoes_usd < GameEngine._world_max_pib * 0.5: faltando.append("PIB ≥ 50% do líder")
			if faltando.size() > 0:
				_add_hint_label("⚠ Contagem pausada — falta: " + ", ".join(faltando))
		else:
			_add_data_row("🏆 Hegemonia Global", "torne-se o #1 em poder (você: #%d)" % my_rank)
	var end_year: int = int(GameEngine.active_scenario.get("end_year", 2100)) if not GameEngine.active_scenario.is_empty() else 2100
	if my_rank <= 5:
		_add_data_row("🏛 Potência do Século", "top-5 em %d — NO CAMINHO ✓" % end_year, Color(0.4, 1, 0.6))
	else:
		_add_data_row("🏛 Potência do Século", "termine %d no top-5 (você: #%d)" % [end_year, my_rank], Color(1, 0.75, 0.4))
	if bool(n.get_meta("model_nation_done", false)):
		_add_data_row("🌟 Nação Modelo", "ALCANÇADA", Color(1, 0.9, 0.4))
	else:
		_add_data_row("🌟 Nação Modelo", "%d/20 turnos exemplares" % int(n.get_meta("victory_streak", 0)))
	_add_separator()

	# ══ TOP 10 PODER MUNDIAL ══
	_add_section_title("TOP 10 — PODER MUNDIAL")
	var by_power: Array = []
	var by_pib: Array = []
	var by_mil: Array = []
	for code in GameEngine.nations:
		var nat = GameEngine.nations[code]
		by_power.append({"code": code, "v": GameEngine.compute_power_score(nat), "n": nat})
		by_pib.append({"code": code, "v": nat.pib_bilhoes_usd, "n": nat})
		by_mil.append({"code": code, "v": nat.get_military_power(), "n": nat})
	by_power.sort_custom(func(a, b): return a["v"] > b["v"])
	by_pib.sort_custom(func(a, b): return a["v"] > b["v"])
	by_mil.sort_custom(func(a, b): return a["v"] > b["v"])
	for i in range(mini(10, by_power.size())):
		var b = by_power[i]
		var color := Color(0, 1, 0.5) if b["code"] == n.codigo_iso else Color(1, 1, 1)
		_add_data_row("#%d %s" % [i + 1, b["n"].nome], "%.1f pts" % b["v"], color)
	if my_rank > 10:
		_add_data_row("⋯", "")
		_add_data_row("#%d %s" % [my_rank, n.nome], "%.1f pts" % bd["total"], Color(0, 1, 0.5))
	_add_separator()

	# ══ Rankings setoriais ══
	var pib_rank := 0
	var mil_rank := 0
	for i in by_pib.size():
		if by_pib[i]["code"] == n.codigo_iso: pib_rank = i + 1
	for i in by_mil.size():
		if by_mil[i]["code"] == n.codigo_iso: mil_rank = i + 1
	_add_section_title("TOP 5 ECONOMIAS")
	_add_data_row("Seu ranking PIB", "#%d / %d" % [pib_rank, by_pib.size()], Color(0, 0.823, 1))
	for i in range(min(5, by_pib.size())):
		var b = by_pib[i]
		var color := Color(1, 1, 1) if b["code"] != n.codigo_iso else Color(0, 1, 0.5)
		_add_data_row("#%d %s" % [i+1, b["n"].nome], _money(b["v"]), color)
	_add_separator()
	_add_section_title("TOP 5 PODERES MILITARES")
	_add_data_row("Seu ranking militar", "#%d / %d" % [mil_rank, by_mil.size()], Color(0, 0.823, 1))
	for i in range(min(5, by_mil.size())):
		var b = by_mil[i]
		var color := Color(1, 1, 1) if b["code"] != n.codigo_iso else Color(0, 1, 0.5)
		_add_data_row("#%d %s" % [i+1, b["n"].nome], "%d" % int(b["v"]), color)

	# ══ LÍDERES MUNDIAIS (#13) — quem governa as grandes potências ══
	_add_separator()
	_add_section_title("LÍDERES MUNDIAIS")
	_add_hint_label("Cada nação tem um líder com ideologia própria. Líderes caem e sobem — e o país muda de rumo.")
	var grandes: Array = []
	for code in GameEngine.nations:
		grandes.append({"code": code, "n": GameEngine.nations[code], "pib": GameEngine.nations[code].pib_bilhoes_usd})
	grandes.sort_custom(func(a, b): return a["pib"] > b["pib"])
	for i in range(min(8, grandes.size())):
		var g = grandes[i]
		var gn = g["n"]
		var lider: String = gn.lider_nome if gn.lider_nome != "" else "—"
		var ideo: String = GameEngine._ideo_label(GameEngine._doctrine_for(gn)).capitalize()
		var tipo: String = "🔒 autocracia" if GameEngine._is_autocracy(gn) else "🗳 democracia"
		var cor := Color(0, 1, 0.5) if g["code"] == n.codigo_iso else Color(0.85, 0.9, 1)
		_add_data_row("%s · %s" % [gn.nome, lider], "%s · %s" % [ideo, tipo], cor)

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

# As três emissoras do jogo, por escopo da notícia.
const NEWS_NETWORKS := {
	"national": {"nome": "National News", "sigla": "NN", "icon": "🏛", "cor": Color(1, 0.82, 0.3),
		"slogan": "Boa noite. Aqui é a National News — o seu país em primeiro lugar."},
	"regional": {"nome": "Regional News", "sigla": "RN", "icon": "📡", "cor": Color(0.5, 0.85, 0.65),
		"slogan": "Aqui é a Regional News, cobrindo a sua vizinhança no continente."},
	"global":   {"nome": "Global News",   "sigla": "GN", "icon": "🌍", "cor": Color(0.4, 0.7, 1),
		"slogan": "Boa noite. Aqui é a Global News, sua janela para o planeta."},
}

func _render_noticias() -> void:
	var n = GameEngine.player_nation
	var hist: Array = GameEngine.news_history
	# Descobre a última manchete urgente e a emissora dela (define quem "abre" o telejornal)
	var last_urgent := ""
	var urgent_scope := "global"
	for i in range(hist.size() - 1, -1, -1):
		var t: String = String(hist[i].get("type", ""))
		if t in ["guerra", "choque", "guerra_vencida", "fmi", "corrupcao"]:
			last_urgent = String(hist[i].get("headline", ""))
			urgent_scope = String(hist[i].get("scope", "global"))
			break
	var net: Dictionary = NEWS_NETWORKS.get(urgent_scope, NEWS_NETWORKS["global"])
	var anchor_expr := "urgente" if last_urgent != "" else "neutro"
	var anchor_fala: String = ("PLANTÃO: " + last_urgent) if last_urgent != "" else String(net["slogan"])
	if n != null:
		_add_advisor_header("ancora", "%s %s — %s" % [net["icon"], String(net["sigla"]), String(net["nome"]).to_upper()], anchor_fala, anchor_expr, net["cor"])

	if hist.is_empty():
		_add_hint_label("Sem notícias ainda. O mundo desperta a cada turno.")
		return

	# Filtro por escopo — nacional em destaque, depois regional, depois global
	_add_section_title("ÚLTIMAS MANCHETES")
	var shown := 0
	for i in range(hist.size() - 1, -1, -1):
		if shown >= 14:
			break
		var ev: Dictionary = hist[i]
		_add_news_card(ev)
		shown += 1

## Card de notícia estilo tarja de TV: identidade da emissora por escopo.
func _add_news_card(ev: Dictionary) -> void:
	var scope: String = String(ev.get("scope", "global"))
	var net: Dictionary = NEWS_NETWORKS.get(scope, NEWS_NETWORKS["global"])
	var accent: Color = net["cor"]
	var tag: String = "%s %s" % [net["icon"], String(net["sigla"])]
	var t: String = String(ev.get("type", ""))
	if t == "guerra" or t == "guerra_vencida":
		accent = Color(1, 0.4, 0.4)
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.11, 0.16, 0.85)
	sb.border_width_left = 3
	sb.border_color = accent
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	box.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	box.add_child(vb)
	var top := Label.new()
	top.text = "%s  ·  Turno %d" % [tag, int(ev.get("turn", 0))]
	top.add_theme_color_override("font_color", accent)
	top.add_theme_font_size_override("font_size", 9)
	vb.add_child(top)
	var head := Label.new()
	head.text = String(ev.get("headline", ""))
	head.add_theme_color_override("font_color", Color(0.9, 0.94, 1))
	head.add_theme_font_size_override("font_size", 11)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(head)
	panel_content.add_child(box)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 4)
	panel_content.add_child(sp)

# ─────────────────────────────────────────────────────────────────
# HELPERS DE UI
# ─────────────────────────────────────────────────────────────────

func _add_section_title(text: String) -> void:
	var lbl := Label.new()
	lbl.text = "■ " + text
	# Dourado premium — chrome do jogo; o ciano fica para DADOS/valores
	lbl.add_theme_color_override("font_color", Color(0.85, 0.70, 0.34, 0.95))
	lbl.add_theme_font_size_override("font_size", 11)
	panel_content.add_child(lbl)

func _add_subtitle(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(0.5, 0.65, 0.85))
	lbl.add_theme_font_size_override("font_size", 10)
	panel_content.add_child(lbl)

## Cabeçalho de assessor: retrato do elenco + nome do cargo + fala contextual.
## Humaniza o painel — quem "fala" com o Presidente tem rosto e personalidade.
func _add_advisor_header(role: String, cargo: String, fala: String, expr: String = "neutro", accent: Color = Color(0, 0.823, 1)) -> void:
	var n = GameEngine.player_nation
	if n == null: return
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.12, 0.17, 0.92)
	sb.border_color = accent.darkened(0.2)
	sb.set_border_width_all(0)
	sb.border_width_left = 3
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	box.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var pv := PortraitView.make(n.codigo_iso, role, expr, 56.0)
	pv.custom_minimum_size = Vector2(56, 67)
	pv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pv)
	var txt := VBoxContainer.new()
	txt.add_theme_constant_override("separation", 2)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(txt)
	var cargo_lbl := Label.new()
	cargo_lbl.text = cargo
	cargo_lbl.add_theme_color_override("font_color", accent)
	cargo_lbl.add_theme_font_size_override("font_size", 10)
	txt.add_child(cargo_lbl)
	var fala_lbl := Label.new()
	fala_lbl.text = "“" + fala + "”"
	fala_lbl.add_theme_color_override("font_color", Color(0.82, 0.88, 0.95))
	fala_lbl.add_theme_font_size_override("font_size", 11)
	fala_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.add_child(fala_lbl)
	panel_content.add_child(box)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	panel_content.add_child(spacer)

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

# Linha de recurso com ícone VETORIAL (game-icons.net) + nome + barra
func _add_resource_row(res_key: String, valor: float) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	var icon_path: String = load("res://scripts/WorldMap.gd").resource_icon_path(res_key)
	if icon_path != "":
		var tr := TextureRect.new()
		tr.texture = load(icon_path)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(18, 18)
		tr.modulate = Color(0.75, 0.88, 1)
		hbox.add_child(tr)
	var lbl := Label.new()
	lbl.text = res_key.replace("_", " ").capitalize()
	lbl.add_theme_color_override("font_color", Color(0.65, 0.74, 0.85))
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.custom_minimum_size = Vector2(120, 0)
	hbox.add_child(lbl)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.value = valor
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = UIStyles.indicator_color(valor)
	fill.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("fill", fill)
	hbox.add_child(bar)
	var v_lbl := Label.new()
	v_lbl.text = "%d" % int(valor)
	v_lbl.add_theme_color_override("font_color", UIStyles.indicator_color(valor))
	v_lbl.add_theme_font_size_override("font_size", 11)
	v_lbl.custom_minimum_size = Vector2(28, 0)
	v_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(v_lbl)
	panel_content.add_child(hbox)

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
	# INDEPENDENTE DE ÁRVORE: este overlay vive FORA da árvore quando nenhum
	# painel está aberto (padrão legacy de re-parent). get_tree() aqui era
	# null e o modal de vitória/derrota simplesmente NUNCA aparecia em
	# gameplay real — bug descoberto pelo GameplayTest.
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null: return
	# Ancora no modal_layer do WorldMap (CanvasLayer da UI — escala correta
	# em qualquer resolução); fallback pra root se o WorldMap não existir
	var host: Node = tree.root.get_node_or_null("WorldMap")
	var modal_parent: Node = tree.root
	if host != null and host.get("modal_layer") != null:
		modal_parent = host.modal_layer
	if modal_parent.get_node_or_null("EndgameOverlay") != null:
		return
	# O modal_layer fica invisível sem modais abertos — liga pra exibir
	if modal_parent is CanvasItem:
		(modal_parent as CanvasItem).visible = true
	endgame_triggered = true
	# Pausa o jogo
	tree.paused = false  # reseta caso houvesse
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
	modal_parent.add_child(modal)
	# Fade-in cinematográfico — tween criado NO MODAL (que está na árvore;
	# este overlay pode estar destacado e create_tween() falharia aqui)
	modal.modulate = Color(1, 1, 1, 0)
	var tw_fade := modal.create_tween()
	tw_fade.tween_property(modal, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_CUBIC)
	# Card central com tema visual diferente pra vitória vs derrota
	# (CenterContainer full-rect: centraliza correto em qualquer resolução —
	# o position manual antigo saía da tela em janelas menores que 1080p)
	var centerc := CenterContainer.new()
	centerc.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.add_child(centerc)
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(640, 480)
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
	centerc.add_child(box)
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
			# Esconde o layer se não sobrou nenhum modal do WorldMap aberto
			if host != null and modal_parent != tree.root and modal_parent is CanvasItem:
				if host.get("_modal_stack") != null and host._modal_stack.is_empty():
					(modal_parent as CanvasItem).visible = false
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
# (independente de árvore: usa o main loop, não o get_tree deste overlay)
func _transition_to_scene(modal: Node, scene_path: String) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null: return
	if modal != null and is_instance_valid(modal) and modal.is_inside_tree():
		var tw := modal.create_tween()
		tw.tween_property(modal, "modulate:a", 0.0, 0.18)
		tw.tween_callback(func():
			if is_instance_valid(modal): modal.queue_free()
			tree.change_scene_to_file(scene_path))
	else:
		tree.change_scene_to_file(scene_path)

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
	# Ancora no modal_layer do WorldMap (CanvasLayer full-rect) para centralizar
	# corretamente. Se adicionado ao próprio GameOverlay (que vive dentro de um
	# card de modal), o PRESET_CENTER + position manual saíam pro canto da tela.
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var host: Node = null
	var modal_parent: Node = self
	if tree != null:
		host = tree.root.get_node_or_null("WorldMap")
		if host != null and host.get("modal_layer") != null:
			modal_parent = host.modal_layer
	var modal := ColorRect.new()
	modal.color = Color(0, 0, 0, 0.85)
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	if modal_parent is CanvasItem:
		(modal_parent as CanvasItem).visible = true
	modal_parent.add_child(modal)
	# CenterContainer full-rect: centraliza sem offset manual, em qualquer resolução
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	modal.add_child(center)
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(560, 360)
	center.add_child(box)
	UIStyles.animate_modal_in(modal, box)
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
