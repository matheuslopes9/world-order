extends Node
## Singleton (autoload) com factories de StyleBox e paleta de cores
## consolidada — referência única pra todo o look-and-feel do jogo.
##
## Uso:
##   panel.add_theme_stylebox_override("panel", UIStyles.modal_panel())
##   panel.add_theme_stylebox_override("panel", UIStyles.modal_panel("warning"))
##   panel.add_theme_stylebox_override("panel", UIStyles.modal_panel("success"))

# ═════════════════════════════════════════════════════════════════
# PALETA CONSOLIDADA — referência única de cores no jogo
# ═════════════════════════════════════════════════════════════════

# Acentos principais
const CYAN := Color(0, 0.823, 1, 0.9)         # Cor signature (logo, bordas, headers)
const CYAN_DIM := Color(0, 0.823, 1, 0.55)
const CYAN_BRIGHT := Color(0, 0.95, 1, 1)     # Hover states, ícones spinner

# Cores semânticas
const SUCCESS := Color(0.4, 1.0, 0.6, 0.95)   # Verde — vitória, ok, aceitar
const SUCCESS_DIM := Color(0.4, 1.0, 0.6, 0.6)
const WARNING := Color(1, 0.85, 0.3, 0.85)    # Amarelo/dourado — atenção, XP
const WARNING_BRIGHT := Color(1, 0.85, 0.4, 1)
const DANGER := Color(1, 0.45, 0.4, 0.85)     # Vermelho — guerra, falha, deletar
const DANGER_BRIGHT := Color(1, 0.4, 0.4, 1)

# Backgrounds
const BG_PANEL := Color(0.035, 0.06, 0.10, 0.99)        # Modal default (azul-escuro)
const BG_PANEL_DANGER := Color(0.10, 0.04, 0.04, 0.99)  # Modal de aviso
const BG_PANEL_SUCCESS := Color(0.05, 0.10, 0.05, 0.99) # Modal de sucesso
const BG_OVERLAY := Color(0, 0.04, 0.08, 0.94)          # Backdrop full-screen

# Texto
const TEXT_PRIMARY := Color(0.95, 0.99, 1)
const TEXT_DIM := Color(0.55, 0.7, 0.85)
const TEXT_MUTED := Color(0.5, 0.65, 0.85)

# ═════════════════════════════════════════════════════════════════
# FACTORIES DE STYLEBOX
# ═════════════════════════════════════════════════════════════════

# Estilo de painel modal — variante muda cor da borda e bg.
# variant: "default" | "danger" | "success" | "warning"
static func modal_panel(variant: String = "default", border_width: int = 2, corner: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	match variant:
		"danger":
			sb.bg_color = BG_PANEL_DANGER
			sb.border_color = DANGER
		"success":
			sb.bg_color = BG_PANEL_SUCCESS
			sb.border_color = WARNING_BRIGHT  # dourado pra vitória
		"warning":
			sb.bg_color = BG_PANEL
			sb.border_color = WARNING
		_:
			sb.bg_color = BG_PANEL
			sb.border_color = CYAN
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(corner)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	return sb

# Card menor — usado em rows de listas (perks, países, etc)
# state: "default" | "selected" | "highlighted" | "disabled"
static func card(state: String = "default") -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	match state:
		"selected":
			sb.bg_color = Color(0.08, 0.15, 0.05, 0.95)
			sb.border_color = SUCCESS
		"highlighted":
			sb.bg_color = Color(0.06, 0.10, 0.16, 0.95)
			sb.border_color = CYAN
		"disabled":
			sb.bg_color = Color(0.05, 0.06, 0.10, 0.95)
			sb.border_color = Color(0.4, 0.4, 0.5, 0.5)
		_:
			sb.bg_color = Color(0.05, 0.06, 0.10, 0.95)
			sb.border_color = CYAN_DIM
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

# Botão padrão (3 estados: normal/hover/pressed)
static func button(state: String = "normal", primary: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	match state:
		"hover":
			sb.bg_color = Color(0, 0.6, 0.85, 1) if primary else Color(0.10, 0.18, 0.28, 1)
		"pressed":
			sb.bg_color = Color(0, 0.5, 0.75, 1) if primary else Color(0.06, 0.12, 0.20, 1)
		_:
			sb.bg_color = Color(0, 0.45, 0.70, 1) if primary else Color(0.05, 0.10, 0.18, 1)
	sb.border_color = CYAN if primary else CYAN_DIM
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

# Toast/notification
static func toast(variant: String = "info") -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.08, 0.14, 0.96)
	match variant:
		"warning":
			sb.border_color = WARNING
		"danger":
			sb.border_color = DANGER
		"success":
			sb.border_color = SUCCESS
		_:
			sb.border_color = CYAN
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb

# ═════════════════════════════════════════════════════════════════
# HELPERS DE COR
# ═════════════════════════════════════════════════════════════════

# Cor de relação diplomática (-100 a 100), respeitando modo daltonismo
static func relation_color(rel: float) -> Color:
	if Accessibility and Accessibility.colorblind_mode:
		if rel > 30: return Color(0.4, 0.7, 1.0)
		if rel < -30: return Color(1.0, 0.55, 0.0)
		return Color(0.7, 0.7, 0.7)
	if rel > 30: return SUCCESS
	if rel < -30: return DANGER_BRIGHT
	return Color(0.85, 0.85, 0.85)

# Cor de indicador (0-100): vermelho<25, amarelo<50, verde>=50
static func indicator_color(value: float, inverted: bool = false) -> Color:
	var v: float = value
	if inverted: v = 100.0 - value
	if v < 25: return DANGER_BRIGHT
	if v < 50: return WARNING_BRIGHT
	return SUCCESS
