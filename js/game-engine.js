class GameEngine {
    constructor() {
        // Data Service Layer
        this.data = {
            nations: {},
            history: null,
            conflicts: [],
            actions: [],
            technologies: [],
            events: []
        };

        // Game State Layer
        this.state = {
            selectedNation: null,
            playerNation: null,
            currentTurn: 0,
            date: { quarter: 4, year: 2024 },
            globalTreasury: 14200,
            defcon: 5,
            gameState: 'INTRO',
            mapMode: 'normal'
        };

        // IA Manager (será instanciado após carregar personalidades)
        this.aiManager = null;
        // Alliance Manager (defesa coletiva, alianças reais 2024)
        this.alliance = null;
        // Diplomacy Manager (gerencia tratados e propostas)
        this.diplomacy = null;
        // News Manager
        this.news = new NewsManager();
        // Economy Manager (rotas, empresas, cripto)
        this.economy = new EconomyManager(this);
        // Buffer de eventos do jogo para converter em notícias no próximo turno
        this.state.recentGameEvents = [];
    }

    async init() {
        console.log("Iniciando Motor do Mundo...");
        await this.loadNations();
        await this.loadConflicts();
        await this.loadActions();
        await this.loadHistory();
        await this.loadEvents(); 
        await this.loadTechnologies();
        this.initializeTechForNations();

        // Inicializar IA aprimorada (aguarda carregamento das personalidades)
        this.aiManager = new AIManager(this);
        await this.aiManager.loadPersonalities();
        // Inicializar Alianças reais de 2024
        this.alliance = new AllianceManager(this);
        await this.alliance.loadAlliances();
        // Inicializar Diplomacia (aguarda carregamento dos tipos de tratado)
        this.diplomacy = new DiplomacyManager(this);
        await this.diplomacy.loadTreatyTypes();

        // Carregar save ou inicializar relações (uma única vez)
        // Always initialize default relationships; save will overwrite if loaded
        this.initializeRelationships();
        this.updateUI();

        this.ui = new UIManager(this);
        this.ui.init();

        this.map = new MapRenderer('world-map', (code) => {
            this.selectNation(code);
        });
        await this.map.init();

        // Show start menu — let user choose new game or continue
        this._renderStartMenu();
    }

    _renderStartMenu() {
        const saved = localStorage.getItem('worldOrderSave');
        const btn   = document.getElementById('btn-continue');
        const hint  = document.getElementById('btn-continue-hint');
        const info  = document.getElementById('startup-save-info');

        // Update nations count
        const nationCount = Object.keys(this.data.nations).length;
        document.querySelectorAll('.startup-brief-line').forEach((el, i) => {
            if (i === 2) el.querySelector('.sbr-val').textContent = `${nationCount} NAÇÕES ATIVAS`;
        });

        if (saved) {
            try {
                const s = JSON.parse(saved);
                const nationName = s.nations?.[s.playerNationCode]?.nome || s.playerNationCode || '—';
                const labels = ['JAN','ABR','JUL','OUT'];
                const d = s.date || {};
                const dateStr = d.quarter ? `${labels[d.quarter-1]} ${d.year}` : '—';
                const turn = s.currentTurn || 0;

                if (btn)  { btn.disabled = false; }
                if (hint) { hint.textContent = `${nationName} • Turno ${turn} • ${dateStr}`; }
                if (info) {
                    info.style.display = 'flex';
                    info.innerHTML = `
                        <span class="save-icon">💾</span>
                        <div class="save-details">
                            <span class="save-nation">${nationName}</span>
                            <span class="save-meta">Turno ${turn} &nbsp;·&nbsp; ${dateStr} &nbsp;·&nbsp; DEFCON ${s.defcon || 5}</span>
                        </div>
                        <button class="save-delete-btn" onclick="engine._deleteSave()" title="Apagar save">✕</button>`;
                }
            } catch(e) {
                localStorage.removeItem('worldOrderSave');
            }
        }
    }

    _deleteSave() {
        if (!confirm('Apagar o progresso salvo? Esta ação é irreversível.')) return;
        localStorage.removeItem('worldOrderSave');
        const btn  = document.getElementById('btn-continue');
        const hint = document.getElementById('btn-continue-hint');
        const info = document.getElementById('startup-save-info');
        if (btn)  btn.disabled = true;
        if (hint) hint.textContent = 'Nenhum progresso salvo';
        if (info) info.style.display = 'none';
    }

    startGame() {
        if (!this.ui) return;
        // Clear any pending save state so new game starts clean
        this._pendingSaveState = null;
        this.state.gameState = 'SELECTING';
        this.hideOverlay();
        this.ui.showNotification("MODO DE SELEÇÃO: Clique em uma nação no mapa para assumir o comando.", "info");
    }

    loadSavedGame() {
        const loaded = this.loadGame();
        if (!loaded) {
            if (this.ui) this.ui.showNotification('Nenhum save encontrado ou corrompido.', 'threat');
            return;
        }
        this._restorePendingSave();
        this.state.gameState = 'PLAYING';
        this.hideOverlay();
        if (this.ui && this.state.playerNation) {
            this.ui.renderPanel('history', this.state.playerNation);
            this.ui.showNotification(`Bem-vindo de volta, Comandante. Liderando: ${this.state.playerNation.nome}.`, 'info');
        }
    }

    quitGame() {
        if (this.state.gameState === 'PLAYING') {
            this._autoSave();
        }
        window.close();
        // Fallback for browsers that block window.close()
        document.body.innerHTML = `
            <div style="position:fixed;inset:0;background:#0d1117;display:flex;flex-direction:column;align-items:center;justify-content:center;font-family:monospace;color:#00d2ff">
                <div style="font-size:2rem;letter-spacing:8px;margin-bottom:16px">WORLD ORDER</div>
                <div style="font-size:0.85rem;color:#8b949e;letter-spacing:2px">Sessão encerrada. Pode fechar esta aba.</div>
            </div>`;
    }

    _autoSave() {
        if (this.state.gameState !== 'PLAYING') return;
        const gameState = {
            nations: this.data.nations,
            date: this.state.date,
            globalTreasury: this.state.globalTreasury,
            currentTurn: this.state.currentTurn,
            defcon: this.state.defcon,
            playerNationCode: this.state.playerNation?.codigo_iso || null,
            treaties: this.diplomacy?.treaties || [],
            proposals: this.diplomacy?.proposals || [],
            commodityPrices: this.economy?.commodityPrices || {},
            portfolio: this.economy?.portfolio || {},
            cryptoWallet: this.economy?.cryptoWallet || {},
        };
        try {
            localStorage.setItem('worldOrderSave', JSON.stringify(gameState));
        } catch(e) {
            console.warn('Auto-save falhou:', e);
        }
    }

    hideOverlay() {
        const overlay = document.getElementById('startup-overlay');
        if (overlay) {
            overlay.style.opacity = '0';
            overlay.style.transition = 'opacity 0.6s ease';
            setTimeout(() => { overlay.style.display = 'none'; }, 600);
        }
    }

    async loadEvents() {
        try {
            const response = await fetch('data/events.json');
            const data = await response.json();
            this.data.events = data.eventos;
        } catch (error) {
            console.error("Erro ao carregar eventos:", error);
            this.data.events = [];
        }
    }

    loadTechnologies() {
        console.log("Sincronizando Banco de Tecnologias...");
        return fetch('data/tech.json')
            .then(res => res.json())
            .then(data => {
                this.data.technologies = data.tecnologias || data.technologies || [];
                this.data.tech_categorias = data.categorias || {};
                console.log(`> ${this.data.technologies.length} Tecnologias Carregadas.`);
            })
            .catch(err => {
                console.error("FALHA CRÍTICA: Banco de Tech inacessível.", err);
                this.data.technologies = [];
            });
    }

    initializeTechForNations() {
        if (!this.data.technologies || !this.data.technologies.length) return;
        for (const tech of this.data.technologies) {
            for (const iso of (tech.posse_atual || [])) {
                const nation = this.data.nations[iso];
                if (!nation) continue;
                if (!nation.tecnologias_concluidas) nation.tecnologias_concluidas = [];
                if (!nation.tecnologias_concluidas.includes(tech.id)) {
                    nation.tecnologias_concluidas.push(tech.id);
                    // Don't re-apply efeitos for starting techs — already baked into nation stats
                }
            }
        }
    }

    saveGame() {
        if (this.state.gameState !== 'PLAYING') {
            this.ui.showNotification("Ação negada: Assuma o comando de uma nação primeiro.", "threat");
            return;
        }
        this._autoSave();
        this._lastSaveTime = new Date();
        this.ui.showNotification("💾 Progresso salvo com sucesso.", "success");
        this._refreshOptionsSaveStatus();
    }

    // ── Options / Pause Menu ─────────────────────────────────────────────────

    openOptions() {
        const modal = document.getElementById('options-modal');
        if (!modal) return;

        // Populate session info
        const nation = this.state.playerNation;
        const d = this.state.date;
        const labels = ['JAN','ABR','JUL','OUT'];
        const dateStr = d?.quarter ? `${labels[d.quarter-1]} ${d.year}` : '—';

        const setEl = (id, txt) => { const el = document.getElementById(id); if (el) el.textContent = txt; };
        setEl('opt-nation', nation?.nome || '— SEM COMANDO —');
        setEl('opt-date',   dateStr);
        setEl('opt-turn',   `Turno ${this.state.currentTurn}`);
        setEl('opt-defcon', `DEFCON ${this.state.defcon}`);

        this._refreshOptionsSaveStatus();
        modal.style.display = 'flex';
        requestAnimationFrame(() => { modal.classList.add('visible'); });
    }

    closeOptions() {
        const modal = document.getElementById('options-modal');
        if (!modal) return;
        modal.classList.remove('visible');
        setTimeout(() => { modal.style.display = 'none'; }, 280);
    }

    _refreshOptionsSaveStatus() {
        const saved = localStorage.getItem('worldOrderSave');
        const dot  = document.getElementById('opt-save-dot');
        const text = document.getElementById('opt-save-text');
        const loadBtn = document.getElementById('opt-load-btn');
        const loadHint = document.getElementById('opt-load-hint');

        if (saved) {
            try {
                const s = JSON.parse(saved);
                const labels = ['JAN','ABR','JUL','OUT'];
                const d = s.date || {};
                const dateStr = d.quarter ? `${labels[d.quarter-1]} ${d.year}` : '—';
                const nationName = s.nations?.[s.playerNationCode]?.nome || s.playerNationCode || '—';
                const timeStr = this._lastSaveTime
                    ? this._lastSaveTime.toLocaleTimeString('pt-BR', { hour:'2-digit', minute:'2-digit' })
                    : 'Sessão anterior';
                if (dot)  { dot.style.background = '#00ff88'; }
                if (text) { text.textContent = `Save: ${nationName} · T${s.currentTurn} · ${dateStr} · ${timeStr}`; }
                if (loadBtn)  loadBtn.disabled = false;
                if (loadHint) loadHint.textContent = `${nationName} · Turno ${s.currentTurn} · ${dateStr}`;
            } catch(e) {
                if (dot)  { dot.style.background = '#ff3333'; }
                if (text) { text.textContent = 'Save corrompido — recomenda-se nova partida'; }
            }
        } else {
            if (dot)  { dot.style.background = '#555'; }
            if (text) { text.textContent = 'Nenhum save detectado'; }
            if (loadBtn)  loadBtn.disabled = true;
            if (loadHint) loadHint.textContent = 'Sem save disponível';
        }
    }

    optionsLoadGame() {
        if (this.state.gameState === 'PLAYING') {
            if (!confirm('Carregar o save irá substituir o progresso atual não salvo. Continuar?')) return;
        }
        this.closeOptions();
        const loaded = this.loadGame();
        if (!loaded) {
            if (this.ui) this.ui.showNotification('Nenhum save encontrado ou corrompido.', 'threat');
            return;
        }
        this._restorePendingSave();
        this.state.gameState = 'PLAYING';
        if (this.ui && this.state.playerNation) {
            this.ui.renderPanel('history', this.state.playerNation);
            this.ui.showNotification(`📂 Save carregado: ${this.state.playerNation.nome}`, 'success');
        }
        const treaties = this.diplomacy?.treaties || [];
        if (this.map?.updateTradeRoutes) this.map.updateTradeRoutes(this.data.nations, treaties);
        this.updateUI();
    }

    returnToMainMenu() {
        if (this.state.gameState === 'PLAYING') {
            if (!confirm('Voltar ao menu principal? O progresso não salvo será perdido.')) return;
        }
        this.closeOptions();
        this.state.gameState = 'INTRO';
        this.state.playerNation = null;
        this.state.selectedNation = null;

        const overlay = document.getElementById('startup-overlay');
        if (overlay) {
            overlay.style.display = 'flex';
            overlay.style.opacity = '0';
            overlay.style.transition = 'opacity 0.5s ease';
            requestAnimationFrame(() => { overlay.style.opacity = '1'; });
        }
        this._renderStartMenu();
    }

    openOptions_settings() {
        // Placeholder for future settings panel
        if (this.ui) this.ui.showNotification('Configurações em desenvolvimento.', 'info');
    }

    loadGame() {
        const savedData = localStorage.getItem('worldOrderSave');
        if (!savedData) return false;

        try {
            const state = JSON.parse(savedData);

            for (let code in state.nations) {
                this.data.nations[code] = new Nation(state.nations[code]);
            }

            this.state.date = state.date;
            this.state.globalTreasury = state.globalTreasury;
            this.state.currentTurn = state.currentTurn;
            this.state.defcon = state.defcon;
            if (state.playerNationCode && this.data.nations[state.playerNationCode]) {
                this.state.playerNation = this.data.nations[state.playerNationCode];
                this.state.selectedNation = this.state.playerNation;
            }
            // Restore sub-system state after they are initialized in init()
            this._pendingSaveState = {
                treaties: state.treaties || [],
                proposals: state.proposals || [],
                commodityPrices: state.commodityPrices || {},
                portfolio: state.portfolio || {},
                cryptoWallet: state.cryptoWallet || {},
            };

            this.updateUI();
            return true;
        } catch (e) {
            console.error("Erro ao carregar save:", e);
            return false;
        }
    }

    _restorePendingSave() {
        const s = this._pendingSaveState;
        if (!s) return;
        if (this.diplomacy && s.treaties.length) {
            this.diplomacy.treaties  = s.treaties;
            this.diplomacy.proposals = s.proposals;
        }
        if (this.economy) {
            if (Object.keys(s.commodityPrices).length) this.economy.commodityPrices = s.commodityPrices;
            this.economy.portfolio    = s.portfolio;
            this.economy.cryptoWallet = s.cryptoWallet;
        }
        this._pendingSaveState = null;
    }

    initializeRelationships() {
        const pairs = [
            ["US", "CN", -30], ["US", "RU", -80], ["US", "GB", 90], ["US", "IL", 85],
            ["CN", "RU", 60], ["CN", "IN", -40], ["CN", "TW", -90],
            ["BR", "CN", 40], ["BR", "US", 20], ["RU", "UA", -100],
            ["IL", "IR", -95], ["SA", "IR", -50], ["JP", "KR", 10]
        ];

        pairs.forEach(([a, b, val]) => {
            if (this.data.nations[a] && this.data.nations[b]) {
                this.data.nations[a].relacoes[b] = val;
                this.data.nations[b].relacoes[a] = val;
            }
        });
    }

    async loadNations() {
        try {
            const response = await fetch('data/nations.json');
            const data = await response.json();
            const nationsData = data.nations || data.nacoes; 
            for (let code in nationsData) {
                this.data.nations[code] = new Nation(nationsData[code]);
            }
        } catch (error) {
            console.error("Erro ao carregar nações:", error);
        }
    }

    async loadConflicts() {
        try {
            const response = await fetch('data/conflicts.json');
            const data = await response.json();
            this.data.conflicts = data.conflitos;
        } catch (error) {
            console.error("Erro ao carregar conflitos:", error);
        }
    }

    async loadActions() {
        try {
            const response = await fetch('data/actions.json');
            const data = await response.json();
            this.data.actions = data.acoes;
        } catch (error) {
            console.error("Erro ao carregar ações:", error);
        }
    }

    async loadHistory() {
        try {
            const response = await fetch('data/history.json');
            const data = await response.json();
            this.data.history = data;
            console.log("Crônica Global carregada.");
        } catch (error) {
            console.error("Erro ao carregar história:", error);
        }
    }

    selectNation(code) {
        // Trava de segurança para áreas neutras/mar
        if (!code || code === "null" || code === "undefined") {
            this.state.selectedNation = null;
            this.ui.showNotification("Território Neutro: Nenhuma jurisdição detectada nesta região.", "info");
            return;
        }

        if (this.data.nations[code]) {
            this.state.selectedNation = this.data.nations[code];
            this.ui.renderPanel(this.ui.currentPanel, this.state.selectedNation);
            this.ui.showNotification(`Foco estabelecido: ${this.state.selectedNation.nome}`, "info");
        } else {
            console.warn(`Nação não encontrada no banco: ${code}`);
            this.ui.showNotification(`DADOS LIMITADOS: Inteligência insuficiente para a região ${code}.`, "threat");
        }
    }

    confirmNation(code) {
        if (this.data.nations[code]) {
            this.state.playerNation = this.data.nations[code];
            this.state.gameState = 'PLAYING';
            this.ui.renderPanel('history', this.state.playerNation);
            this.ui.showNotification(`COMANDO ASSUMIDO: Você agora lidera a ${this.state.playerNation.nome}. Boa sorte, Comandante.`, "success");
            // Initialize live map with capitals and trade routes
            if (this.map && this.map.updateTradeRoutes) {
                const treaties = this.diplomacy?.treaties || [];
                this.map.updateTradeRoutes(this.data.nations, treaties);
            }
        }
    }

    endTurn() {
        if (this.state.gameState !== 'PLAYING') {
            this.ui.showNotification("Não é possível avançar o tempo durante a fase de seleção.", "threat");
            return;
        }
        this.state.currentTurn++;
        
        this.state.date.quarter++;
        if (this.state.date.quarter > 4) {
            this.state.date.quarter = 1;
            this.state.date.year++;
        }

        this.processSimulation();
        if (this.map && this.map.updateTradeRoutes) {
            const treaties = this.diplomacy?.treaties || [];
            this.map.updateTradeRoutes(this.data.nations, treaties);
        }
        this.updateUI();
        this._autoSave();
        this.ui.showNotification(`Turno ${this.state.currentTurn} concluído. Data: T${this.state.date.quarter} ${this.state.date.year} — Auto-save ✓`, "info");

        this.checkGameEndConditions();

        if (this.state.selectedNation) {
            this.ui.renderPanel(this.ui.currentPanel, this.state.selectedNation);
        }
    }

    proposeTreaty(playerNation, targetNation, treatyType) {
        if (!this.diplomacy) return null;
        return this.diplomacy.proposeTreaty(playerNation, targetNation, treatyType);
    }

    processSimulation() {
        for (let code in this.data.nations) {
            const nation = this.data.nations[code];
            
            nation.pib_bilhoes_usd *= 1.005;
            nation.populacao *= 1.002;

            if (nation.estabilidade_politica > 70) nation.estabilidade_politica -= 0.1;
            if (nation.estabilidade_politica < 70) nation.estabilidade_politica += 0.1;

            this.processResearch(nation);

            // Emergency powers decay
            if (nation.poderes_emergencia_ativo) {
                nation.estabilidade_politica = Math.max(0, (nation.estabilidade_politica || 50) - 3);
                nation.corrupcao = Math.min(100, (nation.corrupcao || 30) + 2);
            }

            // Update internal government metrics
            if (nation.updateGovernment) nation.updateGovernment(0.01);
            if (nation.updateElections) nation.updateElections();
            if (nation.updateApproval) nation.updateApproval([]);
            if (nation.processTurnFinances) nation.processTurnFinances();
            if (nation.recordHistory) nation.recordHistory();
        }

        this.processConflicts();
        this.processEvents();
        if (this.aiManager) this.aiManager.run(); else this.runAINations();
        if (this.diplomacy) this.diplomacy.processTurn();
        if (this.economy) this.economy.processTurn();
        if (this.alliance) this.alliance.processTurn();

        // Atualiza globalTreasury como soma dos tesouros nacionais (só para display)
        this.state.globalTreasury = Object.values(this.data.nations).reduce((s, n) => s + (n.tesouro || 0), 0);

        if (this.state.mapMode && this.state.mapMode !== 'normal') {
            this.map.updateColors(this.state.mapMode, this.data.nations);
        }

        // Gera notícias mundiais do turno e atualiza ticker
        if (this.news) {
            this.news.generateTurnNews(this);
            // Atualiza badge de não lidas (não atualiza se painel de news está aberto)
            if (this.ui) {
                const unread = this.news.unreadCount;
                this.ui._updateNewsBadge(unread);
                this.ui.updateNewsTicker();
                // Se o painel de news estiver aberto, re-render automaticamente
                if (this.ui.currentPanel === 'news') {
                    this.ui.renderNewsPanel();
                }
            }
        }
    }

    runAINations() {
        const codes = Object.keys(this.data.nations).filter(c => this.data.nations[c] !== this.state.playerNation);
        const actors = codes.sort(() => 0.5 - Math.random()).slice(0, 5);

        actors.forEach(code => {
            const nation = this.data.nations[code];
            
            if (nation.estabilidade_politica < 55) {
                this.executeAction(code, 'reforma_politica');
            } 
            else if (Object.values(nation.relacoes).some(v => v < -80)) {
                this.executeAction(code, Math.random() > 0.5 ? 'recrutar_tanques' : 'recrutar_avioes');
            }
            else if (nation.estabilidade_politica > 80 && Math.random() < 0.3) {
                this.executeAction(code, 'melhorar_relacoes');
            }
            else {
                this.executeAction(code, 'invest_infra');
            }
        });
    }

    setMapMode(mode) {
        this.state.mapMode = mode;
        this.map.updateColors(mode, this.data.nations);
    }

    processEvents() {
        if (!this.data.events) return;

        this.data.events.forEach(event => {
            let condMet = true;
            if (event.condicao) {
                if (event.condicao.ano_min && this.state.date.year < event.condicao.ano_min) condMet = false;
                if (event.condicao.ano_max && this.state.date.year > event.condicao.ano_max) condMet = false;
            }

            if (condMet && Math.random() < event.chance) {
                this.triggerEvent(event);
            }
        });
    }

    triggerEvent(event) {
        const player = this.state.playerNation;
        const isPlayerEvent = player && (event.efeitos?.global || event.afeta_jogador);

        // Choice-based event: show decision modal to player
        if (isPlayerEvent && event.choices?.length) {
            this.ui.showEventChoiceModal(event, (choiceIdx) => {
                const choice = event.choices[choiceIdx];
                if (choice?.efeitos) this._applyEventEffects(choice.efeitos, player);
                if (choice?.followup_event) {
                    const followup = this.data.events.find(e => e.id === choice.followup_event);
                    if (followup) setTimeout(() => this.triggerEvent(followup), 800);
                }
                this.updateUI();
                if (this.state.selectedNation) this.ui.renderPanel(this.ui.currentPanel, this.state.selectedNation);
            });
            return;
        }

        this.ui.showNotification(`📰 EVENTO: ${event.nome}`, "info");

        if (event.efeitos?.global) {
            for (let code in this.data.nations) {
                this._applyEventEffects(event.efeitos, this.data.nations[code]);
            }
        } else {
            const candidates = Object.values(this.data.nations).filter(n => {
                if (event.condicao?.regime && n.regime_politico !== event.condicao.regime) return false;
                if (event.condicao?.estabilidade_max && n.estabilidade_politica > event.condicao.estabilidade_max) return false;
                return true;
            });
            if (candidates.length > 0) {
                const target = candidates[Math.floor(Math.random() * candidates.length)];
                this._applyEventEffects(event.efeitos, target);
                this.ui.showNotification(`🌍 LOCAL: ${event.nome} afetou ${target.nome}.`, "threat");
            }
        }
        if (this.state.recentGameEvents) this.state.recentGameEvents.push({ type: 'evento', nome: event.nome });
    }

    _applyEventEffects(efeitos, nation) {
        if (!efeitos || !nation) return;
        if (efeitos.pib_fator)             nation.pib_bilhoes_usd     *= efeitos.pib_fator;
        if (efeitos.pib_bonus)             nation.pib_bilhoes_usd     += efeitos.pib_bonus;
        if (efeitos.estabilidade_fator)    nation.estabilidade_politica = Math.max(0, Math.min(100, (nation.estabilidade_politica || 50) + efeitos.estabilidade_fator));
        if (efeitos.apoio_popular)         nation.apoio_popular         = Math.max(0, Math.min(100, (nation.apoio_popular || 50) + efeitos.apoio_popular));
        if (efeitos.felicidade)            nation.felicidade            = Math.max(0, Math.min(100, (nation.felicidade || 60) + efeitos.felicidade));
        if (efeitos.inflacao)              nation.inflacao              = Math.max(0, Math.min(100, (nation.inflacao || 5) + efeitos.inflacao));
        if (efeitos.tesouro)               nation.tesouro               = Math.max(0, (nation.tesouro || 0) + efeitos.tesouro);
        if (efeitos.corrupcao)             nation.corrupcao             = Math.max(0, Math.min(100, (nation.corrupcao || 30) + efeitos.corrupcao));
        if (efeitos.relacoes) {
            Object.entries(efeitos.relacoes).forEach(([code, val]) => {
                if (!nation.relacoes) nation.relacoes = {};
                nation.relacoes[code] = Math.max(-100, Math.min(100, (nation.relacoes[code] || 0) + val));
            });
        }
    }

    updateUI() {
        const dateEl = document.getElementById('current-date');
        const labels = ["JAN", "ABR", "JUL", "OUT"];
        if (dateEl) dateEl.textContent = `${labels[this.state.date.quarter - 1]} ${this.state.date.year}`;

        const treasuryEl = document.getElementById('global-treasury');
        if (treasuryEl) {
            const playerNation = this.state.playerNation;
            if (playerNation) {
                const t = playerNation.tesouro || 0;
                treasuryEl.textContent = `$ ${t >= 1000 ? (t/1000).toFixed(1) + 'T' : t.toFixed(0) + 'B'}`;
            } else {
                const worldTotal = Object.values(this.data.nations).reduce((s, n) => s + (n.tesouro || 0), 0);
                treasuryEl.textContent = `$ ${(worldTotal/1000).toFixed(1)}T`;
            }
        }

        const defconEl = document.getElementById('defcon-level');
        if (defconEl) defconEl.textContent = `DEFCON ${this.state.defcon}`;

        const scoreEl = document.getElementById('global-score');
        if (scoreEl && this.state.playerNation) {
            const p = this.state.playerNation;
            const score = Math.floor(
                (p.pib_bilhoes_usd / 1000) * 10 +
                (p.militar?.poder_militar_global || 0) * 5 +
                (p.estabilidade_politica || 0) * 2 +
                (p.tecnologias_concluidas?.length || 0) * 50 +
                (p.tesouro || 0) * 0.01 +
                this.state.currentTurn * 10
            );
            scoreEl.textContent = score.toString().padStart(4, '0');
        }
    }

    getConflictsForNation(code) {
        return this.data.conflicts.filter(c => {
            const atacante = c.beligerantes?.atacante || [];
            const defensor = c.beligerantes?.defensor || [];
            return atacante.includes(code) || defensor.includes(code);
        });
    }

    processConflicts() {
        for (let codeA in this.data.nations) {
            const nationA = this.data.nations[codeA];
            for (let codeB in nationA.relacoes) {
                if (codeA >= codeB) continue; 
                
                const relation = nationA.relacoes[codeB];
                if (relation < -90 && Math.random() < 0.1) {
                    this.resolveConflict(codeA, codeB);
                }
            }
        }
    }

    resolveConflict(codeA, codeB) {
        const nA = this.data.nations[codeA];
        const nB = this.data.nations[codeB];
        
        // Cálculo de força simplificado
        const getStrength = (n) => {
            const u = n.militar?.unidades || { infantaria: 0, tanques: 0, avioes: 0, navios: 0 };
            const base = (u.infantaria * 0.1) + (u.tanques * 5) + (u.avioes * 20) + (u.navios * 50);
            const milPower = n.militar?.poder_militar_global || 0;
            return base + milPower * 0.3;
        };

        const strengthA = getStrength(nA) * (nA.estabilidade_politica / 100);
        const strengthB = getStrength(nB) * (nB.estabilidade_politica / 100);

        let winner, loserCode;
        if (strengthA > strengthB * 1.2) {
            winner = nA; loserCode = codeB;
        } else if (strengthB > strengthA * 1.2) {
            winner = nB; loserCode = codeA;
        } else {
            this.ui.showNotification(`Confronto de fronteira entre ${nA.nome} e ${nB.nome} terminou em impasse.`, "threat");
            nA.estabilidade_politica -= 5;
            nB.estabilidade_politica -= 5;
            return;
        }

        const loser = this.data.nations[loserCode];
        winner.estabilidade_politica = Math.min(100, winner.estabilidade_politica + 5);
        loser.estabilidade_politica -= 15;
        loser.pib_bilhoes_usd *= 0.95;
        
        this.ui.showNotification(`CONFLITO: ${winner.nome} prevaleceu sobre ${loser.nome}. Instabilidade em ${loser.nome}.`, "threat");
        
        if (winner.militar?.unidades) winner.militar.unidades.infantaria = (winner.militar.unidades.infantaria || 0) * 0.95;
        if (loser.militar?.unidades)  loser.militar.unidades.infantaria  = (loser.militar.unidades.infantaria  || 0) * 0.80;
    }

    executeAction(nationCode, actionType) {
        const nation = this.data.nations[nationCode];
        if (!nation) return;

        // Garante objeto militar e unidades
        if (!nation.militar) nation.militar = { unidades: {}, orcamento_militar_bilhoes: 0, poder_militar_global: 0 };
        if (!nation.militar.unidades) {
            nation.militar.unidades = { infantaria: 0, tanques: 0, avioes: 0, navios: 0 };
        }

        switch(actionType) {
            case 'invest_infra':
                const costInfra = 50;
                if (nation.tesouro >= costInfra) {
                    nation.tesouro -= costInfra;
                    nation.pib_bilhoes_usd *= 1.01;
                    this.ui.showNotification(`Investimento em infraestrutura concluído em ${nation.nome}. PIB +1%.`, "info");
                } else {
                    this.ui.showNotification("Tesouro Nacional insuficiente!", "threat");
                }
                break;
            case 'reforma_politica':
                nation.estabilidade_politica = Math.min(100, nation.estabilidade_politica + 5);
                this.ui.showNotification(`Reforma política em ${nation.nome} aumentou a estabilidade.`, "info");
                break;
            case 'melhorar_relacoes':
                const potencias = ["US", "CN", "RU", "GB", "FR", "BR"];
                const alvo = potencias[Math.floor(Math.random() * potencias.length)];
                if (alvo !== nationCode) {
                    nation.relacoes[alvo] = Math.min(100, (nation.relacoes[alvo] || 0) + 10);
                    this.data.nations[alvo].relacoes[nationCode] = nation.relacoes[alvo];
                    this.ui.showNotification(`Esforços diplomáticos entre ${nation.nome} e ${this.data.nations[alvo].nome} deram frutos.`, "info");
                }
                break;
            case 'recrutar_tanques':
                const costTanks = 5;
                if (nation.tesouro >= costTanks) {
                    nation.tesouro -= costTanks;
                    nation.militar.unidades.tanques += 100;
                    this.ui.showNotification(`${nation.nome} incorporou 100 novos tanques.`, "info");
                } else {
                    this.ui.showNotification("Tesouro Nacional insuficiente!", "threat");
                }
                break;
            case 'recrutar_avioes':
                const costPlanes = 10;
                if (nation.tesouro >= costPlanes) {
                    nation.tesouro -= costPlanes;
                    nation.militar.unidades.avioes += 50;
                    this.ui.showNotification(`${nation.nome} reforçou sua frota com 50 caças.`, "info");
                } else {
                    this.ui.showNotification("Tesouro Nacional insuficiente!", "threat");
                }
                break;
            case 'mobilizar':
                nation.estabilidade_politica -= 2;
                nation.militar.orcamento_militar_bilhoes *= 1.1;
                this.ui.showNotification(`Mobilização em ${nation.nome}. Gastos militares elevados (+10%).`, "threat");
                break;
            case 'desmobilizar': {
                nation.militar.orcamento_militar_bilhoes *= 0.9;
                nation.estabilidade_politica = Math.min(100, nation.estabilidade_politica + 3);
                this.ui.showNotification(`Desmobilização em ${nation.nome}. Gastos militares reduzidos (−10%). Estabilidade +3%.`, "info");
                break;
            }
            case 'recrutar_infantaria': {
                const costInf = 3;
                if (nation.tesouro >= costInf) {
                    nation.tesouro -= costInf;
                    nation.militar.unidades.infantaria += 5000;
                    this.ui.showNotification(`${nation.nome} recrutou 5.000 soldados.`, "info");
                } else { this.ui.showNotification("Tesouro Nacional insuficiente!", "threat"); }
                break;
            }
            case 'recrutar_infantaria_pesada': {
                const costInfP = 8;
                if (nation.tesouro >= costInfP) {
                    nation.tesouro -= costInfP;
                    nation.militar.unidades.infantaria += 20000;
                    this.ui.showNotification(`${nation.nome} recrutou 20.000 soldados de elite.`, "info");
                } else { this.ui.showNotification("Tesouro Nacional insuficiente!", "threat"); }
                break;
            }
            case 'recrutar_tanques_avancados': {
                const costTkA = 15;
                if (nation.tesouro >= costTkA) {
                    nation.tesouro -= costTkA;
                    nation.militar.unidades.tanques += 200;
                    nation.militar.poder_militar_global = (nation.militar.poder_militar_global || 0) + 5;
                    this.ui.showNotification(`${nation.nome} incorporou 200 tanques de última geração.`, "info");
                } else { this.ui.showNotification("Tesouro Nacional insuficiente!", "threat"); }
                break;
            }
            case 'recrutar_avioes_furtivos': {
                const costAvF = 25;
                if (nation.tesouro >= costAvF) {
                    nation.tesouro -= costAvF;
                    nation.militar.unidades.avioes += 20;
                    nation.militar.poder_militar_global = (nation.militar.poder_militar_global || 0) + 8;
                    this.ui.showNotification(`${nation.nome} adquiriu 20 caças furtivos.`, "info");
                } else { this.ui.showNotification("Tesouro Nacional insuficiente!", "threat"); }
                break;
            }
            case 'recrutar_navios': {
                const costNav = 15;
                if (nation.tesouro >= costNav) {
                    nation.tesouro -= costNav;
                    nation.militar.unidades.navios += 5;
                    this.ui.showNotification(`${nation.nome} comissionou 5 novos navios de guerra.`, "info");
                } else { this.ui.showNotification("Tesouro Nacional insuficiente!", "threat"); }
                break;
            }
            case 'recrutar_navios_guerra': {
                const costNavG = 30;
                if (nation.tesouro >= costNavG) {
                    nation.tesouro -= costNavG;
                    nation.militar.unidades.navios += 3;
                    nation.militar.poder_militar_global = (nation.militar.poder_militar_global || 0) + 10;
                    this.ui.showNotification(`${nation.nome} lançou 3 destróieres de última geração.`, "info");
                } else { this.ui.showNotification("Tesouro Nacional insuficiente!", "threat"); }
                break;
            }
            case 'aumentar_orcamento_militar': {
                const costOrc = 20;
                if (nation.tesouro >= costOrc) {
                    nation.tesouro -= costOrc;
                    nation.militar.orcamento_militar_bilhoes *= 1.2;
                    this.ui.showNotification(`Orçamento militar de ${nation.nome} aumentado em 20%.`, "info");
                } else { this.ui.showNotification("Tesouro Nacional insuficiente!", "threat"); }
                break;
            }
            case 'cortar_orcamento_militar': {
                nation.tesouro += 15;
                nation.militar.orcamento_militar_bilhoes *= 0.8;
                this.ui.showNotification(`Corte orçamentário em ${nation.nome}: −20% militar. Tesouro +$15B.`, "threat");
                break;
            }
            case 'construir_base': {
                const costBase = 40;
                if (nation.tesouro >= costBase) {
                    nation.tesouro -= costBase;
                    nation.militar.poder_militar_global = (nation.militar.poder_militar_global || 0) + 10;
                    nation.estabilidade_politica = Math.max(0, nation.estabilidade_politica - 2);
                    this.ui.showNotification(`Base militar construída em ${nation.nome}. Poder +10, Estabilidade −2%.`, "info");
                } else { this.ui.showNotification("Tesouro Nacional insuficiente!", "threat"); }
                break;
            }
            case 'desenvolver_nuclear': {
                const costNuc = 100;
                if (nation.tesouro >= costNuc) {
                    nation.tesouro -= costNuc;
                    if (!nation.militar.armas_nucleares) nation.militar.armas_nucleares = 0;
                    nation.militar.armas_nucleares += 1;
                    nation.estabilidade_politica = Math.max(0, nation.estabilidade_politica - 10);
                    this.state.defcon = Math.max(1, this.state.defcon - 1);
                    this.ui.showNotification(`⚠️ ${nation.nome} desenvolveu armamento nuclear! DEFCON ${this.state.defcon}. Estabilidade −10%.`, "threat");
                } else { this.ui.showNotification("Tesouro Nacional insuficiente!", "threat"); }
                break;
            }
            case 'propaganda':
                const costProp = 10;
                if (nation.tesouro >= costProp) {
                    nation.tesouro -= costProp;
                    nation.apoio_popular = Math.min(100, nation.apoio_popular + 10);
                    this.ui.showNotification(`Campanha de propaganda aumentou o apoio popular em ${nation.nome}.`, "info");
                } else {
                    this.ui.showNotification("Tesouro Nacional insuficiente!", "threat");
                }
                break;
            case 'propaganda_leve':
                const costPropLeve = 5;
                if (nation.tesouro >= costPropLeve) {
                    nation.tesouro -= costPropLeve;
                    nation.apoio_popular = Math.min(100, nation.apoio_popular + 5);
                    this.ui.showNotification(`Campanha de propaganda leve aumentou o apoio popular em ${nation.nome}.`, "info");
                } else {
                    this.ui.showNotification("Tesouro Nacional insuficiente!", "threat");
                }
                break;
            case 'propaganda_massiva':
                const costPropMassiva = 20;
                if (nation.tesouro >= costPropMassiva) {
                    nation.tesouro -= costPropMassiva;
                    nation.apoio_popular = Math.min(100, nation.apoio_popular + 20);
                    nation.felicidade = Math.max(0, nation.felicidade - 5);
                    this.ui.showNotification(`Campanha de propaganda massiva aumentou o apoio popular em ${nation.nome}, mas reduziu a felicidade.`, "info");
                } else {
                    this.ui.showNotification("Tesouro Nacional insuficiente!", "threat");
                }
                break;
            case 'combater_corrupcao':
                const costCorr = 20;
                if (nation.tesouro >= costCorr) {
                    nation.tesouro -= costCorr;
                    nation.corrupcao = Math.max(0, nation.corrupcao - 15);
                    this.ui.showNotification(`Medidas anticorrupção reduziram a corrupção em ${nation.nome}.`, "info");
                } else {
                    this.ui.showNotification("Tesouro Nacional insuficiente!", "threat");
                }
                break;
            case 'combater_corrupcao_leve':
                const costCorrLeve = 10;
                if (nation.tesouro >= costCorrLeve) {
                    nation.tesouro -= costCorrLeve;
                    nation.corrupcao = Math.max(0, nation.corrupcao - 5);
                    this.ui.showNotification(`Investigação leve reduziu a corrupção em ${nation.nome}.`, "info");
                } else {
                    this.ui.showNotification("Tesouro Nacional insuficiente!", "threat");
                }
                break;
            case 'combater_corrupcao_massiva':
                const costCorrMassiva = 40;
                if (nation.tesouro >= costCorrMassiva) {
                    nation.tesouro -= costCorrMassiva;
                    nation.corrupcao = Math.max(0, nation.corrupcao - 30);
                    nation.burocracia_eficiencia = Math.max(0, nation.burocracia_eficiencia - 10);
                    this.ui.showNotification(`Purga total reduziu drasticamente a corrupção em ${nation.nome}, mas afetou a eficiência burocrática.`, "info");
                } else {
                    this.ui.showNotification("Tesouro Nacional insuficiente!", "threat");
                }
                break;
            case 'eleicoes_antecipadas':
                if (nation.isDemocratic && nation.isDemocratic()) {
                    nation.proxima_eleicao_turno = 0; // trigger election next turn
                    this.ui.showNotification(`Eleições antecipadas marcadas para o próximo turno em ${nation.nome}.`, "info");
                } else {
                    this.ui.showNotification("Esta nação não é uma democracia; eleições não são aplicáveis.", "threat");
                }
                break;
            case 'adiar_eleicoes':
                const costAdiar = 5;
                if (nation.tesouro >= costAdiar) {
                    if (nation.isDemocratic && nation.isDemocratic()) {
                        nation.tesouro -= costAdiar;
                        nation.proxima_eleicao_turno = (nation.proxima_eleicao_turno || 0) + 5;
                        nation.estabilidade_politica = Math.min(100, nation.estabilidade_politica + 5);
                        this.ui.showNotification(`Eleições adiadas em 5 turnos. Estabilidade aumentada em ${nation.nome}.`, "info");
                    } else {
                        this.ui.showNotification("Esta nação não é uma democracia; eleições não são aplicáveis.", "threat");
                    }
                } else {
                    this.ui.showNotification("Tesouro Nacional insuficiente!", "threat");
                }
                break;
            case 'reforma_politica_profunda': {
                const costRP = 30;
                if (nation.tesouro >= costRP) {
                    nation.tesouro -= costRP;
                    nation.estabilidade_politica = Math.min(100, nation.estabilidade_politica + 12);
                    nation.felicidade = Math.min(100, nation.felicidade + 5);
                    this.ui.showNotification(`Reforma política profunda em ${nation.nome}: Estabilidade +12%, Felicidade +5%.`, "info");
                } else {
                    this.ui.showNotification("Tesouro Nacional insuficiente!", "threat");
                }
                break;
            }
            case 'politica_fiscal_estimulo': {
                const costEst = 80;
                if (nation.tesouro >= costEst) {
                    nation.tesouro -= costEst;
                    nation.pib_bilhoes_usd *= 1.02;
                    nation.felicidade = Math.min(100, nation.felicidade + 5);
                    nation.corrupcao = Math.min(100, nation.corrupcao + 2);
                    this.ui.showNotification(`Estímulo fiscal em ${nation.nome}: PIB +2%, Felicidade +5%.`, "info");
                } else {
                    this.ui.showNotification("Tesouro Nacional insuficiente!", "threat");
                }
                break;
            }
            case 'politica_fiscal_austeridade': {
                nation.tesouro += 30;
                nation.pib_bilhoes_usd *= 0.995;
                nation.felicidade = Math.max(0, nation.felicidade - 5);
                nation.estabilidade_politica = Math.max(0, nation.estabilidade_politica - 3);
                this.ui.showNotification(`Austeridade em ${nation.nome}: Tesouro +$30B, PIB -0.5%, Felicidade -5%.`, "threat");
                break;
            }
            case 'reforma_burocracia_leve': {
                const costBL = 15;
                if (nation.tesouro >= costBL) {
                    nation.tesouro -= costBL;
                    nation.burocracia_eficiencia = Math.min(100, nation.burocracia_eficiencia + 10);
                    this.ui.showNotification(`Digitalização dos serviços em ${nation.nome}: Eficiência burocrática +10%.`, "info");
                } else {
                    this.ui.showNotification("Tesouro Nacional insuficiente!", "threat");
                }
                break;
            }
            case 'reforma_burocracia': {
                const costBT = 30;
                if (nation.tesouro >= costBT) {
                    nation.tesouro -= costBT;
                    nation.burocracia_eficiencia = Math.min(100, nation.burocracia_eficiencia + 20);
                    nation.corrupcao = Math.max(0, nation.corrupcao - 5);
                    this.ui.showNotification(`Reforma burocrática total em ${nation.nome}: Eficiência +20%, Corrupção -5%.`, "info");
                } else {
                    this.ui.showNotification("Tesouro Nacional insuficiente!", "threat");
                }
                break;
            }
            case 'invest_infra_leve': {
                const costIL = 25;
                if (nation.tesouro >= costIL) {
                    nation.tesouro -= costIL;
                    nation.pib_bilhoes_usd *= 1.005;
                    this.ui.showNotification(`Infraestrutura básica concluída em ${nation.nome}. PIB +0.5%.`, "info");
                } else { this.ui.showNotification("Tesouro Nacional insuficiente!", "threat"); }
                break;
            }
            case 'invest_infra_massivo': {
                const costIM = 100;
                if (nation.tesouro >= costIM) {
                    nation.tesouro -= costIM;
                    nation.pib_bilhoes_usd *= 1.025;
                    nation.estabilidade_politica = Math.max(0, nation.estabilidade_politica - 2);
                    this.ui.showNotification(`Megaprojeto de infraestrutura em ${nation.nome}. PIB +2.5%, Estabilidade −2%.`, "info");
                } else { this.ui.showNotification("Tesouro Nacional insuficiente!", "threat"); }
                break;
            }
            case 'privatizar': {
                nation.tesouro += 30;
                nation.pib_bilhoes_usd *= 0.997;
                nation.felicidade = Math.max(0, nation.felicidade - 3);
                this.ui.showNotification(`Privatização em ${nation.nome}: Tesouro +$30B, PIB −0.3%, Felicidade −3%.`, "threat");
                break;
            }
            case 'subsidios_setor': {
                const costSub = 40;
                if (nation.tesouro >= costSub) {
                    nation.tesouro -= costSub;
                    nation.pib_bilhoes_usd *= 1.015;
                    nation.corrupcao = Math.min(100, nation.corrupcao + 3);
                    this.ui.showNotification(`Subsídios setoriais em ${nation.nome}: PIB +1.5%, Corrupção +3%.`, "info");
                } else { this.ui.showNotification("Tesouro Nacional insuficiente!", "threat"); }
                break;
            }
            case 'livre_comercio_interno': {
                const costLC = 30;
                if (nation.tesouro >= costLC) {
                    nation.tesouro -= costLC;
                    nation.pib_bilhoes_usd *= 1.01;
                    nation.felicidade = Math.min(100, nation.felicidade + 2);
                    this.ui.showNotification(`Liberalização comercial em ${nation.nome}: PIB +1%, Felicidade +2%.`, "info");
                } else { this.ui.showNotification("Tesouro Nacional insuficiente!", "threat"); }
                break;
            }
            case 'protecionismo': {
                nation.tesouro += 20;
                nation.pib_bilhoes_usd *= 0.995;
                this.ui.showNotification(`Protecionismo em ${nation.nome}: Tesouro +$20B, PIB −0.5%.`, "threat");
                break;
            }
            case 'explorar_recursos': {
                const costER = 20;
                if (nation.tesouro >= costER) {
                    nation.tesouro -= costER;
                    const recursos = nation.recursos || {};
                    // Boost the most scarce resource (lowest value)
                    let minKey = null, minVal = 101;
                    for (const [k, v] of Object.entries(recursos)) {
                        if (v < minVal) { minVal = v; minKey = k; }
                    }
                    if (minKey) {
                        recursos[minKey] = Math.min(100, recursos[minKey] + 15);
                        this.ui.showNotification(`Exploração de ${minKey} em ${nation.nome}: reserva +15%.`, "info");
                    }
                } else { this.ui.showNotification("Tesouro Nacional insuficiente!", "threat"); }
                break;
            }
            case 'investir_saude': {
                const costSH = 20;
                if (nation.tesouro >= costSH) {
                    nation.tesouro -= costSH;
                    if (!nation.gasto_social) nation.gasto_social = {};
                    nation.gasto_social.saude = (nation.gasto_social.saude || 0) + costSH;
                    nation.felicidade = Math.min(100, (nation.felicidade || 50) + 4);
                    nation.apoio_popular = Math.min(100, (nation.apoio_popular || 50) + 2);
                    this.ui.showNotification(`Investimento em saúde em ${nation.nome}: Felicidade +4, Apoio +2.`, 'info');
                } else { this.ui.showNotification('Tesouro insuficiente!', 'threat'); }
                break;
            }
            case 'investir_educacao': {
                const costED = 20;
                if (nation.tesouro >= costED) {
                    nation.tesouro -= costED;
                    if (!nation.gasto_social) nation.gasto_social = {};
                    nation.gasto_social.educacao = (nation.gasto_social.educacao || 0) + costED;
                    nation.velocidade_pesquisa = Math.min(3, (nation.velocidade_pesquisa || 1) + 0.05);
                    nation.felicidade = Math.min(100, (nation.felicidade || 50) + 2);
                    this.ui.showNotification(`Investimento em educação em ${nation.nome}: Pesquisa +5%, Felicidade +2.`, 'info');
                } else { this.ui.showNotification('Tesouro insuficiente!', 'threat'); }
                break;
            }
            case 'investir_previdencia': {
                const costPR = 20;
                if (nation.tesouro >= costPR) {
                    nation.tesouro -= costPR;
                    if (!nation.gasto_social) nation.gasto_social = {};
                    nation.gasto_social.previdencia = (nation.gasto_social.previdencia || 0) + costPR;
                    nation.apoio_popular = Math.min(100, (nation.apoio_popular || 50) + 3);
                    this.ui.showNotification(`Previdência social ampliada em ${nation.nome}: Apoio +3.`, 'info');
                } else { this.ui.showNotification('Tesouro insuficiente!', 'threat'); }
                break;
            }
            case 'investir_seguranca': {
                const costSE = 20;
                if (nation.tesouro >= costSE) {
                    nation.tesouro -= costSE;
                    if (!nation.gasto_social) nation.gasto_social = {};
                    nation.gasto_social.seguranca = (nation.gasto_social.seguranca || 0) + costSE;
                    nation.estabilidade_politica = Math.min(100, (nation.estabilidade_politica || 50) + 3);
                    nation.corrupcao = Math.max(0, (nation.corrupcao || 30) - 2);
                    this.ui.showNotification(`Segurança pública reforçada em ${nation.nome}: Estabilidade +3, Corrupção −2.`, 'info');
                } else { this.ui.showNotification('Tesouro insuficiente!', 'threat'); }
                break;
            }
            case 'ativar_emergencia': {
                if (!nation.poderes_emergencia_ativo) {
                    nation.poderes_emergencia_ativo = true;
                    nation.estabilidade_politica = Math.max(0, (nation.estabilidade_politica || 50) - 5);
                    nation.apoio_popular = Math.max(0, (nation.apoio_popular || 50) - 8);
                    this.ui.showNotification(`Poderes de emergência ativados em ${nation.nome}.`, 'threat');
                }
                break;
            }
            case 'desativar_emergencia': {
                if (nation.poderes_emergencia_ativo) {
                    nation.poderes_emergencia_ativo = false;
                    nation.estabilidade_politica = Math.min(100, (nation.estabilidade_politica || 50) + 10);
                    nation.apoio_popular = Math.min(100, (nation.apoio_popular || 50) + 5);
                    this.ui.showNotification(`Poderes de emergência desativados em ${nation.nome}. Estabilidade +10.`, 'info');
                }
                break;
            }
            default:
                this.ui.showNotification("Ação ainda não implementada.", "info");
        }

        this.updateUI();
        this.ui.renderPanel(this.ui.currentPanel, nation);
    }

    // ═══════════════════════════════════════════════════════════
    // ESPIONAGEM — Motor de Operações Secretas
    // ═══════════════════════════════════════════════════════════

    static get SPY_OPS() {
        return {
            infiltrar_governo:       { custo: 30,  baseSuccess: 65, tipo: 'intel'     },
            infiltrar_militar:       { custo: 45,  baseSuccess: 55, tipo: 'intel'     },
            roubar_tecnologia:       { custo: 70,  baseSuccess: 40, tipo: 'tech'      },
            sabotar_infraestrutura:  { custo: 55,  baseSuccess: 50, tipo: 'sabotagem' },
            fomentar_protestos:      { custo: 35,  baseSuccess: 60, tipo: 'sabotagem' },
            assassinar_lider:        { custo: 90,  baseSuccess: 30, tipo: 'sabotagem' },
            tentar_golpe:            { custo: 130, baseSuccess: 20, tipo: 'golpe'     },
            campanha_desinformacao:  { custo: 25,  baseSuccess: 75, tipo: 'influencia'},
        };
    }

    executeSpyOp(fromCode, opId, targetCode) {
        const player = this.data.nations[fromCode];
        const target = this.data.nations[targetCode];
        if (!player || !target) return;

        const op = GameEngine.SPY_OPS[opId];
        if (!op) return;

        if ((player.tesouro || 0) < op.custo) {
            this.ui.showNotification('Fundos insuficientes para esta operação.', 'threat');
            return;
        }
        player.tesouro -= op.custo;

        // Success rate adjusted by intel difference
        const playerIntel = player.intel_score || 0;
        const targetSec   = (target.seguranca_intel || 1) * 10;
        const successRate = Math.min(90, Math.max(10, op.baseSuccess + playerIntel * 0.1 - targetSec));

        const roll    = Math.random() * 100;
        const success = roll < successRate;
        const caught  = !success && roll > (100 - (100 - successRate) * 0.4);

        if (!player.spy_ops_log) player.spy_ops_log = [];

        if (success) {
            this._applySpyOpEffect(opId, player, target);
            const names = { infiltrar_governo:'Infiltração no Governo', infiltrar_militar:'Infiltração Militar',
                roubar_tecnologia:'Roubo Tecnológico', sabotar_infraestrutura:'Sabotagem de Infraestrutura',
                fomentar_protestos:'Fomento de Protestos', assassinar_lider:'Neutralização de Líder',
                tentar_golpe:'Apoio a Golpe', campanha_desinformacao:'Desinformação' };
            this.ui.showNotification(`✅ ÊXITO: ${names[opId]||opId} em ${target.nome} bem-sucedida.`, 'info');
            player.spy_ops_log.unshift({ turn: this.state.currentTurn, op: opId, target: target.nome, success: true });
            if (this.state.recentGameEvents) this.state.recentGameEvents.push({ type:'espionagem_ok', nation: player.nome, target: target.nome });
        } else if (caught) {
            this.ui.showNotification(`❌ AGENTES CAPTURADOS por ${target.nome}. Relações deterioradas -30.`, 'threat');
            if (!player.relacoes) player.relacoes = {};
            if (!target.relacoes) target.relacoes = {};
            player.relacoes[targetCode] = Math.max(-100, (player.relacoes[targetCode] || 0) - 30);
            target.relacoes[fromCode]   = Math.max(-100, (target.relacoes[fromCode]   || 0) - 30);
            player.spy_ops_log.unshift({ turn: this.state.currentTurn, op: opId, target: target.nome, success: false, caught: true });
            if (this.state.recentGameEvents) this.state.recentGameEvents.push({ type:'espionagem_capturado', nation: player.nome, target: target.nome });
        } else {
            this.ui.showNotification(`⚠️ Operação falhou em ${target.nome}. Operativos evacuados sem baixas.`, 'threat');
            player.spy_ops_log.unshift({ turn: this.state.currentTurn, op: opId, target: target.nome, success: false });
        }

        this.updateUI();
        if (this.ui.currentPanel === 'espionagem') this.ui.renderPanel('espionagem', this.state.selectedNation);
    }

    _applySpyOpEffect(opId, player, target) {
        switch(opId) {
            case 'infiltrar_governo':
                if (!player.intel_data) player.intel_data = {};
                player.intel_data[target.codigo_iso] = {
                    ...(player.intel_data[target.codigo_iso] || {}),
                    estabilidade: target.estabilidade_politica,
                    apoio: target.apoio_popular,
                    corrupcao: target.corrupcao,
                    felicidade: target.felicidade,
                    regime: target.regime_politico,
                    turn: this.state.currentTurn
                };
                break;
            case 'infiltrar_militar':
                if (!player.intel_data) player.intel_data = {};
                player.intel_data[target.codigo_iso] = {
                    ...(player.intel_data[target.codigo_iso] || {}),
                    poder_militar: target.militar?.poder_militar_global,
                    nukes: target.militar?.armas_nucleares,
                    orcamento_mil: target.militar?.orcamento_militar_bilhoes,
                    unidades: { ...(target.militar?.unidades || {}) },
                    turn: this.state.currentTurn
                };
                break;
            case 'roubar_tecnologia':
                if (player.pesquisa_atual) {
                    const tech = this.data.technologies.find(t => t.id === player.pesquisa_atual.id);
                    player.pesquisa_atual.progresso = Math.min(
                        tech?.tempo_turnos || 99,
                        (player.pesquisa_atual.progresso || 0) + 3
                    );
                }
                break;
            case 'sabotar_infraestrutura':
                target.pib_bilhoes_usd *= 0.98;
                target.estabilidade_politica = Math.max(0, (target.estabilidade_politica || 50) - 5);
                break;
            case 'fomentar_protestos':
                target.estabilidade_politica = Math.max(0, (target.estabilidade_politica || 50) - 12);
                if (target.apoio_popular !== undefined) target.apoio_popular = Math.max(0, target.apoio_popular - 8);
                break;
            case 'assassinar_lider':
                if (target.pesquisa_atual) target.pesquisa_atual.pausado_turnos = (target.pesquisa_atual.pausado_turnos || 0) + 4;
                target.estabilidade_politica = Math.max(0, (target.estabilidade_politica || 50) - 15);
                break;
            case 'tentar_golpe':
                if ((target.estabilidade_politica || 50) < 40) {
                    target.estabilidade_politica = Math.max(0, (target.estabilidade_politica || 50) - 30);
                    target.regime_politico = 'Junta Militar';
                    target.pesquisa_atual = null;
                } else {
                    target.estabilidade_politica = Math.max(0, (target.estabilidade_politica || 50) - 10);
                }
                break;
            case 'campanha_desinformacao':
                if (target.apoio_popular !== undefined) target.apoio_popular = Math.max(0, target.apoio_popular - 10);
                Object.keys(target.relacoes || {}).slice(0, 3).forEach(code => {
                    if ((target.relacoes[code] || 0) > 0) target.relacoes[code] = Math.max(-100, target.relacoes[code] - 5);
                });
                break;
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MILITAR ESTENDIDO — Guerra, Paz, Ajuda
    // ═══════════════════════════════════════════════════════════

    declaraGuerra(fromCode, targetCode) {
        const player = this.data.nations[fromCode];
        const target = this.data.nations[targetCode];
        if (!player || !target) return;
        if ((player.tesouro || 0) < 0) { this.ui.showNotification('Operação inviável.', 'threat'); return; }

        if (!player.relacoes) player.relacoes = {};
        if (!target.relacoes) target.relacoes = {};
        player.relacoes[targetCode] = -100;
        target.relacoes[fromCode]   = -100;

        player.estabilidade_politica = Math.max(0, (player.estabilidade_politica || 50) - 10);
        target.estabilidade_politica = Math.max(0, (target.estabilidade_politica || 50) - 15);

        this.state.defcon = Math.max(1, this.state.defcon - 1);
        if (!player.em_guerra) player.em_guerra = [];
        if (!player.em_guerra.includes(targetCode)) player.em_guerra.push(targetCode);
        if (!target.em_guerra) target.em_guerra = [];
        if (!target.em_guerra.includes(fromCode)) target.em_guerra.push(fromCode);

        this.ui.showNotification(`⚔️ GUERRA DECLARADA: ${player.nome} × ${target.nome}. DEFCON ${this.state.defcon}.`, 'threat');
        if (this.state.recentGameEvents) this.state.recentGameEvents.push({ type:'guerra', nation: player.nome, target: target.nome });

        // Trigger collective defense from target's alliances
        if (this.alliance) {
            const responders = this.alliance.onWarDeclared(fromCode, targetCode);
            if (responders.length > 0 && this.state.recentGameEvents) {
                const rNames = responders.map(c => this.data.nations[c]?.nome || c).join(', ');
                this.state.recentGameEvents.push({ type: 'alianca_ativada', atacante: player.nome, aliados: rNames });
            }
        }

        this.updateUI();
        this.ui.renderPanel(this.ui.currentPanel, this.state.selectedNation);
    }

    proporPaz(fromCode, targetCode) {
        const player = this.data.nations[fromCode];
        const target = this.data.nations[targetCode];
        if (!player || !target) return;

        if (!player.relacoes) player.relacoes = {};
        if (!target.relacoes) target.relacoes = {};
        player.relacoes[targetCode] = Math.min(40, (player.relacoes[targetCode] || -100) + 40);
        target.relacoes[fromCode]   = Math.min(40, (target.relacoes[fromCode]   || -100) + 40);

        if (player.em_guerra) player.em_guerra = player.em_guerra.filter(c => c !== targetCode);
        if (target.em_guerra) target.em_guerra = target.em_guerra.filter(c => c !== fromCode);

        player.estabilidade_politica = Math.min(100, (player.estabilidade_politica || 50) + 5);
        target.estabilidade_politica = Math.min(100, (target.estabilidade_politica || 50) + 5);
        this.state.defcon = Math.min(5, this.state.defcon + 1);

        this.ui.showNotification(`🕊️ ARMISTÍCIO: ${player.nome} e ${target.nome} cessaram hostilidades. DEFCON ${this.state.defcon}.`, 'info');
        this.updateUI();
        this.ui.renderPanel(this.ui.currentPanel, this.state.selectedNation);
    }

    enviarAjudaMilitar(fromCode, targetCode, valor) {
        const player = this.data.nations[fromCode];
        const target = this.data.nations[targetCode];
        if (!player || !target) return;
        valor = valor || 20;
        if ((player.tesouro || 0) < valor) { this.ui.showNotification('Tesouro insuficiente para ajuda.', 'threat'); return; }

        player.tesouro -= valor;
        if (target.militar) target.militar.poder_militar_global = (target.militar.poder_militar_global || 0) + valor * 0.5;
        if (!player.relacoes) player.relacoes = {};
        if (!target.relacoes) target.relacoes = {};
        player.relacoes[targetCode] = Math.min(100, (player.relacoes[targetCode] || 0) + 15);
        target.relacoes[fromCode]   = Math.min(100, (target.relacoes[fromCode]   || 0) + 15);

        this.ui.showNotification(`🎖️ Ajuda Militar enviada a ${target.nome}: $${valor}B. Relações +15.`, 'info');
        this.updateUI();
        this.ui.renderPanel(this.ui.currentPanel, this.state.selectedNation);
    }

    processResearch(nation) {
        if (!nation.pesquisa_atual) return;

        // Handle research pause (e.g. from spy op assassination)
        if (nation.pesquisa_atual.pausado_turnos > 0) {
            nation.pesquisa_atual.pausado_turnos--;
            return;
        }

        const tech = this.data.technologies.find(t => t.id === nation.pesquisa_atual.id);
        if (!tech) return;

        // velocidade_pesquisa: starts at 1, increased by education/science techs
        const speed = nation.velocidade_pesquisa || 1;
        nation.pesquisa_atual.progresso = Math.min(
            tech.tempo_turnos,
            (nation.pesquisa_atual.progresso || 0) + speed
        );

        if (nation.pesquisa_atual.progresso >= tech.tempo_turnos) {
            this.completeResearch(nation, tech);
        }
    }

    completeResearch(nation, tech) {
        if (!nation.tecnologias_concluidas.includes(tech.id)) {
            nation.tecnologias_concluidas.push(tech.id);
        }

        nation.pesquisa_atual = null;
        this.ui.showNotification(`🔬 DESCOBERTA: ${nation.nome} concluiu ${tech.nome}!`, "info");

        const ef = tech.efeitos || {};

        // Legacy effects (backward compat)
        if (ef.pib_fator)           nation.pib_bilhoes_usd   *= ef.pib_fator;
        if (ef.estabilidade_fator)  nation.estabilidade_politica = Math.min(100, Math.max(0, (nation.estabilidade_politica || 50) + ef.estabilidade_fator));
        if (ef.poder_militar_bonus) { if (nation.militar) nation.militar.poder_militar_global = (nation.militar.poder_militar_global || 0) + ef.poder_militar_bonus; }
        if (ef.populacao_fator)     nation.populacao *= ef.populacao_fator;

        // New percentage PIB bonus
        if (ef.bonus_pib_pct)       nation.pib_bilhoes_usd   *= (1 + ef.bonus_pib_pct / 100);

        // Military bonuses
        if (ef.bonus_militar_defesa) {
            if (!nation.militar) nation.militar = {};
            nation.militar.bonus_defesa_tech = (nation.militar.bonus_defesa_tech || 0) + ef.bonus_militar_defesa;
        }

        // Intelligence score
        if (ef.bonus_intel) {
            nation.intel_score = (nation.intel_score || 0) + ef.bonus_intel;
        }

        // Science speed multiplier (cumulative)
        if (ef.bonus_ciencia) {
            nation.velocidade_pesquisa = (nation.velocidade_pesquisa || 1) + ef.bonus_ciencia;
        }

        // Diplomacy bonus
        if (ef.bonus_diplomacia) {
            nation.diplomacia_bonus = (nation.diplomacia_bonus || 0) + ef.bonus_diplomacia;
        }

        // Population percentage bonus
        if (ef.bonus_populacao_pct) nation.populacao *= (1 + ef.bonus_populacao_pct / 100);

        // Add to news events
        if (this.state.recentGameEvents) {
            this.state.recentGameEvents.push({ type: 'tech', nation: nation.nome, tech: tech.nome, cat: tech.categoria });
        }
    }

    startResearch(nationCode, techId) {
        const nation = this.data.nations[nationCode];
        const tech   = this.data.technologies.find(t => t.id === techId);

        if (!nation || !tech) return;

        // Pre-requisite check
        if (tech.pre_requisitos?.length) {
            for (const pre of tech.pre_requisitos) {
                if (!(nation.tecnologias_concluidas || []).includes(pre)) {
                    const missing = this.data.technologies.find(t => t.id === pre);
                    this.ui.showNotification(`Pré-requisito faltando: "${missing?.nome || pre}"`, "threat");
                    return;
                }
            }
        }

        // PIB minimum check
        if (tech.requisito_pib_minimo && (nation.pib_bilhoes_usd || 0) < tech.requisito_pib_minimo) {
            this.ui.showNotification(`PIB insuficiente. Requer $${tech.requisito_pib_minimo}B (atual: $${Math.floor(nation.pib_bilhoes_usd || 0)}B)`, "threat");
            return;
        }

        // Stability minimum check
        if (tech.requisito_estabilidade && (nation.estabilidade_politica || 0) < tech.requisito_estabilidade) {
            this.ui.showNotification(`Estabilidade insuficiente. Requer ${tech.requisito_estabilidade}% (atual: ${Math.floor(nation.estabilidade_politica || 0)}%)`, "threat");
            return;
        }

        // Already researching something?
        if (nation.pesquisa_atual) {
            this.ui.showNotification(`Já pesquisando: ${this.data.technologies.find(t=>t.id===nation.pesquisa_atual.id)?.nome || nation.pesquisa_atual.id}. Conclua ou aguarde.`, "threat");
            return;
        }

        // Cost check
        if ((nation.tesouro || 0) < tech.custo) {
            this.ui.showNotification(`Tesouro insuficiente! Necessário: $${tech.custo}B`, "threat");
            return;
        }

        nation.tesouro -= tech.custo;
        nation.pesquisa_atual = { id: tech.id, progresso: 0 };
        this.ui.showNotification(`${nation.nome} iniciou pesquisa em ${tech.nome}.`, "info");
        this.updateUI();
        this.ui.renderPanel(this.ui.currentPanel, nation);
    }

    executeTargetedAction(fromCode, actionType, targetCode) {
        const nation = this.data.nations[fromCode];
        const target = this.data.nations[targetCode];
        if (!nation || !target) return;

        switch(actionType) {
            case 'enviar_embaixada': {
                const cost = 15;
                if (nation.tesouro >= cost) {
                    nation.tesouro -= cost;
                    if (!nation.relacoes) nation.relacoes = {};
                    if (!target.relacoes) target.relacoes = {};
                    nation.relacoes[targetCode] = Math.min(100, (nation.relacoes[targetCode] || 0) + 15);
                    target.relacoes[fromCode]   = Math.min(100, (target.relacoes[fromCode]   || 0) + 15);
                    this.ui.showNotification(`Embaixada enviada: ${nation.nome} → ${target.nome}. Relações +15.`, "info");
                } else {
                    this.ui.showNotification("Tesouro Nacional insuficiente!", "threat");
                }
                break;
            }
            case 'sancoes_economicas': {
                if (!nation.relacoes) nation.relacoes = {};
                if (!target.relacoes) target.relacoes = {};
                nation.relacoes[targetCode] = Math.max(-100, (nation.relacoes[targetCode] || 0) - 25);
                target.relacoes[fromCode]   = Math.max(-100, (target.relacoes[fromCode]   || 0) - 25);
                target.pib_bilhoes_usd *= 0.98;
                this.ui.showNotification(`Sanções: ${nation.nome} → ${target.nome}. Relações −25, PIB alvo −2%.`, "threat");
                break;
            }
        }
        this.updateUI();
        if (this.state.selectedNation) this.ui.renderPanel(this.ui.currentPanel, this.state.selectedNation);
    }

    // ═══════════════════════════════════════════════════════════
    // WIN / LOSS CONDITIONS
    // ═══════════════════════════════════════════════════════════

    checkGameEndConditions() {
        const player = this.state.playerNation;
        if (!player || this.state.gameState === 'GAMEOVER') return;

        // Revolution: apoio_popular < 20 for 3 consecutive turns
        if ((player.apoio_popular || 50) < 20) {
            player.revolucao_turnos = (player.revolucao_turnos || 0) + 1;
            if (player.revolucao_turnos >= 3) {
                this.triggerGameOver('revolução', `O povo se revoltou! Apoio popular caiu a ${Math.round(player.apoio_popular)}% por 3 turnos consecutivos. O governo foi deposto.`);
                return;
            }
            this.ui.showNotification(`⚠️ ALERTA: Apoio popular crítico (${Math.round(player.apoio_popular)}%)! Revolução iminente em ${3 - player.revolucao_turnos} turno(s).`, 'threat');
        } else {
            player.revolucao_turnos = 0;
        }

        // Bankruptcy: tesouro <= 0 for 4 consecutive turns
        if ((player.tesouro || 0) <= 0) {
            player.falencia_turnos = (player.falencia_turnos || 0) + 1;
            if (player.falencia_turnos >= 4) {
                this.triggerGameOver('falência nacional', `Colapso fiscal! O tesouro permaneceu vazio por 4 turnos. Credores internacionais assumiram o controle.`);
                return;
            }
            this.ui.showNotification(`💸 CRISE FISCAL: Tesouro esgotado! Risco de falência em ${4 - player.falencia_turnos} turno(s).`, 'threat');
        } else {
            player.falencia_turnos = 0;
        }

        // Coup: political stability < 10
        if ((player.estabilidade_politica || 50) < 10) {
            this.triggerGameOver('golpe de estado', `Instabilidade política catastrófica! As forças armadas derrubaram o governo. Estabilidade: ${Math.round(player.estabilidade_politica)}%.`);
            return;
        }

        // Hyperinflation: inflacao > 80
        if ((player.inflacao || 5) > 80) {
            this.triggerGameOver('hiperinflação', `Colapso monetário! A inflação atingiu ${Math.round(player.inflacao)}%. A moeda nacional se tornou inútil.`);
            return;
        }

        // Victory: 20+ turns, good approval, stability, low inflation
        const turn = this.state.currentTurn;
        if (turn >= 20
            && (player.apoio_popular || 0) >= 65
            && (player.estabilidade_politica || 0) >= 65
            && (player.inflacao || 100) <= 15
            && (player.tesouro || 0) > 0) {
            this.triggerVictory('prosperidade', `Liderança exemplar! Após ${turn} turnos, ${player.nome} é uma nação próspera, estável e respeitada no cenário global.`);
        }
    }

    triggerGameOver(reason, message) {
        if (this.state.gameState === 'GAMEOVER') return;
        this.state.gameState = 'GAMEOVER';
        const overlay = document.getElementById('endgame-overlay');
        if (!overlay) return;
        document.getElementById('endgame-icon').textContent = '💀';
        document.getElementById('endgame-title').textContent = 'DERROTA';
        document.getElementById('endgame-subtitle').textContent = reason.toUpperCase();
        document.getElementById('endgame-message').textContent = message;
        document.getElementById('endgame-stats').innerHTML = this._buildEndStats(this.state.playerNation);
        overlay.className = 'endgame-overlay defeat';
        overlay.style.display = 'flex';
        requestAnimationFrame(() => overlay.classList.add('visible'));
    }

    triggerVictory(reason, message) {
        if (this.state.gameState === 'GAMEOVER') return;
        this.state.gameState = 'GAMEOVER';
        const overlay = document.getElementById('endgame-overlay');
        if (!overlay) return;
        document.getElementById('endgame-icon').textContent = '🏆';
        document.getElementById('endgame-title').textContent = 'VITÓRIA';
        document.getElementById('endgame-subtitle').textContent = reason.toUpperCase();
        document.getElementById('endgame-message').textContent = message;
        document.getElementById('endgame-stats').innerHTML = this._buildEndStats(this.state.playerNation);
        overlay.className = 'endgame-overlay victory';
        overlay.style.display = 'flex';
        requestAnimationFrame(() => overlay.classList.add('visible'));
    }

    _buildEndStats(player) {
        if (!player) return '';
        const leaderName = this.aiManager?.getLeaderName(player) || '—';
        return `
            <div class="eg-stat"><span>Nação</span><span>${player.nome}</span></div>
            <div class="eg-stat"><span>Líder</span><span>${leaderName}</span></div>
            <div class="eg-stat"><span>Turnos Jogados</span><span>${this.state.currentTurn}</span></div>
            <div class="eg-stat"><span>Apoio Popular</span><span>${Math.round(player.apoio_popular || 0)}%</span></div>
            <div class="eg-stat"><span>Inflação</span><span>${Math.round(player.inflacao || 0)}%</span></div>
            <div class="eg-stat"><span>Estabilidade</span><span>${Math.round(player.estabilidade_politica || 0)}%</span></div>
            <div class="eg-stat"><span>PIB</span><span>$${Math.round(player.pib_bilhoes_usd || 0)}B</span></div>
            <div class="eg-stat"><span>Tesouro</span><span>$${Math.round(player.tesouro || 0)}B</span></div>
        `;
    }
}
