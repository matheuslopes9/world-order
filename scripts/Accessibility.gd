extends Node
## Singleton de acessibilidade (autoload).
## Centraliza UI scale, modo daltonismo, tamanho de fonte global e idioma.
## Persiste em user://accessibility.cfg.

const CFG_PATH := "user://accessibility.cfg"
const I18N_CSV := "res://translations/strings.csv"
const SUPPORTED_LOCALES := ["pt_BR", "en"]

# UI scale multiplier — aplicado em get_theme_default_font_size + Tooltips
var ui_scale: float = 1.0  # 0.9 / 1.0 / 1.15 / 1.3

# Modo daltonismo — quando true, substitui pares vermelho/verde por azul/laranja
# nas funções de cor (color_for_relation, color_for_indicator, etc) e adiciona
# ícones redundantes (✓/✕, ↑/↓) ao lado de valores positivos/negativos.
var colorblind_mode: bool = false

# UI font size delta global (-2 / 0 / +2 / +4)
var font_size_delta: int = 0

# Idioma atual (pt_BR | en)
var locale: String = "pt_BR"

signal settings_changed

func _ready() -> void:
	_load()
	_init_translations()
	TranslationServer.set_locale(locale)

# Carrega CSV e registra translations no TranslationServer.
# Fallback simples: se CSV falhar, jogo continua em pt_BR sem traduções.
func _init_translations() -> void:
	var f := FileAccess.open(I18N_CSV, FileAccess.READ)
	if f == null:
		push_warning("[i18n] CSV não encontrado: " + I18N_CSV)
		return
	var lines: Array = []
	while not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges() != "":
			lines.append(line)
	f.close()
	if lines.size() < 2: return
	# Primeira linha: keys,pt_BR,en
	var headers: PackedStringArray = lines[0].split(",")
	if headers.size() < 2: return
	# Cria Translation por locale (cada coluna a partir da 2ª)
	var translations: Dictionary = {}
	for i in range(1, headers.size()):
		var loc: String = headers[i].strip_edges()
		var t := Translation.new()
		t.locale = loc
		translations[loc] = t
	# Para cada linha de dados
	for r in range(1, lines.size()):
		var cols: PackedStringArray = lines[r].split(",")
		if cols.size() < 2: continue
		var key: String = cols[0].strip_edges()
		if key == "": continue
		for i in range(1, cols.size()):
			if i >= headers.size(): break
			var loc2: String = headers[i].strip_edges()
			if translations.has(loc2):
				translations[loc2].add_message(key, cols[i].strip_edges())
	# Registra no servidor
	for loc3 in translations:
		TranslationServer.add_translation(translations[loc3])
	print("[i18n] %d locales carregados, %d strings" % [translations.size(), lines.size() - 1])

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK: return
	ui_scale = float(cfg.get_value("a11y", "ui_scale", 1.0))
	colorblind_mode = bool(cfg.get_value("a11y", "colorblind", false))
	font_size_delta = int(cfg.get_value("a11y", "font_delta", 0))
	locale = String(cfg.get_value("a11y", "locale", "pt_BR"))

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	cfg.set_value("a11y", "ui_scale", ui_scale)
	cfg.set_value("a11y", "colorblind", colorblind_mode)
	cfg.set_value("a11y", "font_delta", font_size_delta)
	cfg.set_value("a11y", "locale", locale)
	cfg.save(CFG_PATH)
	emit_signal("settings_changed")

func set_locale(loc: String) -> void:
	if loc not in SUPPORTED_LOCALES: return
	locale = loc
	TranslationServer.set_locale(loc)
	save()

func set_ui_scale(v: float) -> void:
	ui_scale = clamp(v, 0.8, 1.5)
	save()

func set_colorblind(on: bool) -> void:
	colorblind_mode = on
	save()

func set_font_delta(v: int) -> void:
	font_size_delta = clamp(v, -2, 6)
	save()

# Helpers — usar nas chamadas de cor pra suporte a daltonismo

# Cor positiva (default verde, daltônico = azul)
func color_positive() -> Color:
	if colorblind_mode:
		return Color(0.4, 0.7, 1.0)  # azul claro
	return Color(0.4, 1.0, 0.6)

# Cor negativa (default vermelho, daltônico = laranja)
func color_negative() -> Color:
	if colorblind_mode:
		return Color(1.0, 0.55, 0.0)  # laranja
	return Color(1.0, 0.4, 0.4)

# Cor neutra (sem mudança)
func color_neutral() -> Color:
	return Color(0.85, 0.93, 1)

# Para relação numérica: -100 a 100 mapeia para verde→vermelho ou azul→laranja
func color_for_relation(rel: float) -> Color:
	if colorblind_mode:
		if rel > 0: return Color(0.4, 0.7, 1.0)
		if rel < 0: return Color(1.0, 0.55, 0.0)
		return Color(0.7, 0.7, 0.7)
	if rel > 0: return Color(0.4, 1.0, 0.6)
	if rel < 0: return Color(1.0, 0.4, 0.4)
	return Color(0.7, 0.7, 0.7)

# Ícone redundante pra valor positivo/negativo (acessibilidade)
func icon_for_value(v: float) -> String:
	if not colorblind_mode: return ""
	if v > 0: return "↑ "
	if v < 0: return "↓ "
	return ""

# Aplica font size delta a um size base
func adjusted_font_size(base: int) -> int:
	return max(8, base + font_size_delta)
