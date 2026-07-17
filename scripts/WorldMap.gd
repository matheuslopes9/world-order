extends Node2D
## Tela principal do jogo. Layout estilo Plague Inc:
## - Mapa = tela cheia (background)
## - Top bar fina (50px) com data/turno/tesouro/DEFCON/score/menu
## - Painel esquerdo flutuante (380px) com lista (modo seleção) ou tabs do jogador
## - Painel direito flutuante (380px) com dossiê do país sob foco
## - Bottom bar (60px) com filtros + zoom + ticker INTEL
## - Botão circular grande "PRÓXIMO TURNO" bottom-right (após Assumir Comando)

const MAP_WIDTH: float  = 2000.0
const MAP_HEIGHT: float = 1000.0

# Cores Plague-Inc style
# NEUTRO = quase-branco: o shader de biomas pinta o terreno REAL e o
# self_modulate apenas TINGE (jogador ciano, inimigo vermelho, filtros).
const COUNTRY_FILL    := Color(1.0, 1.0, 1.0)
const COUNTRY_STROKE  := Color(0.72, 0.76, 0.82, 0.50)

# Material de TERRENO compartilhado por TODOS os Polygon2D dos países.
# Uma única instância → o batcher agrupa; o relevo vem do shader em world
# space e a cor política continua no self_modulate (zero re-triangulação).
static var _country_terrain_mat: ShaderMaterial = null

static func _get_country_terrain_mat() -> ShaderMaterial:
	if _country_terrain_mat == null:
		_country_terrain_mat = ShaderMaterial.new()
		_country_terrain_mat.shader = load("res://shaders/country_fill.gdshader")
		# Satélite REAL: NASA Blue Marble (domínio público) — projeção idêntica
		_country_terrain_mat.set_shader_parameter("earth_tex", load("res://assets/earth_blue_marble.jpg"))
	return _country_terrain_mat
# Tintas multiplicativas sobre o terreno realista (mantêm a textura visível)
# VISÃO REALISTA: satélite quase puro — tints de área MÍNIMOS; quem
# identifica jogador/inimigo/aliado é a FRONTEIRA colorida (_border_for).
# Alpha=1.0 → satélite; nos filtros de dados as cores usam alpha=0 (chapado).
const COUNTRY_HOVER   := Color(1.10, 1.10, 1.10, 1.0)
const COUNTRY_PREVIEW := Color(1.06, 1.02, 0.94, 1.0)
const COUNTRY_PLAYER  := Color(0.90, 0.99, 1.06, 1.0)
const COUNTRY_ENEMY   := Color(1.06, 0.85, 0.82, 1.0)
const COUNTRY_ALLY    := Color(0.90, 1.04, 0.92, 1.0)

@onready var camera: Camera2D = $MapCamera
@onready var countries_root: Node2D = $Countries

# Layer pra markers de eventos sobre os países (criado em runtime)
var event_markers_layer: Node2D = null
# Layer pra ícones de recursos (visível só quando filtro = RECURSOS)
var resource_icons_layer: Node2D = null
# Markers ativos: cada item = { node: Node2D, ttl_turns: int, country: String, ev_id: String }
var active_markers: Array = []
const MARKER_TTL_DEFAULT: int = 4  # turnos que o marker fica visível

# Top bar (existem na scene)
@onready var date_label: Label = %DateLabel
@onready var turn_label: Label = %TurnLabel
@onready var treasury_label: Label = %TreasuryLabel
@onready var defcon_label: Label = %DefconLabel
@onready var score_label: Label = %ScoreLabel
@onready var rank_label: Label = %RankLabel
@onready var actions_label: Label = %ActionsLabel
@onready var menu_button: Button = %MenuButton

# Bottom bar (existem na scene)
@onready var action_bar: HBoxContainer = %ActionBar
@onready var resource_bar: PanelContainer = %ResourceBar
@onready var map_filters: HBoxContainer = %MapFilters
@onready var zoom_in_btn: Button = %ZoomIn
@onready var zoom_out_btn: Button = %ZoomOut
@onready var zoom_reset_btn: Button = %ZoomReset
@onready var ticker_inner: HBoxContainer = %TickerInner
@onready var next_turn_button: Button = %NextTurnButton

# Spinner (existe na scene)
@onready var spinner_overlay: Control = %SpinnerOverlay
@onready var spinner_label: Label = %SpinnerLabel
@onready var spinner_icon: Label = %SpinnerIcon

# Modal layer (existe na scene)
@onready var modal_layer: Control = %ModalLayer

# Widgets "legacy" — criados dinamicamente em _build_legacy_nodes() pra preservar
# a lógica antiga sem precisar reescrever 1500 linhas. Vivem dentro de modais
# ou ficam invisíveis quando não usados.
var left_panel: PanelContainer = null
var nations_list: ItemList = null
var search_box: LineEdit = null
var sort_button: OptionButton = null
var right_panel: PanelContainer = null
var preview_name: Label = null
var preview_flag: Control = null  # Container que recebe ColorRects (listras da bandeira)
var preview_portrait_slot: Control = null  # recebe o retrato do líder da nação em foco
var preview_iso: Label = null
var preview_tier: Label = null
var preview_desc: Label = null
var preview_stats: GridContainer = null
var preview_pros_cons: VBoxContainer = null
var confirm_button: Button = null
var declare_war_button: Button = null
var propose_peace_button: Button = null
var embassy_button: Button = null
var sanctions_button: Button = null
var propose_treaty_button: Button = null
var trade_button: Button = null
var espionage_button: Button = null
var next_turn_floater: Control = null
var game_overlay: Control = null

# Sistema de modal central
var _modal_stack: Array = []  # cada item é o Control do modal aberto

# Bot de IA — modo espectador
var bot_player = null          # instância BotPlayer quando ativo
var bot_overlay: Control = null  # painel de pensamento do bot
var bot_log_lines: Array = []    # últimas N linhas de raciocínio
const BOT_LOG_MAX: int = 12

# Estado
var countries: Dictionary = {}
var country_codes_filtered: Array = []
var preview_code: String = ""
var player_code: String = ""
var current_filter: String = "SATELITE"
# Hover tracking — atualiza tooltip flutuante e pequeno highlight no país sob mouse
var hover_code: String = ""
var hover_label: Label = null

# Camera/zoom
var is_dragging: bool = false
var drag_start_pos: Vector2
var drag_start_camera_pos: Vector2
var last_drag_pos: Vector2
var last_drag_time_ms: int = 0
var pan_velocity: Vector2 = Vector2.ZERO  # px/s da última amostra de drag (em coords de tela)
var camera_target_pos: Vector2
var camera_target_zoom: Vector2
var camera_animating: bool = false
const ZOOM_MIN: float = 0.4
const ZOOM_MAX: float = 8.0
const ZOOM_STEP: float = 1.20
const CAM_LERP_SPEED: float = 8.0
const PAN_INERTIA_DAMP: float = 4.5  # decai exp(-DAMP * dt) → ~1s pra parar
const PAN_INERTIA_MIN: float = 8.0   # px/s — abaixo disso considera parado

# Layout (sincronizado com .tscn) — agora sem painéis laterais (estilo AoE)
const LEFT_PANEL_W: float = 0.0
const RIGHT_PANEL_W: float = 0.0
# Heights — modo compact (1366×768 e menores) reduz padding pra dar mais espaço pro mapa
const TOP_BAR_H_NORMAL: float = 54.0
const TOP_BAR_H_COMPACT: float = 46.0
const BOTTOM_BAR_H_NORMAL: float = 170.0
const BOTTOM_BAR_H_COMPACT: float = 138.0
# Respiro extra reservado ao redor do mundo enquadrado (só nos cálculos de
# CÂMERA — não muda a altura visual das barras). Dá aquele "espacinho" entre
# a moldura do mapa e a barra inferior/superior no zoom-out.
const MAP_PAD: float = 26.0
# Threshold: viewports com altura ≤ 800 entram em modo compact
const COMPACT_VIEWPORT_HEIGHT: float = 800.0
# Resolved values (preenchido em _ready conforme viewport)
var TOP_BAR_H: float = TOP_BAR_H_NORMAL
var BOTTOM_BAR_H: float = BOTTOM_BAR_H_NORMAL
var compact_mode: bool = false

# ─────────────────────────────────────────────────────────────────
# READY
# ─────────────────────────────────────────────────────────────────

const MONO_FONT := preload("res://fonts/CascadiaMono.ttf")

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	_apply_saved_video_prefs()
	# TELA DE CARREGAMENTO OPACA: cobre a montagem do mapa (que é feia de
	# ver) do 1º frame até tudo pronto — sai com fade cinematográfico.
	_show_loading_screen()
	await get_tree().process_frame
	_detect_compact_mode()
	_build_legacy_nodes()
	await _load_world_data()
	_setup_camera()
	_populate_nations_list()
	_build_map_filters()
	_build_action_bar()
	_setup_ui_bindings()
	_style_hero_buttons()
	_apply_mono_to_topbar()
	camera_target_pos = camera.position
	camera_target_zoom = camera.zoom

	if GameEngine and GameEngine.has_signal("turn_advanced"):
		GameEngine.turn_advanced.connect(_on_turn_advanced)
	# Signal de eventos históricos com decisão (FASE 4)
	if GameEngine and GameEngine.timeline and GameEngine.timeline.has_signal("historic_event_decision"):
		GameEngine.timeline.historic_event_decision.connect(_open_historic_decision_modal)
	if GameEngine and GameEngine.has_signal("bailout_offered"):
		GameEngine.bailout_offered.connect(_open_bailout_modal)
	# Signal pra MARKERS de eventos no mapa (FASE 8 - integração visual)
	if GameEngine and GameEngine.timeline and GameEngine.timeline.has_signal("event_fired"):
		GameEngine.timeline.event_fired.connect(_on_event_fired_marker)
	# Signal de storylines (Sessão 3 do roadmap) — abre o mesmo modal de decisão
	if GameEngine and GameEngine.storylines and GameEngine.storylines.has_signal("storyline_triggered"):
		GameEngine.storylines.storyline_triggered.connect(_on_storyline_triggered)
	# MOLDURA DO MUNDO: fecha o mapa em [0,2000]x[0,1000] — sem "mundo infinito"
	_build_world_frame()
	# Cria layer pra markers
	event_markers_layer = Node2D.new()
	event_markers_layer.name = "EventMarkers"
	event_markers_layer.z_index = 5
	add_child(event_markers_layer)
	# Cria layer pra ícones de recursos (visível só com filtro RECURSOS)
	resource_icons_layer = Node2D.new()
	resource_icons_layer.name = "ResourceIcons"
	resource_icons_layer.z_index = 4
	resource_icons_layer.visible = false
	add_child(resource_icons_layer)
	# Contador de ações por turno (FASE 7)
	if GameEngine and GameEngine.has_signal("player_actions_changed"):
		GameEngine.player_actions_changed.connect(_refresh_actions_label)
	_refresh_actions_label(GameEngine.player_actions_remaining)
	# Achievements: toast quando desbloqueia
	if GameEngine and GameEngine.achievements and GameEngine.achievements.has_signal("achievement_unlocked"):
		GameEngine.achievements.achievement_unlocked.connect(_show_achievement_toast)

	_refresh_top_bar()

	# Se já há jogador (carregou save) → ativa overlay direto
	if GameEngine.player_nation != null:
		player_code = GameEngine.player_nation.codigo_iso
		game_overlay.activate()
		_show_action_bar(true)
		_repaint_map()
		_zoom_camera_to_world()  # mundo enquadrado na moldura (consistente c/ pós-wizard)
		_log_ticker("📂 SAVE", "Sessão restaurada: turno %d" % GameEngine.current_turn, Color(0.4, 1, 0.6))
	else:
		# Sem save: mostra modal de seleção de nação
		_show_action_bar(false)
		_open_select_nation_modal()

	# Garante visibilidade mínima do spinner pra dar feedback humano
	var elapsed: int = Time.get_ticks_msec() - t0
	if elapsed < 350:
		await get_tree().create_timer((350 - elapsed) / 1000.0).timeout
	_hide_spinner()
	_hide_loading_screen()
	print("[MAP] %d países | carregado em %d ms" % [countries.size(), Time.get_ticks_msec() - t0])

# Moldura fechando o mundo: linha dourada na borda exata do mapa + uma
# linha externa fantasma (efeito "mesa de comando"). Estático, custo zero.
func _build_world_frame() -> void:
	var frame := Line2D.new()
	frame.name = "WorldFrame"
	frame.points = PackedVector2Array([
		Vector2(0, 0), Vector2(2000, 0), Vector2(2000, 1000),
		Vector2(0, 1000), Vector2(0, 0)])
	frame.width = 2.2
	frame.default_color = Color(0.80, 0.65, 0.30, 0.55)
	frame.z_index = 3
	frame.antialiased = true
	add_child(frame)
	var outer := Line2D.new()
	outer.name = "WorldFrameOuter"
	outer.points = PackedVector2Array([
		Vector2(-14, -14), Vector2(2014, -14), Vector2(2014, 1014),
		Vector2(-14, 1014), Vector2(-14, -14)])
	outer.width = 1.0
	outer.default_color = Color(0.80, 0.65, 0.30, 0.20)
	outer.z_index = 3
	outer.antialiased = true
	add_child(outer)

# ── TELA DE CARREGAMENTO ──
# 100 dicas reais de mecânica — uma a cada ~3s enquanto o mundo monta
const LOAD_TIPS := [
	"Você tem 3 ações por turno — gaste com estratégia, elas não acumulam.",
	"Cada turno é 1 mês. A campanha completa atravessa 100 anos: 1200 turnos.",
	"A espiral de crise é real: estabilidade <30 e apoio <35 se retroalimentam até o colapso.",
	"Uma crise ignorada derruba um governo em ~14 meses. Aja rápido.",
	"Autocracias não trocam de líder por impopularidade — só por morte ou golpe.",
	"Democracias fazem eleições a cada ~5 anos. Impopularidade prolongada custa o cargo.",
	"Quando um líder cai, o sucessor pode ter outra ideologia — e mudar o rumo do país.",
	"A ideologia econômica do líder dirige as decisões dos 194 bots.",
	"Líderes vivem ~100 anos. Ditadores idosos são bombas-relógio de sucessão.",
	"O rating de crédito (AAA a D) define os juros dos seus empréstimos.",
	"Dívida acima de 1,5x o PIB freia o crescimento e assusta investidores.",
	"Calote destrói o rating por décadas. Amortize antes do teto de 2,5x PIB.",
	"Superávit comercial sustentado acelera o PIB; déficit crônico o corrói.",
	"Exportar commodity BRUTA rende menos que manufaturar. Industrialize.",
	"O Upgrade Industrial converte matéria bruta em manufatura: +60% de valor agregado.",
	"Complexidade econômica alta = crescimento estável e menos exposto a choques.",
	"Exportadores de commodity bruta sofrem inflação mais volátil. Diversifique.",
	"A bolsa rende no longo prazo, mas choques globais derrubam o índice.",
	"Limite prudencial: invista no máximo 40% do caixa em ações.",
	"A WorldCoin oscila em ciclos. Compre no pânico, venda na euforia.",
	"Adotar cripto como moeda legal reduz o impacto de sanções em 60%.",
	"Tesouro zerado por 4 turnos = falência nacional. O FMI cobra caro pelo resgate.",
	"O resgate do FMI corta seu gasto social pela metade. Soberania tem preço.",
	"Inflação acima de 15% corrói felicidade, apoio e receita ao mesmo tempo.",
	"Hiperinflação (80%+) é espiral de morte. Aperto monetário custa PIB, mas salva.",
	"Gasto militar acima de 5% do PIB pressiona a inflação.",
	"Corrupção alta rouba o tesouro TODO turno e espanta empresas.",
	"A Reforma Judicial derruba corrupção em 10 pontos. Cara, mas transforma.",
	"Confiança do investidor baixa = êxodo de capital. Empresas saem de vez.",
	"Burocracia eficiente multiplica a receita de impostos.",
	"Blocos geopolíticos dão bônus comerciais e defesa coletiva.",
	"Entrar na OTAN protege — mas te arrasta para as guerras do bloco.",
	"Afinidade ideológica aproxima nações parecidas e afasta opostas, turno a turno.",
	"Democracias de mercado confiam umas nas outras. Autocracias também.",
	"Se você dominar demais, o mundo forma uma coalizão de contenção contra você.",
	"Hegemonia exige PIB de 40% ou mais do líder mundial por 4 anos seguidos — após 2025.",
	"Sua nemesis te provoca em ciclos. No Brutal, a cada 8 meses.",
	"Declare guerra com um OBJETIVO: reparações, recursos ou mudança de regime.",
	"Vitória com objetivo de regime impõe seu sistema político ao derrotado.",
	"Guerras drenam 12% de eficiência por frente. Três frentes = metade das ações.",
	"Guerra longa gera crise humanitária — e o mundo lembra.",
	"DEFCON 1 significa guerra nuclear iminente. Recue ou aperte o botão.",
	"Espionagem revela segredos; contra-inteligência protege os seus.",
	"Intel score alto abre operações avançadas: sabotagem, roubo de tech, propaganda.",
	"Cada ministério tem trilha própria de pesquisa. 57 techs no total.",
	"Ministério nível 5 executa ações 40% mais fortes.",
	"Techs concluídas dão bônus permanente de ação: +0,5% cada, até +25%.",
	"25+ techs libertam seu país da armadilha da renda média.",
	"O catch-up é real: países pobres com boas instituições crescem mais rápido.",
	"Na fronteira tecnológica o crescimento desacelera. Inove ou estagne.",
	"Tratados de livre comércio rendem mais com vizinhos ricos.",
	"Pacto de não-agressão segura um vizinho hostil por 10 anos.",
	"Embaixadas melhoram relações e abrem canais de espionagem.",
	"Sanções machucam mais quem depende de importações.",
	"Dependência de importação acima de 50% é vulnerabilidade estratégica.",
	"No filtro Recursos, o mapa mostra a riqueza dominante de cada nação.",
	"O filtro Economia pinta o mundo por PIB — os azuis fortes mandam.",
	"O filtro Estabilidade expõe os países à beira do colapso. Oportunidade?",
	"Satélite = NASA Blue Marble real. Aperte zoom na sua capital.",
	"Passe o mouse num país: fronteira dourada + dossiê no clique.",
	"O ticker embaixo mostra 3 emissoras: nacional, regional e global.",
	"Modo Inspirado: o 11 de Setembro, a crise de 2008 e a COVID virão no tempo real.",
	"Modo Livre: a história é só sua. Sem âncoras do mundo real.",
	"Cenário Década Crítica começa em 2020, com o mundo pegando fogo.",
	"Guerra Fria 2.0: EUA x China, DEFCON 3, corrida tecnológica acelerada.",
	"Dificuldade Brutal: crises 2,2x mais fundas e rivais implacáveis.",
	"No Fácil você aprende; no Normal você joga; no Brutal você sobrevive.",
	"XP ganho vira perks permanentes entre campanhas. Derrota também ensina.",
	"Propaganda estatal dá apoio rápido — mas o efeito enfraquece se repetir.",
	"Estímulo fiscal aquece o PIB e o povo. Cuidado com a inflação depois.",
	"Megaprojetos impressionam (+2,5% PIB) mas desgastam a estabilidade.",
	"Subsídios setoriais compram crescimento com corrupção. Vale a pena?",
	"Explorar recursos eleva seu recurso mais escasso em +15%.",
	"Universidades: pesquisa +8% e PIB +0,5%. O investimento que sempre paga.",
	"Vacinação em massa: felicidade +6 e população crescendo.",
	"Rede hospitalar sólida segura a estabilidade em tempos de crise.",
	"Recrute infantaria barata cedo; navios e aviões custam caro depois.",
	"Bases militares projetam poder: +10 de poder global cada.",
	"Poder global = economia (40%) + militar + tech + diplomacia.",
	"Score é história: tudo que você constrói e sobrevive soma pontos.",
	"Nações pequenas PODEM virar potência — o poder usa escala comprimida.",
	"Um Chile bem jogado vale mais que um império mal administrado.",
	"A elite rouba enquanto você não olha: corrupção cresce sozinha.",
	"Gasto social melhora felicidade — e felicidade segura eleições.",
	"O PIB per capita define seu estágio: pobre cresce rápido, rico inova.",
	"Choque do petróleo dobra o valor de exportação de quem tem energia.",
	"Recessão global derruba todos os PIBs. Caixa cheio é seguro.",
	"Pandemias fecham comércio. Saúde alta = recuperação rápida.",
	"Eventos históricos pedem decisões. Não existe escolha sem custo.",
	"Storylines secretas se desbloqueiam com suas decisões acumuladas.",
	"Conquistas rendem XP extra. Colecione-as entre campanhas.",
	"O jogo salva sozinho a cada turno. Feche sem medo.",
	"Aliados aparecem em verde no mapa; inimigos pulsam em vermelho.",
	"A moldura dourada marca o fim do mundo jogável. Não há nada além.",
	"Zoom out total mostra o planeta inteiro entre as barras.",
	"Os Andes, o Saara e o Himalaia estão lá de verdade. Olhe de perto.",
	"Groenlândia e Antártida: brancas, geladas e sem PIB relevante.",
	"O sucessor herda o país — mas não as suas promessas.",
	"Cada campanha é única: 195 nações, 195 histórias possíveis.",
	"O hover acende o país em dourado. O clique abre o dossiê completo.",
]

var _loading_layer: CanvasLayer = null

func _show_loading_screen() -> void:
	_loading_layer = CanvasLayer.new()
	_loading_layer.layer = 100
	add_child(_loading_layer)
	# Fundo com TEXTURA (metal desgastado azul-petróleo) — cobre a tela toda
	var bg := TextureRect.new()
	bg.texture = load("res://assets/loading_bg.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_layer.add_child(bg)
	# Vinheta escura por cima (foca o centro + garante legibilidade do texto)
	var vig := ColorRect.new()
	vig.color = Color(0.01, 0.015, 0.025, 0.55)
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_layer.add_child(vig)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_layer.add_child(center)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	center.add_child(v)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Caixa EXATA no aspect do logo (1080x1350 = 0.8): sem vazio em volta.
	# (Antes a caixa tinha largura solta: o logo encolhia p/ a largura do
	# texto e sobrava um buraco enorme até o "Carregando…")
	logo.custom_minimum_size = Vector2(576, 720)
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(logo)
	var lbl := Label.new()
	lbl.name = "LoadingLabel"
	lbl.text = "Carregando o mundo…"
	lbl.add_theme_color_override("font_color", Color(0.88, 0.83, 0.70))
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(lbl)
	# SPINNER de arco (desenhado via _draw — suave, profissional)
	var spin := Control.new()
	spin.name = "LoadingSpinner"
	spin.set_script(load("res://scripts/LoadingSpinner.gd"))
	spin.custom_minimum_size = Vector2(58, 58)
	spin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(spin)
	var tip := Label.new()
	tip.name = "LoadingTip"
	tip.text = "💡 " + LOAD_TIPS[randi() % LOAD_TIPS.size()]
	tip.add_theme_color_override("font_color", Color(0.70, 0.67, 0.60))
	tip.add_theme_font_size_override("font_size", 13)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(680, 0)
	tip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(tip)
	# Rotação de dicas: espera → fade-out → troca → fade-in (~3,2s por dica)
	var tip_tw := tip.create_tween().set_loops()
	tip_tw.tween_interval(2.6)
	tip_tw.tween_property(tip, "modulate:a", 0.0, 0.30).set_trans(Tween.TRANS_CUBIC)
	tip_tw.tween_callback(func():
		if is_instance_valid(tip):
			tip.text = "💡 " + LOAD_TIPS[randi() % LOAD_TIPS.size()])
	tip_tw.tween_property(tip, "modulate:a", 1.0, 0.30).set_trans(Tween.TRANS_CUBIC)
	# Respiração do texto (vida enquanto carrega)
	var tw := lbl.create_tween().set_loops()
	tw.tween_property(lbl, "modulate:a", 0.45, 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_property(lbl, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)

func _hide_loading_screen() -> void:
	if _loading_layer == null or not is_instance_valid(_loading_layer):
		return
	var layer := _loading_layer
	_loading_layer = null
	# Fade cinematográfico: o mundo "acende" por trás do loading
	var faders: Array = []
	for c in layer.get_children():
		if c is CanvasItem:
			faders.append(c)
	if faders.is_empty():
		layer.queue_free()
		return
	var tw := (faders[0] as CanvasItem).create_tween()
	for f in faders:
		tw.parallel().tween_property(f, "modulate:a", 0.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(layer.queue_free)

# Fade-in cinematográfico ao entrar no mapa: overlay preto desvanece e o
# mundo "acende". Roda por cima de tudo (CanvasLayer 99) e se remove sozinho.
func _play_scene_fade_in() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 99
	add_child(layer)
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 1)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(black)
	var tw := black.create_tween()
	tw.tween_property(black, "color:a", 0.0, 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(layer.queue_free)

# Animação pulse contínuo no botão "PRÓXIMO TURNO"
func _start_next_turn_pulse() -> void:
	if next_turn_button == null: return
	var tw := create_tween().set_loops()
	tw.tween_property(next_turn_button, "modulate", Color(1.15, 1.15, 1.15), 1.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(next_turn_button, "modulate", Color(1, 1, 1), 1.0).set_trans(Tween.TRANS_SINE)

# ─────────────────────────────────────────────────────────────────
# CONSTRUÇÃO DOS WIDGETS LEGADOS
# Cria LeftPanel, RightPanel, GameOverlay como nós invisíveis sob o ModalLayer.
# Mantém todas as referências @onready do código antigo funcionando.
# ─────────────────────────────────────────────────────────────────

func _build_legacy_nodes() -> void:
	# Tamanhos calibrados pra caber no modal (modal_min - 60 de padding/margem)
	# ─── LEFT PANEL (lista de seleção de nação) — modal será 540 ───
	left_panel = PanelContainer.new()
	left_panel.name = "LeftPanel"
	left_panel.custom_minimum_size = Vector2(460, 600)
	left_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 10)
	left_panel.add_child(lv)
	var lp_title := Label.new()
	lp_title.text = "■ SELECIONE SUA NAÇÃO"
	lp_title.add_theme_color_override("font_color", Color(0.85, 0.70, 0.34, 0.95))
	lp_title.add_theme_font_size_override("font_size", 14)
	lv.add_child(lp_title)
	var lp_sub := Label.new()
	lp_sub.text = "195 nações disponíveis — escolha sabiamente"
	lp_sub.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
	lp_sub.add_theme_font_size_override("font_size", 11)
	lv.add_child(lp_sub)
	lv.add_child(HSeparator.new())
	search_box = LineEdit.new()
	search_box.name = "SearchBox"
	search_box.placeholder_text = "🔍 Buscar nação..."
	lv.add_child(search_box)
	sort_button = OptionButton.new()
	sort_button.name = "SortButton"
	lv.add_child(sort_button)
	nations_list = ItemList.new()
	nations_list.name = "NationsList"
	nations_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nations_list.custom_minimum_size = Vector2(0, 380)
	nations_list.auto_height = false
	lv.add_child(nations_list)
	# left_panel é adicionado em modal quando precisa

	# ─── RIGHT PANEL (dossiê do país) ───
	right_panel = PanelContainer.new()
	right_panel.name = "RightPanel"
	right_panel.custom_minimum_size = Vector2(460, 580)
	right_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	right_panel.visible = false
	var rscroll := ScrollContainer.new()
	rscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_panel.add_child(rscroll)
	var rv := VBoxContainer.new()
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.custom_minimum_size = Vector2(420, 0)
	rv.add_theme_constant_override("separation", 10)
	rscroll.add_child(rv)
	# Header: bandeira + nome
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 14)
	header_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	rv.add_child(header_row)
	# Bandeira: PanelContainer com listras coloridas (ColorRects desenhados em runtime)
	# Usa um Panel pra ter borda + corner radius, e um VBox/HBox interno pra listras
	preview_flag = PanelContainer.new()
	preview_flag.name = "PreviewFlag"
	preview_flag.custom_minimum_size = Vector2(64, 44)
	preview_flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var flag_style := StyleBoxFlat.new()
	flag_style.bg_color = Color(0.08, 0.10, 0.14, 1)
	flag_style.set_border_width_all(1)
	flag_style.border_color = Color(0.3, 0.5, 0.65, 0.8)
	flag_style.set_corner_radius_all(4)
	flag_style.content_margin_left = 0
	flag_style.content_margin_right = 0
	flag_style.content_margin_top = 0
	flag_style.content_margin_bottom = 0
	preview_flag.add_theme_stylebox_override("panel", flag_style)
	preview_flag.clip_contents = true
	header_row.add_child(preview_flag)
	# Retrato do líder da nação em foco (o "Presidente" daquele povo)
	preview_portrait_slot = Control.new()
	preview_portrait_slot.name = "PreviewPortraitSlot"
	preview_portrait_slot.custom_minimum_size = Vector2(50, 60)
	preview_portrait_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_row.add_child(preview_portrait_slot)
	preview_name = Label.new()
	preview_name.name = "PreviewName"
	preview_name.add_theme_color_override("font_color", Color(0, 0.95, 1))
	preview_name.add_theme_font_size_override("font_size", 26)
	preview_name.text = "—"
	preview_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(preview_name)
	preview_iso = Label.new()
	preview_iso.name = "PreviewISO"
	preview_iso.add_theme_color_override("font_color", Color(0.5, 0.65, 0.85))
	preview_iso.add_theme_font_size_override("font_size", 11)
	preview_iso.text = "—"
	rv.add_child(preview_iso)
	preview_tier = Label.new()
	preview_tier.name = "PreviewTier"
	preview_tier.add_theme_color_override("font_color", Color(0, 1, 0.5))
	preview_tier.add_theme_font_size_override("font_size", 13)
	preview_tier.text = "—"
	rv.add_child(preview_tier)
	preview_desc = Label.new()
	preview_desc.name = "PreviewDesc"
	preview_desc.add_theme_color_override("font_color", Color(0.7, 0.78, 0.88))
	preview_desc.add_theme_font_size_override("font_size", 11)
	preview_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_desc.text = "—"
	rv.add_child(preview_desc)
	rv.add_child(HSeparator.new())
	var rt := Label.new()
	rt.text = "■ DOSSIÊ"
	rt.add_theme_color_override("font_color", Color(0.45, 0.55, 0.7))
	rt.add_theme_font_size_override("font_size", 11)
	rv.add_child(rt)
	preview_stats = GridContainer.new()
	preview_stats.name = "PreviewStats"
	preview_stats.columns = 2
	preview_stats.add_theme_constant_override("h_separation", 18)
	preview_stats.add_theme_constant_override("v_separation", 5)
	rv.add_child(preview_stats)
	rv.add_child(HSeparator.new())
	# ─── Vantagens / Desvantagens ───
	var pc_title := Label.new()
	pc_title.text = "■ ANÁLISE ESTRATÉGICA"
	pc_title.add_theme_color_override("font_color", Color(0.45, 0.55, 0.7))
	pc_title.add_theme_font_size_override("font_size", 11)
	rv.add_child(pc_title)
	preview_pros_cons = VBoxContainer.new()
	preview_pros_cons.name = "PreviewProsCons"
	preview_pros_cons.add_theme_constant_override("separation", 4)
	rv.add_child(preview_pros_cons)
	rv.add_child(HSeparator.new())
	# Botões do dossiê
	confirm_button = Button.new()
	confirm_button.name = "ConfirmButton"
	confirm_button.custom_minimum_size = Vector2(0, 46)
	confirm_button.add_theme_font_size_override("font_size", 14)
	confirm_button.text = "⚡ ASSUMIR COMANDO"
	rv.add_child(confirm_button)
	declare_war_button = _create_action_btn("DeclareWarButton", "⚔️ DECLARAR GUERRA")
	rv.add_child(declare_war_button)
	propose_peace_button = _create_action_btn("ProposePeaceButton", "🕊️ PROPOR PAZ")
	rv.add_child(propose_peace_button)
	embassy_button = _create_action_btn("EmbassyButton", "🤝 ENVIAR EMBAIXADA")
	rv.add_child(embassy_button)
	sanctions_button = _create_action_btn("SanctionsButton", "🚫 IMPOR SANÇÕES")
	rv.add_child(sanctions_button)
	propose_treaty_button = _create_action_btn("ProposeTreatyButton", "📜 PROPOR TRATADO")
	rv.add_child(propose_treaty_button)
	trade_button = _create_action_btn("TradeButton", "💰 EXPORTAR RECURSO")
	rv.add_child(trade_button)
	espionage_button = _create_action_btn("EspionageButton", "🕵 OPERAÇÃO DE ESPIONAGEM")
	rv.add_child(espionage_button)

	# ─── GAME OVERLAY (9 painéis temáticos do jogador) ───
	# Reaproveita o script GameOverlay.gd ATTACHED via SetScript
	game_overlay = Control.new()
	game_overlay.name = "GameOverlay"
	game_overlay.set_script(preload("res://scripts/GameOverlay.gd"))
	game_overlay.visible = false
	# O overlay preenche o card do modal (sem largura fixa que encostava à esq.)
	game_overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game_overlay.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Estrutura interna esperada pelo GameOverlay.gd
	var go_panel := PanelContainer.new()
	go_panel.name = "PlayerPanel"
	go_panel.custom_minimum_size = Vector2(560, 620)
	go_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	go_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# TRANSPARENTE: o modal já é o card — nada de card-dentro-de-card
	var flat := StyleBoxEmpty.new()
	go_panel.add_theme_stylebox_override("panel", flat)
	game_overlay.add_child(go_panel)
	var go_v := VBoxContainer.new()
	go_v.add_theme_constant_override("separation", 8)
	go_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	go_panel.add_child(go_v)
	var nh := Label.new()
	nh.name = "NationHeader"
	nh.unique_name_in_owner = true
	nh.add_theme_color_override("font_color", Color(0, 0.823, 1))
	nh.add_theme_font_size_override("font_size", 20)
	nh.text = "—"
	go_v.add_child(nh)
	var nt := Label.new()
	nt.name = "NationTier"
	nt.unique_name_in_owner = true
	nt.add_theme_color_override("font_color", Color(0.7, 0.85, 1))
	nt.add_theme_font_size_override("font_size", 11)
	nt.text = "—"
	go_v.add_child(nt)
	go_v.add_child(HSeparator.new())
	# PanelTabs mantido no owner (compat com _resolve_widgets/_build_tabs) mas
	# OCULTO: cada painel já tem seu botão na barra inferior — a fila de tabs
	# aqui dentro era redundante e desalinhava o topo do modal.
	var pt := HBoxContainer.new()
	pt.name = "PanelTabs"
	pt.unique_name_in_owner = true
	pt.visible = false
	go_v.add_child(pt)
	var ps := ScrollContainer.new()
	ps.name = "PanelScroll"
	ps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ps.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ps.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	go_v.add_child(ps)
	var pc := VBoxContainer.new()
	pc.name = "PanelContent"
	pc.unique_name_in_owner = true
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.add_theme_constant_override("separation", 8)
	ps.add_child(pc)

	# Floater não existe mais — botão Próximo Turno agora vive na bottom bar.
	next_turn_floater = Control.new()
	next_turn_floater.name = "DeprecatedFloater"
	next_turn_floater.visible = false

func _create_action_btn(node_name: String, label: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.visible = false
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", 12)
	b.text = label
	return b

# ─────────────────────────────────────────────────────────────────
# SISTEMA DE MODAL CENTRAL
# ─────────────────────────────────────────────────────────────────

# Verdadeiro se há algum modal aberto — usado pra travar input do mapa
func _is_modal_open() -> bool:
	return _modal_stack.size() > 0

# Cria backdrop full-screen + card central com `content` como filho.
# Retorna o nó do modal pra quem precisa fechar manualmente.
func _open_modal(content: Control, title: String = "", min_size: Vector2 = Vector2(560, 480), closable: bool = true) -> Control:
	if modal_layer == null: return null
	modal_layer.visible = true
	# Para inércia/animação de câmera ao abrir modal (impede que continue se mexendo)
	pan_velocity = Vector2.ZERO
	camera_animating = false
	is_dragging = false

	var modal := Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.z_index = 10 + _modal_stack.size()
	modal_layer.add_child(modal)

	var bg := ColorRect.new()
	bg.color = Color(0, 0.05, 0.08, 0.78)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP if not closable else Control.MOUSE_FILTER_PASS
	modal.add_child(bg)
	# Click no backdrop fecha o modal (se closable)
	if closable:
		bg.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_close_modal(modal))

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	modal.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = min_size
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.06, 0.10, 0.99)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.80, 0.65, 0.30, 0.60)
	sb.set_corner_radius_all(14)
	# (sem shadow externo — visual pode iludir hitbox)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	card.add_theme_stylebox_override("panel", sb)
	center.add_child(card)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(v)

	# Cabeçalho com título + botão de fechar (X)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	if title != "":
		var tl := Label.new()
		tl.text = title
		tl.add_theme_color_override("font_color", Color(0.95, 1, 1))
		tl.add_theme_font_size_override("font_size", 20)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(tl)
	else:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(spacer)
	if closable:
		var x := Button.new()
		x.text = "✕"
		x.custom_minimum_size = Vector2(36, 32)
		x.add_theme_font_size_override("font_size", 16)
		x.pressed.connect(func(): _close_modal(modal))
		head.add_child(x)

	# Linha decorativa ciano
	var deco := ColorRect.new()
	deco.color = Color(0.80, 0.65, 0.30, 0.50)
	deco.custom_minimum_size = Vector2(80, 2)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(deco)

	# Conteúdo — preenche a largura/altura do card do modal
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(content)

	# Animação de entrada padrão (fade do backdrop + scale-in do card).
	# O pivot bug antigo foi resolvido no helper (pivô re-calculado no resized).
	UIStyles.animate_modal_in(modal, card)

	_modal_stack.append(modal)
	return modal

func _close_modal(modal: Control) -> void:
	if modal == null or not is_instance_valid(modal): return
	_modal_stack.erase(modal)
	# Limpa referência ao modal de seleção se for ele
	if modal == _select_modal:
		_select_modal = null
	# Re-parenta conteúdo crítico antes de free pra não destruir widgets reutilizáveis
	_detach_persistent_content(modal)
	modal.queue_free()
	if _modal_stack.is_empty() and modal_layer:
		modal_layer.visible = false

func _close_top_modal() -> void:
	if _modal_stack.is_empty(): return
	_close_modal(_modal_stack[-1])

# Tira widgets que devem persistir (left_panel, right_panel, game_overlay)
# do modal antes de queue_free
func _detach_persistent_content(modal: Control) -> void:
	for persist in [left_panel, right_panel, game_overlay]:
		if persist == null or not is_instance_valid(persist): continue
		if persist.get_parent() != null and persist.is_ancestor_of(modal) == false and modal.is_ancestor_of(persist):
			persist.get_parent().remove_child(persist)
			persist.visible = false

# ─── Modais específicos ───

# Track do modal de seleção pra reaproveitar quando o usuário clica em país
var _select_modal: Control = null

func _open_select_nation_modal() -> void:
	# Modal LARGO: lista à esquerda, dossiê à direita, num único container.
	if left_panel == null or right_panel == null: return
	# Tira ambos do parent atual (caso estejam em outro modal)
	if left_panel.get_parent() != null:
		left_panel.get_parent().remove_child(left_panel)
	if right_panel.get_parent() != null:
		right_panel.get_parent().remove_child(right_panel)
	left_panel.visible = true
	right_panel.visible = true
	# Reduz o size dos sub-painéis pra caberem lado a lado no modal único
	left_panel.custom_minimum_size = Vector2(420, 600)
	right_panel.custom_minimum_size = Vector2(540, 600)
	# Remove o background/border dos sub-painéis (o modal já tem) — fica mais clean
	var blank := StyleBoxFlat.new()
	blank.bg_color = Color(0, 0, 0, 0)
	blank.set_border_width_all(0)
	blank.content_margin_left = 0
	blank.content_margin_right = 0
	blank.content_margin_top = 0
	blank.content_margin_bottom = 0
	left_panel.add_theme_stylebox_override("panel", blank)
	right_panel.add_theme_stylebox_override("panel", blank)

	# Container com divisor visual entre os dois painéis
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 20)
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(left_panel)
	# Linha vertical decorativa
	var vsep := ColorRect.new()
	vsep.color = Color(0.78, 0.62, 0.28, 0.35)
	vsep.custom_minimum_size = Vector2(2, 0)
	vsep.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vsep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	split.add_child(vsep)
	split.add_child(right_panel)

	_select_modal = _open_modal(split, "🌍 SELECIONE SUA NAÇÃO", Vector2(1080, 660), false)
	# Pré-seleciona a 1ª nação: o dossiê abre preenchido (nunca vazio/quebrado)
	if preview_code == "" and nations_list != null and nations_list.item_count > 0:
		nations_list.select(0)
		_on_nation_list_selected(0)

# Mantido para compatibilidade — abre dossiê quando NÃO há modal de seleção aberto
# (ex: após assumir comando, clicando em outro país no mapa)
func _open_dossier_modal(code: String) -> void:
	if right_panel == null: return
	preview_code = code
	if code != player_code:
		_paint_country(code, COUNTRY_PREVIEW)
	_fill_preview_panel(code)
	# Se modal de seleção está aberto, NÃO abre outro modal — o painel direito já está lá
	if _select_modal != null and is_instance_valid(_select_modal):
		return
	# Restaura o panel-style do right_panel (caso tenha sido limpo pra modal de seleção)
	right_panel.remove_theme_stylebox_override("panel")
	if right_panel.get_parent() != null:
		right_panel.get_parent().remove_child(right_panel)
	right_panel.visible = true
	right_panel.custom_minimum_size = Vector2(540, 600)
	var nation_name: String = "—"
	if GameEngine.nations.has(code):
		nation_name = GameEngine.nations[code].nome
	_open_modal(right_panel, "📋 DOSSIÊ — %s" % nation_name, Vector2(580, 720))

func _open_overlay_modal(panel_id: String = "governo") -> void:
	# Caso especial: o painel "noticias" agora abre o modal dedicado de notícias
	if panel_id == "noticias":
		_open_news_modal()
		return
	if game_overlay == null: return
	if not game_overlay.has_method("activate"): return
	if game_overlay.get_parent() != null:
		game_overlay.get_parent().remove_child(game_overlay)
	game_overlay.visible = true
	# Se ainda não foi ativado, ativa agora
	if not game_overlay.activated:
		game_overlay.activate()
	# Troca para o painel pedido
	if game_overlay.has_method("_on_tab_pressed"):
		game_overlay._on_tab_pressed(panel_id)
	_open_modal(game_overlay, "", Vector2(680, 720))

# ─────────────────────────────────────────────────────────────────
# MODAL DE DECISÃO HISTÓRICA (FASE 4)
# Disparado quando timeline.historic_event_decision é emitido —
# evento âncora com modal_decision=true e jogador é o primary_country.
# Aplica choices[i].effects via timeline.apply_choice_by_id().
# ─────────────────────────────────────────────────────────────────

# Storylines disparam através do mesmo modal de decisão histórica.
# A diferença é que ao escolher, chama storylines.apply_storyline_choice
# (em vez de timeline.apply_choice_by_id).
func _on_storyline_triggered(storyline_id: String, event: Dictionary) -> void:
	_open_historic_decision_modal(event)

func _open_historic_decision_modal(event: Dictionary) -> void:
	if event.is_empty(): return

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	content.custom_minimum_size = Vector2(700, 0)

	# Bandeira animada de "evento histórico"
	var badge := Label.new()
	badge.text = "◆ EVENTO HISTÓRICO"
	badge.add_theme_color_override("font_color", Color(1, 0.78, 0.30, 0.95))
	badge.add_theme_font_size_override("font_size", 11)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(badge)

	# Headline
	var headline := Label.new()
	headline.text = event.get("headline", "—")
	headline.add_theme_color_override("font_color", Color(0.95, 1, 1))
	headline.add_theme_font_size_override("font_size", 22)
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	headline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(headline)

	# Linha decorativa
	var deco := ColorRect.new()
	deco.color = Color(1, 0.78, 0.30, 0.6)
	deco.custom_minimum_size = Vector2(80, 2)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(deco)

	# Contexto (data + categorias)
	var ctx := Label.new()
	var year: int = int(event.get("year", 0))
	var quarter: int = int(event.get("month", event.get("quarter", 1)))
	var quarters := ["JAN", "FEV", "MAR", "ABR", "MAI", "JUN", "JUL", "AGO", "SET", "OUT", "NOV", "DEZ"]
	var cats: Array = event.get("categories", [])
	ctx.text = "📅 %s %d   •   %s" % [quarters[clamp(quarter - 1, 0, 11)], year, "  ·  ".join(cats)]
	ctx.add_theme_color_override("font_color", Color(0.55, 0.65, 0.78))
	ctx.add_theme_font_size_override("font_size", 11)
	ctx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(ctx)

	# Body (descrição do evento)
	var body := Label.new()
	body.text = event.get("body", "")
	body.add_theme_color_override("font_color", Color(0.82, 0.90, 1))
	body.add_theme_font_size_override("font_size", 13)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(0, 60)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(body)

	# Bloco de CONSELHEIROS (cada um recomenda 1 choice, com viés diferente)
	var choices_for_recommend: Array = event.get("choices", [])
	if choices_for_recommend.size() >= 2:
		_render_advisor_panel(content, choices_for_recommend, event)

	# Pergunta
	var prompt := Label.new()
	prompt.text = "Qual será sua resposta como líder?"
	prompt.add_theme_color_override("font_color", Color(0, 0.95, 1))
	prompt.add_theme_font_size_override("font_size", 14)
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(prompt)

	# Ref pra fechar de dentro dos callbacks
	var modal_ref: Array = [null]
	var event_id: String = event.get("id", "")

	# Lista de choices como botões grandes verticais
	var choices: Array = event.get("choices", [])
	for i in choices.size():
		var ch: Dictionary = choices[i]
		var btn := Button.new()
		btn.text = "  %s" % ch.get("label", "Opção %d" % (i + 1))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 52)
		btn.add_theme_font_size_override("font_size", 13)
		# Estilo distinto pra esses botões (border esquerdo amarelo)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.10, 0.14, 0.95)
		sb.border_color = Color(1, 0.78, 0.30, 0.85)
		sb.set_border_width_all(1)
		sb.border_width_left = 4
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 18
		sb.content_margin_right = 14
		sb.content_margin_top = 12
		sb.content_margin_bottom = 12
		var sb_h := sb.duplicate() as StyleBoxFlat
		sb_h.bg_color = Color(0, 0.40, 0.60, 0.9)
		sb_h.border_color = Color(0, 1, 1, 1)
		var sb_p := sb.duplicate() as StyleBoxFlat
		sb_p.bg_color = Color(0, 0.30, 0.48, 1)
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb_h)
		btn.add_theme_stylebox_override("pressed", sb_p)
		btn.add_theme_stylebox_override("focus", sb_h)
		btn.add_theme_color_override("font_color", Color(0.92, 0.96, 1))
		btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
		var choice_id: String = ch.get("id", "choice_%d" % i)
		var is_storyline: bool = bool(event.get("is_storyline", false))
		var storyline_id: String = String(event.get("storyline_id", ""))
		btn.pressed.connect(func():
			if is_storyline and GameEngine and GameEngine.storylines:
				GameEngine.storylines.apply_storyline_choice(storyline_id, choice_id)
				_log_ticker("📖 NARRATIVA", "Decisão: %s" % ch.get("label", "?"), Color(0.85, 0.6, 1))
			elif GameEngine and GameEngine.timeline:
				GameEngine.timeline.apply_choice_by_id(event_id, choice_id)
				_log_ticker("📜 HISTÓRIA", "Decisão tomada: %s" % ch.get("label", "?"), Color(1, 0.85, 0.4))
			_close_modal(modal_ref[0]))
		content.add_child(btn)

	# Aviso de irreversibilidade
	var warn := Label.new()
	warn.text = "⚠ Decisão irreversível — afeta sua nação e o mundo"
	warn.add_theme_color_override("font_color", Color(1, 0.55, 0.35, 0.85))
	warn.add_theme_font_size_override("font_size", 10)
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(warn)

	modal_ref[0] = _open_modal(content, "🕰 MOMENTO HISTÓRICO", Vector2(740, 600), false)

# ─────────────────────────────────────────────────────────────────
# MODAL DE NOTÍCIAS — filtros: Globais, Aliados, Inimigos, Regionais, Nacionais
# + filtro de tempo: 5 turnos / 20 turnos / Tudo
# ─────────────────────────────────────────────────────────────────

var _news_filter_scope: String = "global"  # global | ally | enemy | regional | national
var _news_filter_window: int = 5  # turnos para trás; 0 = tudo

const NEWS_SCOPES := [
	{"id": "global",   "icon": "🌐", "label": "Globais"},
	{"id": "ally",     "icon": "🤝", "label": "Aliados"},
	{"id": "enemy",    "icon": "⚔",  "label": "Inimigos"},
	{"id": "regional", "icon": "🗺", "label": "Regionais"},
	{"id": "national", "icon": "🏛", "label": "Nacionais"},
]

const NEWS_WINDOWS := [
	{"label": "Últimos 5 turnos", "value": 5},
	{"label": "Últimos 20 turnos", "value": 20},
	{"label": "Tudo", "value": 0},
]

func _open_news_modal() -> void:
	# Container raiz (vai pro _open_modal)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	root.mouse_filter = Control.MOUSE_FILTER_PASS

	# ─── Bancada do WON: âncora dá o "boa noite" e a chamada urgente ───
	if GameEngine.player_nation != null:
		var anchor_row := PanelContainer.new()
		var asb := StyleBoxFlat.new()
		asb.bg_color = Color(0.07, 0.11, 0.18, 0.95)
		asb.border_width_left = 4
		asb.border_color = Color(0.25, 0.55, 0.9)
		asb.set_corner_radius_all(6)
		asb.content_margin_left = 10
		asb.content_margin_right = 10
		asb.content_margin_top = 8
		asb.content_margin_bottom = 8
		anchor_row.add_theme_stylebox_override("panel", asb)
		root.add_child(anchor_row)
		var arow := HBoxContainer.new()
		arow.add_theme_constant_override("separation", 12)
		anchor_row.add_child(arow)
		# Detecta a última manchete urgente + o ESCOPO dela (define a emissora)
		var urgent := ""
		var urgent_scope := "global"
		for i in range(GameEngine.news_history.size() - 1, -1, -1):
			var ht: String = String(GameEngine.news_history[i].get("type", ""))
			if ht in ["guerra", "choque", "guerra_vencida", "fmi", "corrupcao"]:
				urgent = String(GameEngine.news_history[i].get("headline", ""))
				urgent_scope = String(GameEngine.news_history[i].get("scope", "global"))
				break
		# Identidade da emissora por escopo (National / Regional / Global News)
		var nets := {
			"national": ["🏛 NN — NATIONAL NEWS", Color(1, 0.82, 0.3), "Aqui é a National News — o seu país em primeiro lugar."],
			"regional": ["📡 RN — REGIONAL NEWS", Color(0.5, 0.85, 0.65), "Aqui é a Regional News, cobrindo o continente."],
			"global": ["🌍 GN — GLOBAL NEWS", Color(0.4, 0.7, 1), "Boa noite. Aqui é a Global News — o mundo em tempo real."],
		}
		var net: Array = nets.get(urgent_scope, nets["global"])
		var apv := PortraitView.make(GameEngine.player_nation.codigo_iso, "ancora",
			"urgente" if urgent != "" else "neutro", 62.0)
		apv.custom_minimum_size = Vector2(62, 74)
		apv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		arow.add_child(apv)
		var atxt := VBoxContainer.new()
		atxt.add_theme_constant_override("separation", 2)
		atxt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		arow.add_child(atxt)
		var wonlbl := Label.new()
		wonlbl.text = String(net[0])
		wonlbl.add_theme_color_override("font_color", net[1])
		wonlbl.add_theme_font_size_override("font_size", 11)
		atxt.add_child(wonlbl)
		var falalbl := Label.new()
		falalbl.text = ("🔴 PLANTÃO: " + urgent) if urgent != "" else "“%s”" % String(net[2])
		falalbl.add_theme_color_override("font_color", Color(0.9, 0.94, 1) if urgent != "" else Color(0.78, 0.85, 0.95))
		falalbl.add_theme_font_size_override("font_size", 13)
		falalbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		atxt.add_child(falalbl)

	# ─── Linha de filtros ───
	var filters_row := HBoxContainer.new()
	filters_row.add_theme_constant_override("separation", 6)
	filters_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(filters_row)

	# ScrollContainer pra lista de notícias (preenchido depois)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(820, 480)
	root.add_child(scroll)
	var list_box := VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.custom_minimum_size = Vector2(800, 0)
	list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(list_box)

	# Footer: dropdown de janela de tempo
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	foot.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(foot)
	var foot_lbl := Label.new()
	foot_lbl.text = "Período:"
	foot_lbl.add_theme_color_override("font_color", Color(0.55, 0.65, 0.78))
	foot_lbl.add_theme_font_size_override("font_size", 11)
	foot.add_child(foot_lbl)
	var window_dd := OptionButton.new()
	for w in NEWS_WINDOWS:
		window_dd.add_item(w["label"])
	for i in NEWS_WINDOWS.size():
		if NEWS_WINDOWS[i]["value"] == _news_filter_window:
			window_dd.select(i); break
	foot.add_child(window_dd)

	# Função de re-renderizar a lista
	var rerender := func():
		for c in list_box.get_children(): c.queue_free()
		var entries: Array = _filter_news(_news_filter_scope, _news_filter_window)
		if entries.is_empty():
			var empty := Label.new()
			empty.text = "  Nenhuma notícia neste filtro."
			empty.add_theme_color_override("font_color", Color(0.5, 0.6, 0.72))
			empty.add_theme_font_size_override("font_size", 12)
			list_box.add_child(empty)
			return
		# Mais recentes primeiro
		for i in range(entries.size() - 1, -1, -1):
			var e: Dictionary = entries[i]
			list_box.add_child(_make_news_card(e))

	# Constrói botões de filtro com estado togglável visual
	var filter_btns: Array = []
	var update_filter_buttons := func():
		for b in filter_btns:
			b.button_pressed = (b.get_meta("scope_id") == _news_filter_scope)
	for entry in NEWS_SCOPES:
		var btn := Button.new()
		btn.text = "%s  %s" % [entry["icon"], entry["label"]]
		btn.toggle_mode = true
		btn.set_meta("scope_id", entry["id"])
		btn.button_pressed = (entry["id"] == _news_filter_scope)
		btn.custom_minimum_size = Vector2(130, 36)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 12)
		var sc_id: String = entry["id"]
		btn.pressed.connect(func():
			_news_filter_scope = sc_id
			update_filter_buttons.call()
			rerender.call())
		filters_row.add_child(btn)
		filter_btns.append(btn)

	window_dd.item_selected.connect(func(idx: int):
		_news_filter_window = int(NEWS_WINDOWS[idx]["value"])
		rerender.call())

	# Renderiza inicial
	rerender.call()

	_open_modal(root, "📡 CENTRAL DE NOTÍCIAS", Vector2(900, 640))

# Filtra news_history pelo escopo e janela de tempo solicitados
func _filter_news(scope: String, window_turns: int) -> Array:
	if GameEngine == null: return []
	var history: Array = GameEngine.news_history
	var cutoff: int = -1
	if window_turns > 0:
		cutoff = GameEngine.current_turn - window_turns
	var player: String = ""
	var player_continent: String = ""
	var allies: Array = []
	var enemies: Array = []
	if GameEngine.player_nation != null:
		player = GameEngine.player_nation.codigo_iso
		player_continent = GameEngine.player_nation.continente
		enemies = GameEngine.player_nation.em_guerra.duplicate()
		# Aliados via tratados ativos
		if GameEngine.diplomacy:
			for t in GameEngine.diplomacy.treaties:
				var sigs: Array = t.get("signatories", [])
				if player in sigs:
					for s in sigs:
						if s != player and not (s in allies):
							allies.append(s)
	var out: Array = []
	for entry in history:
		var entry_dict: Dictionary = entry
		if cutoff > 0 and int(entry_dict.get("turn", 0)) < cutoff:
			continue
		match scope:
			"global":
				out.append(entry_dict)
			"national":
				if player != "" and player in entry_dict.get("involves", []):
					out.append(entry_dict)
			"regional":
				if entry_dict.get("region", "") == player_continent and player_continent != "":
					out.append(entry_dict)
			"ally":
				var inv: Array = entry_dict.get("involves", [])
				for a in allies:
					if a in inv:
						out.append(entry_dict); break
			"enemy":
				var inv2: Array = entry_dict.get("involves", [])
				for en in enemies:
					if en in inv2:
						out.append(entry_dict); break
	return out

func _make_news_card(entry: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.09, 0.13, 0.85)
	sb.border_color = Color(0.15, 0.30, 0.45, 0.6)
	sb.border_width_left = 3
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	# Borda esquerda colorida por tipo
	var c: Color = entry.get("color", Color(0.5, 0.7, 1))
	if entry.get("type", "") == "guerra": c = Color(1, 0.35, 0.35)
	elif entry.get("type", "") == "paz": c = Color(0.35, 1, 0.55)
	elif String(entry.get("type", "")).begins_with("evento"): c = Color(1, 0.78, 0.30)
	sb.border_color = c
	card.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	card.add_child(v)
	# Header: turno + scope
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	v.add_child(hdr)
	var turn_lbl := Label.new()
	turn_lbl.text = "T%d" % int(entry.get("turn", 0))
	turn_lbl.add_theme_color_override("font_color", Color(0.45, 0.55, 0.7))
	turn_lbl.add_theme_font_size_override("font_size", 10)
	turn_lbl.custom_minimum_size = Vector2(40, 0)
	hdr.add_child(turn_lbl)
	var scope_lbl := Label.new()
	var scope_str: String = entry.get("scope", "global")
	var scope_icons := {"national": "🏛 NACIONAL", "regional": "🗺 REGIONAL", "global": "🌐 GLOBAL"}
	scope_lbl.text = scope_icons.get(scope_str, "🌐 GLOBAL")
	scope_lbl.add_theme_color_override("font_color", Color(0.5, 0.62, 0.78))
	scope_lbl.add_theme_font_size_override("font_size", 10)
	hdr.add_child(scope_lbl)
	# Título
	var title := Label.new()
	title.text = entry.get("headline", "—")
	title.add_theme_color_override("font_color", Color(0.92, 0.96, 1))
	title.add_theme_font_size_override("font_size", 13)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(title)
	# Corpo (se houver)
	var body_text: String = entry.get("body", "")
	if body_text != "":
		var body := Label.new()
		body.text = body_text
		body.add_theme_color_override("font_color", Color(0.65, 0.75, 0.88))
		body.add_theme_font_size_override("font_size", 11)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(body)
	return card

# ─────────────────────────────────────────────────────────────────
# BOTTOM ACTION BAR (estilo AoE)
# ─────────────────────────────────────────────────────────────────

const ACTION_BUTTONS := [
	{"id": "gabinete",   "icon": "🏛", "label": "Gabinete"},
	{"id": "governo",    "icon": "📋", "label": "Casa Civil"},
	{"id": "economia",   "icon": "💰", "label": "Fazenda"},
	{"id": "seguranca",  "icon": "⚖",  "label": "Justiça & Seg."},
	{"id": "saude",      "icon": "🏥", "label": "Saúde"},
	{"id": "educacao",   "icon": "📚", "label": "Educação"},
	{"id": "diplomacia", "icon": "🌐", "label": "Exterior"},
	{"id": "tech",       "icon": "🔬", "label": "Pesquisa"},
	{"id": "situacao",   "icon": "🗺", "label": "Situação"},
	{"id": "historico",  "icon": "📜", "label": "Histórico"},
	{"id": "noticias",   "icon": "📡", "label": "News"},
]

const GameOverlayScript = preload("res://scripts/GameOverlay.gd")

func _build_action_bar() -> void:
	if action_bar == null: return
	for c in action_bar.get_children(): c.queue_free()
	for entry in ACTION_BUTTONS:
		var pid: String = entry["id"]
		var accent: Color = GameOverlayScript.ministry_color(pid)
		# Botão EMPILHADO: ícone vetorial único em cima, label curto embaixo.
		# Fim do texto cortado — o rótulo tem sua própria linha com autowrap.
		var b := Button.new()
		b.custom_minimum_size = Vector2(64, 56)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = entry["label"]
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(func(): _open_overlay_modal(pid))
		# Realce dourado no hover/pressed
		var sb_h := StyleBoxFlat.new()
		sb_h.bg_color = Color(accent.r * 0.20, accent.g * 0.20, accent.b * 0.20, 0.9)
		sb_h.border_color = accent
		sb_h.set_border_width_all(1)
		sb_h.set_corner_radius_all(7)
		b.add_theme_stylebox_override("hover", sb_h)
		b.add_theme_stylebox_override("pressed", sb_h)
		# Conteúdo empilhado (ignora mouse → clique vai pro botão)
		var vb := VBoxContainer.new()
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_theme_constant_override("separation", 2)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var ico := GameOverlayScript.make_ministry_icon(pid, 22.0)
		ico.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(ico)
		var lbl := Label.new()
		lbl.text = entry["label"]
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color(0.80, 0.83, 0.88))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.clip_text = true
		lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_child(lbl)
		b.add_child(vb)
		action_bar.add_child(b)

func _show_action_bar(visible_state: bool) -> void:
	if action_bar:
		action_bar.visible = visible_state
	if next_turn_button:
		next_turn_button.visible = visible_state
	if resource_bar:
		resource_bar.visible = visible_state
	if visible_state:
		_start_next_turn_pulse()
		_build_resource_bar()
		_refresh_resource_bar()

# ─────────────────────────────────────────────────────────────────
# RESOURCE BAR (recursos chave da nação — vive na bottom bar)
# ─────────────────────────────────────────────────────────────────

var _resource_widgets: Dictionary = {}  # id → Label (valor)

const RESOURCE_FIELDS := [
	{"id": "poder",    "icon": "🌍", "label": "Poder",    "color": Color(0, 0.90, 1)},
	{"id": "score",    "icon": "🏆", "label": "Score",    "color": Color(0.4, 0.85, 1)},
	{"id": "pib",      "icon": "💰", "label": "PIB",      "color": Color(0, 0.95, 1)},
	{"id": "tesouro",  "icon": "🏦", "label": "Tesouro",  "color": Color(0, 1, 0.55)},
	{"id": "militar",  "icon": "⚔",  "label": "Militar",  "color": Color(1, 0.55, 0.45)},
	{"id": "populacao","icon": "👥", "label": "População","color": Color(0.85, 0.93, 1)},
	{"id": "estab",    "icon": "🏛", "label": "Estab",    "color": Color(0.7, 0.95, 0.55)},
	{"id": "apoio",    "icon": "❤", "label": "Apoio",    "color": Color(1, 0.7, 0.85)},
	{"id": "inflacao", "icon": "📉", "label": "Inflação", "color": Color(1, 0.78, 0.30)},
	{"id": "tech",     "icon": "🔬", "label": "Tech",     "color": Color(0.6, 0.85, 1)},
]

func _build_resource_bar() -> void:
	if resource_bar == null: return
	var hbox: HBoxContainer = resource_bar.get_node_or_null("HBox")
	if hbox == null: return
	for c in hbox.get_children(): c.queue_free()
	_resource_widgets.clear()
	for entry in RESOURCE_FIELDS:
		var cell := VBoxContainer.new()
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.custom_minimum_size = Vector2(110, 0)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Linha 1: ícone + label
		var top := HBoxContainer.new()
		top.alignment = BoxContainer.ALIGNMENT_CENTER
		top.add_theme_constant_override("separation", 4)
		var icon := Label.new()
		icon.text = entry["icon"]
		icon.add_theme_font_size_override("font_size", 12)
		top.add_child(icon)
		var lab := Label.new()
		lab.text = entry["label"].to_upper()
		lab.add_theme_color_override("font_color", Color(0.5, 0.62, 0.78))
		lab.add_theme_font_size_override("font_size", 10)
		top.add_child(lab)
		cell.add_child(top)
		# Linha 2: valor (mono, glow)
		var val := Label.new()
		val.name = "Val_" + entry["id"]
		val.text = "—"
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.add_theme_color_override("font_color", entry["color"])
		val.add_theme_font_size_override("font_size", 16)
		val.add_theme_font_override("font", MONO_FONT)
		# Sombra chapada discreta (o shadow_outline serrilhava os números)
		val.add_theme_constant_override("shadow_outline_size", 0)
		val.add_theme_constant_override("shadow_offset_x", 1)
		val.add_theme_constant_override("shadow_offset_y", 1)
		val.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
		cell.add_child(val)
		hbox.add_child(cell)
		_resource_widgets[entry["id"]] = val

# Score do jogador (mesma fórmula de antes, agora reutilizável nas 2 barras).
func _compute_score(n) -> int:
	return int(
		(n.pib_bilhoes_usd / 1000.0) * 10 +
		(n.estabilidade_politica * 2) +
		(n.tecnologias_concluidas.size() * 50) +
		(n.tesouro * 0.01) +
		GameEngine.current_turn * 10)

func _refresh_resource_bar() -> void:
	if _resource_widgets.is_empty() or GameEngine.player_nation == null: return
	var n = GameEngine.player_nation
	# PIB em $T se ≥1000B, senão $B
	var pib_str: String
	if n.pib_bilhoes_usd >= 1000.0:
		pib_str = "$%.2fT" % (n.pib_bilhoes_usd / 1000.0)
	else:
		pib_str = "$%dB" % int(n.pib_bilhoes_usd)
	# População
	var pop_str: String
	if n.populacao >= 1_000_000_000:
		pop_str = "%.1fB" % (n.populacao / 1_000_000_000.0)
	elif n.populacao >= 1_000_000:
		pop_str = "%dM" % (n.populacao / 1_000_000)
	else:
		pop_str = "%d" % n.populacao
	# Poder militar efetivo (derivado dos dados reais: orçamento, unidades, arsenal)
	var pm: float = n.get_military_power()
	# Tech
	var tech_count: int = n.tecnologias_concluidas.size()
	# Poder mundial (rank) e Score — movidos da barra superior
	var rank: int = GameEngine.get_power_rank(n.codigo_iso)
	var values := {
		"poder":     "#%d" % rank,
		"score":     "%04d" % _compute_score(n),
		"pib":       pib_str,
		"tesouro":   "$%dB" % int(n.tesouro),
		"militar":   "%.1f" % pm,
		"populacao": pop_str,
		"estab":     "%d%%" % int(n.estabilidade_politica),
		"apoio":     "%d%%" % int(n.apoio_popular),
		"inflacao":  "%.1f%%" % n.inflacao,
		"tech":      "%d" % tech_count,
	}
	for k in values.keys():
		var w: Label = _resource_widgets.get(k)
		if w and is_instance_valid(w):
			w.text = values[k]

# Estiliza botões "hero" (Menu Opções, Próximo Turno, Zoom) com visual único
func _style_hero_buttons() -> void:
	# Botão MENU/OPÇÕES da topbar — pílula com glow ciano
	if menu_button:
		var sb_n := StyleBoxFlat.new()
		sb_n.bg_color = Color(0.070, 0.072, 0.085, 0.92)
		sb_n.border_color = Color(0.80, 0.65, 0.30, 0.65)
		sb_n.set_border_width_all(1)
		sb_n.set_corner_radius_all(18)  # pílula
		sb_n.content_margin_left = 16
		sb_n.content_margin_right = 16
		sb_n.content_margin_top = 8
		sb_n.content_margin_bottom = 8
		var sb_h := sb_n.duplicate() as StyleBoxFlat
		sb_h.bg_color = Color(0.128, 0.122, 0.105, 1.0)
		sb_h.border_color = Color(0.92, 0.76, 0.38, 1)
		# (sem shadow — evita offset entre visual e hitbox)
		var sb_p := sb_n.duplicate() as StyleBoxFlat
		sb_p.bg_color = Color(0.30, 0.24, 0.11, 1)
		menu_button.add_theme_stylebox_override("normal", sb_n)
		menu_button.add_theme_stylebox_override("hover", sb_h)
		menu_button.add_theme_stylebox_override("pressed", sb_p)
		menu_button.add_theme_stylebox_override("focus", sb_h)
		menu_button.add_theme_color_override("font_color", Color(0.85, 0.95, 1))
		menu_button.add_theme_color_override("font_hover_color", Color(1, 1, 1))

	# Botão PRÓXIMO TURNO — retangular destacado, SEM shadow (evita offset visual)
	if next_turn_button:
		var sb_n2 := StyleBoxFlat.new()
		sb_n2.bg_color = Color(0.86, 0.69, 0.30, 1)
		sb_n2.border_color = Color(1.0, 0.88, 0.55, 0.9)
		sb_n2.set_border_width_all(2)
		sb_n2.set_corner_radius_all(10)
		sb_n2.content_margin_left = 18
		sb_n2.content_margin_right = 18
		sb_n2.content_margin_top = 10
		sb_n2.content_margin_bottom = 10
		var sb_h2 := sb_n2.duplicate() as StyleBoxFlat
		sb_h2.bg_color = Color(0.95, 0.79, 0.40, 1)
		var sb_p2 := sb_n2.duplicate() as StyleBoxFlat
		sb_p2.bg_color = Color(0.70, 0.55, 0.22, 1)
		next_turn_button.add_theme_stylebox_override("normal", sb_n2)
		next_turn_button.add_theme_stylebox_override("hover", sb_h2)
		next_turn_button.add_theme_stylebox_override("pressed", sb_p2)
		next_turn_button.add_theme_stylebox_override("focus", sb_h2)
		next_turn_button.add_theme_color_override("font_color", Color(0.11, 0.09, 0.04))
		next_turn_button.add_theme_color_override("font_hover_color", Color(0.08, 0.06, 0.02))
		next_turn_button.add_theme_color_override("font_pressed_color", Color(0.11, 0.09, 0.04))
		next_turn_button.add_theme_font_size_override("font_size", 14)

	# Botões de zoom — sem shadow
	for zb in [zoom_in_btn, zoom_out_btn, zoom_reset_btn]:
		if zb == null: continue
		var sb_z := StyleBoxFlat.new()
		sb_z.bg_color = Color(0.065, 0.068, 0.080, 0.92)
		sb_z.border_color = Color(0.42, 0.38, 0.30, 0.55)
		sb_z.set_border_width_all(1)
		sb_z.set_corner_radius_all(8)
		var sb_zh := sb_z.duplicate() as StyleBoxFlat
		sb_zh.bg_color = Color(0.128, 0.122, 0.105, 1)
		sb_zh.border_color = Color(0.92, 0.76, 0.38, 1)
		zb.add_theme_stylebox_override("normal", sb_z)
		zb.add_theme_stylebox_override("hover", sb_zh)
		zb.add_theme_stylebox_override("pressed", sb_zh)
		zb.add_theme_stylebox_override("focus", sb_zh)
		_attach_hover_pop(zb)

	# Hover-pop nos botões hero (NÃO no next_turn_button — ele tem pulse de modulate)
	if menu_button: _attach_hover_pop(menu_button)

# Aplica fonte mono Cascadia + glow a labels numéricas da topbar
func _apply_mono_to_topbar() -> void:
	for lbl in [date_label, turn_label, treasury_label, defcon_label, score_label, rank_label, actions_label]:
		if lbl == null: continue
		lbl.add_theme_font_override("font", MONO_FONT)
		lbl.add_theme_font_size_override("font_size", 15)
		# Sombra CHAPADA discreta p/ legibilidade (o shadow_outline grande
		# criava aquele serrilhado pixelado feio nos números). Limpo e nítido.
		lbl.add_theme_constant_override("outline_size", 0)
		lbl.add_theme_constant_override("shadow_outline_size", 0)
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 1)
		lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))

# Hover "pop" SEM scale — apenas brilho via modulate (não desloca hitbox)
func _attach_hover_pop(btn: Control, _scale_unused: float = 1.04) -> void:
	if btn == null: return
	btn.mouse_entered.connect(func():
		var tw := create_tween()
		tw.tween_property(btn, "modulate", Color(1.18, 1.18, 1.18, 1.0), 0.10).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT))
	btn.mouse_exited.connect(func():
		var tw := create_tween()
		tw.tween_property(btn, "modulate", Color(1, 1, 1, 1), 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT))

# Scanline animada na topbar (linha ciano que atravessa horizontalmente)
func _start_topbar_scanline() -> void:
	var top_bar := get_node_or_null("HUD/TopBar")
	if top_bar == null: return
	var scan := ColorRect.new()
	scan.color = Color(0, 0.823, 1, 0.0)  # invisível inicialmente
	scan.custom_minimum_size = Vector2(180, 1)
	scan.size = Vector2(180, 1)
	scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scan.position = Vector2(-200, 60)  # base do top_bar
	top_bar.add_child(scan)
	# Sweep horizontal contínuo com gradiente fake (cor pulsa)
	var tw := create_tween().set_loops()
	tw.tween_callback(func():
		var vp_w: float = get_viewport_rect().size.x
		scan.position = Vector2(-200, TOP_BAR_H - 1)
		var t2 := create_tween().set_parallel(true)
		t2.tween_property(scan, "position:x", vp_w + 50, 4.0).set_trans(Tween.TRANS_LINEAR)
		t2.tween_property(scan, "color", Color(0, 0.95, 1, 0.65), 0.5)
		t2.chain().tween_property(scan, "color", Color(0, 0.823, 1, 0.0), 0.5).set_delay(3.0))
	tw.tween_interval(4.5)

# Spinner com rotação real
func _start_spinner_animation() -> void:
	if spinner_icon == null: return
	# Rotaciona o ícone continuamente
	spinner_icon.pivot_offset = spinner_icon.size / 2.0
	var tw := create_tween().set_loops()
	tw.tween_property(spinner_icon, "rotation", TAU, 1.2).set_trans(Tween.TRANS_LINEAR)
	tw.tween_callback(func(): spinner_icon.rotation = 0.0)

# ─────────────────────────────────────────────────────────────────
# CARREGAMENTO DE GEOMETRIA
# ─────────────────────────────────────────────────────────────────

# ── CARREGAMENTO EM DUAS FASES (spinner FLUIDO de verdade) ──
# Fase 1 (Thread em background): ler arquivo + JSON.parse + converter toda a
#   geometria em PackedVector2Array — a MAIN THREAD FICA LIVRE (60 FPS reais).
# Fase 2 (main, obrigatória p/ nós): instanciar Polygon2D/Line2D com
#   orçamento de VÉRTICES por frame — nem a Rússia estoura um frame.
var _world_parse_thread: Thread = null
var _world_parsed: Array = []
var _world_parse_done: bool = false

func _parse_world_threaded() -> void:
	var file := FileAccess.open("res://data/world.json", FileAccess.READ)
	if file == null:
		push_error("Não foi possível abrir res://data/world.json")
		_world_parse_done = true
		return
	var raw := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(raw) != OK:
		push_error("Erro ao parsear world.json")
		_world_parse_done = true
		return
	var out: Array = []
	for feature in json.data.get("features", []):
		var props: Dictionary = feature.get("properties", {})
		var geometry: Dictionary = feature.get("geometry", {})
		var coords = geometry.get("coordinates", [])
		var rings: Array = []
		if geometry.get("type") == "Polygon":
			rings.append(_ring_to_packed(coords[0]))
		elif geometry.get("type") == "MultiPolygon":
			for poly in coords:
				if poly.size() > 0:
					rings.append(_ring_to_packed(poly[0]))
		out.append({
			"code": String(props.get("ISO3166-1-Alpha-2", "")),
			"name": String(props.get("name", "")),
			"rings": rings,
		})
	_world_parsed = out
	_world_parse_done = true

func _load_world_data() -> void:
	# FASE 1: parse pesado em background — spinner gira a 60 FPS puros
	_world_parse_done = false
	_world_parse_thread = Thread.new()
	_world_parse_thread.start(_parse_world_threaded)
	while not _world_parse_done:
		await get_tree().process_frame
	_world_parse_thread.wait_to_finish()
	_world_parse_thread = null
	# FASE 2: instanciação fatiada por VÉRTICES (~2200/frame ≈ 60 FPS).
	# Em HEADLESS (testes/sims) monta tudo síncrono — o fatiamento existe
	# só para o spinner do jogador; nos testes ele só atrasa o boot.
	var headless: bool = DisplayServer.get_name() == "headless"
	var verts_left: int = 2200
	for data in _world_parsed:
		if headless:
			verts_left = await _instantiate_country(data, 999999999)
		else:
			verts_left = await _instantiate_country(data, verts_left)
	_world_parsed = []

# Instancia um país a partir da geometria pré-convertida (Fase 2).
# Devolve o orçamento de vértices restante; cede o frame quando estoura.
func _instantiate_country(data: Dictionary, verts_left: int) -> int:
	var code: String = data["code"]
	var country_name: String = data["name"]
	var rings: Array = data["rings"]

	var country_node := Node2D.new()
	country_node.name = code if code != "" else country_name

	var bounds := Rect2(0, 0, 0, 0)
	var first := true
	for ring in rings:
		if ring.size() < 3: continue
		# Orçamento de vértices POR ANEL: cede o frame antes de anéis grandes
		verts_left -= ring.size()
		if verts_left <= 0:
			await get_tree().process_frame
			verts_left = 2200
		var ring_closed := PackedVector2Array(ring)
		ring_closed.append(ring[0])
		# (Shelf costeiro artificial REMOVIDO: a batimetria real da NASA já
		# desenha o raso costeiro, e o Line2D borrava nas fronteiras internas)
		var poly := Polygon2D.new()
		poly.polygon = ring
		# Base BRANCA: a cor visível vem de self_modulate (modular não
		# re-triangula o mesh — setar .color re-triangulava 548k vértices)
		poly.color = Color.WHITE
		poly.self_modulate = COUNTRY_FILL
		# Textura de terreno procedural (relevo) — material COMPARTILHADO
		poly.material = _get_country_terrain_mat()
		country_node.add_child(poly)
		var line := Line2D.new()
		line.points = ring_closed
		line.width = 0.9
		line.default_color = COUNTRY_STROKE
		line.antialiased = true
		country_node.add_child(line)
		for pt in ring:
			if first:
				bounds = Rect2(pt, Vector2.ZERO)
				first = false
			else:
				bounds = bounds.expand(pt)

	countries_root.add_child(country_node)
	countries[code] = {"node": country_node, "name": country_name, "bounds": bounds}
	return verts_left

func _ring_to_packed(ring: Array) -> PackedVector2Array:
	var arr := PackedVector2Array()
	arr.resize(ring.size())
	for i in ring.size():
		var pt = ring[i]
		var x: float = (pt[0] + 180.0) * (MAP_WIDTH / 360.0)
		var y: float = (90.0 - pt[1]) * (MAP_HEIGHT / 180.0)
		arr[i] = Vector2(x, y)
	return arr

# ─────────────────────────────────────────────────────────────────
# CÂMERA
# ─────────────────────────────────────────────────────────────────

func _setup_camera() -> void:
	camera.make_current()
	camera.position = Vector2(MAP_WIDTH / 2.0, MAP_HEIGHT / 2.0)
	var vp_size := get_viewport_rect().size
	var central_w: float = vp_size.x - LEFT_PANEL_W - RIGHT_PANEL_W
	var central_h: float = vp_size.y - TOP_BAR_H - BOTTOM_BAR_H - MAP_PAD * 2.0
	var z: float = min(central_w / MAP_WIDTH, central_h / MAP_HEIGHT) * 0.95
	camera.zoom = Vector2(z, z)
	_apply_central_offset()

func _apply_central_offset() -> void:
	var vp_size := get_viewport_rect().size
	# Painel direito só é considerado se visível
	var right_used: float = RIGHT_PANEL_W if (right_panel and right_panel.visible) else 0.0
	var central_left: float = LEFT_PANEL_W
	var central_right: float = vp_size.x - right_used
	var central_center_x: float = (central_left + central_right) / 2.0
	var screen_center_x: float = vp_size.x / 2.0
	var dx_screen: float = screen_center_x - central_center_x
	# +MAP_PAD dos dois lados: o centro de foco reserva respiro em cima e embaixo
	var central_top: float = TOP_BAR_H + MAP_PAD
	var central_bottom: float = vp_size.y - BOTTOM_BAR_H - MAP_PAD
	var central_center_y: float = (central_top + central_bottom) / 2.0
	var screen_center_y: float = vp_size.y / 2.0
	var dy_screen: float = screen_center_y - central_center_y
	camera.offset = Vector2(dx_screen / camera.zoom.x, dy_screen / camera.zoom.y)

func _process(delta: float) -> void:
	# Pulso de guerra: inimigos ativos respiram em vermelho (sutil, 0.45Hz).
	# Custo: 1 set de modulate por país em guerra — normalmente 0-3 nodes.
	if not _war_pulse_nodes.is_empty():
		var k: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.0028)
		var pulse := Color(1.0 + 0.30 * k, 1.0 - 0.10 * k, 1.0 - 0.10 * k)
		for nd in _war_pulse_nodes:
			if is_instance_valid(nd):
				nd.modulate = pulse
	# Lerp suave (exponencial) com easing — quanto mais perto, mais lento
	if camera_animating:
		var t: float = 1.0 - exp(-CAM_LERP_SPEED * delta)
		camera.position = camera.position.lerp(camera_target_pos, t)
		camera.zoom = camera.zoom.lerp(camera_target_zoom, t)
		_clamp_camera()
		_apply_central_offset()
		if camera.position.distance_to(camera_target_pos) < 0.5 and abs(camera.zoom.x - camera_target_zoom.x) < 0.001:
			camera.position = camera_target_pos
			camera.zoom = camera_target_zoom
			_clamp_camera()
			_apply_central_offset()
			camera_animating = false
	# Inércia de pan: aplicar enquanto não está em drag e velocidade > limiar
	elif pan_velocity.length() > PAN_INERTIA_MIN:
		var world_v: Vector2 = pan_velocity / camera.zoom.x
		camera.position -= world_v * delta
		_clamp_camera()
		_apply_central_offset()
		camera_target_pos = camera.position
		# Decaimento exponencial — natural e estável
		pan_velocity *= exp(-PAN_INERTIA_DAMP * delta)
	# Pan via gamepad (analógico esquerdo) — só ativo se não há modal aberto
	if not _is_modal_open() and not camera_animating:
		var pan_x: float = Input.get_action_strength("game_pan_right") - Input.get_action_strength("game_pan_left")
		var pan_y: float = Input.get_action_strength("game_pan_down") - Input.get_action_strength("game_pan_up")
		if abs(pan_x) > 0.15 or abs(pan_y) > 0.15:
			var pan_speed: float = 600.0 / camera.zoom.x  # px/s no espaço-mundo
			camera.position += Vector2(pan_x, pan_y) * pan_speed * delta
			camera_target_pos = camera.position
			_clamp_camera()
			_apply_central_offset()

func _zoom_camera_to_country(code: String) -> void:
	if not countries.has(code): return
	var bounds: Rect2 = countries[code]["bounds"]
	if bounds.size.length_squared() <= 0: return
	var vp_size := get_viewport_rect().size
	var right_used: float = RIGHT_PANEL_W if (right_panel and right_panel.visible) else 0.0
	# Enquadramento SUAVE: o país ocupa ~55%% da área útil — sobra contexto
	# regional e nada encosta nas barras (85%%/75%% cortava em fullscreen)
	var avail_w: float = (vp_size.x - LEFT_PANEL_W - right_used) * 0.55
	var avail_h: float = (vp_size.y - TOP_BAR_H - BOTTOM_BAR_H) * 0.55
	var zx: float = avail_w / max(1.0, bounds.size.x)
	var zy: float = avail_h / max(1.0, bounds.size.y)
	var z: float = clamp(min(zx, zy), 0.5, 2.6)
	camera_target_zoom = Vector2(z, z)
	camera_target_pos = bounds.position + bounds.size / 2.0
	camera_animating = true

func _zoom_camera_to_world() -> void:
	camera_target_pos = Vector2(MAP_WIDTH / 2.0, MAP_HEIGHT / 2.0)
	var vp_size := get_viewport_rect().size
	var right_used: float = RIGHT_PANEL_W if (right_panel and right_panel.visible) else 0.0
	var central_w: float = vp_size.x - LEFT_PANEL_W - right_used
	var central_h: float = vp_size.y - TOP_BAR_H - BOTTOM_BAR_H - MAP_PAD * 2.0
	var z: float = min(central_w / MAP_WIDTH, central_h / MAP_HEIGHT) * 0.95
	camera_target_zoom = Vector2(z, z)
	camera_animating = true

func _clamp_camera() -> void:
	var vp_size := get_viewport_rect().size
	var right_used: float = RIGHT_PANEL_W if (right_panel and right_panel.visible) else 0.0
	var central_w: float = max(100.0, vp_size.x - LEFT_PANEL_W - right_used)
	# +2×MAP_PAD reserva respiro em cima e embaixo do mundo enquadrado
	var central_h: float = max(100.0, vp_size.y - TOP_BAR_H - BOTTOM_BAR_H - MAP_PAD * 2.0)
	var min_zoom_x: float = central_w / MAP_WIDTH
	var min_zoom_y: float = central_h / MAP_HEIGHT
	# Zoom mínimo = CONTAIN-fit: o mundo INTEIRO cabe na área central (entre
	# as barras), com a moldura visível — antes era cover-fit e a parte de
	# baixo do mapa ficava escondida atrás dos menus ("mapa descendo").
	var min_zoom_local: float = min(min_zoom_x, min_zoom_y) * 0.94
	var z: float = clamp(camera.zoom.x, min_zoom_local, ZOOM_MAX)
	camera.zoom = Vector2(z, z)
	var half_w: float = (central_w * 0.5) / z
	var half_h: float = (central_h * 0.5) / z
	# Eixo em que o mapa cabe inteiro: trava no centro E mata a inércia
	# daquele eixo (senão a inércia empurra contra o snap → tremida)
	if half_w * 2.0 >= MAP_WIDTH:
		camera.position.x = MAP_WIDTH / 2.0
		pan_velocity.x = 0.0
	else:
		var cx: float = clamp(camera.position.x, half_w, MAP_WIDTH - half_w)
		if cx != camera.position.x:
			pan_velocity.x = 0.0  # bateu na parede → sem empurrar
		camera.position.x = cx
	if half_h * 2.0 >= MAP_HEIGHT:
		camera.position.y = MAP_HEIGHT / 2.0
		pan_velocity.y = 0.0
	else:
		var cy: float = clamp(camera.position.y, half_h, MAP_HEIGHT - half_h)
		if cy != camera.position.y:
			pan_velocity.y = 0.0
		camera.position.y = cy

# ─────────────────────────────────────────────────────────────────
# UI: LISTA + FILTROS + ZOOM + MENU
# ─────────────────────────────────────────────────────────────────

func _setup_ui_bindings() -> void:
	if menu_button:
		menu_button.pressed.connect(_on_menu_pressed)
	if confirm_button:
		confirm_button.pressed.connect(_on_confirm_pressed)
	if declare_war_button:
		declare_war_button.pressed.connect(_on_declare_war_pressed)
	if propose_peace_button:
		propose_peace_button.pressed.connect(_on_propose_peace_pressed)
	if embassy_button:
		embassy_button.pressed.connect(_on_embassy_pressed)
	if sanctions_button:
		sanctions_button.pressed.connect(_on_sanctions_pressed)
	if propose_treaty_button:
		propose_treaty_button.pressed.connect(_on_propose_treaty_pressed)
	if trade_button:
		trade_button.pressed.connect(_on_trade_pressed)
	if espionage_button:
		espionage_button.pressed.connect(_on_espionage_pressed)
	if nations_list:
		nations_list.item_selected.connect(_on_nation_list_selected)
		nations_list.item_activated.connect(_on_nation_list_activated)
	if search_box:
		search_box.text_changed.connect(_filter_nations)
	if sort_button:
		sort_button.add_item("Por PIB ↓")
		sort_button.add_item("Por Nome A-Z")
		sort_button.add_item("Por Dificuldade")
		sort_button.item_selected.connect(_on_sort_changed)
	if zoom_in_btn:    zoom_in_btn.pressed.connect(_on_zoom_in_pressed)
	if zoom_out_btn:   zoom_out_btn.pressed.connect(_on_zoom_out_pressed)
	if zoom_reset_btn: zoom_reset_btn.pressed.connect(_on_zoom_reset_pressed)
	if next_turn_button: next_turn_button.pressed.connect(_on_next_turn_pressed)
	# Ticker da bottom bar é clicável → abre modal de notícias
	var ticker_scroll: ScrollContainer = get_node_or_null("HUD/BottomBar/V/TickerRow/TickerScroll")
	if ticker_scroll:
		ticker_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
		ticker_scroll.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		ticker_scroll.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_open_news_modal())
	# TickerCap (rótulo "◆ INTEL") também clicável
	var ticker_cap: Label = get_node_or_null("HUD/BottomBar/V/TickerRow/TickerCap")
	if ticker_cap:
		ticker_cap.mouse_filter = Control.MOUSE_FILTER_STOP
		ticker_cap.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		ticker_cap.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_open_news_modal())

func _on_zoom_in_pressed() -> void:
	var vp_center: Vector2 = get_viewport_rect().size / 2.0
	_zoom_at(vp_center, ZOOM_STEP)

func _on_zoom_out_pressed() -> void:
	var vp_center: Vector2 = get_viewport_rect().size / 2.0
	_zoom_at(vp_center, 1.0 / ZOOM_STEP)

func _on_zoom_reset_pressed() -> void:
	_zoom_camera_to_world()

func _on_menu_pressed() -> void:
	_show_options_modal()

func _make_modal_shell(min_size: Vector2, title_text: String) -> Dictionary:
	# Helper: cria backdrop full-screen + card centralizado.
	# Retorna { modal, content_box } — adicione widgets em content_box.
	var modal := Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.z_index = 100
	# Parentear no modal_layer (full-rect no CanvasLayer), não no WorldMap (Node2D).
	if modal_layer != null:
		modal_layer.visible = true
		modal_layer.add_child(modal)
	else:
		add_child(modal)
	var bg := ColorRect.new()
	bg.color = Color(0, 0.05, 0.08, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	modal.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = min_size
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.06, 0.10, 0.98)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.80, 0.65, 0.30, 0.60)
	sb.set_corner_radius_all(14)
	# (sem shadow)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 24
	sb.content_margin_bottom = 22
	card.add_theme_stylebox_override("panel", sb)
	center.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(v)
	if title_text != "":
		var title := Label.new()
		title.text = title_text
		title.add_theme_color_override("font_color", Color(0.95, 1, 1))
		title.add_theme_font_size_override("font_size", 22)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(title)
		var deco := ColorRect.new()
		deco.color = Color(0.80, 0.65, 0.30, 0.50)
		deco.custom_minimum_size = Vector2(60, 2)
		deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(deco)
	# Animação de entrada padrão (fade + scale-in)
	UIStyles.animate_modal_in(modal, card)
	return {"modal": modal, "content": v}

# Aplica e persiste o modo de janela (janela / tela cheia / sem bordas).
# Suporte a qualquer monitor: sem resolução forçada — a UI é ancorada e a
# barra de ações é elástica, então qualquer tamanho de janela funciona.
static func apply_window_mode(mode: String, w: int = 0, h: int = 0) -> void:
	match mode:
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			if w > 0 and h > 0:
				DisplayServer.window_set_size(Vector2i(w, h))
				var scr := DisplayServer.screen_get_size()
				var pos := DisplayServer.screen_get_position() + (scr - Vector2i(w, h)) / 2
				DisplayServer.window_set_position(pos)
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("video", "mode", mode)
	if w > 0: cfg.set_value("video", "w", w)
	if h > 0: cfg.set_value("video", "h", h)
	cfg.save("user://settings.cfg")

func _show_options_modal() -> void:
	# Modal de OPÇÕES em 4 abas (Jogo · Vídeo · Áudio · Sistema).
	# Cada aba é um ScrollContainer com um VBox — organização limpa.
	var modal_ref: Array = [null]
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(540, 560)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(_build_tab_jogo(modal_ref))
	tabs.add_child(_build_tab_video())
	tabs.add_child(_build_tab_audio())
	tabs.add_child(_build_tab_sistema(modal_ref))
	tabs.set_tab_title(0, "🎮 Jogo")
	tabs.set_tab_title(1, "🖥 Vídeo")
	tabs.set_tab_title(2, "🔊 Áudio")
	tabs.set_tab_title(3, "⚙ Sistema")
	modal_ref[0] = _open_modal(tabs, "⚙ OPÇÕES", Vector2(560, 620))

# Container-padrão de uma aba: ScrollContainer > VBox (retorna o VBox p/ encher)
func _new_options_tab(tab_name: String) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.name = tab_name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.name = "V"
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.custom_minimum_size = Vector2(500, 0)
	sc.add_child(v)
	return sc

# Título de seção dentro de uma aba (dourado)
func _opt_section(v: VBoxContainer, texto: String) -> void:
	var l := Label.new()
	l.text = "■ " + texto
	l.add_theme_color_override("font_color", Color(0.85, 0.70, 0.34, 0.95))
	l.add_theme_font_size_override("font_size", 11)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l)

# Slider rotulado 0-100% (para volumes / brilho). on_change recebe 0..1.
func _opt_slider(v: VBoxContainer, label: String, valor: float, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_color_override("font_color", Color(0.75, 0.80, 0.88))
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.custom_minimum_size = Vector2(90, 0)
	row.add_child(lbl)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = valor
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sl)
	var pct := Label.new()
	pct.text = "%d%%" % int(valor * 100.0)
	pct.add_theme_color_override("font_color", Color(0.88, 0.72, 0.34))
	pct.add_theme_font_size_override("font_size", 11)
	pct.custom_minimum_size = Vector2(42, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(pct)
	sl.value_changed.connect(func(nv: float):
		pct.text = "%d%%" % int(nv * 100.0)
		on_change.call(nv))
	v.add_child(row)

# Linha de botões-toggle mutuamente exclusivos. options = Array[[label, id]].
func _opt_toggle_row(v: VBoxContainer, options: Array, atual: String, on_pick: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for opt in options:
		var btn := _make_modal_toggle(String(opt[0]), String(opt[1]) == atual)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 11)
		btn.set_meta("opt_id", String(opt[1]))
		var oid: String = String(opt[1])
		btn.pressed.connect(func():
			for c in row.get_children():
				if c is Button:
					c.button_pressed = (c.get_meta("opt_id", "") == oid)
			on_pick.call(oid))
		row.add_child(btn)
	v.add_child(row)

# ── ABA: JOGO ──
func _build_tab_jogo(modal_ref: Array) -> ScrollContainer:
	var sc := _new_options_tab("Jogo")
	var v: VBoxContainer = sc.get_node("V")
	if GameEngine.player_nation:
		var info := Label.new()
		var quarters := ["JAN", "FEV", "MAR", "ABR", "MAI", "JUN", "JUL", "AGO", "SET", "OUT", "NOV", "DEZ"]
		info.text = "🌍 %s  ·  %s %d  ·  TURNO %d  ·  DEFCON %d" % [
			GameEngine.player_nation.nome, quarters[GameEngine.date_month - 1],
			GameEngine.date_year, GameEngine.current_turn, GameEngine.defcon]
		info.add_theme_color_override("font_color", Color(0.55, 0.75, 0.92))
		info.add_theme_font_size_override("font_size", 12)
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(info)
		v.add_child(HSeparator.new())
	_opt_section(v, "DIFICULDADE")
	_opt_toggle_row(v, [["Fácil", "easy"], ["Normal", "normal"], ["Difícil", "hard"], ["Brutal", "brutal"]],
		String(GameEngine.settings.get("difficulty", "normal")),
		func(id): GameEngine.settings["difficulty"] = id)
	_opt_section(v, "VELOCIDADE DA IA")
	_opt_toggle_row(v, [["4 ações", "4"], ["8 ações", "8"], ["15 ações", "15"]],
		str(int(GameEngine.settings.get("ai_speed", 8))),
		func(id): GameEngine.settings["ai_speed"] = int(id))
	v.add_child(HSeparator.new())
	_opt_section(v, "MODO ESPECTADOR (BOT IA)")
	var bot_hint := Label.new()
	bot_hint.text = "O bot assume o controle e joga em tempo real enquanto você assiste."
	bot_hint.add_theme_color_override("font_color", Color(0.55, 0.7, 0.85))
	bot_hint.add_theme_font_size_override("font_size", 10)
	bot_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bot_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(bot_hint)
	var persona_val: Array = ["balanced"]
	_opt_toggle_row(v, [["⚖ Balanceado", "balanced"], ["💰 Econômico", "economic"], ["⚔ Militar", "military"], ["🤝 Diplomata", "diplomat"]],
		"balanced", func(id): persona_val[0] = id)
	var speed_val: Array = [2.0]
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 5)
	for pair in [["🐢 Lento", 4.0], ["▶ Normal", 2.0], ["⚡ Rápido", 0.8]]:
		var spd: float = float(pair[1])
		var sbtn := _make_modal_toggle(String(pair[0]), spd == 2.0)
		sbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sbtn.add_theme_font_size_override("font_size", 10)
		sbtn.set_meta("spd", spd)
		sbtn.pressed.connect(func():
			speed_val[0] = spd
			for c in speed_row.get_children():
				if c is Button: c.button_pressed = (absf(float(c.get_meta("spd", 0.0)) - spd) < 0.01))
		speed_row.add_child(sbtn)
	v.add_child(speed_row)
	var is_bot_running: bool = bot_player != null
	var bot_toggle := _make_modal_button("⏹ PARAR BOT" if is_bot_running else "🤖 INICIAR BOT IA", not is_bot_running)
	bot_toggle.custom_minimum_size = Vector2(0, 42)
	if is_bot_running: bot_toggle.modulate = Color(1, 0.6, 0.6)
	bot_toggle.pressed.connect(func():
		_close_modal(modal_ref[0])
		if bot_player != null:
			stop_bot_mode()
		else:
			start_bot_mode(persona_val[0], speed_val[0]))
	v.add_child(bot_toggle)
	var btn_history := _make_modal_button("📜 HISTÓRICO DE DECISÕES", false)
	btn_history.custom_minimum_size = Vector2(0, 38)
	btn_history.pressed.connect(func():
		_close_modal(modal_ref[0])
		_open_decisions_history_modal())
	v.add_child(btn_history)
	return sc

# ── ABA: VÍDEO ──
func _build_tab_video() -> ScrollContainer:
	var sc := _new_options_tab("Vídeo")
	var v: VBoxContainer = sc.get_node("V")
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	_opt_section(v, "MODO DE JANELA")
	var cur_mode: String = String(cfg.get_value("video", "mode", "windowed"))
	_opt_toggle_row(v, [["🪟 Janela", "windowed"], ["🖥 Tela Cheia", "fullscreen"], ["⬜ Sem Bordas", "borderless"]],
		cur_mode, func(id): apply_window_mode(id))
	_opt_section(v, "RESOLUÇÃO (modo janela)")
	var res_dd := OptionButton.new()
	res_dd.custom_minimum_size = Vector2(200, 34)
	var resolutions := [[1280, 720], [1366, 768], [1600, 900], [1920, 1080], [2560, 1440], [3440, 1440], [3840, 2160]]
	var cur_w: int = int(cfg.get_value("video", "w", 1600))
	var sel_idx: int = 2
	for ri in resolutions.size():
		res_dd.add_item("%d × %d" % [resolutions[ri][0], resolutions[ri][1]])
		if resolutions[ri][0] == cur_w: sel_idx = ri
	res_dd.select(sel_idx)
	res_dd.item_selected.connect(func(idx: int):
		apply_window_mode("windowed", resolutions[idx][0], resolutions[idx][1]))
	v.add_child(res_dd)
	_opt_section(v, "VSYNC")
	var vsync_on: bool = bool(cfg.get_value("video", "vsync", true))
	_opt_toggle_row(v, [["Ligado", "on"], ["Desligado", "off"]], "on" if vsync_on else "off",
		func(id): _apply_vsync(id == "on"))
	_opt_section(v, "LIMITE DE FPS")
	var cur_fps: int = int(cfg.get_value("video", "fps", 0))
	_opt_toggle_row(v, [["30", "30"], ["60", "60"], ["120", "120"], ["∞", "0"]], str(cur_fps),
		func(id): _apply_fps_limit(int(id)))
	_opt_section(v, "BRILHO DO MAPA")
	var cur_bri: float = float(cfg.get_value("video", "map_brightness", 1.38))
	_opt_slider(v, "Brilho", clampf((cur_bri - 0.6) / 1.4, 0.0, 1.0), func(nv):
		_apply_map_brightness(0.6 + nv * 1.4))
	v.add_child(HSeparator.new())
	_opt_section(v, "ACESSIBILIDADE")
	var cb_btn := _make_modal_toggle("👁 Modo Daltonismo (verm/verde → azul/laranja)", Accessibility.colorblind_mode)
	cb_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cb_btn.add_theme_font_size_override("font_size", 11)
	cb_btn.pressed.connect(func():
		Accessibility.set_colorblind(not Accessibility.colorblind_mode)
		cb_btn.button_pressed = Accessibility.colorblind_mode)
	v.add_child(cb_btn)
	var font_lbl := Label.new()
	font_lbl.text = "Tamanho da fonte:"
	font_lbl.add_theme_color_override("font_color", Color(0.62, 0.66, 0.72))
	font_lbl.add_theme_font_size_override("font_size", 10)
	font_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(font_lbl)
	_opt_toggle_row(v, [["Pequena", "-2"], ["Normal", "0"], ["Grande", "2"], ["Muito Grande", "4"]],
		str(Accessibility.font_size_delta), func(id): Accessibility.set_font_delta(int(id)))
	return sc

# ── ABA: ÁUDIO ──
func _build_tab_audio() -> ScrollContainer:
	var sc := _new_options_tab("Áudio")
	var v: VBoxContainer = sc.get_node("V")
	_opt_section(v, "VOLUME")
	_opt_slider(v, "Música", AudioManager.music_volume, func(nv): AudioManager.set_music_volume(nv))
	_opt_slider(v, "Efeitos", AudioManager.sfx_volume, func(nv): AudioManager.set_sfx_volume(nv))
	v.add_child(HSeparator.new())
	var mute_btn := _make_modal_toggle("🔇 Mudo geral", AudioManager.muted)
	mute_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mute_btn.add_theme_font_size_override("font_size", 12)
	mute_btn.pressed.connect(func():
		AudioManager.set_muted(not AudioManager.muted)
		mute_btn.button_pressed = AudioManager.muted)
	v.add_child(mute_btn)
	var hint := Label.new()
	hint.text = "As configurações de áudio são salvas automaticamente."
	hint.add_theme_color_override("font_color", Color(0.5, 0.55, 0.62))
	hint.add_theme_font_size_override("font_size", 10)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(hint)
	return sc

# ── ABA: SISTEMA (salvar / carregar / sair) ──
func _build_tab_sistema(modal_ref: Array) -> ScrollContainer:
	var sc := _new_options_tab("Sistema")
	var v: VBoxContainer = sc.get_node("V")
	var SaveSys = preload("res://scripts/SaveSystem.gd")
	_opt_section(v, "PROGRESSO")
	var btn_save := _make_modal_button("💾 SALVAR PROGRESSO", true)
	btn_save.custom_minimum_size = Vector2(0, 46)
	btn_save.disabled = (GameEngine.player_nation == null)
	btn_save.pressed.connect(func():
		if SaveSys.save_game(GameEngine):
			_log_ticker("💾 SAVE", "Progresso salvo com sucesso", Color(0.4, 1, 0.6))
		_close_modal(modal_ref[0]))
	v.add_child(btn_save)
	var btn_load := _make_modal_button("📂 CARREGAR SAVE", false)
	btn_load.custom_minimum_size = Vector2(0, 42)
	btn_load.disabled = not SaveSys.has_save()
	btn_load.pressed.connect(func():
		if SaveSys.load_game(GameEngine):
			_close_modal(modal_ref[0])
			get_tree().change_scene_to_file("res://scenes/WorldMap.tscn")
		else:
			_log_ticker("⚠ LOAD", "Falha ao carregar save", Color(1, 0.4, 0.4))
			_close_modal(modal_ref[0]))
	v.add_child(btn_load)
	v.add_child(HSeparator.new())
	_opt_section(v, "PREFERÊNCIAS")
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	var confirm_exit: bool = bool(cfg.get_value("game", "confirm_exit", true))
	var ce_btn := _make_modal_toggle("⚠ Confirmar antes de sair", confirm_exit)
	ce_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ce_btn.add_theme_font_size_override("font_size", 11)
	ce_btn.pressed.connect(func():
		var c2 := ConfigFile.new()
		c2.load("user://settings.cfg")
		c2.set_value("game", "confirm_exit", ce_btn.button_pressed)
		c2.save("user://settings.cfg"))
	v.add_child(ce_btn)
	v.add_child(HSeparator.new())
	_opt_section(v, "SAIR")
	var btn_quit := _make_modal_button("🏠 SAIR PARA MENU PRINCIPAL", false)
	btn_quit.custom_minimum_size = Vector2(0, 42)
	btn_quit.pressed.connect(func():
		_close_modal(modal_ref[0])
		var cfg2 := ConfigFile.new()
		cfg2.load("user://settings.cfg")
		if bool(cfg2.get_value("game", "confirm_exit", true)):
			_show_confirmation_modal("🏠 SAIR PARA O MENU",
				"Tem certeza que quer sair? Progresso desde o último save será perdido.",
				func():
					_show_spinner("Voltando ao menu…")
					await get_tree().process_frame
					get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
		else:
			get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	v.add_child(btn_quit)
	var btn_exit := _make_modal_button("✕ FECHAR O JOGO", false)
	btn_exit.custom_minimum_size = Vector2(0, 42)
	btn_exit.modulate = Color(1, 0.7, 0.7)
	btn_exit.pressed.connect(func():
		_close_modal(modal_ref[0])
		_show_confirmation_modal("✕ FECHAR O JOGO",
			"Tem certeza que quer fechar? Progresso não salvo será perdido.",
			func(): get_tree().quit()))
	v.add_child(btn_exit)
	return sc

# Aplica no boot as preferências de vídeo salvas (VSync/FPS/brilho)
func _apply_saved_video_prefs() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") != OK: return
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if bool(cfg.get_value("video", "vsync", true)) else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(cfg.get_value("video", "fps", 0))
	var bri: float = float(cfg.get_value("video", "map_brightness", 1.38))
	var mat := _get_country_terrain_mat()
	if mat != null:
		mat.set_shader_parameter("brightness", bri)

# Aplica e persiste VSync
func _apply_vsync(on: bool) -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if on else DisplayServer.VSYNC_DISABLED)
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("video", "vsync", on)
	cfg.save("user://settings.cfg")

# Aplica e persiste limite de FPS (0 = ilimitado)
func _apply_fps_limit(fps: int) -> void:
	Engine.max_fps = fps
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("video", "fps", fps)
	cfg.save("user://settings.cfg")

# Aplica e persiste brilho do mapa (nos uniforms do shader de terreno)
func _apply_map_brightness(bri: float) -> void:
	var mat := _get_country_terrain_mat()
	if mat != null:
		mat.set_shader_parameter("brightness", bri)
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("video", "map_brightness", bri)
	cfg.save("user://settings.cfg")

# Modal: histórico de decisões + estatísticas de divergência
func _open_decisions_history_modal() -> void:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.mouse_filter = Control.MOUSE_FILTER_PASS

	var log_entries: Array = GameEngine.timeline.decision_log if GameEngine.timeline else []
	# Stats sumário
	var summary := Label.new()
	summary.add_theme_color_override("font_color", Color(0.55, 0.75, 0.92))
	summary.add_theme_font_size_override("font_size", 12)
	summary.text = "📊 %d decisão(ões) histórica(s) tomada(s)" % log_entries.size()
	summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(summary)

	# Sub-stats: convergência vs divergência
	# Para simplificar: assumimos que choice id == "war_terror" / "bailout" / "heavy_sanctions" /
	# "sign_full" são alinhados com história real. Resto = divergência.
	var historical_choices := {
		"ataques_911": "war_terror",
		"invasao_iraque": "support_invasion",
		"tsunami_indico": "help_big",
		"kp_nuclear_1": "sanctions",
		"lehman_crash": "bailout",
		"primavera_arabe": "support_revolutions",
		"fukushima": "nuclear_safe",
		"crimea_anexada": "heavy_sanctions",
		"acordo_paris": "sign_full",
		"brexit_voto": "neutral_brexit",
		"trump_eleito": "neutral_trump",
		"covid_19": "lockdown_hard",
		"russia_ucrania": "heavy_sanctions_ru",
	}
	var convergent: int = 0
	var divergent: int = 0
	for d in log_entries:
		var entry: Dictionary = d
		var eid: String = entry.get("event_id", "")
		var cid: String = entry.get("choice_id", "")
		if historical_choices.has(eid):
			if historical_choices[eid] == cid:
				convergent += 1
			else:
				divergent += 1
	if log_entries.size() > 0:
		var div_lbl := Label.new()
		div_lbl.text = "⚖ Convergente com história: %d   |   Divergente: %d" % [convergent, divergent]
		div_lbl.add_theme_color_override("font_color", Color(0.45, 0.95, 0.55) if convergent >= divergent else Color(1, 0.78, 0.30))
		div_lbl.add_theme_font_size_override("font_size", 11)
		div_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(div_lbl)

	# Linha decorativa
	var deco := ColorRect.new()
	deco.color = Color(1, 0.78, 0.30, 0.55)
	deco.custom_minimum_size = Vector2(80, 2)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(deco)

	# Lista de decisões em ScrollContainer
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(720, 400)
	content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)

	if log_entries.is_empty():
		var empty := Label.new()
		empty.text = "  Nenhuma decisão histórica tomada ainda."
		empty.add_theme_color_override("font_color", Color(0.5, 0.6, 0.72))
		empty.add_theme_font_size_override("font_size", 12)
		list.add_child(empty)
	else:
		# Mais recentes primeiro
		for i in range(log_entries.size() - 1, -1, -1):
			var d: Dictionary = log_entries[i]
			list.add_child(_make_decision_card(d, historical_choices.get(d.get("event_id", ""), "")))

	_open_modal(content, "📜 HISTÓRICO DE DECISÕES", Vector2(800, 580))

func _make_decision_card(entry: Dictionary, historical_choice: String) -> PanelContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.09, 0.13, 0.9)
	var matched: bool = (historical_choice != "" and historical_choice == entry.get("choice_id", ""))
	sb.border_color = Color(0.35, 0.95, 0.55, 0.85) if matched else Color(1, 0.78, 0.30, 0.85)
	sb.border_width_left = 4
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	# Cabeçalho: ano + tag
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 10)
	v.add_child(hdr)
	var year_lbl := Label.new()
	year_lbl.text = "Y%d" % int(entry.get("year", 0))
	year_lbl.add_theme_color_override("font_color", Color(0.5, 0.62, 0.78))
	year_lbl.add_theme_font_size_override("font_size", 11)
	year_lbl.custom_minimum_size = Vector2(50, 0)
	hdr.add_child(year_lbl)
	if historical_choice != "":
		var tag := Label.new()
		tag.text = "✓ Convergente" if matched else "✗ Divergente"
		tag.add_theme_color_override("font_color", Color(0.45, 0.95, 0.55) if matched else Color(1, 0.55, 0.45))
		tag.add_theme_font_size_override("font_size", 10)
		hdr.add_child(tag)
	# Título do evento
	var title := Label.new()
	title.text = entry.get("event_headline", "—")
	title.add_theme_color_override("font_color", Color(0.92, 0.96, 1))
	title.add_theme_font_size_override("font_size", 12)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(title)
	# Choice tomada
	var choice := Label.new()
	choice.text = "→ %s" % entry.get("choice_label", entry.get("choice_id", ""))
	choice.add_theme_color_override("font_color", Color(0.65, 0.85, 1))
	choice.add_theme_font_size_override("font_size", 11)
	choice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(choice)
	return card

func _make_modal_toggle(label: String, pressed: bool) -> Button:
	var b := _make_modal_button(label, pressed)
	b.toggle_mode = true
	b.button_pressed = pressed
	return b

func _on_next_turn_pressed() -> void:
	if GameEngine == null or GameEngine.player_nation == null: return
	# Efeito visual: flash de brilho (modulate, sem scale, pra não bagunçar hitbox)
	var t := create_tween()
	t.tween_property(next_turn_button, "modulate", Color(0.7, 0.85, 1.0), 0.06)
	t.tween_property(next_turn_button, "modulate", Color(1, 1, 1), 0.18)
	# Spinner enquanto processa — garante visível pelo menos 350ms
	_show_spinner("Processando turno...")
	var t0_ms := Time.get_ticks_msec()
	await get_tree().process_frame
	GameEngine.end_turn()
	await get_tree().process_frame
	var elapsed_ms: int = Time.get_ticks_msec() - t0_ms
	var min_show_ms: int = 350
	if elapsed_ms < min_show_ms:
		await get_tree().create_timer((min_show_ms - elapsed_ms) / 1000.0).timeout
	_hide_spinner()

# ─────────────────────────────────────────────────────────────────
# LISTA DE NAÇÕES
# ─────────────────────────────────────────────────────────────────

func _populate_nations_list() -> void:
	if GameEngine == null: return
	var codes: Array = GameEngine.nations.keys()
	_apply_sort(codes, 0)
	country_codes_filtered = codes
	_render_nations_list()

func _apply_sort(codes: Array, mode: int) -> void:
	var tier_order := {"FACIL": 0, "NORMAL": 1, "DIFICIL": 2, "MUITO_DIFICIL": 3, "QUASE_IMPOSSIVEL": 4}
	match mode:
		0:
			codes.sort_custom(func(a, b):
				return GameEngine.nations[a].pib_bilhoes_usd > GameEngine.nations[b].pib_bilhoes_usd)
		1:
			codes.sort_custom(func(a, b):
				return GameEngine.nations[a].nome.naturalnocasecmp_to(GameEngine.nations[b].nome) < 0)
		2:
			codes.sort_custom(func(a, b):
				var ta: int = tier_order.get(GameEngine.nations[a].tier_dificuldade, 99)
				var tb: int = tier_order.get(GameEngine.nations[b].tier_dificuldade, 99)
				if ta != tb: return ta < tb
				return GameEngine.nations[a].pib_bilhoes_usd > GameEngine.nations[b].pib_bilhoes_usd)

func _render_nations_list() -> void:
	if nations_list == null: return
	nations_list.clear()
	for code in country_codes_filtered:
		var n = GameEngine.nations[code]
		var meta = GameEngine.get_difficulty_meta(n.tier_dificuldade)
		var label := "%s  %s" % [meta["icon"], n.nome]
		var idx: int = nations_list.add_item(label)
		nations_list.set_item_metadata(idx, code)
		nations_list.set_item_custom_fg_color(idx, meta["color"])

func _filter_nations(query: String) -> void:
	var q := query.strip_edges().to_lower()
	if q == "":
		country_codes_filtered = GameEngine.nations.keys()
	else:
		country_codes_filtered = []
		for code in GameEngine.nations:
			var n = GameEngine.nations[code]
			if q in n.nome.to_lower() or q in code.to_lower():
				country_codes_filtered.append(code)
	var sort_mode: int = sort_button.selected if sort_button else 0
	_apply_sort(country_codes_filtered, sort_mode)
	_render_nations_list()

func _on_sort_changed(idx: int) -> void:
	_apply_sort(country_codes_filtered, idx)
	_render_nations_list()

func _on_nation_list_selected(idx: int) -> void:
	var code: String = nations_list.get_item_metadata(idx)
	_show_preview(code)

func _on_nation_list_activated(idx: int) -> void:
	var code: String = nations_list.get_item_metadata(idx)
	_show_preview(code)
	if player_code == "":
		_on_confirm_pressed()

# ─────────────────────────────────────────────────────────────────
# PREVIEW DO PAÍS (right panel)
# ─────────────────────────────────────────────────────────────────

func _show_preview(code: String) -> void:
	if not countries.has(code) or not GameEngine.nations.has(code):
		return
	if preview_code != "" and preview_code != player_code:
		_repaint_country_state(preview_code)
	preview_code = code
	if code != player_code:
		_paint_country(code, COUNTRY_PREVIEW)
	# Se modal de seleção está aberto, atualiza o painel direito IN-PLACE
	if _select_modal != null and is_instance_valid(_select_modal):
		_fill_preview_panel(code)
		return
	# Caso contrário, abre dossiê como modal solo
	_open_dossier_modal(code)

func _fill_preview_panel(code: String) -> void:
	var n = GameEngine.nations[code]
	if preview_flag:
		_paint_flag(preview_flag, code, n.continente)
	# Retrato do líder daquela nação — expressão reage à estabilidade política
	if preview_portrait_slot:
		for c in preview_portrait_slot.get_children():
			c.queue_free()
		var lead_expr := "neutro"
		if n.estabilidade_politica < 35.0:
			lead_expr = "preocupado"
		elif n.em_guerra.size() > 0:
			lead_expr = "bravo"
		elif n.apoio_popular > 65.0:
			lead_expr = "feliz"
		var pv := PortraitView.make(code, "presidente", lead_expr, 50.0)
		pv.custom_minimum_size = Vector2(50, 60)
		preview_portrait_slot.add_child(pv)
	preview_name.text = n.nome
	preview_iso.text = "%s  •  %s  •  %s" % [code, n.continente, n.regime_politico.replace("_", " ")]
	var meta = GameEngine.get_difficulty_meta(n.tier_dificuldade)
	preview_tier.text = "%s DIFICULDADE: %s" % [meta["icon"], meta["label"]]
	preview_tier.add_theme_color_override("font_color", meta["color"])
	preview_desc.text = meta["desc"]

	for child in preview_stats.get_children():
		child.queue_free()

	var pib_str: String = "$%.2fT" % (n.pib_bilhoes_usd / 1000.0) if n.pib_bilhoes_usd >= 1000 else "$%dB" % int(n.pib_bilhoes_usd)
	var pop_str: String
	if n.populacao >= 1_000_000_000:
		pop_str = "%.2fB" % (n.populacao / 1_000_000_000.0)
	elif n.populacao >= 1_000_000:
		pop_str = "%dM" % (n.populacao / 1_000_000)
	else:
		pop_str = "%d" % n.populacao

	# Recursos naturais (top 3 pelo valor)
	var rec_str: String = "—"
	if n.recursos and n.recursos.size() > 0:
		var pairs: Array = []
		for k_res in n.recursos.keys():
			pairs.append([k_res, float(n.recursos[k_res])])
		pairs.sort_custom(func(a, b): return a[1] > b[1])
		var top: Array = []
		for i in min(3, pairs.size()):
			top.append("%s %.0f" % [pairs[i][0].capitalize(), pairs[i][1]])
		rec_str = "  ·  ".join(top)

	# Poder militar efetivo (derivado dos dados reais: orçamento, unidades, arsenal)
	var pm: float = n.get_military_power()
	var mil_str: String = "%.0f" % pm
	# Rank de poder global do país (a régua da vitória — visível pra TODOS)
	GameEngine._refresh_world_maxima()
	var prank: int = GameEngine.get_power_rank(code)

	var stats := [
		["Poder Global",  "#%d no mundo" % prank],
		["Capital",      n.capital],
		["População",    pop_str],
		["PIB anual",    pib_str],
		["Tesouro",      "$%dB" % int(n.tesouro)],
		["Poder mil.",   mil_str],
		["Recursos",     rec_str],
		["Estabilidade", "%d%%" % int(n.estabilidade_politica)],
		["Apoio",        "%d%%" % int(n.apoio_popular)],
		["Felicidade",   "%d%%" % int(n.felicidade)],
		["Corrupção",    "%d%%" % int(n.corrupcao)],
		["Inflação",     "%.1f%%" % n.inflacao],
		["Personalid.",  String(n.personalidade).capitalize()],
	]
	# Liderança (Fase 2/3): líder atual e ideologia econômica do país
	if n.lider_nome != "":
		stats.append(["Líder", "%s (%d anos)" % [n.lider_nome, n.lider_idade]])
	# Ideologia econômica derivada da personalidade (consistente desde o turno 1,
	# antes de _process_leadership normalizar o campo do save).
	stats.append(["Ideologia", GameEngine._ideo_label(GameEngine._doctrine_for(n)).capitalize()])
	if n.divida_publica > 0:
		stats.append(["Dívida",       "$%dB" % int(n.divida_publica)])
	if n.em_guerra.size() > 0:
		stats.append(["Em guerra",    "%d frente(s)" % n.em_guerra.size()])

	for pair in stats:
		var k := Label.new()
		k.text = String(pair[0]).to_upper()
		k.add_theme_color_override("font_color", Color(0.5, 0.62, 0.78))
		k.add_theme_font_size_override("font_size", 10)
		preview_stats.add_child(k)
		var v := Label.new()
		v.text = str(pair[1])
		v.add_theme_color_override("font_color", Color(0, 0.95, 1))
		v.add_theme_font_size_override("font_size", 12)
		v.add_theme_font_override("font", MONO_FONT)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		preview_stats.add_child(v)

	# Renderiza vantagens/desvantagens
	_render_pros_cons(n)

	# Botões dinâmicos
	if player_code == "":
		# Modo seleção
		confirm_button.visible = true
		declare_war_button.visible = false
		propose_peace_button.visible = false
		embassy_button.visible = false
		sanctions_button.visible = false
		propose_treaty_button.visible = false
		espionage_button.visible = false
		if trade_button: trade_button.visible = false
	else:
		# Modo jogo
		confirm_button.visible = false
		if code == player_code:
			declare_war_button.visible = false
			propose_peace_button.visible = false
			embassy_button.visible = false
			sanctions_button.visible = false
			propose_treaty_button.visible = false
			espionage_button.visible = false
			if trade_button: trade_button.visible = false
		elif code in GameEngine.player_nation.em_guerra:
			declare_war_button.visible = false
			propose_peace_button.visible = true
			embassy_button.visible = false
			sanctions_button.visible = true
			propose_treaty_button.visible = false
			espionage_button.visible = true
			if trade_button: trade_button.visible = false
		else:
			declare_war_button.visible = true
			propose_peace_button.visible = false
			embassy_button.visible = true
			sanctions_button.visible = true
			propose_treaty_button.visible = true
			espionage_button.visible = true
			if trade_button: trade_button.visible = true

# ─────────────────────────────────────────────────────────────────
# BANDEIRA EMOJI A PARTIR DO ISO-2
# Cada letra ASCII A-Z mapeia pra um Regional Indicator Symbol (U+1F1E6 + offset).
# Combinar duas letras gera o emoji da bandeira do país.
# ─────────────────────────────────────────────────────────────────

# Pinta uma bandeira no PanelContainer dado, baseada nas cores oficiais do país
const FlagData = preload("res://scripts/FlagData.gd")

func _paint_flag(panel: Control, iso2: String, continente: String) -> void:
	if panel == null: return
	# Limpa filhos antigos
	for c in panel.get_children(): c.queue_free()
	# 1) Bandeira OFICIAL (SVG em domínio público, res://flags/) — nítida em
	# qualquer escala. Fallback abaixo cobre códigos sem arquivo.
	var flag_path := "res://flags/%s.svg" % iso2.to_lower()
	if ResourceLoader.exists(flag_path):
		var tex := TextureRect.new()
		tex.texture = load(flag_path)
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_SCALE
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(tex)
		return
	# 2) Fallback: listras aproximadas por FlagData
	var data: Dictionary = FlagData.get_flag(iso2, continente)
	var colors: Array = data.get("colors", [])
	var layout: String = data.get("layout", "h")
	if colors.is_empty(): return
	# Container interno (V para horizontal, H para vertical)
	var box: BoxContainer
	if layout == "h":
		box = VBoxContainer.new()
	else:
		box = HBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	# Cada cor vira um ColorRect que ocupa fração igual do espaço
	for col in colors:
		var stripe := ColorRect.new()
		stripe.color = col
		stripe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stripe.size_flags_vertical = Control.SIZE_EXPAND_FILL
		stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(stripe)

func _iso_to_flag_emoji(iso2: String) -> String:
	if iso2 == null or iso2.length() != 2:
		return "🏳"
	var upper: String = iso2.to_upper()
	var c1: int = upper.unicode_at(0)
	var c2: int = upper.unicode_at(1)
	if c1 < 65 or c1 > 90 or c2 < 65 or c2 > 90:
		return "🏳"
	# Regional Indicator Symbol Letter A = U+1F1E6 = 127462
	var base: int = 127397  # 127462 - 65
	return char(base + c1) + char(base + c2)

# ─────────────────────────────────────────────────────────────────
# VANTAGENS / DESVANTAGENS
# Calcula 4-6 pros e 3-5 cons baseados nos dados reais da nação.
# ─────────────────────────────────────────────────────────────────

func _compute_pros_cons(n) -> Dictionary:
	var pros: Array = []
	var cons: Array = []
	# PIB
	if n.pib_bilhoes_usd >= 5000:
		pros.append("Superpotência econômica — PIB top mundial")
	elif n.pib_bilhoes_usd >= 1500:
		pros.append("Economia robusta capaz de absorver crises")
	elif n.pib_bilhoes_usd >= 500:
		pros.append("Economia média estável")
	elif n.pib_bilhoes_usd < 50:
		cons.append("Economia frágil — pouco espaço fiscal")
	# Tesouro
	if n.tesouro >= 1000:
		pros.append("Tesouro inicial massivo (>$1T)")
	elif n.tesouro >= 200:
		pros.append("Reservas confortáveis para investir")
	elif n.tesouro <= 80:
		cons.append("Tesouro apertado — escolhas dolorosas no início")
	# Estabilidade
	if n.estabilidade_politica >= 75:
		pros.append("Estabilidade política excelente")
	elif n.estabilidade_politica < 35:
		cons.append("Instabilidade política severa — risco de golpe")
	# Apoio popular
	if n.apoio_popular >= 70:
		pros.append("Alta legitimidade popular")
	elif n.apoio_popular < 35:
		cons.append("Baixo apoio popular — janela política curta")
	# Corrupção
	if n.corrupcao <= 25:
		pros.append("Instituições limpas — receita fiscal eficiente")
	elif n.corrupcao >= 60:
		cons.append("Corrupção endêmica corrói receita do Estado")
	# Inflação
	if n.inflacao <= 4:
		pros.append("Inflação controlada")
	elif n.inflacao >= 25:
		cons.append("Inflação alta destrói poder de compra")
	# Militar (poder efetivo derivado dos dados; escala: EUA ~550, regional ~30-150)
	var pm: float = n.get_military_power()
	if pm >= 200:
		pros.append("Forças armadas dominantes globalmente")
	elif pm >= 30:
		pros.append("Capacidade militar regional sólida")
	elif pm < 8:
		cons.append("Militar fraco — vulnerável a ameaças externas")
	# Recursos naturais (média alta)
	if n.recursos and n.recursos.size() > 0:
		var sum: float = 0.0
		for v in n.recursos.values():
			sum += float(v)
		var avg: float = sum / n.recursos.size()
		if avg >= 60:
			pros.append("Recursos naturais abundantes — exporta com folga")
		elif avg < 25:
			cons.append("Pobreza de recursos naturais limita exportações")
	# Regime
	if "DEMOCRACIA" in n.regime_politico or "REPUBLICA" in n.regime_politico or "PARLAMENTAR" in n.regime_politico:
		pros.append("Regime democrático — IA responde bem em tratados")
	elif "DITADURA" in n.regime_politico or "AUTORITA" in n.regime_politico:
		pros.append("Regime forte — decisões rápidas, sem oposição")
		cons.append("Sanções ocidentais mais prováveis")
	elif "TEOCRACIA" in n.regime_politico:
		cons.append("Isolamento diplomático — poucos parceiros")
	# Dívida
	if n.divida_publica > n.pib_bilhoes_usd * 1.5:
		cons.append("Dívida pública >150%% do PIB — risco fiscal")
	# Em guerra
	if n.em_guerra.size() > 0:
		cons.append("Já em guerra (%d frente(s)) — sangra recursos" % n.em_guerra.size())
	# População
	if n.populacao >= 200_000_000:
		pros.append("População massiva — base humana enorme")
	elif n.populacao < 5_000_000:
		cons.append("População pequena limita escala")
	return {"pros": pros, "cons": cons}

func _render_pros_cons(n) -> void:
	if preview_pros_cons == null: return
	for c in preview_pros_cons.get_children(): c.queue_free()
	var data: Dictionary = _compute_pros_cons(n)
	var pros: Array = data["pros"]
	var cons: Array = data["cons"]
	# Limita pra não estourar o painel
	if pros.size() > 5: pros.resize(5)
	if cons.size() > 4: cons.resize(4)
	for txt in pros:
		var l := Label.new()
		l.text = "  ✓  %s" % txt
		l.add_theme_color_override("font_color", Color(0.45, 0.95, 0.55))
		l.add_theme_font_size_override("font_size", 11)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		preview_pros_cons.add_child(l)
	for txt in cons:
		var l := Label.new()
		l.text = "  ✗  %s" % txt
		l.add_theme_color_override("font_color", Color(1, 0.50, 0.45))
		l.add_theme_font_size_override("font_size", 11)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		preview_pros_cons.add_child(l)
	if pros.is_empty() and cons.is_empty():
		var l := Label.new()
		l.text = "  —  Nação balanceada, sem destaques marcantes"
		l.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
		l.add_theme_font_size_override("font_size", 11)
		preview_pros_cons.add_child(l)

func _on_confirm_pressed() -> void:
	if preview_code == "" or not GameEngine.nations.has(preview_code):
		return
	# Abre wizard de tomada de posse antes de iniciar o jogo de fato
	_open_takeover_wizard(preview_code)

# Estado coletado pelo wizard (4 etapas)
var _takeover_state: Dictionary = {}

# Cache dos líderes históricos (carregado uma vez)
var _historical_leaders_cache: Array = []

func _load_historical_leaders() -> void:
	if not _historical_leaders_cache.is_empty(): return
	var f := FileAccess.open("res://data/historical_leaders.json", FileAccess.READ)
	if f == null: return
	var raw := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(raw) != OK: return
	var d: Dictionary = json.data
	_historical_leaders_cache = d.get("leaders", [])

# Busca um líder histórico que combine com (country_code, year_min..year_max)
func _find_historical_leader(country_code: String, year: int) -> Dictionary:
	_load_historical_leaders()
	for leader in _historical_leaders_cache:
		var l: Dictionary = leader
		if l.get("country", "") != country_code: continue
		var window: Array = l.get("year_window", [l.get("year", 0), l.get("year", 0)])
		if window.size() == 2:
			if year >= int(window[0]) and year <= int(window[1]):
				return l
	return {}

# Preenche _takeover_state com os dados do líder histórico
func _apply_historical_leader_to_state(leader: Dictionary) -> void:
	_takeover_state["leader_name"] = String(leader.get("name", ""))
	_takeover_state["leader_motto"] = String(leader.get("motto", ""))
	_takeover_state["leader_background"] = String(leader.get("background", "politico"))
	_takeover_state["government_type"] = String(leader.get("government_type", "manter"))
	_takeover_state["economic_doctrine"] = String(leader.get("economic_doctrine", "mista"))
	_takeover_state["first_steps"] = leader.get("first_steps", []).duplicate()
	# Salva trait pra aplicar no Nation depois
	_takeover_state["historical_trait"] = leader.get("trait", {})

func _open_takeover_wizard(country_code: String) -> void:
	var n = GameEngine.nations[country_code]
	# Inicializa estado com defaults
	_takeover_state = {
		"country_code": country_code,
		"leader_name": "",
		"leader_age": 50,
		"leader_background": "politico",
		"leader_motto": "",
		"government_type": n.regime_politico,
		"economic_doctrine": "mista",
		"first_steps": [],  # 3 ações grátis escolhidas
	}
	_show_takeover_step_1(country_code)

# ───────────────────────────────────────────────────────────
# WIZARD DE TOMADA DE POSSE — 4 etapas (carinho com o jogador)
# ───────────────────────────────────────────────────────────

func _show_takeover_step_1(country_code: String) -> void:
	var n = GameEngine.nations[country_code]
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	content.custom_minimum_size = Vector2(560, 0)
	# Indicador de etapa
	var step_lbl := Label.new()
	step_lbl.text = "ETAPA 1 / 4 — IDENTIDADE DO LÍDER"
	step_lbl.add_theme_color_override("font_color", Color(0.85, 0.70, 0.34, 0.95))
	step_lbl.add_theme_font_size_override("font_size", 11)
	step_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(step_lbl)
	var intro := Label.new()
	intro.text = "Você assume %s, %s. Quem é você nesse mundo?" % [n.nome, n.continente]
	intro.add_theme_color_override("font_color", Color(0.85, 0.93, 1))
	intro.add_theme_font_size_override("font_size", 13)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(intro)

	# Sugestão de líder histórico (se há match com country + year)
	var historical: Dictionary = _find_historical_leader(country_code, GameEngine.date_year)
	if not historical.is_empty():
		var hist_panel := PanelContainer.new()
		var hsb := StyleBoxFlat.new()
		hsb.bg_color = Color(0.05, 0.10, 0.15, 0.88)
		hsb.border_color = Color(1, 0.85, 0.3, 0.85)
		hsb.set_border_width_all(1)
		hsb.border_width_left = 4
		hsb.set_corner_radius_all(8)
		hsb.content_margin_left = 12
		hsb.content_margin_right = 12
		hsb.content_margin_top = 10
		hsb.content_margin_bottom = 10
		hist_panel.add_theme_stylebox_override("panel", hsb)
		content.add_child(hist_panel)
		var hv := VBoxContainer.new()
		hv.add_theme_constant_override("separation", 4)
		hist_panel.add_child(hv)
		var h_title := Label.new()
		h_title.text = "🕰 LÍDER HISTÓRICO DISPONÍVEL"
		h_title.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
		h_title.add_theme_font_size_override("font_size", 10)
		hv.add_child(h_title)
		var h_name := Label.new()
		h_name.text = "%s — %s" % [historical.get("name", ""), historical.get("tagline", "")]
		h_name.add_theme_color_override("font_color", Color(0.95, 1, 1))
		h_name.add_theme_font_size_override("font_size", 12)
		h_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hv.add_child(h_name)
		var h_trait := Label.new()
		var trait_data: Dictionary = historical.get("trait", {})
		h_trait.text = "✦ %s — %s" % [trait_data.get("name", ""), trait_data.get("description", "")]
		h_trait.add_theme_color_override("font_color", Color(0.65, 0.78, 0.92))
		h_trait.add_theme_font_size_override("font_size", 10)
		h_trait.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hv.add_child(h_trait)
		var h_btn := Button.new()
		h_btn.text = "🕰 Usar este líder histórico"
		h_btn.custom_minimum_size = Vector2(0, 32)
		h_btn.add_theme_font_size_override("font_size", 11)
		h_btn.pressed.connect(func():
			_apply_historical_leader_to_state(historical)
			# Re-renderiza step 1 com campos preenchidos
			_close_top_modal()
			_show_takeover_step_1(country_code))
		hv.add_child(h_btn)

	content.add_child(HSeparator.new())
	# Nome do líder
	var name_label := Label.new()
	name_label.text = "Nome do líder:"
	name_label.add_theme_color_override("font_color", Color(0.55, 0.7, 0.9))
	name_label.add_theme_font_size_override("font_size", 11)
	content.add_child(name_label)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Ex: Maria Silva, John Doe, ..."
	name_edit.text = _takeover_state.get("leader_name", "")
	name_edit.custom_minimum_size = Vector2(0, 36)
	name_edit.text_changed.connect(func(t: String): _takeover_state["leader_name"] = t)
	content.add_child(name_edit)
	# Idade do líder (35-70) — afeta quanto tempo até a sucessão por idade
	var age_label := Label.new()
	age_label.add_theme_color_override("font_color", Color(0.55, 0.7, 0.9))
	age_label.add_theme_font_size_override("font_size", 11)
	content.add_child(age_label)
	var age_row := HBoxContainer.new()
	age_row.add_theme_constant_override("separation", 8)
	content.add_child(age_row)
	var age_slider := HSlider.new()
	age_slider.min_value = 35
	age_slider.max_value = 70
	age_slider.step = 1
	age_slider.value = int(_takeover_state.get("leader_age", 50))
	age_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	age_slider.custom_minimum_size = Vector2(0, 28)
	age_row.add_child(age_slider)
	age_label.text = "Idade do líder: %d anos" % int(age_slider.value)
	age_slider.value_changed.connect(func(v: float):
		_takeover_state["leader_age"] = int(v)
		age_label.text = "Idade do líder: %d anos" % int(v))
	# Background
	var bg_label := Label.new()
	bg_label.text = "Background do líder:"
	bg_label.add_theme_color_override("font_color", Color(0.55, 0.7, 0.9))
	bg_label.add_theme_font_size_override("font_size", 11)
	content.add_child(bg_label)
	var bg_row := HBoxContainer.new()
	bg_row.add_theme_constant_override("separation", 6)
	content.add_child(bg_row)
	var bg_btns: Array = []
	var backgrounds := [
		{"id": "militar",   "label": "⚔ Militar",     "tip": "+5 poder militar inicial"},
		{"id": "empresario","label": "💼 Empresário",  "tip": "+$50B tesouro inicial"},
		{"id": "academico", "label": "🎓 Acadêmico",   "tip": "+10% velocidade pesquisa"},
		{"id": "politico",  "label": "🏛 Político",    "tip": "+5 estabilidade inicial"},
	]
	for bg in backgrounds:
		var btn := Button.new()
		btn.text = bg["label"]
		btn.tooltip_text = bg["tip"]
		btn.toggle_mode = true
		btn.button_pressed = (_takeover_state.get("leader_background", "politico") == bg["id"])
		btn.set_meta("bg_id", bg["id"])
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 38)
		btn.add_theme_font_size_override("font_size", 11)
		var bid: String = bg["id"]
		btn.pressed.connect(func():
			_takeover_state["leader_background"] = bid
			for b in bg_btns:
				b.button_pressed = (b.get_meta("bg_id") == bid))
		bg_row.add_child(btn)
		bg_btns.append(btn)
	# Lema/slogan
	var motto_label := Label.new()
	motto_label.text = "Lema/Slogan (aparece no game over):"
	motto_label.add_theme_color_override("font_color", Color(0.55, 0.7, 0.9))
	motto_label.add_theme_font_size_override("font_size", 11)
	content.add_child(motto_label)
	var motto_edit := LineEdit.new()
	motto_edit.placeholder_text = "Ex: 'Pelo bem do povo', 'Ordem e Progresso', ..."
	motto_edit.text = _takeover_state.get("leader_motto", "")
	motto_edit.custom_minimum_size = Vector2(0, 36)
	motto_edit.text_changed.connect(func(t: String): _takeover_state["leader_motto"] = t)
	content.add_child(motto_edit)
	# Botões navegação
	content.add_child(HSeparator.new())
	var nav_row := HBoxContainer.new()
	nav_row.alignment = BoxContainer.ALIGNMENT_END
	nav_row.add_theme_constant_override("separation", 10)
	content.add_child(nav_row)
	var modal_ref: Array = [null]
	var btn_cancel := _make_modal_button("✕ Cancelar", false)
	btn_cancel.custom_minimum_size = Vector2(120, 36)
	btn_cancel.pressed.connect(func(): _close_modal(modal_ref[0]))
	nav_row.add_child(btn_cancel)
	var btn_next := _make_modal_button("PRÓXIMO ▶", true)
	btn_next.custom_minimum_size = Vector2(160, 36)
	btn_next.pressed.connect(func():
		# Auto-fill nome se vazio
		if String(_takeover_state.get("leader_name", "")).strip_edges() == "":
			_takeover_state["leader_name"] = "Líder de %s" % n.nome
		_close_modal(modal_ref[0])
		_show_takeover_step_2(country_code))
	nav_row.add_child(btn_next)
	modal_ref[0] = _open_modal(content, "🎭 ASSUMIR COMANDO — %s" % n.nome, Vector2(620, 540), false)

func _show_takeover_step_2(country_code: String) -> void:
	var n = GameEngine.nations[country_code]
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	content.custom_minimum_size = Vector2(560, 0)
	var step_lbl := Label.new()
	step_lbl.text = "ETAPA 2 / 4 — SISTEMA DE GOVERNO"
	step_lbl.add_theme_color_override("font_color", Color(0.85, 0.70, 0.34, 0.95))
	step_lbl.add_theme_font_size_override("font_size", 11)
	step_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(step_lbl)
	var intro := Label.new()
	intro.text = "Atual: %s\n\nMudar regime no início do governo é caro: $50B + -10 estabilidade. Mas pode valer a pena estrategicamente." % n.regime_politico.replace("_", " ").capitalize()
	intro.add_theme_color_override("font_color", Color(0.85, 0.93, 1))
	intro.add_theme_font_size_override("font_size", 12)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(intro)
	content.add_child(HSeparator.new())
	var gov_btns: Array = []
	var governments := [
		{"id": "manter",                "label": "✓ Manter regime atual",  "tip": "Sem custo, sem mudanças"},
		{"id": "DEMOCRACIA_PLENA",      "label": "🗳 Democracia Plena",     "tip": "-10 corrupção, decisões mais lentas"},
		{"id": "DEMOCRACIA_IMPERFEITA", "label": "🏛 Democracia Imperfeita","tip": "Balanceada"},
		{"id": "REGIME_HIBRIDO",        "label": "⚖ Regime Híbrido",        "tip": "+5 corrupção, decisões rápidas"},
		{"id": "DITADURA",              "label": "👑 Ditadura Militar",     "tip": "+10 estabilidade, -10 apoio popular"},
		{"id": "TEOCRACIA",             "label": "✝ Teocracia",             "tip": "+15 estabilidade, mas poucos parceiros"},
	]
	# Default: manter
	if not _takeover_state.has("government_type") or _takeover_state["government_type"] == n.regime_politico:
		_takeover_state["government_type"] = "manter"
	for gov in governments:
		var btn := Button.new()
		btn.text = "  " + gov["label"]
		btn.tooltip_text = gov["tip"]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.toggle_mode = true
		btn.button_pressed = (_takeover_state.get("government_type", "manter") == gov["id"])
		btn.set_meta("gov_id", gov["id"])
		btn.custom_minimum_size = Vector2(0, 40)
		btn.add_theme_font_size_override("font_size", 12)
		var gid: String = gov["id"]
		btn.pressed.connect(func():
			_takeover_state["government_type"] = gid
			for b in gov_btns:
				b.button_pressed = (b.get_meta("gov_id") == gid))
		content.add_child(btn)
		gov_btns.append(btn)
	# Nav
	content.add_child(HSeparator.new())
	var nav_row := HBoxContainer.new()
	nav_row.alignment = BoxContainer.ALIGNMENT_END
	nav_row.add_theme_constant_override("separation", 10)
	content.add_child(nav_row)
	var modal_ref: Array = [null]
	var btn_back := _make_modal_button("◀ Voltar", false)
	btn_back.custom_minimum_size = Vector2(120, 36)
	btn_back.pressed.connect(func():
		_close_modal(modal_ref[0])
		_show_takeover_step_1(country_code))
	nav_row.add_child(btn_back)
	var btn_next := _make_modal_button("PRÓXIMO ▶", true)
	btn_next.custom_minimum_size = Vector2(160, 36)
	btn_next.pressed.connect(func():
		_close_modal(modal_ref[0])
		_show_takeover_step_3(country_code))
	nav_row.add_child(btn_next)
	modal_ref[0] = _open_modal(content, "🏛 SISTEMA DE GOVERNO", Vector2(620, 580), false)

func _show_takeover_step_3(country_code: String) -> void:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	content.custom_minimum_size = Vector2(560, 0)
	var step_lbl := Label.new()
	step_lbl.text = "ETAPA 3 / 4 — DOUTRINA ECONÔMICA"
	step_lbl.add_theme_color_override("font_color", Color(0.85, 0.70, 0.34, 0.95))
	step_lbl.add_theme_font_size_override("font_size", 11)
	step_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(step_lbl)
	var intro := Label.new()
	intro.text = "Sua filosofia econômica afeta crescimento, desigualdade e tesouro a longo prazo."
	intro.add_theme_color_override("font_color", Color(0.85, 0.93, 1))
	intro.add_theme_font_size_override("font_size", 12)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(intro)
	content.add_child(HSeparator.new())
	var doc_btns: Array = []
	var doctrines := [
		{"id": "livre_mercado", "label": "💹 Livre Mercado",      "tip": "Crescimento do PIB acelerado ao longo dos anos, mas +5 corrupção"},
		{"id": "mista",         "label": "⚖ Economia Mista",      "tip": "Balanceada (atual) — sem viés"},
		{"id": "planejada",     "label": "🏭 Planejamento Estatal","tip": "Tesouro cresce mais; PIB um pouco mais lento"},
		{"id": "nordica",       "label": "🌲 Modelo Nórdico",      "tip": "Bem-estar/felicidade em alta; PIB mais lento"},
	]
	for doc in doctrines:
		var btn := Button.new()
		btn.text = "  " + doc["label"]
		btn.tooltip_text = doc["tip"]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.toggle_mode = true
		btn.button_pressed = (_takeover_state.get("economic_doctrine", "mista") == doc["id"])
		btn.set_meta("doc_id", doc["id"])
		btn.custom_minimum_size = Vector2(0, 40)
		btn.add_theme_font_size_override("font_size", 12)
		var did: String = doc["id"]
		btn.pressed.connect(func():
			_takeover_state["economic_doctrine"] = did
			for b in doc_btns:
				b.button_pressed = (b.get_meta("doc_id") == did))
		content.add_child(btn)
		doc_btns.append(btn)
	# Nav
	content.add_child(HSeparator.new())
	var nav_row := HBoxContainer.new()
	nav_row.alignment = BoxContainer.ALIGNMENT_END
	nav_row.add_theme_constant_override("separation", 10)
	content.add_child(nav_row)
	var modal_ref: Array = [null]
	var btn_back := _make_modal_button("◀ Voltar", false)
	btn_back.custom_minimum_size = Vector2(120, 36)
	btn_back.pressed.connect(func():
		_close_modal(modal_ref[0])
		_show_takeover_step_2(country_code))
	nav_row.add_child(btn_back)
	var btn_next := _make_modal_button("PRÓXIMO ▶", true)
	btn_next.custom_minimum_size = Vector2(160, 36)
	btn_next.pressed.connect(func():
		_close_modal(modal_ref[0])
		_show_takeover_step_4(country_code))
	nav_row.add_child(btn_next)
	modal_ref[0] = _open_modal(content, "💰 DOUTRINA ECONÔMICA", Vector2(620, 460), false)

const TAKEOVER_FIRST_STEPS := [
	{"id": "saude",       "label": "🏥 Investir em saúde pública",  "tip": "+8 felicidade, +5 apoio"},
	{"id": "educacao",    "label": "🎓 Reforma educacional",         "tip": "+5 apoio, +3 burocracia"},
	{"id": "militar",     "label": "⚔ Modernizar forças armadas",   "tip": "+5 poder militar"},
	{"id": "diplomacia",  "label": "🤝 Diplomacia ofensiva",          "tip": "+10 relações com vizinhos"},
	{"id": "estimulo",    "label": "💰 Pacote de estímulo fiscal",   "tip": "+2% PIB"},
	{"id": "energia",     "label": "🛢 Reforma energética",           "tip": "+5 cada recurso"},
	{"id": "digital",     "label": "📡 Modernização digital",         "tip": "+10% velocidade pesquisa"},
	{"id": "infra",       "label": "🏗 Infraestrutura nacional",      "tip": "+1% PIB, +3 estabilidade"},
]

func _show_takeover_step_4(country_code: String) -> void:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	content.custom_minimum_size = Vector2(560, 0)
	var step_lbl := Label.new()
	step_lbl.text = "ETAPA 4 / 4 — PRIMEIROS 100 DIAS"
	step_lbl.add_theme_color_override("font_color", Color(0.85, 0.70, 0.34, 0.95))
	step_lbl.add_theme_font_size_override("font_size", 11)
	step_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(step_lbl)
	var intro := Label.new()
	intro.text = "Escolha 3 prioridades. Estas ações são GRATUITAS e aplicadas antes do turno 1."
	intro.add_theme_color_override("font_color", Color(0.85, 0.93, 1))
	intro.add_theme_font_size_override("font_size", 12)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(intro)
	# Contador "X/3 escolhidas"
	var counter_lbl := Label.new()
	counter_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	counter_lbl.add_theme_font_size_override("font_size", 12)
	counter_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(counter_lbl)
	var update_counter := func():
		var sel: Array = _takeover_state.get("first_steps", [])
		counter_lbl.text = "  ◆ %d/3 prioridades escolhidas" % sel.size()
	update_counter.call()
	content.add_child(HSeparator.new())
	# Lista de checkboxes (na verdade botões togglable)
	var step_btns: Array = []
	for step in TAKEOVER_FIRST_STEPS:
		var btn := Button.new()
		btn.text = "  " + step["label"]
		btn.tooltip_text = step["tip"]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.toggle_mode = true
		var sel: Array = _takeover_state.get("first_steps", [])
		btn.button_pressed = (step["id"] in sel)
		btn.set_meta("step_id", step["id"])
		btn.custom_minimum_size = Vector2(0, 36)
		btn.add_theme_font_size_override("font_size", 11)
		var sid: String = step["id"]
		btn.pressed.connect(func():
			var current: Array = _takeover_state.get("first_steps", [])
			if sid in current:
				current.erase(sid)
				btn.button_pressed = false
			else:
				if current.size() >= 3:
					# Já chegou ao limite — desselecionar este (foi visualmente toggled)
					btn.button_pressed = false
					return
				current.append(sid)
				btn.button_pressed = true
			_takeover_state["first_steps"] = current
			update_counter.call())
		content.add_child(btn)
		step_btns.append(btn)
	# Nav
	content.add_child(HSeparator.new())
	var nav_row := HBoxContainer.new()
	nav_row.alignment = BoxContainer.ALIGNMENT_END
	nav_row.add_theme_constant_override("separation", 10)
	content.add_child(nav_row)
	var modal_ref: Array = [null]
	var btn_back := _make_modal_button("◀ Voltar", false)
	btn_back.custom_minimum_size = Vector2(120, 36)
	btn_back.pressed.connect(func():
		_close_modal(modal_ref[0])
		_show_takeover_step_3(country_code))
	nav_row.add_child(btn_back)
	var btn_finish := _make_modal_button("⚡ INICIAR GOVERNO", true)
	btn_finish.custom_minimum_size = Vector2(200, 38)
	btn_finish.pressed.connect(func():
		_close_modal(modal_ref[0])
		_finalize_takeover())
	nav_row.add_child(btn_finish)
	modal_ref[0] = _open_modal(content, "🚀 PRIMEIROS 100 DIAS NO PODER", Vector2(620, 620), false)

# Aplica todas as escolhas do wizard ao Nation e inicia o jogo
func _finalize_takeover() -> void:
	var country_code: String = _takeover_state.get("country_code", preview_code)
	if country_code == "" or not GameEngine.nations.has(country_code):
		return
	# Spinner
	_show_spinner("Iniciando governo…")
	var t0_ms := Time.get_ticks_msec()
	await get_tree().process_frame
	# Confirma a nação como jogadora
	GameEngine.confirm_player_nation(country_code)
	player_code = country_code
	var n = GameEngine.player_nation
	# Aplica escolhas do wizard
	_apply_takeover_choices(n)
	# Fecha modais abertos
	while not _modal_stack.is_empty():
		_close_top_modal()
	# Ativa overlay e action bar
	if game_overlay and game_overlay.has_method("activate"):
		game_overlay.activate()
	_show_action_bar(true)
	_repaint_map()
	# Mundo inteiro "preso na moldura" (como na tela de seleção) — o país
	# do jogador fica destacado pela borda ciano; o zoom é escolha dele.
	_zoom_camera_to_world()
	_refresh_top_bar()
	# Log dramatic
	var leader: String = String(_takeover_state.get("leader_name", "Líder"))
	var motto: String = String(_takeover_state.get("leader_motto", ""))
	var motto_str: String = " — \"%s\"" % motto if motto != "" else ""
	_log_ticker("🎭 NOVO GOVERNO", "%s assume o comando de %s%s" % [leader, n.nome, motto_str], Color(1, 0.85, 0.3))
	# Garante visibilidade mínima do spinner
	var elapsed: int = Time.get_ticks_msec() - t0_ms
	if elapsed < 500:
		await get_tree().create_timer((500 - elapsed) / 1000.0).timeout
	_hide_spinner()
	# Tutorial se primeira partida
	var cfg = ConfigFile.new()
	if cfg.load("user://settings.cfg") != OK:
		_show_tutorial()
		cfg.set_value("tutorial", "shown", true)
		cfg.save("user://settings.cfg")
	elif not cfg.get_value("tutorial", "shown", false):
		_show_tutorial()
		cfg.set_value("tutorial", "shown", true)
		cfg.save("user://settings.cfg")

func _apply_takeover_choices(n) -> void:
	# Salva metadados pro game over usar
	n.set_meta("leader_name", _takeover_state.get("leader_name", "Líder"))
	n.set_meta("leader_age", _takeover_state.get("leader_age", 50))
	n.set_meta("leader_background", _takeover_state.get("leader_background", "politico"))
	n.set_meta("leader_motto", _takeover_state.get("leader_motto", ""))
	# Líder do jogador (para o dossiê e coerência com o sistema de liderança)
	n.lider_nome = String(_takeover_state.get("leader_name", "Líder"))
	n.lider_idade = int(_takeover_state.get("leader_age", 50))
	n.lider_desde_turno = GameEngine.current_turn
	n.set_meta("economic_doctrine", _takeover_state.get("economic_doctrine", "mista"))
	# Aplica trait do líder histórico se houver
	var leader_trait: Dictionary = _takeover_state.get("historical_trait", {})
	if not leader_trait.is_empty():
		n.set_meta("historical_trait_name", String(leader_trait.get("name", "")))
		var effects: Dictionary = leader_trait.get("effects", {})
		# Aplica efeitos imediatos do trait (offsets fixos)
		if effects.has("apoio_offset"):
			n.apoio_popular = clamp(n.apoio_popular + float(effects["apoio_offset"]), 0.0, 100.0)
		if effects.has("stab_offset"):
			n.estabilidade_politica = clamp(n.estabilidade_politica + float(effects["stab_offset"]), 0.0, 100.0)
		if effects.has("corrupcao_offset"):
			n.corrupcao = clamp(n.corrupcao + float(effects["corrupcao_offset"]), 0.0, 100.0)
		if effects.has("tesouro_offset"):
			n.tesouro = max(0.0, n.tesouro + float(effects["tesouro_offset"]))
		if effects.has("research_bonus"):
			n.velocidade_pesquisa *= (1.0 + float(effects["research_bonus"]) / 100.0)
		if effects.has("continent_relations_bonus"):
			var bonus: float = float(effects["continent_relations_bonus"])
			for code in GameEngine.nations.keys():
				if code == n.codigo_iso: continue
				var other = GameEngine.nations[code]
				if other.continente == n.continente:
					n.relacoes[code] = clamp(float(n.relacoes.get(code, 0)) + bonus, -100.0, 100.0)
					other.relacoes[n.codigo_iso] = clamp(float(other.relacoes.get(n.codigo_iso, 0)) + bonus, -100.0, 100.0)
	# Background do líder
	match String(_takeover_state.get("leader_background", "politico")):
		"militar":
			if n.militar:
				n.militar["poder_militar_global"] = float(n.militar.get("poder_militar_global", 0)) + 5.0
		"empresario":
			n.tesouro += 50.0
		"academico":
			n.velocidade_pesquisa = n.velocidade_pesquisa * 1.10
		"politico":
			n.estabilidade_politica = clamp(n.estabilidade_politica + 5.0, 0.0, 100.0)
	# Mudança de regime (custa $50B + -10 estab de transição se diferente)
	var new_gov: String = String(_takeover_state.get("government_type", "manter"))
	if new_gov != "manter" and new_gov != n.regime_politico:
		n.regime_politico = new_gov
		n.tesouro = max(0.0, n.tesouro - 50.0)
		n.estabilidade_politica = clamp(n.estabilidade_politica - 10.0, 0.0, 100.0)
		# Efeitos imediatos do novo regime (cumpre a promessa dos tooltips da etapa 2)
		match new_gov:
			"DEMOCRACIA_PLENA":
				n.corrupcao = clamp(n.corrupcao - 10.0, 0.0, 100.0)
			"REGIME_HIBRIDO":
				n.corrupcao = clamp(n.corrupcao + 5.0, 0.0, 100.0)
			"DITADURA":
				n.estabilidade_politica = clamp(n.estabilidade_politica + 10.0, 0.0, 100.0)
				n.apoio_popular = clamp(n.apoio_popular - 10.0, 0.0, 100.0)
			"TEOCRACIA":
				n.estabilidade_politica = clamp(n.estabilidade_politica + 15.0, 0.0, 100.0)
	# Doutrina econômica: o efeito ESTRUTURAL (1×) é aplicado agora; o efeito
	# POR TURNO roda em GameEngine._process_economic_doctrine (lê a meta gravada acima).
	GameEngine._apply_economic_doctrine_once(n)
	# Primeiros passos (3 ações grátis sem custar tesouro nem ações)
	var steps: Array = _takeover_state.get("first_steps", [])
	for sid in steps:
		_apply_first_step(n, String(sid))

func _apply_first_step(n, step_id: String) -> void:
	match step_id:
		"saude":
			n.felicidade = clamp(n.felicidade + 8.0, 0.0, 100.0)
			n.apoio_popular = clamp(n.apoio_popular + 5.0, 0.0, 100.0)
		"educacao":
			n.apoio_popular = clamp(n.apoio_popular + 5.0, 0.0, 100.0)
			n.burocracia_eficiencia = clamp(n.burocracia_eficiencia + 3.0, 0.0, 100.0)
		"militar":
			if n.militar:
				n.militar["poder_militar_global"] = float(n.militar.get("poder_militar_global", 0)) + 5.0
		"diplomacia":
			# +10 relações com 3 vizinhos do mesmo continente
			var added: int = 0
			for code in GameEngine.nations.keys():
				if added >= 3: break
				if code == n.codigo_iso: continue
				var other = GameEngine.nations[code]
				if other.continente == n.continente:
					n.relacoes[code] = clamp(float(n.relacoes.get(code, 0)) + 10.0, -100.0, 100.0)
					other.relacoes[n.codigo_iso] = clamp(float(other.relacoes.get(n.codigo_iso, 0)) + 10.0, -100.0, 100.0)
					added += 1
		"estimulo":
			n.apply_pib_multiplier(1.02)
		"energia":
			if n.recursos:
				for k in n.recursos.keys():
					n.recursos[k] = min(100.0, float(n.recursos[k]) + 5.0)
		"digital":
			n.velocidade_pesquisa = n.velocidade_pesquisa * 1.10
		"infra":
			n.apply_pib_multiplier(1.01)
			n.estabilidade_politica = clamp(n.estabilidade_politica + 3.0, 0.0, 100.0)

# ─────────────────────────────────────────────────────────────────
# TUTORIAL
# ─────────────────────────────────────────────────────────────────

func _show_tutorial() -> void:
	var pages := [
		{
			"title": "🌍 Bem-vindo a NATIONS: NEW DAWN",
			"body": "Você assumiu o comando geopolítico de uma nação real. Sua missão: levar seu país à hegemonia mundial — ou pelo menos sobreviver. Cada turno equivale a 1 mês."
		},
		{
			"title": "📊 Indicadores Vitais",
			"body": "5 indicadores definem sua sobrevivência: Estabilidade, Apoio Popular, Felicidade, Corrupção e Inflação. Mantenha alto Apoio (≥65%) e Estabilidade (≥65%), com Inflação baixa (≤15%) e Tesouro positivo. Falhe e enfrente revolução, golpe, falência ou hiperinflação."
		},
		{
			"title": "🏛 Ações de Governo",
			"body": "No painel esquerdo, o jogador acessa 9 abas temáticas: Governo, Militar, Economia, Diplomacia, Tech, Intel, Situação, Histórico, Notícias. Cada ação custa $B do tesouro e dá efeitos positivos (com bônus de tier para nações difíceis)."
		},
		{
			"title": "🤝 Diplomacia & Guerra",
			"body": "Clique em qualquer país no mapa ou na lista para abrir o dossiê (à direita). Use os botões para: enviar embaixada (+rel), impor sanções (-PIB alvo), propor tratado, espionar (8 ops), ou declarar guerra. Ao declarar guerra, escolha um OBJETIVO (reparações, tomar recursos, mudar o regime) — ele define o que a vitória extrai."
		},
		{
			"title": "🌐 Blocos & Ideologias",
			"body": "Cada nação tem um LÍDER com ideologia (comunista, liberal, tecnocrata…). Nações de ideologia afim se aliam e formam BLOCOS (OTAN, BRICS…). Você pode aderir a blocos onde é bem-quisto. Cuidado: se você virar hegemon, o mundo pode se unir contra você. Líderes caem e sobem — e os países mudam de rumo."
		},
		{
			"title": "▶ Avançar Turno",
			"body": "Quando satisfeito com suas decisões, clique no botão circular GRANDE no canto inferior direito. A IA das outras 194 nações decide, eventos históricos disparam (11/9, COVID, Ucrânia…), e as notícias aparecem no rodapé. São 100 anos pela frente (mês a mês). Boa sorte, Comandante!"
		},
	]
	_show_tutorial_page(pages, 0)

func _show_tutorial_page(pages: Array, idx: int) -> void:
	# Backdrop em tela cheia (bloqueia cliques no jogo, mas permite cliques nos filhos)
	# IMPORTANTE: parentear no modal_layer (Control full-rect no CanvasLayer), NÃO no
	# WorldMap (Node2D) — senão o CenterContainer calcula contra rect zero e vai pro canto.
	var modal := Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.z_index = 100
	if modal_layer != null:
		modal_layer.visible = true
		modal_layer.add_child(modal)
	else:
		add_child(modal)

	var bg := ColorRect.new()
	bg.color = Color(0, 0.05, 0.08, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE  # backdrop não rouba o clique do botão
	modal.add_child(bg)

	# CenterContainer garante centralização sem cálculos manuais
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	modal.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(640, 360)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	# Estilo neon AAA
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.035, 0.06, 0.10, 0.98)
	card_style.set_border_width_all(2)
	card_style.border_color = Color(0, 0.823, 1, 0.85)
	card_style.set_corner_radius_all(14)
	# (sem shadow)
	card_style.content_margin_left = 32
	card_style.content_margin_right = 32
	card_style.content_margin_top = 28
	card_style.content_margin_bottom = 24
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)
	UIStyles.animate_modal_in(modal, card)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(v)

	var page: Dictionary = pages[idx]

	var cap := Label.new()
	cap.text = "◆ TUTORIAL  %d / %d" % [idx + 1, pages.size()]
	cap.add_theme_color_override("font_color", Color(0, 0.823, 1, 0.7))
	cap.add_theme_font_size_override("font_size", 11)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cap)

	var title := Label.new()
	title.text = page["title"]
	title.add_theme_color_override("font_color", Color(0.95, 1, 1))
	title.add_theme_font_size_override("font_size", 26)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(title)

	# Linha decorativa cyan
	var deco := ColorRect.new()
	deco.color = Color(0.80, 0.65, 0.30, 0.50)
	deco.custom_minimum_size = Vector2(60, 2)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(deco)

	var body := Label.new()
	body.text = page["body"]
	body.add_theme_color_override("font_color", Color(0.82, 0.90, 1))
	body.add_theme_font_size_override("font_size", 14)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.custom_minimum_size = Vector2(0, 120)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(body)

	# Indicador de progresso (pontos)
	var dots := HBoxContainer.new()
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	dots.add_theme_constant_override("separation", 8)
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in pages.size():
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(8, 8)
		dot.color = Color(0, 0.823, 1, 1.0) if i == idx else Color(0.2, 0.3, 0.4, 1.0)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dots.add_child(dot)
	v.add_child(dots)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 10)
	btn_row.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(btn_row)

	if idx > 0:
		var btn_back := _make_modal_button("◀ ANTERIOR", false)
		btn_back.pressed.connect(func():
			modal.queue_free()
			_show_tutorial_page(pages, idx - 1))
		btn_row.add_child(btn_back)

	var btn_skip := _make_modal_button("PULAR", false)
	btn_skip.pressed.connect(func(): modal.queue_free())
	btn_row.add_child(btn_skip)

	var is_last: bool = idx >= pages.size() - 1
	var btn_next := _make_modal_button("✓ COMEÇAR" if is_last else "PRÓXIMO ▶", true)
	if is_last:
		btn_next.pressed.connect(func(): modal.queue_free())
	else:
		btn_next.pressed.connect(func():
			modal.queue_free()
			_show_tutorial_page(pages, idx + 1))
	btn_row.add_child(btn_next)

	# Animação de entrada (só fade pra não bagunçar hitbox dos botões)
	card.modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property(card, "modulate", Color(1, 1, 1, 1), 0.22).set_trans(Tween.TRANS_CUBIC)

func _make_modal_button(label: String, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(140, 40)
	b.add_theme_font_size_override("font_size", 13)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb_norm := StyleBoxFlat.new()
	if primary:
		sb_norm.bg_color = Color(0.86, 0.69, 0.30, 1)
		sb_norm.border_color = Color(1.0, 0.88, 0.55, 0.9)
	else:
		sb_norm.bg_color = Color(0.075, 0.080, 0.095, 0.94)
		sb_norm.border_color = Color(0.36, 0.34, 0.28, 0.7)
	sb_norm.set_border_width_all(1)
	sb_norm.set_corner_radius_all(8)
	sb_norm.content_margin_left = 14
	sb_norm.content_margin_right = 14
	sb_norm.content_margin_top = 10
	sb_norm.content_margin_bottom = 10
	var sb_hover := sb_norm.duplicate() as StyleBoxFlat
	sb_hover.bg_color = Color(0.95, 0.79, 0.40, 1) if primary else Color(0.125, 0.120, 0.105, 1)
	sb_hover.border_color = Color(0.92, 0.76, 0.38, 1)
	var sb_press := sb_norm.duplicate() as StyleBoxFlat
	sb_press.bg_color = Color(0.70, 0.55, 0.22, 1) if primary else Color(0.30, 0.24, 0.11, 1)
	b.add_theme_stylebox_override("normal", sb_norm)
	b.add_theme_stylebox_override("hover", sb_hover)
	b.add_theme_stylebox_override("pressed", sb_press)
	b.add_theme_stylebox_override("focus", sb_hover)
	b.add_theme_color_override("font_color", Color(0.11, 0.09, 0.04) if primary else Color(0.92, 0.91, 0.88))
	b.add_theme_color_override("font_hover_color", Color(0.08, 0.06, 0.02) if primary else Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(0.11, 0.09, 0.04) if primary else Color(1, 0.95, 0.82))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	return b

# ─────────────────────────────────────────────────────────────────
# MODAL DE CONFIRMAÇÃO PARA AÇÕES DESTRUTIVAS
# Reutilizável: passe título, mensagem, callback quando confirmado.
# Inclui label de "consequência irreversível" e estilo amarelo de alerta.
# ─────────────────────────────────────────────────────────────────

# Renderiza painel com 4 conselheiros recomendando choices.
# Cada conselheiro tem viés (Diplomata/Militar/Economista/Mídia) e sugere
# uma das choices baseado em palavras-chave + efeitos numéricos.
const AdvisorScript = preload("res://scripts/AdvisorManager.gd")

func _render_advisor_panel(parent: Control, choices: Array, event: Dictionary) -> void:
	var section := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.07, 0.10, 0.85)
	sb.border_color = Color(0.30, 0.55, 0.85, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	section.add_theme_stylebox_override("panel", sb)
	parent.add_child(section)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	section.add_child(v)
	var title := Label.new()
	title.text = "💬 SEU GABINETE RECOMENDA"
	title.add_theme_color_override("font_color", Color(0, 0.823, 1, 0.85))
	title.add_theme_font_size_override("font_size", 11)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(title)
	var recs: Array = AdvisorScript.get_all_recommendations(choices, event)
	for r in recs:
		var entry: Dictionary = r
		var rec: Dictionary = entry.get("recommendation", {})
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		v.add_child(row)
		# Ícone + nome
		var icon_lbl := Label.new()
		icon_lbl.text = String(entry.get("advisor_icon", "👤"))
		icon_lbl.add_theme_font_size_override("font_size", 14)
		icon_lbl.custom_minimum_size = Vector2(28, 0)
		row.add_child(icon_lbl)
		var name_lbl := Label.new()
		name_lbl.text = String(entry.get("advisor_name", "?"))
		name_lbl.add_theme_color_override("font_color", entry.get("advisor_color", Color(0.7, 0.85, 1)))
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.custom_minimum_size = Vector2(140, 0)
		row.add_child(name_lbl)
		# Recomendação
		var rec_lbl := Label.new()
		var choice_label: String = String(rec.get("choice_label", "?")).strip_edges()
		rec_lbl.text = "→ " + choice_label
		rec_lbl.add_theme_color_override("font_color", Color(0.92, 0.96, 1))
		rec_lbl.add_theme_font_size_override("font_size", 11)
		rec_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rec_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rec_lbl.tooltip_text = String(rec.get("reason", ""))
		row.add_child(rec_lbl)

# Mostra toast (notificação canto da tela) quando achievement é desbloqueado.
# Não-bloqueante: aparece, fica 4s, fade out automático.
func _show_achievement_toast(id: String, name: String, description: String) -> void:
	# Acha o icon do achievement
	var icon: String = "🏅"
	for ach in GameEngine.achievements.ACHIEVEMENTS:
		if ach.get("id", "") == id:
			icon = ach.get("icon", "🏅")
			break
	# Cria toast como Control flutuante no canto superior direito
	var toast := PanelContainer.new()
	toast.size = Vector2(380, 76)
	toast.position = Vector2(get_viewport_rect().size.x - 400, 100)
	toast.z_index = 200
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.10, 0.15, 0.97)
	sb.border_color = Color(1, 0.85, 0.2, 1)
	sb.border_width_left = 4
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	toast.add_theme_stylebox_override("panel", sb)
	add_child(toast)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	toast.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	var icon_lbl := Label.new()
	icon_lbl.text = icon
	icon_lbl.add_theme_font_size_override("font_size", 22)
	head.add_child(icon_lbl)
	var col := VBoxContainer.new()
	head.add_child(col)
	var badge := Label.new()
	badge.text = "🏆 CONQUISTA DESBLOQUEADA"
	badge.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	badge.add_theme_font_size_override("font_size", 10)
	col.add_child(badge)
	var name_lbl := Label.new()
	name_lbl.text = name
	name_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	name_lbl.add_theme_font_size_override("font_size", 13)
	col.add_child(name_lbl)
	var desc_lbl := Label.new()
	desc_lbl.text = description
	desc_lbl.add_theme_color_override("font_color", Color(0.65, 0.78, 0.92))
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc_lbl)
	# Animação: slide-in da direita + fade-out depois de 4s
	toast.modulate = Color(1, 1, 1, 0)
	toast.position.x += 50
	var tw := create_tween().set_parallel(true)
	tw.tween_property(toast, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(toast, "position:x", get_viewport_rect().size.x - 400, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Fade out após 4 segundos
	var tw_out := create_tween()
	tw_out.tween_interval(4.0)
	tw_out.tween_property(toast, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_CUBIC)
	tw_out.tween_callback(func(): if is_instance_valid(toast): toast.queue_free())

func _show_confirmation_modal(title: String, msg: String, on_confirm: Callable, danger: bool = true) -> void:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	content.custom_minimum_size = Vector2(520, 0)
	# Mensagem
	var msg_lbl := Label.new()
	msg_lbl.text = msg
	msg_lbl.add_theme_color_override("font_color", Color(0.92, 0.96, 1))
	msg_lbl.add_theme_font_size_override("font_size", 13)
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(msg_lbl)
	# Aviso
	if danger:
		var warn := Label.new()
		warn.text = "⚠ Ação irreversível neste turno"
		warn.add_theme_color_override("font_color", Color(1, 0.65, 0.35))
		warn.add_theme_font_size_override("font_size", 11)
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(warn)
	# Botões
	var modal_ref: Array = [null]
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	content.add_child(row)
	var btn_no := _make_modal_button("✖ Cancelar", false)
	btn_no.custom_minimum_size = Vector2(140, 38)
	btn_no.pressed.connect(func(): _close_modal(modal_ref[0]))
	row.add_child(btn_no)
	var btn_yes := _make_modal_button("✓ Confirmar", true)
	btn_yes.custom_minimum_size = Vector2(140, 38)
	btn_yes.pressed.connect(func():
		_close_modal(modal_ref[0])
		on_confirm.call())
	row.add_child(btn_yes)
	modal_ref[0] = _open_modal(content, title, Vector2(560, 220))

func _on_declare_war_pressed() -> void:
	if preview_code == "" or preview_code == player_code: return
	_show_war_objective_modal(preview_code)

# Modal de OBJETIVO DE GUERRA: o jogador declara guerra POR ALGO. O objetivo
# amplifica o espólio correspondente na vitória (reparações / recurso / mudar regime).
func _show_war_objective_modal(target: String) -> void:
	var target_name: String = GameEngine.nations[target].nome
	var cost: float = max(20.0, GameEngine.player_nation.pib_bilhoes_usd * 0.02)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.custom_minimum_size = Vector2(520, 0)
	var title := Label.new()
	title.text = "⚔️ DECLARAR GUERRA — %s" % target_name
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1, 0.4, 0.35))
	content.add_child(title)
	var info := Label.new()
	info.text = "Custo: $%dB. Aliados de %s podem entrar na guerra. DEFCON cai.\nQual é o seu OBJETIVO? Ele define o que a vitória vai extrair." % [int(cost), target_name]
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_color_override("font_color", Color(0.85, 0.9, 1))
	content.add_child(info)
	content.add_child(HSeparator.new())
	var objetivos := [
		{"id": "reparacoes", "label": "💰 Reparações de guerra", "tip": "Vitória extrai muito mais tesouro do inimigo"},
		{"id": "recurso",    "label": "⛏ Tomar recursos",       "tip": "Vitória confisca mais do melhor recurso do inimigo"},
		{"id": "regime",     "label": "🏛 Mudança de regime",    "tip": "Vitória impõe seu regime ao inimigo (instabilidade extra nele)"},
		{"id": "conter",     "label": "🛡 Conter/enfraquecer",   "tip": "Espólio equilibrado; enfraquece o rival sem exigências específicas"},
	]
	for obj in objetivos:
		var btn := Button.new()
		btn.text = "  " + obj["label"]
		btn.tooltip_text = obj["tip"]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 44)
		btn.add_theme_font_size_override("font_size", 13)
		var oid: String = obj["id"]
		btn.pressed.connect(func():
			_close_top_modal()
			if GameEngine.player_declare_war(target, oid):
				_log_ticker("⚔️ MILITAR", "Guerra contra %s (objetivo: %s)" % [target_name, oid], Color(1, 0.3, 0.3))
				_repaint_map()
				_show_preview(target))
		content.add_child(btn)
	var cancel := Button.new()
	cancel.text = "✕ Cancelar"
	cancel.pressed.connect(func(): _close_top_modal())
	content.add_child(cancel)
	_open_modal(content, "", Vector2(560, 380))

func _on_propose_peace_pressed() -> void:
	if preview_code == "" or preview_code == player_code: return
	if GameEngine.player_propose_peace(preview_code):
		_log_ticker("🕊️ DIPLOMACIA", "Armistício com %s" % GameEngine.nations[preview_code].nome, Color(0.4, 1, 0.6))
		_repaint_map()
		_show_preview(preview_code)

func _on_embassy_pressed() -> void:
	if preview_code == "" or preview_code == player_code: return
	# Via API central: consome ação como toda iniciativa diplomática
	var res: Dictionary = GameEngine.player_open_embassy(preview_code)
	if res.get("ok", false):
		_log_ticker("🤝 DIPLOMACIA", String(res.get("msg", "")), Color(0.4, 0.85, 1))
	else:
		_log_ticker("⚠ DIPLOMACIA", String(res.get("reason", "Falhou")), Color(1, 0.6, 0.4))
	_show_preview(preview_code)
	_refresh_top_bar()

func _on_sanctions_pressed() -> void:
	if preview_code == "" or preview_code == player_code: return
	var t = GameEngine.nations[preview_code]
	_show_confirmation_modal(
		"🚫 IMPOR SANÇÕES",
		"Impor sanções contra %s?\n\nCusto: $%dB + 1 ação. Aplica -1.5%% PIB/turno no alvo por %d turnos. Relações caem -30. Bloqueia comércio bilateral." % [t.nome, GameEngine.SANCTION_COST, GameEngine.SANCTION_DURATION],
		func():
			var res: Dictionary = GameEngine.player_impose_sanctions(preview_code)
			if res.get("ok", false):
				_log_ticker("🚫 SANÇÕES", "Sanções contra %s — duração %d turnos" % [t.nome, GameEngine.SANCTION_DURATION], Color(1, 0.7, 0))
				_show_preview(preview_code)
			else:
				_log_ticker("⚠ SANÇÕES", res.get("reason", "Falha ao impor sanções"), Color(1, 0.4, 0.4)))

func _on_trade_pressed() -> void:
	if preview_code == "" or preview_code == player_code: return
	if GameEngine.player_nation == null: return
	# Abre modal listando recursos do jogador, jogador escolhe um pra exportar
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	var p = GameEngine.player_nation
	var t = GameEngine.nations[preview_code]
	var info := Label.new()
	info.text = "Exportar de %s para %s\nValor base: $8B/turno × (recurso/100) × bônus de relação\nDuração: %d turnos" % [p.nome, t.nome, GameEngine.TRADE_DURATION]
	info.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	info.add_theme_font_size_override("font_size", 11)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(info)
	var deco := ColorRect.new()
	deco.color = Color(0, 0.823, 1, 0.5)
	deco.custom_minimum_size = Vector2(60, 2)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(deco)
	var modal_ref: Array = [null]
	# Lista os recursos do jogador com valor >= 30
	var sorted_resources: Array = []
	for k in p.recursos.keys():
		var v: float = float(p.recursos[k])
		if v >= 30:
			sorted_resources.append({"id": k, "value": v})
	sorted_resources.sort_custom(func(a, b): return float(a["value"]) > float(b["value"]))
	if sorted_resources.is_empty():
		var none := Label.new()
		none.text = "Sua nação não tem recursos suficientes (mínimo 30/100) pra exportar."
		none.add_theme_color_override("font_color", Color(1, 0.6, 0.5))
		none.add_theme_font_size_override("font_size", 11)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(none)
	else:
		for entry in sorted_resources:
			var res_id: String = String(entry["id"])
			var res_val: float = float(entry["value"])
			var btn := Button.new()
			# Calcula receita estimada
			var rel_norm: float = clamp(float(p.relacoes.get(preview_code, 0)) / 100.0, -0.3, 0.3)
			var est_value: float = (res_val / 100.0) * GameEngine.TRADE_BASE_VALUE * (1.0 + rel_norm)
			var icon: String = "📦"
			if WorldMap_RESOURCE_ICONS.has(res_id):
				icon = WorldMap_RESOURCE_ICONS[res_id]
			btn.text = "%s  %s  (%.0f/100)   →   $%.1fB/turno" % [icon, res_id.capitalize().replace("_", " "), res_val, est_value]
			btn.custom_minimum_size = Vector2(0, 44)
			btn.add_theme_font_size_override("font_size", 12)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.pressed.connect(func():
				var r: Dictionary = GameEngine.player_export_resource(preview_code, res_id)
				if r.get("ok", false):
					_log_ticker("💰 COMÉRCIO", "Exportando %s p/ %s — $%.1fB/turno" % [res_id, t.nome, float(r.get("value_per_turn", 0))], Color(0.4, 1, 0.6))
				else:
					_log_ticker("⚠ COMÉRCIO", r.get("reason", "Falha"), Color(1, 0.4, 0.4))
				_close_modal(modal_ref[0])
				_show_preview(preview_code))
			content.add_child(btn)
	# Cancelar
	var cancel := _make_modal_button("✖ CANCELAR", false)
	cancel.custom_minimum_size = Vector2(0, 36)
	cancel.pressed.connect(func(): _close_modal(modal_ref[0]))
	content.add_child(cancel)
	modal_ref[0] = _open_modal(content, "💰 EXPORTAR RECURSOS — %s" % t.nome, Vector2(560, 540))

# Mapa rápido de ícones de recursos (pra reuso fora da função RESOURCE_META local)

# Recursos da cauda longa → ícone existente (nations.json tem 50+ tipos;
# os principais têm ícone próprio, o resto mapeia pro tematicamente próximo)
const RESOURCE_ICON_ALIAS := {
	"pesca": "peixes", "agricultura": "terras_araveis", "graos": "terras_araveis",
	"algodao": "terras_araveis", "acucar": "terras_araveis", "cha": "terras_araveis",
	"tabaco": "terras_araveis", "vinho": "terras_araveis", "amendoim": "terras_araveis",
	"oleo_palma": "terras_araveis", "borracha": "terras_araveis", "cacau": "cafe",
	"minerios": "minerios_raros", "litio": "minerios_raros", "coltan": "minerios_raros",
	"bauxita": "minerios_raros", "niquel": "minerios_raros", "platina": "minerios_raros",
	"prata": "minerios_raros", "cobalto": "minerios_raros", "esmeraldas": "diamantes",
	"jade": "diamantes", "rutilo": "minerios_raros", "fosfatos": "minerios_raros",
	"potassa": "minerios_raros", "sal": "minerios_raros",
	"hidreletrica": "agua_doce", "hidroeletricidade": "agua_doce",
	"energia_hidreletrica": "agua_doce", "energia_geotermica": "agua_doce",
	"energias_renovaveis": "agua_doce", "biodiversidade": "madeira", "cortica": "madeira",
	"servicos": "financas", "servicos_financeiros": "financas", "logistica": "financas",
	"navegacao": "peixes", "semicondutores": "tecnologia", "automotiva": "manufatura",
	"textil": "manufatura", "diplomacia": "financas", "selos_postais": "financas",
	"opio": "terras_araveis", "baunilha": "cafe", "ilang_ilang": "cafe",
}

static func resource_icon_path(res_name: String) -> String:
	var key: String = RESOURCE_ICON_ALIAS.get(res_name, res_name)
	var path: String = "res://icons/resources/%s.svg" % key
	return path if ResourceLoader.exists(path) else ""

const WorldMap_RESOURCE_ICONS := {
	"petroleo": "🛢", "gas_natural": "🔥", "minerios_raros": "💎",
	"uranio": "☢", "ferro": "⚙", "terras_araveis": "🌾",
	"agua_doce": "💧", "madeira": "🌲", "peixes": "🐟",
	"carvao": "⬛", "cobre": "🟫", "ouro": "🟡",
}

func _on_propose_treaty_pressed() -> void:
	if preview_code == "" or preview_code == player_code: return
	if GameEngine.diplomacy == null: return
	_show_treaty_picker_modal(preview_code)

func _on_espionage_pressed() -> void:
	if preview_code == "" or preview_code == player_code: return
	if GameEngine.espionage == null: return
	_show_spy_picker_modal(preview_code)

func _show_spy_picker_modal(target_code: String) -> void:
	var target = GameEngine.nations.get(target_code)
	if target == null: return
	var operator = GameEngine.player_nation
	var modal := ColorRect.new()
	modal.color = Color(0, 0, 0, 0.85)
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	if modal_layer != null:
		modal_layer.visible = true
		modal_layer.add_child(modal)
	else:
		add_child(modal)
	# CenterContainer full-rect centraliza sem offset manual (funciona em qualquer resolução)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	modal.add_child(center)
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(640, 600)
	center.add_child(box)
	UIStyles.animate_modal_in(modal, box)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.custom_minimum_size = Vector2(600, 0)
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)
	var cap := Label.new()
	cap.text = "🕵 OPERAÇÃO DE ESPIONAGEM"
	cap.add_theme_color_override("font_color", Color(0, 0.823, 1))
	cap.add_theme_font_size_override("font_size", 11)
	v.add_child(cap)
	var title := Label.new()
	title.text = "Alvo: " + target.nome
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	title.add_theme_font_size_override("font_size", 18)
	v.add_child(title)
	var info := Label.new()
	info.text = "Seu Intel: %.1f  •  Segurança alvo: %.1f  •  Tesouro: $%dB" % [operator.intel_score, target.seguranca_intel, int(operator.tesouro)]
	info.add_theme_color_override("font_color", Color(0.7, 0.78, 0.88))
	info.add_theme_font_size_override("font_size", 11)
	v.add_child(info)
	v.add_child(HSeparator.new())
	for op_id in GameEngine.espionage.OPS:
		var op: Dictionary = GameEngine.espionage.get_op_with_chance(operator, target, op_id)
		var btn := Button.new()
		var chance: float = float(op.get("chance_real", op["base_success"]))
		btn.text = "%s %s — $%dB | êxito %d%%\n%s" % [
			op["icon"], op["nome"], int(op["custo"]),
			int(chance * 100), op["descricao"]
		]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 56)
		btn.add_theme_font_size_override("font_size", 11)
		if operator.tesouro < int(op["custo"]):
			btn.disabled = true
		btn.pressed.connect(func():
			var res: Dictionary = GameEngine.player_execute_spy(op_id, target_code)
			var color := Color(0.4, 1, 0.6) if res.get("success", false) else Color(1, 0.4, 0.4)
			_log_ticker("🕵 INTEL", res.get("msg", "?"), color)
			modal.queue_free()
			_show_preview(target_code))
		v.add_child(btn)
	v.add_child(HSeparator.new())
	var btn_cancel := Button.new()
	btn_cancel.text = "❌ CANCELAR"
	btn_cancel.custom_minimum_size = Vector2(0, 36)
	btn_cancel.pressed.connect(func(): modal.queue_free())
	v.add_child(btn_cancel)

func _show_treaty_picker_modal(target_code: String) -> void:
	var target = GameEngine.nations.get(target_code)
	if target == null: return
	var modal := ColorRect.new()
	modal.color = Color(0, 0, 0, 0.85)
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	if modal_layer != null:
		modal_layer.visible = true
		modal_layer.add_child(modal)
	else:
		add_child(modal)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	modal.add_child(center)
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(560, 480)
	center.add_child(box)
	UIStyles.animate_modal_in(modal, box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	box.add_child(v)
	var cap := Label.new()
	cap.text = "📜 PROPOR TRATADO"
	cap.add_theme_color_override("font_color", Color(0, 0.823, 1))
	cap.add_theme_font_size_override("font_size", 11)
	v.add_child(cap)
	var title := Label.new()
	title.text = "Para: " + target.nome
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	title.add_theme_font_size_override("font_size", 18)
	v.add_child(title)
	var hint := Label.new()
	hint.text = "Selecione o tipo de tratado a propor. A IA decidirá com base em personalidade e relação atual."
	hint.add_theme_color_override("font_color", Color(0.7, 0.78, 0.88))
	hint.add_theme_font_size_override("font_size", 11)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	v.add_child(HSeparator.new())
	for tt_id in GameEngine.diplomacy.TIPOS_TRATADO:
		var meta = GameEngine.diplomacy.TIPOS_TRATADO[tt_id]
		var btn := Button.new()
		btn.text = "📜 %s\n%s" % [meta["nome"], meta["descricao"]]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 50)
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(func():
			GameEngine.player_propose_treaty(target_code, tt_id)
			_log_ticker("📜 DIPLOMACIA", "Proposta de %s enviada a %s" % [meta["nome"], target.nome], Color(0.7, 0.5, 1))
			modal.queue_free())
		v.add_child(btn)
	v.add_child(HSeparator.new())
	var btn_cancel := Button.new()
	btn_cancel.text = "❌ CANCELAR"
	btn_cancel.custom_minimum_size = Vector2(0, 36)
	btn_cancel.pressed.connect(func(): modal.queue_free())
	v.add_child(btn_cancel)

# ─────────────────────────────────────────────────────────────────
# MODAL DO FMI — resgate em crise fiscal (aceitar/recusar)
# ─────────────────────────────────────────────────────────────────

func _open_bailout_modal(terms: Dictionary) -> void:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	content.custom_minimum_size = Vector2(600, 0)
	# Retrato da Ministra da Fazenda entregando a má notícia — dá rosto à crise
	if GameEngine.player_nation != null:
		var min_row := HBoxContainer.new()
		min_row.add_theme_constant_override("separation", 12)
		content.add_child(min_row)
		var mpv := PortraitView.make(GameEngine.player_nation.codigo_iso, "economia", "urgente", 72.0)
		mpv.custom_minimum_size = Vector2(72, 86)
		mpv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		min_row.add_child(mpv)
		var quote := Label.new()
		quote.text = "“Presidente, esgotamos as alternativas. O Fundo é a única saída — mas o preço é alto.”"
		quote.add_theme_color_override("font_color", Color(0.88, 0.82, 0.7))
		quote.add_theme_font_size_override("font_size", 13)
		quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		quote.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		quote.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		min_row.add_child(quote)
	var badge := Label.new()
	badge.text = "🏦 FUNDO MONETÁRIO INTERNACIONAL"
	badge.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	badge.add_theme_font_size_override("font_size", 11)
	content.add_child(badge)
	var headline := Label.new()
	headline.text = "Resgate de $%dB — aceitar as condições?" % int(terms.get("valor", 0))
	headline.add_theme_color_override("font_color", Color(0.95, 1, 1))
	headline.add_theme_font_size_override("font_size", 20)
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(headline)
	var body := Label.new()
	body.text = "Seu tesouro está zerado há 2 turnos — mais 2 e é FALÊNCIA NACIONAL.\n\nCONDIÇÕES DO FUNDO:\n• Empréstimo de $%dB entra no tesouro\n• Dívida pública +$%dB (juros embutidos)\n• Austeridade: gasto social cortado pela metade\n• Apoio popular -8, felicidade -5\n\nRecusar mantém a soberania — e o risco." % [int(terms.get("valor", 0)), int(float(terms.get("valor", 0)) * 1.2)]
	body.add_theme_color_override("font_color", Color(0.8, 0.87, 0.95))
	body.add_theme_font_size_override("font_size", 12)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	content.add_child(row)
	var modal_ref: Array = [null]
	var btn_no := _make_modal_button("✊ RECUSAR (soberania)", false)
	btn_no.custom_minimum_size = Vector2(220, 44)
	btn_no.pressed.connect(func():
		GameEngine.decline_bailout()
		_log_ticker("🏦 FMI", "Resgate RECUSADO — o tesouro segue no vermelho.", Color(1, 0.55, 0.3))
		_close_modal(modal_ref[0]))
	row.add_child(btn_no)
	var btn_yes := _make_modal_button("🏦 ACEITAR RESGATE", true)
	btn_yes.custom_minimum_size = Vector2(220, 44)
	btn_yes.pressed.connect(func():
		if GameEngine.accept_bailout():
			_log_ticker("🏦 FMI", "Resgate aceito — tesouro reforçado, povo sente a austeridade.", Color(0.4, 0.85, 1))
		_close_modal(modal_ref[0])
		_refresh_top_bar()
		_refresh_resource_bar())
	row.add_child(btn_yes)
	modal_ref[0] = _open_modal(content, "⚠ CRISE FISCAL", Vector2(660, 420), false)

# ─────────────────────────────────────────────────────────────────
# FILTROS DE MAPA
# ─────────────────────────────────────────────────────────────────

# Filtros do mapa: glifo + COR que casa com o que o filtro pinta no mapa.
# (Satélite/Político = neutro; Economia azul; Militar vermelho;
#  Estabilidade verde; Recursos dourado — a mesma lógica de _filter_color.)
const MAP_FILTERS := [
	{"id": "SATELITE",     "label": "Satélite",     "glifo": "🛰", "cor": Color(0.55, 0.75, 0.95)},
	{"id": "POLITICO",     "label": "Político",     "glifo": "🏛", "cor": Color(0.70, 0.75, 0.85)},
	{"id": "ECONOMIA",     "label": "Economia",     "glifo": "💰", "cor": Color(0.30, 0.62, 0.98)},
	{"id": "MILITAR",      "label": "Militar",      "glifo": "⚔",  "cor": Color(0.95, 0.38, 0.32)},
	{"id": "ESTABILIDADE", "label": "Estabilidade", "glifo": "🏛", "cor": Color(0.35, 0.90, 0.55)},
	{"id": "RECURSOS",     "label": "Recursos",     "glifo": "⛏", "cor": Color(0.92, 0.76, 0.36)},
]

func _build_map_filters() -> void:
	if map_filters == null: return
	for c in map_filters.get_children(): c.queue_free()
	# Filtros = botões SÓ-GLIFO quadrados (nunca cortam; o nome vai no tooltip
	# e numa etiqueta abaixo do ativo). Compactos, cabem ao lado dos 11
	# ministérios sem espremer o rótulo.
	for f in MAP_FILTERS:
		var fid: String = f["id"]
		var cor: Color = f["cor"]
		var is_sel: bool = fid == current_filter
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_pressed = is_sel
		btn.set_meta("filter_id", fid)
		btn.set_meta("filter_cor", cor)
		btn.text = f["glifo"]
		btn.custom_minimum_size = Vector2(34, 32)
		btn.tooltip_text = f["label"]
		btn.add_theme_font_size_override("font_size", 15)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		# Selecionado: acende na cor do filtro. Normal/hover: neutro discreto.
		var sb_n := StyleBoxFlat.new()
		sb_n.bg_color = Color(0.065, 0.068, 0.080, 0.85)
		sb_n.border_color = Color(0.30, 0.32, 0.36, 0.5)
		sb_n.set_border_width_all(1)
		sb_n.set_corner_radius_all(8)
		btn.add_theme_stylebox_override("normal", sb_n)
		var sb_sel := StyleBoxFlat.new()
		sb_sel.bg_color = Color(cor.r * 0.22, cor.g * 0.22, cor.b * 0.22, 0.95)
		sb_sel.border_color = cor
		sb_sel.set_border_width_all(2)
		sb_sel.set_corner_radius_all(8)
		sb_sel.shadow_color = Color(cor.r, cor.g, cor.b, 0.25)
		sb_sel.shadow_size = 4
		btn.add_theme_stylebox_override("pressed", sb_sel)
		var sb_h := sb_n.duplicate() as StyleBoxFlat
		sb_h.bg_color = Color(cor.r * 0.14, cor.g * 0.14, cor.b * 0.14, 0.85)
		sb_h.border_color = Color(cor.r, cor.g, cor.b, 0.7)
		btn.add_theme_stylebox_override("hover", sb_h)
		btn.pressed.connect(_on_map_filter_pressed.bind(fid))
		map_filters.add_child(btn)
	_refresh_filter_label()

func _on_map_filter_pressed(filter_id: String) -> void:
	current_filter = filter_id
	for child in map_filters.get_children():
		if child is Button:
			child.button_pressed = (child.get_meta("filter_id", "") == filter_id)
	# Oceano acompanha: satélite no realista, CHAPADO escuro nos filtros de dados
	var ocean := get_node_or_null("Ocean") as ColorRect
	if ocean != null and ocean.material is ShaderMaterial:
		(ocean.material as ShaderMaterial).set_shader_parameter(
			"data_mode", 0.0 if filter_id == "SATELITE" else 1.0)
	_refresh_filter_label()
	_repaint_map()
	_refresh_resource_icons()  # mostra/esconde camada de ícones

# Etiqueta "MAPA: <filtro>" antes dos botões de filtro — como viraram
# só-glifo, o nome do modo ativo (na cor do filtro) aparece aqui.
func _refresh_filter_label() -> void:
	if map_filters == null: return
	var lbl := map_filters.get_node_or_null("FilterLabel") as Label
	if lbl == null:
		lbl = Label.new()
		lbl.name = "FilterLabel"
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_filters.add_child(lbl)
		map_filters.move_child(lbl, 0)  # antes dos botões
	var meta := {}
	for f in MAP_FILTERS:
		if f["id"] == current_filter:
			meta = f
			break
	lbl.text = String(meta.get("label", "")).to_upper()
	lbl.add_theme_color_override("font_color", meta.get("cor", Color(0.7, 0.7, 0.75)))

# Constrói (ou esconde) a camada de ícones de recursos.
# Aparece só quando filtro == RECURSOS. Cada país com top resource >= 60
# ganha um ícone emoji no centro do território.
func _refresh_resource_icons() -> void:
	if resource_icons_layer == null: return
	# Limpa filhos atuais
	for c in resource_icons_layer.get_children():
		c.queue_free()
	if current_filter != "RECURSOS":
		resource_icons_layer.visible = false
		return
	resource_icons_layer.visible = true
	# Pra cada país, se tem recurso predominante >= 60, cria ícone
	for code in countries.keys():
		if not GameEngine.nations.has(code): continue
		var n = GameEngine.nations[code]
		var top: Dictionary = _top_resource(n)
		if top.is_empty(): continue
		if float(top["value"]) < 60.0: continue
		var entry: Dictionary = countries[code]
		var bounds: Rect2 = entry.get("bounds", Rect2())
		if bounds.size.length_squared() <= 0: continue
		var center: Vector2 = bounds.position + bounds.size / 2.0
		var meta: Dictionary = RESOURCE_META.get(top["name"], {})
		var icon_str: String = meta.get("icon", "📦")
		# Container do ícone
		var holder := Node2D.new()
		holder.position = center
		holder.z_index = 4
		resource_icons_layer.add_child(holder)
		# Fundo translúcido
		var bg := Polygon2D.new()
		var bg_pts := PackedVector2Array()
		var radius: float = 7.0
		for i in 16:
			var a: float = TAU * i / 16.0
			bg_pts.append(Vector2(cos(a) * radius, sin(a) * radius))
		bg.polygon = bg_pts
		var bg_color: Color = meta.get("color", Color(0.5, 0.5, 0.5))
		bg.color = Color(bg_color.r, bg_color.g, bg_color.b, 0.55)
		holder.add_child(bg)
		# Ícone VETORIAL do recurso (game-icons.net, CC BY 3.0) — nítido em
		# qualquer zoom; fallback pro emoji se o SVG não existir
		var icon_path: String = resource_icon_path(String(top["name"]))
		if icon_path != "":
			var spr := Sprite2D.new()
			spr.texture = load(icon_path)
			var tex_size: float = max(1.0, spr.texture.get_width())
			spr.scale = Vector2(11.0 / tex_size, 11.0 / tex_size)
			spr.modulate = Color(1, 1, 1, 0.95)
			holder.add_child(spr)
		else:
			var lbl := Label.new()
			lbl.text = icon_str
			lbl.add_theme_font_size_override("font_size", 12)
			lbl.position = Vector2(-7, -10)
			holder.add_child(lbl)
		# Tooltip com valor no círculo de fundo (Área clicável seria overkill)
		bg.set_meta("tooltip", "%s: %d/100" % [meta.get("label", top["name"]), int(top["value"])])

# ─────────────────────────────────────────────────────────────────
# COR POR ESTADO + FILTROS DE MAPA
# ─────────────────────────────────────────────────────────────────

# Países que pulsam em vermelho (inimigos em guerra ativa com o jogador).
# Pulso via modulate do node-pai: 1 propriedade/país, sem re-triangulação.
var _war_pulse_nodes: Array = []

func _repaint_map() -> void:
	# Reset do pulso anterior (nodes que saíram da guerra voltam ao neutro)
	for nd in _war_pulse_nodes:
		if is_instance_valid(nd):
			nd.modulate = Color(1, 1, 1)
	_war_pulse_nodes.clear()
	for code in countries:
		_repaint_country_state(code)
	# Coleta os inimigos ativos do jogador para o pulso de guerra
	if player_code != "" and GameEngine.player_nation != null:
		for enemy_code in GameEngine.player_nation.em_guerra:
			var entry: Dictionary = countries.get(enemy_code, {})
			var nd = entry.get("node")
			if nd != null and is_instance_valid(nd):
				_war_pulse_nodes.append(nd)

func _repaint_country_state(code: String) -> void:
	var is_sat: bool = current_filter == "SATELITE"
	if not GameEngine.nations.has(code):
		_paint_country_full(code,
			COUNTRY_FILL if is_sat else Color(0.18, 0.20, 0.25, 0.0), COUNTRY_STROKE)
		return
	var n = GameEngine.nations[code]
	var color := _filter_color(n)
	var border := COUNTRY_STROKE
	if player_code != "":
		var p = GameEngine.player_nation
		if code == player_code:
			border = Color(0.40, 1.02, 1.26, 0.95)
			if is_sat: color = COUNTRY_PLAYER
		elif code in p.em_guerra:
			border = Color(1.28, 0.38, 0.34, 0.95)
			if is_sat: color = COUNTRY_ENEMY
		elif _is_ally(code):
			border = Color(0.50, 1.18, 0.66, 0.85)
			if is_sat: color = color.lerp(COUNTRY_ALLY, 0.6)
	# Nos filtros de dados NINGUÉM vaza satélite: área = cor do filtro para
	# todos (coroplético uniforme); jogador/inimigo/aliado aparecem na BORDA.
	_paint_country_full(code, color, border)

func _is_ally(code: String) -> bool:
	if player_code == "" or GameEngine.alliances_data.is_empty():
		return false
	for alliance in GameEngine.alliances_data:
		var members: Array = alliance.get("membros", [])
		if player_code in members and code in members and code != player_code:
			return true
	return false

# Mapa POLÍTICO clássico: cor chapada por REGIME, com variação leve por
# país (vizinhos do mesmo regime não colam). Democracias azuis, híbridos
# âmbar, autocracias vermelhas, teocracias roxas.
func _regime_color(n) -> Color:
	var r: String = n.regime_politico
	var base: Color
	if "COMUNIS" in r or "DITADURA" in r:
		base = Color(0.60, 0.16, 0.14)
	elif "TEOCRA" in r:
		base = Color(0.44, 0.22, 0.58)
	elif "MONARQUIA_ABS" in r:
		base = Color(0.52, 0.28, 0.58)
	elif "AUTORITA" in r or "HIBRIDO" in r:
		base = Color(0.76, 0.47, 0.14)
	else:
		base = Color(0.16, 0.40, 0.72)
	var h: float = float(abs(n.codigo_iso.hash()) % 100) / 100.0
	var shade: float = 0.86 + 0.26 * h
	return Color(base.r * shade, base.g * shade, base.b * shade, 0.0)

func _filter_color(n) -> Color:
	match current_filter:
		"SATELITE":
			return COUNTRY_FILL
		"POLITICO":
			return _regime_color(n)
		"ECONOMIA":
			# COROPLÉTICO (a=0 → cor lisa no shader): rampa verde-escuro → verde
			var pib: float = n.pib_bilhoes_usd
			var v: float = clamp(0.1 + log(pib + 1) / log(30000.0) * 0.7, 0.1, 1.0)
			return Color(0.045, 0.075, 0.150, 0.0).lerp(Color(0.24, 0.56, 0.96, 0.0), v)
		"MILITAR":
			var orc: float = float(n.militar.get("orcamento_militar_bilhoes", 0))
			var nukes: int = int(n.militar.get("armas_nucleares", 0))
			var v: float = clamp(orc / 900.0 + (0.3 if nukes > 0 else 0.0) + 0.05, 0.05, 1.0)
			return Color(0.16, 0.055, 0.05, 0.0).lerp(Color(0.88, 0.24, 0.19, 0.0), v)
		"ESTABILIDADE":
			var stab: float = n.estabilidade_politica
			if stab >= 65:
				var g: float = clamp((stab - 65.0) / 35.0, 0.0, 1.0)
				return Color(0.14, 0.42, 0.22, 0.0).lerp(Color(0.20, 0.72, 0.36, 0.0), g)
			elif stab >= 35:
				var y: float = clamp((stab - 35.0) / 30.0, 0.0, 1.0)
				return Color(0.72, 0.50, 0.12, 0.0).lerp(Color(0.80, 0.64, 0.16, 0.0), y)
			else:
				var r: float = clamp(stab / 35.0, 0.0, 1.0)
				return Color(0.52, 0.10, 0.09, 0.0).lerp(Color(0.72, 0.20, 0.15, 0.0), r)
		"RECURSOS":
			# Pinta país pela cor do recurso predominante (valor mais alto)
			# Intensidade = magnitude do valor (recursos vão 0-100)
			var top: Dictionary = _top_resource(n)
			if top.is_empty(): return COUNTRY_FILL
			var meta: Dictionary = RESOURCE_META.get(top["name"], {})
			var col: Color = meta.get("color", Color(0.5, 0.5, 0.5))
			var intensity: float = clamp(float(top["value"]) / 100.0, 0.15, 1.0)
			# COROPLÉTICO: cor lisa do recurso, sombreada pela abundância
			var shade: float = 0.45 + 0.55 * intensity
			return Color(col.r * shade, col.g * shade, col.b * shade, 0.0)
	return COUNTRY_FILL

# Recursos do jogo com cor + ícone emoji (usado no filtro RECURSOS)
const RESOURCE_META := {
	"petroleo":       {"color": Color(0.15, 0.10, 0.05),  "icon": "🛢", "label": "Petróleo"},
	"gas_natural":    {"color": Color(0.45, 0.45, 0.55),  "icon": "🔥", "label": "Gás Natural"},
	"minerios_raros": {"color": Color(0.85, 0.55, 0.10),  "icon": "💎", "label": "Minérios Raros"},
	"uranio":         {"color": Color(0.55, 1.00, 0.30),  "icon": "☢", "label": "Urânio"},
	"ferro":          {"color": Color(0.55, 0.35, 0.25),  "icon": "⚙", "label": "Ferro"},
	"terras_araveis": {"color": Color(0.30, 0.85, 0.35),  "icon": "🌾", "label": "Agricultura"},
	"agua_doce":      {"color": Color(0.35, 0.65, 1.00),  "icon": "💧", "label": "Água"},
	"madeira":        {"color": Color(0.45, 0.30, 0.15),  "icon": "🌲", "label": "Madeira"},
	"peixes":         {"color": Color(0.20, 0.60, 0.85),  "icon": "🐟", "label": "Pesca"},
	"carvao":         {"color": Color(0.20, 0.20, 0.20),  "icon": "⬛", "label": "Carvão"},
	"cobre":          {"color": Color(0.85, 0.45, 0.20),  "icon": "🟫", "label": "Cobre"},
	"ouro":           {"color": Color(1.00, 0.85, 0.20),  "icon": "🟡", "label": "Ouro"},
}

# Retorna {name, value} do recurso predominante (maior valor) da nação
func _top_resource(n) -> Dictionary:
	if n.recursos == null or n.recursos.is_empty(): return {}
	var best_name: String = ""
	var best_val: float = -1.0
	for k in n.recursos.keys():
		var v: float = float(n.recursos[k])
		if v > best_val:
			best_val = v
			best_name = String(k)
	if best_name == "" or best_val <= 0: return {}
	return {"name": best_name, "value": best_val}

func _paint_country(code: String, color: Color) -> void:
	var entry = countries.get(code)
	if entry == null: return
	# CRÍTICO DE PERFORMANCE: pintar TODOS os países todo turno marcava
	# ~3000 Polygon2D como sujos → re-triangulação de 548k vértices no
	# frame seguinte = ~9 SEGUNDOS DE CONGELAMENTO POR TURNO (medido em
	# Vulkan e headless). Cache da última cor: só repinta quem MUDOU.
	_paint_country_full(code, color, _border_for(color))

# Pintura completa (área + fronteira) com cache — só repinta quem mudou.
func _paint_country_full(code: String, color: Color, border: Color) -> void:
	var entry = countries.get(code)
	if entry == null: return
	if entry.get("last_color", Color(-1, -1, -1)) == color 			and entry.get("last_border", Color(-1, -1, -1)) == border:
		return
	entry["last_color"] = color
	entry["last_border"] = border
	for child in entry["node"].get_children():
		if child is Polygon2D:
			child.self_modulate = color
		elif child is Line2D:
			child.default_color = border

# Fronteira colorida por estado: o highlight elegante em mapa de satélite
# é o CONTORNO brilhante, não lavar a área inteira. (>1.0 = glow no HDR)
func _border_for(fill: Color) -> Color:
	if fill.is_equal_approx(COUNTRY_PLAYER):
		return Color(0.40, 1.02, 1.26, 0.95)
	if fill.is_equal_approx(COUNTRY_ENEMY):
		return Color(1.28, 0.38, 0.34, 0.95)
	if fill.is_equal_approx(COUNTRY_PREVIEW):
		return Color(1.30, 1.06, 0.42, 0.95)  # DOURADO — assinatura do jogo
	if fill.is_equal_approx(COUNTRY_ALLY):
		return Color(0.50, 1.18, 0.66, 0.85)
	return COUNTRY_STROKE

# ─────────────────────────────────────────────────────────────────
# TOP BAR REFRESH
# ─────────────────────────────────────────────────────────────────

func _refresh_actions_label(remaining: int) -> void:
	if actions_label == null or GameEngine == null: return
	actions_label.text = "%d / %d" % [remaining, GameEngine.PLAYER_ACTIONS_PER_TURN]
	# Cor dinâmica: amarelo quando cheio, laranja meio, vermelho zero
	if remaining == 0:
		actions_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	elif remaining == 1:
		actions_label.add_theme_color_override("font_color", Color(1, 0.6, 0.3))
	else:
		actions_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))

func _refresh_top_bar() -> void:
	if GameEngine == null: return
	var quarters := ["JAN", "FEV", "MAR", "ABR", "MAI", "JUN", "JUL", "AGO", "SET", "OUT", "NOV", "DEZ"]
	if date_label:
		date_label.text = "%s %d" % [quarters[GameEngine.date_month - 1], GameEngine.date_year]
	if turn_label:
		turn_label.text = str(GameEngine.current_turn)
	if defcon_label:
		defcon_label.text = "DEFCON %d" % GameEngine.defcon
	if GameEngine.player_nation and treasury_label:
		var t: float = GameEngine.player_nation.tesouro
		treasury_label.text = "$%.1fT" % (t / 1000.0) if abs(t) >= 1000.0 else "$%dB" % int(t)
	elif treasury_label:
		treasury_label.text = "—"
	if GameEngine.player_nation and score_label:
		score_label.text = "%04d" % _compute_score(GameEngine.player_nation)
	elif score_label:
		score_label.text = "0000"
	# Posição no ranking mundial de poder (a métrica de vitória, sempre à vista)
	# Lê do histórico registrado pelo engine a cada turno — custo zero aqui.
	if GameEngine.player_nation and rank_label:
		var hist: Array = GameEngine.player_power_rank_history
		var rank: int
		if hist.size() > 0:
			rank = int(hist[hist.size() - 1])
		else:
			GameEngine._refresh_world_maxima()
			rank = GameEngine.get_power_rank(GameEngine.player_nation.codigo_iso)
		var arrow := ""
		if hist.size() >= 2:
			var prev: int = int(hist[hist.size() - 2])
			if rank < prev: arrow = " ▲"
			elif rank > prev: arrow = " ▼"
		rank_label.text = "🌍 #%d%s" % [rank, arrow]
		var rank_color: Color
		if rank == 1: rank_color = Color(1, 0.85, 0.2)
		elif rank <= 5: rank_color = Color(0.4, 1, 0.6)
		elif rank <= 20: rank_color = Color(0, 0.823, 1)
		else: rank_color = Color(0.75, 0.85, 1)
		rank_label.add_theme_color_override("font_color", rank_color)
	elif rank_label:
		rank_label.text = "🌍 #—"

func _on_turn_advanced(_t: int) -> void:
	_repaint_map()
	if preview_code != "" and right_panel and right_panel.visible:
		_fill_preview_panel(preview_code)
	_refresh_top_bar()
	_refresh_resource_bar()
	_update_news_ticker()
	_notify_upcoming_decisions()
	_decay_event_markers()
	_maybe_autosave()
	_maybe_show_contextual_tip()

# Tooltip-toast contextual nos primeiros turnos. Aparece no canto superior por 6s,
# não bloqueia gameplay. Persiste turnos mostrados em user://settings.cfg.
func _maybe_show_contextual_tip() -> void:
	var t: int = GameEngine.current_turn
	var cfg = ConfigFile.new()
	cfg.load("user://settings.cfg")
	var shown_turns: Array = cfg.get_value("tips", "shown_turns", [])
	if t in shown_turns: return
	var tip: String = ""
	# Dicas dos primeiros turnos (onboarding inicial)
	match t:
		2:
			tip = "💡 DICA: Você tem 3 ações por turno. Use os 9 painéis (G, M, E, etc) para agir antes de avançar com SPACE."
		3:
			tip = "💡 DICA: Clique em qualquer país no mapa para ver detalhes e abrir ações diplomáticas (embaixada, sanção, tratado)."
		4:
			tip = "💡 DICA: Acompanhe a barra de notícias no rodapé — eventos históricos podem disparar decisões importantes."
		6:
			tip = "💡 DICA: Sua relação com outros países muda com o tempo. Quem cair abaixo de -50 vira rival declarado."
		# Onboarding de MÉDIO/LATE-GAME (#14): metas por fase da campanha
		36:  # ~2003 (3 anos)
			tip = "🎯 FASE INICIAL: consolide as bases — estabilidade, apoio e um tesouro saudável. Considere aderir a um BLOCO (painel Diplomacia) para ganhar aliados."
		120:  # ~2010 (10 anos)
			tip = "🎯 MÉDIO PRAZO: hora de crescer. Invista em Educação (pesquisa) e Economia. Suba o nível da Casa Civil para abrir mais trilhas de pesquisa paralelas."
		300:  # ~2025 (25 anos)
			tip = "🎯 ASCENSÃO: mire o top-5 de poder mundial (painel Situação). Techs, PIB e diplomacia contam. Cuidado: virar hegemon faz o mundo se unir contra você."
		600:  # ~2050 (50 anos)
			tip = "🎯 LEGADO: meio século se passou. Busque a HEGEMONIA (#1 em poder por 4 anos) ou garanta a Potência do Século (top-5 em 2100)."
	if tip == "":
		return
	_show_tutorial_toast(tip)
	shown_turns.append(t)
	cfg.set_value("tips", "shown_turns", shown_turns)
	cfg.save("user://settings.cfg")

# Detecta se está em viewport compacto (laptop 1366x768) e ajusta layout
func _detect_compact_mode() -> void:
	var vp_size := get_viewport_rect().size
	compact_mode = vp_size.y <= COMPACT_VIEWPORT_HEIGHT
	if compact_mode:
		TOP_BAR_H = TOP_BAR_H_COMPACT
		BOTTOM_BAR_H = BOTTOM_BAR_H_COMPACT
		# Ajusta altura visual da bottom bar (ancorada embaixo → offset_top)
		var bb := get_node_or_null("HUD/BottomBar")
		if bb is Control:
			(bb as Control).offset_top = -BOTTOM_BAR_H
			(bb as Control).custom_minimum_size = Vector2(0, BOTTOM_BAR_H)
		var tb := get_node_or_null("HUD/TopBar")
		if tb is Control:
			(tb as Control).custom_minimum_size = Vector2(0, TOP_BAR_H)
		# Reduz altura do mapa de recursos e action row
		var rb := get_node_or_null("HUD/BottomBar/V/ResourceBar")
		if rb is Control:
			(rb as Control).custom_minimum_size = Vector2(0, 22)
		print("[LAYOUT] Modo compacto ativo (viewport=%dx%d)" % [vp_size.x, vp_size.y])
	else:
		TOP_BAR_H = TOP_BAR_H_NORMAL
		BOTTOM_BAR_H = BOTTOM_BAR_H_NORMAL
		var bb_n := get_node_or_null("HUD/BottomBar")
		if bb_n is Control:
			(bb_n as Control).offset_top = -BOTTOM_BAR_H

func _show_tutorial_toast(text: String) -> void:
	var toast := PanelContainer.new()
	toast.name = "TutorialToast_%d" % Time.get_ticks_msec()
	toast.add_theme_stylebox_override("panel", UIStyles.toast("warning"))
	# CRÍTICO: a largura fixa vai no CONTAINER, nunca no label — Label com
	# autowrap + minimum size dentro de PanelContainer auto-fit criava LOOP
	# INFINITO DE LAYOUT (resize↔rewrap no mesmo frame), CONGELANDO O JOGO
	# no exato turno da 1ª dica contextual (turnos 2/3/5 de toda partida nova).
	toast.custom_minimum_size = Vector2(470, 0)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast.add_child(lbl)
	add_child(toast)
	# Posiciona no topo-centro
	toast.position = Vector2(get_viewport_rect().size.x * 0.5 - 235, 110)
	toast.modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property(toast, "modulate:a", 1.0, 0.4)
	tw.tween_interval(6.0)
	tw.tween_property(toast, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func():
		if is_instance_valid(toast): toast.queue_free())

# Auto-save a cada AUTOSAVE_INTERVAL turnos. Silencioso, só loga no ticker
# se foi feito. Não bloqueia jogo.
const AUTOSAVE_INTERVAL: int = 5
func _maybe_autosave() -> void:
	if GameEngine == null or GameEngine.player_nation == null: return
	if GameEngine.current_turn <= 0: return
	if GameEngine.current_turn % AUTOSAVE_INTERVAL != 0: return
	var SaveSys = preload("res://scripts/SaveSystem.gd")
	if SaveSys.save_game(GameEngine):
		_log_ticker("💾 AUTOSAVE", "Salvo automaticamente (turno %d)" % GameEngine.current_turn, Color(0.4, 0.85, 1))

# ─────────────────────────────────────────────────────────────────
# BOT DE IA — MODO ESPECTADOR
# ─────────────────────────────────────────────────────────────────

func start_bot_mode(personality: String = "balanced", speed: float = 2.0) -> void:
	if bot_player != null:
		bot_player.stop()
	var BotScript = load("res://scripts/BotPlayer.gd")
	bot_player = BotScript.new(GameEngine, get_tree(), personality)
	bot_player.speed_delay = speed
	bot_player.turn_delay = maxf(0.8, speed * 0.7)
	bot_player.thinking.connect(_on_bot_thinking)
	bot_player.action_taken.connect(_on_bot_action)
	bot_player.turn_starting.connect(_on_bot_turn_starting)
	_build_bot_overlay()
	bot_player.start()
	_log_ticker("🤖 BOT", "Modo espectador ativado — Personalidade: %s" % personality.capitalize(), Color(0.4, 0.85, 1))

func stop_bot_mode() -> void:
	if bot_player != null:
		bot_player.stop()
		bot_player = null
	if bot_overlay != null and is_instance_valid(bot_overlay):
		bot_overlay.queue_free()
		bot_overlay = null
	_log_ticker("🤖 BOT", "Modo espectador desativado.", Color(0.7, 0.7, 0.7))

func _on_bot_thinking(msg: String) -> void:
	bot_log_lines.append(msg)
	if bot_log_lines.size() > BOT_LOG_MAX:
		bot_log_lines = bot_log_lines.slice(bot_log_lines.size() - BOT_LOG_MAX)
	_refresh_bot_overlay()

func _on_bot_action(action: Dictionary) -> void:
	_refresh_top_bar()
	_repaint_map()

func _on_bot_turn_starting(turn: int) -> void:
	bot_log_lines.clear()
	bot_log_lines.append("━━━ Turno %d ━━━" % turn)
	_refresh_bot_overlay()

# Painel HUD flutuante no canto direito — mostra o raciocínio em tempo real
func _build_bot_overlay() -> void:
	if bot_overlay != null and is_instance_valid(bot_overlay):
		bot_overlay.queue_free()
	bot_overlay = Control.new()
	bot_overlay.name = "BotOverlay"
	bot_overlay.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bot_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bot_overlay.z_index = 40
	add_child(bot_overlay)
	var panel := PanelContainer.new()
	panel.name = "BotPanel"
	panel.custom_minimum_size = Vector2(320, 0)
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -330
	panel.offset_top = 60
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.06, 0.12, 0.92)
	sb.border_color = Color(0.4, 0.85, 1, 0.85)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	bot_overlay.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.name = "BotVBox"
	vbox.add_theme_constant_override("separation", 3)
	panel.add_child(vbox)
	# Header
	var header := Label.new()
	header.name = "BotHeader"
	header.text = "🤖 BOT IA — PENSANDO"
	header.add_theme_color_override("font_color", Color(0.4, 0.85, 1))
	header.add_theme_font_size_override("font_size", 11)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())
	# Log de pensamento
	var log_lbl := Label.new()
	log_lbl.name = "BotLog"
	log_lbl.add_theme_color_override("font_color", Color(0.85, 0.93, 1))
	log_lbl.add_theme_font_size_override("font_size", 10)
	log_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(log_lbl)
	vbox.add_child(HSeparator.new())
	# Botão parar
	var stop_btn := Button.new()
	stop_btn.text = "⏹ PARAR BOT"
	stop_btn.add_theme_font_size_override("font_size", 10)
	stop_btn.pressed.connect(stop_bot_mode)
	vbox.add_child(stop_btn)

func _refresh_bot_overlay() -> void:
	if bot_overlay == null or not is_instance_valid(bot_overlay): return
	var log_lbl := bot_overlay.get_node_or_null("BotPanel/BotVBox/BotLog")
	if log_lbl == null: return
	log_lbl.text = "\n".join(bot_log_lines)

# ─────────────────────────────────────────────────────────────────
# MARKERS DE EVENTOS NO MAPA — visual sobre países afetados
# ─────────────────────────────────────────────────────────────────

# Quando um evento dispara, cria markers nos países envolvidos.
func _on_event_fired_marker(ev: Dictionary) -> void:
	if event_markers_layer == null: return
	var trig: Dictionary = ev.get("trigger", {})
	var primary: String = trig.get("primary_country", "")
	var involves: Array = trig.get("involves", [])
	if involves.is_empty() and primary != "":
		involves = [primary]
	var cats: Array = ev.get("categories", [])
	# Cor + ícone por categoria
	var icon: String = "📰"
	var color: Color = Color(0.5, 0.7, 1)
	if cats.has("guerra") or cats.has("terrorismo"):
		icon = "⚔"; color = Color(1, 0.35, 0.35)
	elif cats.has("paz"):
		icon = "🕊"; color = Color(0.4, 1, 0.6)
	elif cats.has("crise") or cats.has("economia"):
		icon = "📉"; color = Color(1, 0.78, 0.30)
	elif cats.has("pandemia") or cats.has("desastre_natural"):
		icon = "💢"; color = Color(0.85, 0.45, 1)
	elif cats.has("clima"):
		icon = "🌍"; color = Color(0.4, 1, 0.6)
	elif cats.has("revolucao") or cats.has("politica"):
		icon = "🏛"; color = Color(0.4, 0.85, 1)
	elif cats.has("nuclear"):
		icon = "☢"; color = Color(1, 1, 0.35)
	elif cats.has("tecnologia") or cats.has("ai"):
		icon = "💡"; color = Color(0.6, 0.85, 1)
	elif cats.has("espacial"):
		icon = "🚀"; color = Color(0.85, 0.7, 1)
	# Cria um marker em cada país envolvido
	for code in involves:
		if not (code is String) or not countries.has(code): continue
		_spawn_marker(code, icon, color, ev.get("headline", ""))

func _spawn_marker(code: String, icon: String, color: Color, tooltip: String) -> void:
	var entry: Dictionary = countries[code]
	var bounds: Rect2 = entry.get("bounds", Rect2())
	if bounds.size.length_squared() <= 0: return
	var center: Vector2 = bounds.position + bounds.size / 2.0
	# Container do marker (fica num Node2D pra acompanhar pan/zoom do mapa)
	var marker := Node2D.new()
	marker.position = center
	marker.z_index = 5
	event_markers_layer.add_child(marker)
	# Círculo pulsante de fundo (Polygon2D)
	var halo := Polygon2D.new()
	var halo_pts := PackedVector2Array()
	var radius: float = 14.0
	for i in 24:
		var a: float = TAU * i / 24.0
		halo_pts.append(Vector2(cos(a) * radius, sin(a) * radius))
	halo.polygon = halo_pts
	halo.color = Color(color.r, color.g, color.b, 0.4)
	marker.add_child(halo)
	# Círculo interno sólido
	var core := Polygon2D.new()
	var core_pts := PackedVector2Array()
	var core_r: float = 8.0
	for i in 16:
		var a: float = TAU * i / 16.0
		core_pts.append(Vector2(cos(a) * core_r, sin(a) * core_r))
	core.polygon = core_pts
	core.color = color
	marker.add_child(core)
	# Label com emoji
	var lbl := Label.new()
	lbl.text = icon
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.position = Vector2(-7, -10)
	lbl.tooltip_text = tooltip
	marker.add_child(lbl)
	# Anima halo (pulse)
	var tw := create_tween().set_loops(MARKER_TTL_DEFAULT * 2)
	tw.tween_property(halo, "scale", Vector2(1.4, 1.4), 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(halo, "scale", Vector2(1.0, 1.0), 0.6).set_trans(Tween.TRANS_SINE)
	# Registra
	active_markers.append({"node": marker, "ttl": MARKER_TTL_DEFAULT, "country": code, "tooltip": tooltip})

# Decai TTL e remove markers expirados
func _decay_event_markers() -> void:
	var still_alive: Array = []
	for m in active_markers:
		var entry: Dictionary = m
		entry["ttl"] = int(entry.get("ttl", 0)) - 1
		if entry["ttl"] <= 0:
			# Fade out + remove
			var node: Node2D = entry.get("node")
			if node and is_instance_valid(node):
				var tw := create_tween()
				tw.tween_property(node, "modulate:a", 0.0, 0.5)
				tw.tween_callback(func(): if is_instance_valid(node): node.queue_free())
		else:
			still_alive.append(entry)
	active_markers = still_alive

# Avisa via ticker quando há evento histórico de decisão a 1-2 turnos de distância
func _notify_upcoming_decisions() -> void:
	if GameEngine == null or GameEngine.timeline == null: return
	var upcoming: Array = GameEngine.timeline.get_upcoming_decisions(2)
	for entry in upcoming:
		var ev: Dictionary = entry["event"]
		var turns: int = int(entry["turns_until"])
		var label: String = "🕰 EM %d TURNO%s" % [turns, "" if turns == 1 else "S"]
		_log_ticker(label, ev.get("headline", "Evento histórico iminente"), Color(1, 0.85, 0.4))

# ─────────────────────────────────────────────────────────────────
# TICKER (eventos do mundo no rodapé)
# ─────────────────────────────────────────────────────────────────

func _update_news_ticker() -> void:
	if ticker_inner == null or GameEngine == null: return
	for evt in GameEngine.recent_events:
		if not evt.get("involves_player", false):
			continue
		var color := Color(0.6, 0.8, 1)
		var t: String = evt.get("type", "")
		var cat := "📰 EVENTO"
		if t == "guerra":
			color = Color(1, 0.3, 0.3); cat = "⚔️ MILITAR"
		elif t == "paz":
			color = Color(0.4, 1, 0.6); cat = "🕊️ DIPLOMACIA"
		elif t == "evento_escolha":
			color = Color(0.7, 0.5, 1); cat = "🎯 EVENTO"
		_log_ticker(cat, evt.get("headline", ""), color)
	if GameEngine.player_nation:
		var n = GameEngine.player_nation
		_log_ticker("🌐 TURNO %d" % GameEngine.current_turn,
			"PIB $%dB • Tesouro $%dB • Inflação %.1f%% • Estab %d%%" %
			[int(n.pib_bilhoes_usd), int(n.tesouro), n.inflacao, int(n.estabilidade_politica)],
			Color(0.6, 0.8, 1))
	# Limita ticker a 12 itens (FIFO)
	# CRÍTICO: queue_free() NÃO remove o filho no mesmo frame — o count não
	# cai e o while congelava O JOGO INTEIRO quando o ticker passava de 12
	# (turno ~2-6 de qualquer partida). remove_child imediato + free depois.
	while ticker_inner.get_child_count() > 12:
		var oldest := ticker_inner.get_child(0)
		ticker_inner.remove_child(oldest)
		oldest.queue_free()
	GameEngine.recent_events.clear()

func _log_ticker(category: String, headline: String, color: Color) -> void:
	if ticker_inner == null: return
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.modulate = Color(1, 1, 1, 0)  # começa invisível pra fade-in
	var cat_lbl := Label.new()
	cat_lbl.text = category
	cat_lbl.add_theme_color_override("font_color", color)
	cat_lbl.add_theme_font_size_override("font_size", 10)
	cat_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(cat_lbl)
	var sep := Label.new()
	sep.text = "│"
	sep.add_theme_color_override("font_color", Color(0.3, 0.4, 0.5))
	hbox.add_child(sep)
	var text_lbl := Label.new()
	text_lbl.text = headline
	text_lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	text_lbl.add_theme_font_size_override("font_size", 10)
	text_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(text_lbl)
	ticker_inner.add_child(hbox)
	# Fade-in suave
	var tw := create_tween()
	tw.tween_property(hbox, "modulate:a", 1.0, 0.3)

# ─────────────────────────────────────────────────────────────────
# SPINNER
# ─────────────────────────────────────────────────────────────────

var _spinner_tween: Tween = null
var _spinner_visible: bool = false

func _show_spinner(text: String = "Carregando…") -> void:
	if spinner_overlay == null: return
	spinner_label.text = text
	spinner_overlay.visible = true
	spinner_overlay.modulate.a = 1.0
	_spinner_visible = true
	# Garante pivot no centro do ícone — sem isso rotaciona em volta do canto
	if spinner_icon:
		spinner_icon.pivot_offset = spinner_icon.size / 2.0
		spinner_icon.rotation = 0.0
	if _spinner_tween:
		_spinner_tween.kill()
	# Loop simples: rotaciona 1 volta completa em 0.9s, reseta, repete
	_spinner_tween = create_tween().set_loops()
	_spinner_tween.tween_method(func(angle: float): if spinner_icon: spinner_icon.rotation = angle, 0.0, TAU, 0.9)

func _hide_spinner() -> void:
	if spinner_overlay == null or not _spinner_visible: return
	_spinner_visible = false
	if _spinner_tween:
		_spinner_tween.kill()
		_spinner_tween = null
	var t := create_tween()
	t.tween_property(spinner_overlay, "modulate:a", 0.0, 0.18)
	t.tween_callback(func():
		spinner_overlay.visible = false
		spinner_overlay.modulate.a = 1.0)

# ─────────────────────────────────────────────────────────────────
# INPUT (pan/zoom no mapa — usa _unhandled_input pra UI funcionar)
# ─────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)
	elif event is InputEventJoypadButton and event.pressed:
		_handle_key(event)

func _handle_key(event: InputEvent) -> void:
	# ESC: abre opções
	if event.is_action_pressed("game_open_options"):
		_show_options_modal()
		return
	# SPACE: avança turno
	if event.is_action_pressed("game_next_turn") and player_code != "":
		_on_next_turn_pressed()
		return
	# CTRL+S: salva
	if event.is_action_pressed("game_save") and player_code != "":
		var SaveSys = preload("res://scripts/SaveSystem.gd")
		if SaveSys.save_game(GameEngine):
			_log_ticker("💾 SAVE", "Progresso salvo (Ctrl+S)", Color(0.4, 1, 0.6))
		return
	# B — toggle bot rápido (sem abrir opções)
	if event is InputEventKey and event.keycode == KEY_B and event.pressed and not event.echo:
		if bot_player != null:
			stop_bot_mode()
		else:
			start_bot_mode("balanced", 2.0)
		return
	# Zoom in/out via teclado ou trigger de gamepad
	if event.is_action_pressed("game_zoom_in"):
		var vp_center: Vector2 = get_viewport_rect().size * 0.5
		_zoom_at(vp_center, ZOOM_STEP)
		return
	if event.is_action_pressed("game_zoom_out"):
		var vp_center2: Vector2 = get_viewport_rect().size * 0.5
		_zoom_at(vp_center2, 1.0 / ZOOM_STEP)
		return

func _is_in_map_area(screen_pos: Vector2) -> bool:
	# True se o ponto da tela está na área visível do mapa.
	# Modal aberto → mapa NUNCA recebe input (travado).
	if _is_modal_open(): return false
	var vp_size := get_viewport_rect().size
	if screen_pos.y < TOP_BAR_H or screen_pos.y > vp_size.y - BOTTOM_BAR_H: return false
	return true

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		if _is_in_map_area(event.position):
			_zoom_at(event.position, ZOOM_STEP)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if _is_in_map_area(event.position):
			_zoom_at(event.position, 1.0 / ZOOM_STEP)
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Só inicia drag se o clique foi na área do mapa
			if not _is_in_map_area(event.position): return
			is_dragging = true
			drag_start_pos = event.position
			drag_start_camera_pos = camera.position
			last_drag_pos = event.position
			last_drag_time_ms = Time.get_ticks_msec()
			pan_velocity = Vector2.ZERO
			Input.set_default_cursor_shape(Input.CURSOR_DRAG)
		else:
			if not is_dragging: return
			var moved := (event.position - drag_start_pos).length()
			is_dragging = false
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
			if moved < 4.0:
				pan_velocity = Vector2.ZERO  # foi um clique, sem inércia
				_handle_click(event.position)
			# Caso contrário, pan_velocity já foi calculada na última amostra de motion → inércia segue

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if is_dragging:
		var delta := event.position - drag_start_pos
		camera.position = drag_start_camera_pos - delta / camera.zoom.x
		_clamp_camera()
		camera_target_pos = camera.position
		camera_animating = false
		# Estima velocidade de pan em px/s (coords de tela) pra inércia
		var now_ms := Time.get_ticks_msec()
		var dt: float = max(0.001, (now_ms - last_drag_time_ms) / 1000.0)
		var inst_v: Vector2 = (event.position - last_drag_pos) / dt
		# Suaviza com EMA pra não pegar pico de jitter.
		# SINAL POSITIVO: a inércia continua o movimento do drag
		# (com -inst_v ela REBATIA contra o clamp → "handshake" no zoom-out)
		pan_velocity = pan_velocity.lerp(inst_v, 0.5)
		last_drag_pos = event.position
		last_drag_time_ms = now_ms
		return
	# Sem drag: atualiza hover (tooltip flutuante com nome do país)
	if not _is_in_map_area(event.position):
		_clear_hover()
		return
	var world := _screen_to_world(event.position)
	var hit := _country_at(world)
	if hit == "":
		_clear_hover()
		return
	if hit != hover_code:
		_clear_hover()
		hover_code = hit
		_update_hover_label(event.position)
		_apply_hover_highlight(hit)
	elif hover_label != null:
		# Mantém label seguindo o cursor com offset
		hover_label.position = event.position + Vector2(14, -28)

# Pinta o país sob hover com cor mais clara (lerp + branco) — sem mudar
# o estado real. Repintar o país via _repaint_country_state restaura o
# original quando o mouse sai.
func _apply_hover_highlight(code: String) -> void:
	if code == "" or code == player_code: return
	var entry = countries.get(code)
	if entry == null: return
	# Invalida o cache de pintura: o restore (_repaint_country_state) precisa
	# repintar mesmo que o estado lógico não tenha mudado.
	entry["last_color"] = Color(-1, -1, -1)
	entry["last_border"] = Color(-1, -1, -1)
	# Brilho multiplicativo (visível TAMBÉM sobre satélite — o lerp p/ branco
	# era imperceptível) + fronteira dourada acesa. Alpha preservado (modo).
	for child in entry["node"].get_children():
		if child is Polygon2D:
			var c: Color = child.self_modulate
			child.self_modulate = Color(c.r * 1.30, c.g * 1.28, c.b * 1.22, c.a)
		elif child is Line2D:
			child.default_color = Color(1.30, 1.08, 0.46, 1.0)

func _update_hover_label(screen_pos: Vector2) -> void:
	if not GameEngine.nations.has(hover_code):
		_clear_hover()
		return
	var n = GameEngine.nations[hover_code]
	if hover_label == null:
		hover_label = Label.new()
		hover_label.name = "HoverLabel"
		hover_label.add_theme_font_size_override("font_size", 12)
		hover_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		hover_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		hover_label.add_theme_constant_override("outline_size", 4)
		hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hover_label.z_index = 50
		add_child(hover_label)
	hover_label.text = "%s  ·  %s" % [n.nome, hover_code]
	hover_label.position = screen_pos + Vector2(14, -28)
	hover_label.modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property(hover_label, "modulate:a", 1.0, 0.12)

func _clear_hover() -> void:
	if hover_code != "" and hover_code != player_code:
		# Restaura cor original do país
		_repaint_country_state(hover_code)
	hover_code = ""
	if hover_label != null and is_instance_valid(hover_label):
		hover_label.queue_free()
		hover_label = null

func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	camera_animating = false
	var world_before := _screen_to_world(screen_pos)
	var new_zoom: float = clamp(camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(new_zoom, new_zoom)
	_apply_central_offset()
	var world_after := _screen_to_world(screen_pos)
	camera.position += world_before - world_after
	_clamp_camera()
	_apply_central_offset()
	camera_target_pos = camera.position
	camera_target_zoom = camera.zoom

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos

func _handle_click(screen_pos: Vector2) -> void:
	var world := _screen_to_world(screen_pos)
	var hit := _country_at(world)
	if hit != "":
		_show_preview(hit)
		_select_in_list(hit)

func _select_in_list(code: String) -> void:
	if nations_list == null or not nations_list.visible: return
	for i in nations_list.item_count:
		if nations_list.get_item_metadata(i) == code:
			nations_list.select(i)
			nations_list.ensure_current_is_visible()
			return

func _country_at(world_pos: Vector2) -> String:
	for code in countries:
		var entry = countries[code]
		for child in entry["node"].get_children():
			if child is Polygon2D:
				if Geometry2D.is_point_in_polygon(world_pos, child.polygon):
					return code
	return ""
