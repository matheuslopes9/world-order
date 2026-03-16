class UIManager {
    constructor(engine) {
        this.engine = engine;
        this.currentPanel = 'history';
        this.historyMode = 'national'; // 'national' ou 'global'
        this.techFilter  = 'ALL';
        this._spyTab     = 'operacoes';
        this._dipTab     = 'tratados';
    }

    init() {
        console.log("Inicializando UIManager...");
        this.bindEvents();
    }

    bindEvents() {
        // Side Menu Panels - Specific selector to avoid conflict with Map Controls
        document.querySelectorAll('#side-menu .nav-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                const panel = btn.getAttribute('data-panel');
                this.switchPanel(panel);
            });
        });

        const endTurnBtn = document.getElementById('end-turn-btn');
        if (endTurnBtn) {
            endTurnBtn.addEventListener('click', () => {
                this.engine.endTurn();
            });
        }

        // Map mode buttons (only those with data-mode attribute)
        document.querySelectorAll('#map-controls .nav-btn[data-mode]').forEach(btn => {
            btn.addEventListener('click', () => {
                const mode = btn.getAttribute('data-mode');
                
                // Toggle active class only among map mode buttons
                document.querySelectorAll('#map-controls .nav-btn[data-mode]').forEach(b => b.classList.remove('active'));
                btn.classList.add('active');

                this.engine.setMapMode(mode);
            });
        });

        // Government modal close button
        const govModalClose = document.getElementById('gov-modal-close');
        if (govModalClose) {
            govModalClose.addEventListener('click', () => {
                this.hideGovernmentModal();
            });
        }

        // Close options/gov modal with Escape key
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape') {
                const optModal = document.getElementById('options-modal');
                if (optModal && optModal.style.display !== 'none') {
                    this.engine.closeOptions();
                    return;
                }
                const govModal = document.getElementById('gov-modal');
                if (govModal && govModal.classList.contains('active')) {
                    this.hideGovernmentModal();
                }
            }
        });

        // Click outside options-box to close options modal
        const optOverlay = document.getElementById('options-modal');
        if (optOverlay) {
            optOverlay.addEventListener('click', (e) => {
                if (e.target === optOverlay) this.engine.closeOptions();
            });
        }
    }

    hideGovernmentModal() {
        const modal = document.getElementById('gov-modal');
        if (modal) modal.classList.remove('active');
    }

    showGovernmentModal(action, nation) {
        const modal = document.getElementById('gov-modal');
        const title = document.getElementById('gov-modal-title');
        const content = document.getElementById('gov-modal-content');
        if (!modal || !title || !content) return;

        let nationObj = typeof nation === 'string' ? this.engine.data.nations[nation] : nation;
        if (!nationObj) return;

        const actionNames = {
            'propaganda':           '📢 Campanha de Propaganda',
            'combater_corrupcao':   '⚖️ Combater Corrupção',
            'eleicoes_antecipadas': '🗳️ Gerenciar Eleições',
            'reforma_politica':     '🏛️ Reforma Política',
            'politica_fiscal':      '💰 Política Fiscal',
            'reforma_burocracia':   '📋 Reforma Burocrática',
            'alocacao_orcamento':   '📊 Alocação Orçamentária',
            'poderes_emergencia':   '⚡ Poderes de Emergência'
        };
        title.textContent = actionNames[action] || 'Ação de Governo';

        let html = '';
        switch(action) {
            case 'propaganda':           html = this.getPropagandaHTML(nationObj); break;
            case 'combater_corrupcao':   html = this.getAntiCorruptionHTML(nationObj); break;
            case 'eleicoes_antecipadas': html = this.getEarlyElectionsHTML(nationObj); break;
            case 'reforma_politica':     html = this.getReformaPoliticaHTML(nationObj); break;
            case 'politica_fiscal':      html = this.getPoliticaFiscalHTML(nationObj); break;
            case 'reforma_burocracia':   html = this.getReformaBurocraciaHTML(nationObj); break;
            case 'alocacao_orcamento':   html = this.getAlocacaoOrcamentoHTML(nationObj); break;
            case 'poderes_emergencia':   html = this.getPoderesEmergenciaHTML(nationObj); break;
            default: html = `<p style="color:var(--text-dim)">Ação não disponível.</p>`;
        }
        content.innerHTML = html;
        modal.classList.add('active');
    }

    // ---- Chart helpers ----

    /**
     * Renders a full SVG mini-chart with grid, area fill and trend indicator.
     * @param {number[]} data - Historical values array
     * @param {string} color - CSS color string
     * @param {string} title - Chart label
     * @returns {string} HTML string
     */
    renderMiniChart(data, color, title) {
        if (!data || data.length < 2) {
            return `<div class="chart-placeholder">Jogue mais turnos para ver o histórico.</div>`;
        }
        const W = 320, H = 80;
        const PL = 30, PR = 8, PT = 8, PB = 18;
        const cw = W - PL - PR, ch = H - PT - PB;
        const min = Math.min(...data), max = Math.max(...data);
        const range = (max - min) || 1;
        const toX = i => PL + (i / (data.length - 1)) * cw;
        const toY = v => PT + ch - ((v - min) / range) * ch;
        const pts = data.map((v, i) => `${toX(i).toFixed(1)},${toY(v).toFixed(1)}`).join(' ');
        const last = data[data.length - 1];
        const first = data[0];
        const diff = last - first;
        const diffStr = (diff >= 0 ? '+' : '') + diff.toFixed(1);
        const diffCol = diff > 0 ? '#00ff88' : diff < 0 ? '#ff3333' : '#8b949e';
        const areaBase = PT + ch;
        const areaPts = `${PL},${areaBase} ${pts} ${toX(data.length - 1).toFixed(1)},${areaBase}`;
        const gridMid = ((min + max) / 2).toFixed(0);
        const lastX = toX(data.length - 1).toFixed(1);
        const lastY = toY(last).toFixed(1);
        const labelY = (parseFloat(lastY) - 7).toFixed(1);
        const dots = data.length <= 15
            ? data.map((v, i) => `<circle cx="${toX(i).toFixed(1)}" cy="${toY(v).toFixed(1)}" r="2" fill="${color}" opacity="0.7"/>`).join('')
            : '';
        return `
        <div class="chart-container">
            <div class="chart-header-row">
                <span class="chart-title">${title}</span>
                <span class="chart-diff" style="color:${diffCol}">${diffStr} (${data.length} turnos)</span>
            </div>
            <svg viewBox="0 0 ${W} ${H}" width="100%" height="${H}" style="display:block;overflow:visible">
                <defs>
                    <linearGradient id="cg_${color.replace(/[^a-z0-9]/gi,'')}" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stop-color="${color}" stop-opacity="0.25"/>
                        <stop offset="100%" stop-color="${color}" stop-opacity="0.01"/>
                    </linearGradient>
                </defs>
                <line x1="${PL}" y1="${PT}" x2="${PL}" y2="${PT+ch}" stroke="rgba(255,255,255,0.12)" stroke-width="1"/>
                <line x1="${PL}" y1="${PT+ch}" x2="${PL+cw}" y2="${PT+ch}" stroke="rgba(255,255,255,0.12)" stroke-width="1"/>
                <line x1="${PL}" y1="${PT+ch/2}" x2="${PL+cw}" y2="${PT+ch/2}" stroke="rgba(255,255,255,0.07)" stroke-width="1" stroke-dasharray="4,4"/>
                <text x="${PL-4}" y="${PT+ch}" fill="rgba(255,255,255,0.35)" font-size="7.5" text-anchor="end">${min.toFixed(0)}</text>
                <text x="${PL-4}" y="${(PT+ch/2+3).toFixed(0)}" fill="rgba(255,255,255,0.35)" font-size="7.5" text-anchor="end">${gridMid}</text>
                <text x="${PL-4}" y="${PT+8}" fill="rgba(255,255,255,0.35)" font-size="7.5" text-anchor="end">${max.toFixed(0)}</text>
                <polygon points="${areaPts}" fill="url(#cg_${color.replace(/[^a-z0-9]/gi,'')})"/>
                <polyline points="${pts}" fill="none" stroke="${color}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>
                ${dots}
                <circle cx="${lastX}" cy="${lastY}" r="4" fill="${color}"/>
                <text x="${lastX}" y="${labelY}" fill="${color}" font-size="9" text-anchor="middle" font-weight="bold">${last.toFixed(1)}</text>
            </svg>
        </div>`;
    }

    /**
     * Renders a tiny inline sparkline SVG from history array.
     */
    getSparkline(data, color) {
        if (!data || data.length < 2) {
            return `<svg class="sparkline" viewBox="0 0 80 22" width="80" height="22"><text x="40" y="14" fill="rgba(255,255,255,0.2)" font-size="7" text-anchor="middle">SEM DADOS</text></svg>`;
        }
        const W = 80, H = 22;
        const min = Math.min(...data), max = Math.max(...data);
        const range = (max - min) || 1;
        const pts = data.map((v, i) => {
            const x = (i / (data.length - 1)) * W;
            const y = H - 2 - ((v - min) / range) * (H - 4);
            return `${x.toFixed(1)},${y.toFixed(1)}`;
        }).join(' ');
        return `<svg class="sparkline" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}">
            <polyline points="${pts}" fill="none" stroke="${color}" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round" opacity="0.9"/>
        </svg>`;
    }

    /**
     * Renders a metric card with inline sparkline for the government panel.
     */
    govMetricCard(label, value, history, color, goodDir) {
        const numVal = parseFloat(value);
        let valueClass = '';
        if (!isNaN(numVal)) {
            if (goodDir === '+') {
                if (numVal > 70) valueClass = 'val-good';
                else if (numVal < 35) valueClass = 'val-bad';
            } else {
                if (numVal > 65) valueClass = 'val-bad';
                else if (numVal < 25) valueClass = 'val-good';
            }
        }
        return `
        <div class="gov-metric-card">
            <div class="metric-top">
                <span class="metric-label">${label}</span>
                <span class="metric-value ${valueClass}">${value}%</span>
            </div>
            ${this.getSparkline(history, color)}
        </div>`;
    }

    // ---- Modal content generators ----

    getPropagandaHTML(nation) {
        const apoio = nation.apoio_popular || 0;
        const treasury = nation.tesouro || 0;
        const chart = this.renderMiniChart(nation.historico?.apoio_popular, '#00d2ff', 'Apoio Popular (%)');
        const iso = nation.codigo_iso;
        return `
        ${chart}
        <p class="modal-current">Valor atual: <strong style="color:var(--accent-primary)">${apoio.toFixed(1)}%</strong></p>
        <div class="action-options">
            <div class="option-card">
                <div class="option-badge cost">$5B</div>
                <h4>Propaganda Leve</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">Apoio +5%</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','propaganda_leve')">EXECUTAR</button>
            </div>
            <div class="option-card">
                <div class="option-badge cost">$10B</div>
                <h4>Propaganda Moderada</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">Apoio +10%</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','propaganda')">EXECUTAR</button>
            </div>
            <div class="option-card">
                <div class="option-badge cost">$20B</div>
                <h4>Propaganda Massiva</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">Apoio +20%</span>
                    <span class="effect-tag negative">Felicidade −5%</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','propaganda_massiva')">EXECUTAR</button>
            </div>
        </div>
        <p class="treasury-display">Tesouro disponível: <strong>$${treasury.toFixed(0)}B</strong></p>`;
    }

    getAntiCorruptionHTML(nation) {
        const corrupcao = nation.corrupcao || 0;
        const treasury = nation.tesouro || 0;
        const chart = this.renderMiniChart(nation.historico?.corrupcao, '#ff3333', 'Corrupção (%)');
        const iso = nation.codigo_iso;
        return `
        ${chart}
        <p class="modal-current">Nível atual: <strong style="color:var(--accent-threat)">${corrupcao.toFixed(1)}%</strong></p>
        <div class="action-options">
            <div class="option-card">
                <div class="option-badge cost">$10B</div>
                <h4>Investigação Leve</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">Corrupção −5%</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','combater_corrupcao_leve')">EXECUTAR</button>
            </div>
            <div class="option-card">
                <div class="option-badge cost">$20B</div>
                <h4>Operação Anticorrupção</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">Corrupção −15%</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','combater_corrupcao')">EXECUTAR</button>
            </div>
            <div class="option-card">
                <div class="option-badge cost">$40B</div>
                <h4>Purga Total</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">Corrupção −30%</span>
                    <span class="effect-tag negative">Burocracia −10%</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','combater_corrupcao_massiva')">EXECUTAR</button>
            </div>
        </div>
        <p class="treasury-display">Tesouro disponível: <strong>$${treasury.toFixed(0)}B</strong></p>`;
    }

    getReformaPoliticaHTML(nation) {
        const estab = nation.estabilidade_politica || 0;
        const treasury = nation.tesouro || 0;
        const chart = this.renderMiniChart(nation.historico?.estabilidade, '#00d2ff', 'Estabilidade Política (%)');
        const iso = nation.codigo_iso;
        return `
        ${chart}
        <p class="modal-current">Estabilidade atual: <strong style="color:var(--accent-primary)">${estab.toFixed(1)}%</strong></p>
        <div class="action-options" style="grid-template-columns:1fr 1fr">
            <div class="option-card">
                <div class="option-badge free">Grátis</div>
                <h4>Reforma Simples</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">Estabilidade +5%</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','reforma_politica')">EXECUTAR</button>
            </div>
            <div class="option-card">
                <div class="option-badge cost">$30B</div>
                <h4>Reforma Profunda</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">Estabilidade +12%</span>
                    <span class="effect-tag positive">Felicidade +5%</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','reforma_politica_profunda')">EXECUTAR</button>
            </div>
        </div>
        <p class="treasury-display">Tesouro disponível: <strong>$${treasury.toFixed(0)}B</strong></p>`;
    }

    getPoliticaFiscalHTML(nation) {
        const treasury = nation.tesouro || 0;
        const pib = (nation.pib_bilhoes_usd / 1000).toFixed(2);
        const inflacao = nation.inflacao || 0;
        const inflacaoColor = inflacao > 50 ? '#ff3333' : inflacao > 25 ? '#ffaa00' : inflacao > 10 ? '#ffd700' : '#00ff88';
        const chart = this.renderMiniChart(nation.historico?.felicidade, '#00ff88', 'Felicidade (%)');
        const iso = nation.codigo_iso;
        return `
        ${chart}
        <div class="fiscal-summary">
            <div class="fiscal-item">
                <span class="fiscal-label">Tesouro Nacional</span>
                <span class="fiscal-value">$${treasury.toFixed(0)}B</span>
            </div>
            <div class="fiscal-item">
                <span class="fiscal-label">Felicidade</span>
                <span class="fiscal-value">${(nation.felicidade || 0).toFixed(1)}%</span>
            </div>
            <div class="fiscal-item">
                <span class="fiscal-label">PIB</span>
                <span class="fiscal-value">$${pib}T</span>
            </div>
            <div class="fiscal-item">
                <span class="fiscal-label">Inflação</span>
                <span class="fiscal-value" style="color:${inflacaoColor}">${inflacao.toFixed(1)}%${inflacao > 50 ? ' ⚠️' : ''}</span>
            </div>
        </div>
        <div class="action-options" style="grid-template-columns:1fr 1fr">
            <div class="option-card">
                <div class="option-badge income">+$30B</div>
                <h4>Austeridade Fiscal</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">Tesouro +$30B</span>
                    <span class="effect-tag negative">PIB −0.5%</span>
                    <span class="effect-tag negative">Felicidade −5%</span>
                    <span class="effect-tag negative">Estabilidade −3%</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','politica_fiscal_austeridade')">EXECUTAR</button>
            </div>
            <div class="option-card">
                <div class="option-badge cost">$80B</div>
                <h4>Estímulo Fiscal</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">PIB +2%</span>
                    <span class="effect-tag positive">Felicidade +5%</span>
                    <span class="effect-tag negative">Corrupção +2%</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','politica_fiscal_estimulo')">EXECUTAR</button>
            </div>
        </div>`;
    }

    getReformaBurocraciaHTML(nation) {
        const buro = nation.burocracia_eficiencia || 0;
        const treasury = nation.tesouro || 0;
        const chart = this.renderMiniChart(nation.historico?.burocracia, '#ffaa00', 'Eficiência Burocrática (%)');
        const iso = nation.codigo_iso;
        return `
        ${chart}
        <p class="modal-current">Eficiência atual: <strong style="color:var(--accent-warning)">${buro.toFixed(1)}%</strong></p>
        <div class="action-options" style="grid-template-columns:1fr 1fr">
            <div class="option-card">
                <div class="option-badge cost">$15B</div>
                <h4>Digitalização</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">Eficiência +10%</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','reforma_burocracia_leve')">EXECUTAR</button>
            </div>
            <div class="option-card">
                <div class="option-badge cost">$30B</div>
                <h4>Reforma Total</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">Eficiência +20%</span>
                    <span class="effect-tag positive">Corrupção −5%</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','reforma_burocracia')">EXECUTAR</button>
            </div>
        </div>
        <p class="treasury-display">Tesouro disponível: <strong>$${treasury.toFixed(0)}B</strong></p>`;
    }

    getAlocacaoOrcamentoHTML(nation) {
        const iso = nation.codigo_iso;
        const treasury = nation.tesouro || 0;
        const sp = nation.gasto_social || {};
        const saude   = sp.saude   || 0;
        const edu     = sp.educacao || 0;
        const seguro  = sp.previdencia || 0;
        const seg     = sp.seguranca || 0;
        const total   = saude + edu + seguro + seg || 1;
        const pct = v => ((v / total) * 100).toFixed(0);
        const bar = (label, val, color, action) => `
            <div class="spend-row">
                <span class="spend-label">${label}</span>
                <div class="spend-bar-track"><div class="spend-bar-fill" style="width:${pct(val)}%;background:${color}"></div></div>
                <span class="spend-val" style="color:${color}">$${val.toFixed(0)}B</span>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','${action}')">+$20B</button>
            </div>`;
        return `
        <p class="modal-current" style="margin-bottom:12px">Redistribua recursos do orçamento social. Cada +$20B aumenta o setor correspondente e seus bônus.</p>
        ${bar('🏥 Saúde',        saude,  '#00ff88', 'investir_saude')}
        ${bar('📚 Educação',     edu,    '#00d2ff', 'investir_educacao')}
        ${bar('🏦 Previdência',  seguro, '#ffaa00', 'investir_previdencia')}
        ${bar('👮 Segurança',    seg,    '#ff8844', 'investir_seguranca')}
        <div class="fiscal-summary" style="margin-top:14px">
            <div class="fiscal-item"><span class="fiscal-label">Efeito Saúde</span><span class="fiscal-value" style="color:#00ff88">Felicidade ↑</span></div>
            <div class="fiscal-item"><span class="fiscal-label">Efeito Edu</span><span class="fiscal-value" style="color:#00d2ff">Ciência ↑</span></div>
            <div class="fiscal-item"><span class="fiscal-label">Efeito Seg</span><span class="fiscal-value" style="color:#ff8844">Estabilidade ↑</span></div>
        </div>
        <p class="treasury-display">Tesouro disponível: <strong>$${treasury.toFixed(0)}B</strong></p>`;
    }

    getPoderesEmergenciaHTML(nation) {
        const iso = nation.codigo_iso;
        const isActive = nation.poderes_emergencia_ativo || false;
        const estab    = (nation.estabilidade_politica || 0).toFixed(1);
        const apoio    = (nation.apoio_popular || 0).toFixed(1);
        return `
        <p class="modal-current" style="margin-bottom:12px">
            Status: <strong style="color:${isActive?'var(--accent-threat)':'var(--accent-secondary)'}">${isActive?'ATIVO':'INATIVO'}</strong><br>
            <span style="font-size:0.72rem;color:var(--text-secondary)">Poderes de emergência suspendem processos democráticos normais. Cada turno ativo: Estabilidade −3, Corrupção +2.</span>
        </p>
        <div class="fiscal-summary" style="margin-bottom:14px">
            <div class="fiscal-item"><span class="fiscal-label">Estabilidade</span><span class="fiscal-value">${estab}%</span></div>
            <div class="fiscal-item"><span class="fiscal-label">Apoio Popular</span><span class="fiscal-value">${apoio}%</span></div>
        </div>
        <div class="action-options" style="grid-template-columns:1fr 1fr">
            <div class="option-card">
                <div class="option-badge free">${isActive?'Ativo':'Inativo'}</div>
                <h4>Ativar Poderes</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">Controle total</span>
                    <span class="effect-tag negative">Estabilidade −5/turno</span>
                    <span class="effect-tag negative">Apoio −8</span>
                </div>
                <button class="action-btn small" style="${isActive?'opacity:0.4':''}"
                    onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','ativar_emergencia')"
                    ${isActive?'disabled':''}>ATIVAR</button>
            </div>
            <div class="option-card">
                <div class="option-badge free">${!isActive?'Inativo':'Ativo'}</div>
                <h4>Desativar Poderes</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">Estabilidade +10</span>
                    <span class="effect-tag positive">Apoio +5</span>
                </div>
                <button class="action-btn small" style="${!isActive?'opacity:0.4':''}"
                    onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','desativar_emergencia')"
                    ${!isActive?'disabled':''}>DESATIVAR</button>
            </div>
        </div>`;
    }

    getEarlyElectionsHTML(nation) {
        const proxima = nation.proxima_eleicao_turno;
        const intervalo = nation.intervalo_eleicoes;
        const apoio = nation.apoio_popular || 0;
        const treasury = nation.tesouro || 0;
        const chart = this.renderMiniChart(nation.historico?.apoio_popular, '#00d2ff', 'Apoio Popular (%)');
        const iso = nation.codigo_iso;
        const eleicaoInfo = proxima === null
            ? `<p class="modal-current" style="color:var(--text-dim)">Eleições indefinidas para este regime.</p>`
            : `<p class="modal-current">Próxima eleição em <strong>${proxima}</strong> turnos (intervalo: ${intervalo}). Apoio atual: <strong style="color:var(--accent-primary)">${apoio.toFixed(1)}%</strong></p>`;
        return `
        ${chart}
        ${eleicaoInfo}
        <div class="action-options" style="grid-template-columns:1fr 1fr">
            <div class="option-card">
                <div class="option-badge free">Grátis</div>
                <h4>Eleições Antecipadas</h4>
                <div class="option-effects">
                    <span class="effect-tag" style="color:var(--accent-warning);background:rgba(255,170,0,0.1)">Resultado: ${apoio.toFixed(0)}% apoio</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','eleicoes_antecipadas')">CONVOCAR</button>
            </div>
            <div class="option-card">
                <div class="option-badge cost">$5B</div>
                <h4>Adiar Eleições</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">+5 turnos</span>
                    <span class="effect-tag positive">Estabilidade +5%</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','adiar_eleicoes')">ADIAR</button>
            </div>
        </div>
        <p class="treasury-display">Tesouro disponível: <strong>$${treasury.toFixed(0)}B</strong></p>`;
    }

    switchPanel(panel) {
        this.currentPanel = panel;
        // Only toggle active state for side menu buttons
        document.querySelectorAll('#side-menu .nav-btn').forEach(btn => {
            btn.classList.toggle('active', btn.getAttribute('data-panel') === panel);
        });

        // News and Espionagem panels handle their own rendering
        if (panel === 'news') { this.renderNewsPanel(); return; }
        if (panel === 'espionagem') {
            if (this.engine.state.selectedNation) {
                this.renderPanel('espionagem', this.engine.state.selectedNation);
            } else {
                this.renderGlobalOverview();
            }
            return;
        }

        if (this.engine.state.selectedNation) {
            this.renderPanel(panel, this.engine.state.selectedNation);
        } else {
            this.renderGlobalOverview();
        }
    }

    renderGlobalOverview() {
        const details = document.getElementById('nation-details');
        if (!details) return;

        details.innerHTML = `
            <div style="text-align: center; color: var(--text-secondary); margin-top: 50px; padding: 20px;">
                <h3 style="color: var(--accent-primary); margin-bottom: 20px;">SITUAÇÃO MUNDIAL</h3>
                <p style="font-size: 0.85rem; line-height: 1.6;">O mundo enfrenta um período de transição multipolar. Selecione uma nação específica no mapa para obter inteligência detalhada e capacidade de intervenção.</p>
                <div class="data-grid" style="margin-top: 30px;">
                    <div class="data-card"><span class="label">Poder Global</span><span class="value">Multipolar</span></div>
                    <div class="data-card"><span class="label">Tensões</span><span class="value">Médias/Altas</span></div>
                </div>
            </div>
        `;
    }

    // ─── NEWS PANEL ──────────────────────────────────────────────────────────

    renderNewsPanel(activeCat = 'all') {
        const details = document.getElementById('nation-details');
        if (!details) return;

        const nm      = this.engine.news;
        const cats    = NewsManager.CATEGORIES;
        const news    = nm ? nm.getNews(40, activeCat) : [];
        const unread  = nm ? nm.unreadCount : 0;
        if (nm) nm.markAllRead();

        // Update badge on side menu button
        this._updateNewsBadge(0);

        const catKeys = Object.keys(cats);

        // Category filter pills
        const filterHTML = `
            <button class="news-filter-btn ${activeCat === 'all' ? 'active' : ''}"
                    onclick="engine.ui.renderNewsPanel('all')">Todos</button>
            ${catKeys.map(k => `
                <button class="news-filter-btn ${activeCat === k ? 'active' : ''}"
                        onclick="engine.ui.renderNewsPanel('${k}')"
                        style="border-color:${activeCat === k ? cats[k].color : ''}; color:${activeCat === k ? cats[k].color : ''}">
                    ${cats[k].icon} ${cats[k].label}
                </button>
            `).join('')}
        `;

        // News cards
        const cardsHTML = news.length === 0
            ? `<div class="news-empty">📡 Nenhuma notícia disponível nesta categoria. Avance o turno para gerar inteligência mundial.</div>`
            : news.map(n => `
                <div class="news-card urgency-${n.urgency}">
                    <div class="news-card-top">
                        ${n.urgency === 'critical' ? '<span class="breaking-badge">URGENTE</span>' : ''}
                        <span class="news-cat-badge"
                              style="background:${n.catBg};color:${n.catColor};border:1px solid ${n.catColor}40">
                            ${n.catIcon} ${n.catLabel}
                        </span>
                        <span class="news-date-tag">${n.date}</span>
                    </div>
                    <div class="news-headline">${n.headline}</div>
                    ${n.body ? `<div class="news-body">${n.body}</div>` : ''}
                </div>
            `).join('');

        details.innerHTML = `
            <div style="padding: 4px 0;">
                <div class="news-panel-header">
                    <span class="news-panel-title">📡 Feed Mundial de Inteligência</span>
                    <span class="news-panel-date">T${this.engine.state.currentTurn} — Q${this.engine.state.date.quarter} ${this.engine.state.date.year}</span>
                </div>
                <div class="news-filter-bar">${filterHTML}</div>
                <div class="news-feed">${cardsHTML}</div>
            </div>
        `;
    }

    _updateNewsBadge(count) {
        const btn = document.querySelector('#side-menu .nav-btn[data-panel="news"]');
        if (!btn) return;
        let badge = btn.querySelector('.news-badge');
        if (count > 0) {
            if (!badge) {
                badge = document.createElement('span');
                badge.className = 'news-badge';
                badge.style.cssText = `
                    position:absolute; top:6px; right:6px;
                    background:var(--accent-threat); color:white;
                    font-size:0.5rem; font-weight:800;
                    border-radius:8px; padding:1px 4px;
                    font-family:var(--font-data);
                    animation:pulse 1.5s infinite;
                `;
                btn.style.position = 'relative';
                btn.appendChild(badge);
            }
            badge.textContent = count > 99 ? '99+' : count;
        } else if (badge) {
            badge.remove();
        }
    }

    updateNewsTicker() {
        const nm = this.engine.news;
        if (!nm) return;
        const track = document.getElementById('news-ticker-track');
        if (!track) return;

        const items  = nm.getTickerItems(20);
        if (!items.length) return;

        // Duplicate list for seamless loop
        const makeItems = list => list.map(n => `
            <span class="ticker-item urgency-${n.urgency}">
                <span class="t-cat" style="background:${n.catBg};color:${n.catColor}">${n.catIcon} ${n.catLabel}</span>
                <span class="t-text">${n.headline}</span>
            </span>
        `).join('');

        track.innerHTML = `
            <div id="news-ticker-inner">
                ${makeItems(items)}${makeItems(items)}
            </div>
        `;
    }

    renderPanel(type, nation) {
        try {
            const details = document.getElementById('nation-details');
            if (!details) return;

            // Limpa e prepara o container
            const leaderName = this.engine.aiManager?.getLeaderName(nation);
            const leaderHTML = leaderName
                ? `<div class="data-card" style="grid-column:1/-1"><span class="label">Lider (2024)</span><span class="value" style="color:var(--accent-secondary)">${leaderName}</span></div>`
                : '';
            const inflacaoVal = (nation.inflacao || 0).toFixed(1);
            const inflacaoColor = (nation.inflacao || 0) > 25 ? '#ffaa00' : (nation.inflacao || 0) > 50 ? '#ff3333' : 'inherit';
            details.innerHTML = `
                <div id="panel-content">
                    <h2 style="color: var(--accent-primary)">${nation.nome}</h2>
                    <div class="data-grid" id="main-data-summary">
                        <div class="data-card"><span class="label">Capital</span><span class="value">${nation.capital || "---"}</span></div>
                        <div class="data-card"><span class="label">Regime</span><span class="value">${nation.regime_politico || "ESTADO"}</span></div>
                        ${leaderHTML}
                        <div class="data-card"><span class="label">Inflação</span><span class="value" style="color:${inflacaoColor}">${inflacaoVal}%</span></div>
                        <div class="data-card"><span class="label">Apoio Popular</span><span class="value">${(nation.apoio_popular || 0).toFixed(0)}%</span></div>
                    </div>
                    <div id="dynamic-content"></div>
                </div>
            `;

            const dynamic = document.getElementById('dynamic-content');

            // Add selection confirm button if still in SELECTING mode
            if (this.engine.state.gameState === 'SELECTING') {
                const footer = document.createElement('div');
                footer.style.marginTop = '20px';
                footer.style.padding = '15px';
                footer.style.borderTop = '1px dashed var(--glass-border)';
                footer.style.textAlign = 'center';
                footer.className = 'fadeIn';
                footer.innerHTML = `
                    <p style="font-size: 0.7rem; color: var(--accent-secondary); margin-bottom: 15px;">Dossiê analítico ativo. Pronto para assumir o comando?</p>
                    <button class="action-btn" style="background: var(--accent-secondary); color: var(--bg-deep); border: none; width: 100%;" 
                        onclick="engine.confirmNation('${nation.codigo_iso}')">ASSUMIR COMANDO: ${nation.nome}</button>
                `;
                details.appendChild(footer);
            }

            switch(type) {
                case 'history': this.renderHistory(nation, dynamic); break;
                case 'situation': this.renderSituation(nation, dynamic); break;
                case 'government': this.renderGovernment(nation, dynamic); break;
                case 'military': this.renderMilitary(nation, dynamic); break;
                case 'economy': this.renderEconomy(nation, dynamic); break;
                case 'tech': this.renderTech(nation, dynamic); break;
                case 'diplomacy': this.renderDiplomacy(nation, dynamic); break;
                case 'espionagem': this.renderEspionagem(nation, dynamic); break;
            }
        } catch (error) {
            console.error("Erro na renderização do painel:", error);
            const dynamic = document.getElementById('dynamic-content');
            if (dynamic) dynamic.innerHTML = `<p class="text-danger">ERRO DE INTELIGÊNCIA: Dados corrompidos ou incompletos para esta nação.</p>`;
        }
    }

    renderHistory(nation, container) {
        const achievements = nation.conquistas_historicas || ["Nenhuma conquista registrada."];
        
        container.innerHTML = `
            <div class="toggle-container">
                <button class="toggle-btn ${this.historyMode === 'national' ? 'active' : ''}" onclick="engine.ui.toggleHistoryMode('national')">LEGADO NACIONAL</button>
                <button class="toggle-btn ${this.historyMode === 'global' ? 'active' : ''}" onclick="engine.ui.toggleHistoryMode('global')">LINHA DO TEMPO</button>
            </div>
            <div id="history-view-content">
                ${this.historyMode === 'national' ? this.getNationalLegacyHTML(achievements) : this.getGlobalTimelineHTML()}
            </div>
        `;
    }

    getNationalLegacyHTML(achievements) {
        return `
            <div class="section-title">Legado e Conquistas</div>
            <div class="achievement-list">
                ${achievements.map(a => `<div class="history-item">${a}</div>`).join('')}
            </div>
        `;
    }

    getGlobalTimelineHTML() {
        if (!this.engine.data.history || !this.engine.data.history.eventos_historicos) {
            return `<p style="color: var(--text-dim)">Carregando dados históricos...</p>`;
        }

        return `
            <div class="section-title">Crônica Global (1800-2026)</div>
            <div class="timeline-container">
                ${this.engine.data.history.eventos_historicos.map(period => `
                    <div class="timeline-period">
                        <div class="period-header">${period.nome} (${period.periodo})</div>
                        ${period.eventos.map(ev => `
                            <div class="timeline-event">
                                <span class="event-year">${ev.ano}</span>
                                <span class="event-name">${ev.nome}</span>
                                <p class="event-desc">${ev.descricao}</p>
                            </div>
                        `).join('')}
                    </div>
                `).join('')}
            </div>
        `;
    }

    toggleHistoryMode(mode) {
        this.historyMode = mode;
        if (this.engine.state.selectedNation) {
            this.renderHistory(this.engine.state.selectedNation, document.getElementById('dynamic-content'));
        }
    }

    renderSituation(nation, container) {
        const iso        = nation.codigo_iso;
        const allNations = Object.values(this.engine.data.nations);
        const total      = allNations.length;

        // ── Global rankings ───────────────────────────────────────
        const byPib  = [...allNations].sort((a,b) => (b.pib_bilhoes_usd||0) - (a.pib_bilhoes_usd||0));
        const byMil  = [...allNations].sort((a,b) => (b.militar?.poder_militar_global||0) - (a.militar?.poder_militar_global||0));
        const byStab = [...allNations].sort((a,b) => (b.estabilidade_politica||0) - (a.estabilidade_politica||0));
        const rankOf = (sorted) => sorted.findIndex(x => x.codigo_iso === iso) + 1;
        const pibRank  = rankOf(byPib);
        const milRank  = rankOf(byMil);
        const stabRank = rankOf(byStab);

        const rankBar = (rank, label) => {
            const pct = ((total - rank) / total * 100).toFixed(0);
            const col = rank <= 5 ? '#00ff88' : rank <= 20 ? '#ffaa00' : '#8b949e';
            return `<div class="sit-rank-item">
                <span class="sit-rank-label">${label}</span>
                <div class="sit-rank-bar"><div style="width:${pct}%;background:${col}"></div></div>
                <span class="sit-rank-pos" style="color:${col}">#${rank}</span>
            </div>`;
        };

        // ── Top 10 power table ────────────────────────────────────
        const top10 = byMil.slice(0, 10);
        const tableRows = top10.map((n, i) => {
            const isThis  = n.codigo_iso === iso;
            const relVal  = nation.relacoes?.[n.codigo_iso];
            const relCol  = relVal > 30 ? '#00ff88' : relVal < -30 ? '#ff4444' : '#8b949e';
            const relTxt  = relVal !== undefined ? `${relVal > 0 ? '+' : ''}${relVal}` : '—';
            const nukes   = n.militar?.armas_nucleares > 0 ? ' ☢' : '';
            return `<div class="sit-row${isThis ? ' sit-row-self' : ''}">
                <span class="sit-col-rank">${i+1}</span>
                <span class="sit-col-name">${n.nome.length > 18 ? n.nome.slice(0,17)+'…' : n.nome}${nukes}</span>
                <span class="sit-col-mil">${Math.floor(n.militar?.poder_militar_global||0)}</span>
                <span class="sit-col-pib">$${((n.pib_bilhoes_usd||0)/1000).toFixed(1)}T</span>
                <span class="sit-col-rel" style="color:${relCol}">${relTxt}</span>
            </div>`;
        }).join('');

        // ── Threat assessment ─────────────────────────────────────
        const threats = allNations
            .filter(n => n.codigo_iso !== iso)
            .map(n => {
                const rel   = nation.relacoes?.[n.codigo_iso] || 0;
                const score = (n.militar?.poder_militar_global || 0) * 0.5
                            - (rel + 100) * 0.25
                            + (n.militar?.armas_nucleares || 0) * 40;
                return { n, score, rel };
            })
            .sort((a,b) => b.score - a.score)
            .slice(0, 6);

        const threatHTML = threats.map(({n, score, rel}) => {
            const lvl = score > 200 ? 'CRÍTICA' : score > 100 ? 'ALTA' : score > 50 ? 'MÉDIA' : 'BAIXA';
            const col = score > 200 ? '#ff4444' : score > 100 ? '#ff8844' : score > 50 ? '#ffaa00' : '#8b949e';
            return `<div class="sit-threat-row">
                <div class="sit-threat-info">
                    <span class="sit-threat-name">${n.nome}</span>
                    <span class="sit-threat-sub">Poder ${Math.floor(n.militar?.poder_militar_global||0)} · Relação ${rel>0?'+':''}${rel}</span>
                </div>
                <span class="sit-threat-lv" style="color:${col};border-color:${col}40">${lvl}</span>
            </div>`;
        }).join('');

        // ── Conflicts ─────────────────────────────────────────────
        const conflicts = this.engine.getConflictsForNation(iso);
        const conflictHTML = conflicts.length
            ? conflicts.map(c => {
                const g = c.gravidade || 0;
                const col = g >= 80 ? '#ff4444' : g >= 50 ? '#ffaa00' : '#8b949e';
                return `<div class="sit-conflict-row">
                    <span class="sit-conflict-type" style="color:${col}">${c.tipo}</span>
                    <span class="sit-conflict-name">${c.nome}</span>
                    <div class="progress-container" style="flex:1;margin:0 8px"><div class="progress-bar" style="width:${g}%;background:${col}"></div></div>
                    <span style="color:${col};font-size:0.6rem;font-family:var(--font-data)">${g}/100</span>
                </div>`;
            }).join('')
            : `<p style="color:var(--text-dim);font-size:0.78rem">Nenhum conflito ativo detectado.</p>`;

        // ── Global crisis alerts ──────────────────────────────────
        const crises = allNations
            .filter(n => n.codigo_iso !== iso && (
                (n.estabilidade_politica || 50) < 25 ||
                (n.corrupcao || 0) > 88 ||
                (n.em_guerra?.length > 0)
            ))
            .slice(0, 6);
        const crisisHTML = crises.length
            ? crises.map(n => {
                const war  = n.em_guerra?.length > 0;
                const tag  = war ? '⚔️ Em Guerra' : (n.estabilidade_politica || 50) < 25 ? '⚠️ Colapsando' : '🔴 Crise Política';
                const col  = war ? '#ff4444' : '#ffaa00';
                return `<div class="sit-crisis-row">
                    <span class="sit-crisis-tag" style="color:${col}">${tag}</span>
                    <span class="sit-crisis-name">${n.nome}</span>
                    <span class="sit-crisis-val" style="color:${col}">Est. ${Math.floor(n.estabilidade_politica||0)}%</span>
                </div>`;
            }).join('')
            : `<p style="color:var(--text-dim);font-size:0.78rem">Nenhuma crise crítica global ativa.</p>`;

        // ── Personality ───────────────────────────────────────────
        const pers = nation.personalidade || 'agressivo';
        let personaHTML = '';
        if (this.engine.aiManager?.personalities) {
            const p = this.engine.aiManager.personalities[pers];
            if (p) personaHTML = `
                <div class="section-title">Perfil Geopolítico</div>
                <div class="sit-persona-card" style="border-left:3px solid ${p.cor||'#00d2ff'}">
                    <span class="sit-persona-name" style="color:${p.cor||'#00d2ff'}">${p.nome}</span>
                    <span class="sit-persona-desc">${p.descricao}</span>
                </div>`;
        }

        container.innerHTML = `
            ${personaHTML}

            <div class="section-title" style="margin-top:10px">Posição Global</div>
            <div class="sit-ranks">
                ${rankBar(pibRank,  'PIB')}
                ${rankBar(milRank,  'Militar')}
                ${rankBar(stabRank, 'Estabilidade')}
            </div>

            <div class="section-title" style="margin-top:14px">Top 10 — Potências Militares</div>
            <div class="sit-table">
                <div class="sit-header">
                    <span class="sit-col-rank">#</span>
                    <span class="sit-col-name">Nação</span>
                    <span class="sit-col-mil">Militar</span>
                    <span class="sit-col-pib">PIB</span>
                    <span class="sit-col-rel">Relação</span>
                </div>
                ${tableRows}
            </div>

            <div class="section-title" style="margin-top:14px">Avaliação de Ameaças</div>
            <div class="sit-threats">${threatHTML}</div>

            <div class="section-title" style="margin-top:14px">Conflitos Ativos</div>
            <div class="sit-conflicts">${conflictHTML}</div>

            <div class="section-title" style="margin-top:14px">Alertas de Crise Global</div>
            <div class="sit-crises">${crisisHTML}</div>
        `;
    }

    renderGovernment(nation, container) {
        const fmt = v => (v !== undefined ? v.toFixed(1) : '---');
        const estabilidade = fmt(nation.estabilidade_politica);
        const apoio       = fmt(nation.apoio_popular);
        const corrupcao   = fmt(nation.corrupcao);
        const burocracia  = fmt(nation.burocracia_eficiencia);
        const felicidade  = fmt(nation.felicidade);
        const treasury    = nation.tesouro || 0;
        const iso = nation.codigo_iso;

        const isPlayer = this.engine.state.gameState === 'PLAYING' &&
                         this.engine.state.playerNation?.codigo_iso === iso;

        let eleicaoHTML = '';
        if (nation.isDemocratic && nation.isDemocratic()) {
            const proxima = nation.proxima_eleicao_turno;
            eleicaoHTML = `<div class="data-card"><span class="label">Próxima Eleição</span><span class="value">${proxima !== null ? proxima + ' turnos' : 'Indefinido'}</span></div>`;
        }

        const actionsHTML = isPlayer ? `
        <div class="section-title">Ações de Governo</div>
        <div class="gov-actions-grid">
            <button class="gov-action-btn" onclick="engine.ui.showGovernmentModal('propaganda','${iso}')">
                <span class="gov-action-name">Propaganda</span>
                <span class="gov-action-cost">$5 – $20B</span>
                <span class="gov-action-effect">Apoio Popular ↑</span>
            </button>
            <button class="gov-action-btn" onclick="engine.ui.showGovernmentModal('combater_corrupcao','${iso}')">
                <span class="gov-action-name">Anti-Corrupção</span>
                <span class="gov-action-cost">$10 – $40B</span>
                <span class="gov-action-effect">Corrupção ↓</span>
            </button>
            <button class="gov-action-btn" onclick="engine.ui.showGovernmentModal('reforma_politica','${iso}')">
                <span class="gov-action-name">Reforma Política</span>
                <span class="gov-action-cost">Grátis / $30B</span>
                <span class="gov-action-effect">Estabilidade ↑</span>
            </button>
            <button class="gov-action-btn" onclick="engine.ui.showGovernmentModal('politica_fiscal','${iso}')">
                <span class="gov-action-name">Política Fiscal</span>
                <span class="gov-action-cost">−$30B / +$80B</span>
                <span class="gov-action-effect">PIB / Tesouro</span>
            </button>
            <button class="gov-action-btn" onclick="engine.ui.showGovernmentModal('reforma_burocracia','${iso}')">
                <span class="gov-action-name">Burocracia</span>
                <span class="gov-action-cost">$15 – $30B</span>
                <span class="gov-action-effect">Eficiência ↑</span>
            </button>
            <button class="gov-action-btn" onclick="engine.ui.showGovernmentModal('alocacao_orcamento','${iso}')">
                <span class="gov-action-name">Alocação Orçamentária</span>
                <span class="gov-action-cost">Redistribuição</span>
                <span class="gov-action-effect">Saúde/Edu/Seg ↑</span>
            </button>
            <button class="gov-action-btn" onclick="engine.ui.showGovernmentModal('poderes_emergencia','${iso}')">
                <span class="gov-action-name">Poderes de Emergência</span>
                <span class="gov-action-cost">Grátis</span>
                <span class="gov-action-effect">Controle Total</span>
            </button>
            ${nation.isDemocratic && nation.isDemocratic() ? `
            <button class="gov-action-btn" onclick="engine.ui.showGovernmentModal('eleicoes_antecipadas','${iso}')">
                <span class="gov-action-name">Eleições</span>
                <span class="gov-action-cost">Grátis / $5B</span>
                <span class="gov-action-effect">Democracia</span>
            </button>` : ''}
        </div>
        <p class="treasury-info">Tesouro disponível: <strong class="treasury-val">$${treasury.toFixed(0)}B</strong></p>
        ` : `<p style="color:var(--text-dim);font-size:0.8rem;margin-top:12px">Assuma o comando desta nação para gerenciar o governo.</p>`;

        container.innerHTML = `
            <div class="section-title">Administração</div>
            <div class="data-grid">
                <div class="data-card"><span class="label">Regime</span><span class="value">${nation.regime_politico || 'ESTADO'}</span></div>
                <div class="data-card"><span class="label">Ideologia</span><span class="value">${nation.ideologia_dominante || 'CENTRO'}</span></div>
                ${eleicaoHTML}
            </div>

            <div class="section-title">Indicadores</div>
            <div class="gov-metrics-grid">
                ${this.govMetricCard('Estabilidade',    estabilidade, nation.historico?.estabilidade,   '#00d2ff', '+')}
                ${this.govMetricCard('Apoio Popular',   apoio,        nation.historico?.apoio_popular,   '#00d2ff', '+')}
                ${this.govMetricCard('Corrupção',       corrupcao,    nation.historico?.corrupcao,       '#ff3333', '-')}
                ${this.govMetricCard('Felicidade',      felicidade,   nation.historico?.felicidade,      '#00ff88', '+')}
                ${this.govMetricCard('Efic. Burocrát.', burocracia,  nation.historico?.burocracia,      '#ffaa00', '+')}
            </div>

            ${actionsHTML}
        `;
    }

    renderMilitary(nation, container) {
        const m = nation.militar || {};
        const u = m.unidades || {};
        const iso = nation.codigo_iso;
        const treasury = nation.tesouro || 0;
        const defcon = this.engine.state.defcon || 5;

        const nukes = m.armas_nucleares || 0;
        const poder = (m.poder_militar_global || 0).toFixed(0);
        const orca  = (m.orcamento_militar_bilhoes || 0).toFixed(1);
        const fmtK  = v => v >= 1000 ? (v / 1000).toFixed(0) + 'K' : String(v);

        const isPlayer = this.engine.state.gameState === 'PLAYING' &&
                         this.engine.state.playerNation?.codigo_iso === iso;

        const actionsHTML = isPlayer ? `
        <div class="section-title">Operações</div>
        <div class="gov-actions-grid">
            <button class="gov-action-btn mil-btn" onclick="engine.ui.showMilitaryModal('mil_recrutamento','${iso}')">
                <span class="gov-action-name">Recrutamento</span>
                <span class="gov-action-cost">$3 – $30B</span>
                <span class="gov-action-effect">Unidades ↑</span>
            </button>
            <button class="gov-action-btn mil-btn" onclick="engine.ui.showMilitaryModal('mil_orcamento','${iso}')">
                <span class="gov-action-name">Orçamento</span>
                <span class="gov-action-cost">−$20B / +$15B</span>
                <span class="gov-action-effect">Budget ↑↓</span>
            </button>
            <button class="gov-action-btn mil-btn" onclick="engine.ui.showMilitaryModal('mil_mobilizacao','${iso}')">
                <span class="gov-action-name">Mobilização</span>
                <span class="gov-action-cost">Grátis</span>
                <span class="gov-action-effect">Prontidão ↑↓</span>
            </button>
            <button class="gov-action-btn mil-btn" onclick="engine.ui.showMilitaryModal('mil_armamento','${iso}')">
                <span class="gov-action-name">Armamento</span>
                <span class="gov-action-cost">$40 – $100B</span>
                <span class="gov-action-effect">Poder ↑</span>
            </button>
            <button class="gov-action-btn mil-btn" onclick="engine.ui.showMilitaryModal('mil_ajuda','${iso}')">
                <span class="gov-action-name">Ajuda Militar</span>
                <span class="gov-action-cost">$20 – $80B</span>
                <span class="gov-action-effect">Aliado ↑, Rel ↑</span>
            </button>
            <button class="gov-action-btn mil-btn" style="border-color:rgba(255,51,51,0.4)" onclick="engine.ui.showMilitaryModal('mil_guerra','${iso}')">
                <span class="gov-action-name" style="color:var(--accent-threat)">Declarar Guerra</span>
                <span class="gov-action-cost">Alto Risco</span>
                <span class="gov-action-effect">DEFCON −1</span>
            </button>
            ${(nation.em_guerra||[]).length > 0 ? `
            <button class="gov-action-btn mil-btn" style="border-color:rgba(0,255,136,0.4)" onclick="engine.ui.showMilitaryModal('mil_paz','${iso}')">
                <span class="gov-action-name" style="color:var(--accent-secondary)">Propor Paz</span>
                <span class="gov-action-cost">Grátis</span>
                <span class="gov-action-effect">Rel +40, DEFCON +1</span>
            </button>` : ''}
        </div>
        <p class="treasury-info">Tesouro disponível: <strong class="treasury-val">$${treasury.toFixed(0)}B</strong></p>
        ` : `<p style="color:var(--text-dim);font-size:0.8rem;margin-top:12px">Assuma o comando desta nação para gerenciar operações militares.</p>`;

        container.innerHTML = `
            <div class="section-title">Capacidade Estratégica</div>
            <div class="data-grid">
                <div class="data-card">
                    <span class="label">Poder Militar</span>
                    <span class="value">${poder}</span>
                    ${this.getSparkline(nation.historico?.poder_militar, '#ff3333')}
                </div>
                <div class="data-card">
                    <span class="label">Orçamento</span>
                    <span class="value">$${orca}B</span>
                    ${this.getSparkline(nation.historico?.orcamento_militar, '#ffaa00')}
                </div>
                <div class="data-card">
                    <span class="label">Nukes</span>
                    <span class="value" style="color:${nukes > 0 ? 'var(--accent-threat)' : 'var(--text-secondary)'}">${nukes > 0 ? nukes : 'N/A'}</span>
                </div>
                <div class="data-card">
                    <span class="label">DEFCON</span>
                    <span class="value" style="color:${defcon <= 2 ? 'var(--accent-threat)' : defcon <= 3 ? 'var(--accent-warning)' : 'var(--accent-secondary)'}">DEFCON ${defcon}</span>
                </div>
            </div>

            <div class="section-title">Efetivo e Equipamento</div>
            <div class="gov-metrics-grid">
                ${this.milMetricCard('Infantaria',  fmtK(u.infantaria || 0), nation.historico?.infantaria, '#00d2ff')}
                ${this.milMetricCard('Tanques',     fmtK(u.tanques    || 0), nation.historico?.tanques,    '#ffaa00')}
                ${this.milMetricCard('Força Aérea', fmtK(u.avioes     || 0), nation.historico?.avioes,     '#00ff88')}
                ${this.milMetricCard('Marinha',     fmtK(u.navios     || 0), nation.historico?.navios,     '#00d2ff')}
            </div>

            ${actionsHTML}
        `;
    }

    milMetricCard(label, value, history, color) {
        return `
        <div class="gov-metric-card">
            <div class="metric-top">
                <span class="metric-label">${label}</span>
                <span class="metric-value">${value}</span>
            </div>
            ${this.getSparkline(history, color)}
        </div>`;
    }

    showMilitaryModal(action, nation) {
        const modal = document.getElementById('gov-modal');
        const title = document.getElementById('gov-modal-title');
        const content = document.getElementById('gov-modal-content');
        if (!modal || !title || !content) return;

        const nationObj = typeof nation === 'string' ? this.engine.data.nations[nation] : nation;
        if (!nationObj) return;

        const actionNames = {
            'mil_recrutamento': '⚔️ Recrutamento Militar',
            'mil_orcamento':    '💵 Orçamento Militar',
            'mil_mobilizacao':  '🚀 Mobilização',
            'mil_armamento':    '☢️ Armamento Estratégico',
            'mil_ajuda':        '🤝 Ajuda Militar',
            'mil_guerra':       '⚔️ Declaração de Guerra',
            'mil_paz':          '🕊️ Proposta de Paz'
        };
        title.textContent = actionNames[action] || 'Operação Militar';

        let html = '';
        switch(action) {
            case 'mil_recrutamento': html = this.getMilRecrutamentoHTML(nationObj); break;
            case 'mil_orcamento':    html = this.getMilOrcamentoHTML(nationObj);    break;
            case 'mil_mobilizacao':  html = this.getMilMobilizacaoHTML(nationObj);  break;
            case 'mil_armamento':    html = this.getMilArmamentoHTML(nationObj);    break;
            case 'mil_ajuda':        html = this.getMilAjudaHTML(nationObj);        break;
            case 'mil_guerra':       html = this.getMilGuerraHTML(nationObj);       break;
            case 'mil_paz':          html = this.getMilPazHTML(nationObj);          break;
            default: html = `<p style="color:var(--text-dim)">Operação não disponível.</p>`;
        }
        content.innerHTML = html;
        modal.classList.add('active');
    }

    getMilRecrutamentoHTML(nation) {
        const iso = nation.codigo_iso;
        const u = nation.militar?.unidades || {};
        const treasury = nation.tesouro || 0;
        const fmtK = v => v >= 1000 ? (v / 1000).toFixed(0) + 'K' : String(v);
        return `
        <div class="mil-unit-grid">
            <div class="mil-unit-card">
                <div class="mil-unit-header">
                    <span class="mil-unit-icon">🪖</span>
                    <span class="mil-unit-name">Infantaria</span>
                    <span class="mil-unit-current">${fmtK(u.infantaria || 0)} ativos</span>
                </div>
                ${this.getSparkline(nation.historico?.infantaria, '#00d2ff')}
                <div class="mil-tier-btns">
                    <div class="option-card">
                        <div class="option-badge cost">$3B</div>
                        <div class="option-effects"><span class="effect-tag positive">+5.000</span></div>
                        <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','recrutar_infantaria')">RECRUTAR</button>
                    </div>
                    <div class="option-card">
                        <div class="option-badge cost">$8B</div>
                        <div class="option-effects"><span class="effect-tag positive">+20.000 elite</span></div>
                        <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','recrutar_infantaria_pesada')">RECRUTAR</button>
                    </div>
                </div>
            </div>
            <div class="mil-unit-card">
                <div class="mil-unit-header">
                    <span class="mil-unit-icon">🛡️</span>
                    <span class="mil-unit-name">Blindados</span>
                    <span class="mil-unit-current">${fmtK(u.tanques || 0)} ativos</span>
                </div>
                ${this.getSparkline(nation.historico?.tanques, '#ffaa00')}
                <div class="mil-tier-btns">
                    <div class="option-card">
                        <div class="option-badge cost">$5B</div>
                        <div class="option-effects"><span class="effect-tag positive">+100 tanques</span></div>
                        <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','recrutar_tanques')">RECRUTAR</button>
                    </div>
                    <div class="option-card">
                        <div class="option-badge cost">$15B</div>
                        <div class="option-effects"><span class="effect-tag positive">+200 avançados</span><span class="effect-tag positive">Poder +5</span></div>
                        <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','recrutar_tanques_avancados')">RECRUTAR</button>
                    </div>
                </div>
            </div>
            <div class="mil-unit-card">
                <div class="mil-unit-header">
                    <span class="mil-unit-icon">✈️</span>
                    <span class="mil-unit-name">Força Aérea</span>
                    <span class="mil-unit-current">${fmtK(u.avioes || 0)} ativos</span>
                </div>
                ${this.getSparkline(nation.historico?.avioes, '#00ff88')}
                <div class="mil-tier-btns">
                    <div class="option-card">
                        <div class="option-badge cost">$10B</div>
                        <div class="option-effects"><span class="effect-tag positive">+50 caças</span></div>
                        <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','recrutar_avioes')">RECRUTAR</button>
                    </div>
                    <div class="option-card">
                        <div class="option-badge cost">$25B</div>
                        <div class="option-effects"><span class="effect-tag positive">+20 furtivos</span><span class="effect-tag positive">Poder +8</span></div>
                        <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','recrutar_avioes_furtivos')">RECRUTAR</button>
                    </div>
                </div>
            </div>
            <div class="mil-unit-card">
                <div class="mil-unit-header">
                    <span class="mil-unit-icon">⚓</span>
                    <span class="mil-unit-name">Marinha</span>
                    <span class="mil-unit-current">${fmtK(u.navios || 0)} ativos</span>
                </div>
                ${this.getSparkline(nation.historico?.navios, '#00d2ff')}
                <div class="mil-tier-btns">
                    <div class="option-card">
                        <div class="option-badge cost">$15B</div>
                        <div class="option-effects"><span class="effect-tag positive">+5 navios</span></div>
                        <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','recrutar_navios')">RECRUTAR</button>
                    </div>
                    <div class="option-card">
                        <div class="option-badge cost">$30B</div>
                        <div class="option-effects"><span class="effect-tag positive">+3 destróieres</span><span class="effect-tag positive">Poder +10</span></div>
                        <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','recrutar_navios_guerra')">RECRUTAR</button>
                    </div>
                </div>
            </div>
        </div>
        <p class="treasury-display">Tesouro disponível: <strong>$${treasury.toFixed(0)}B</strong></p>`;
    }

    getMilOrcamentoHTML(nation) {
        const iso = nation.codigo_iso;
        const treasury = nation.tesouro || 0;
        const orca = (nation.militar?.orcamento_militar_bilhoes || 0).toFixed(1);
        const chart = this.renderMiniChart(nation.historico?.orcamento_militar, '#ffaa00', 'Orçamento Militar ($B)');
        return `
        ${chart}
        <p class="modal-current">Orçamento atual: <strong style="color:var(--accent-warning)">$${orca}B</strong></p>
        <div class="action-options" style="grid-template-columns:1fr 1fr">
            <div class="option-card">
                <div class="option-badge cost">$20B</div>
                <h4>Ampliar Orçamento</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">Budget +20%</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','aumentar_orcamento_militar')">EXECUTAR</button>
            </div>
            <div class="option-card">
                <div class="option-badge income">+$15B</div>
                <h4>Cortar Orçamento</h4>
                <div class="option-effects">
                    <span class="effect-tag negative">Budget −20%</span>
                    <span class="effect-tag positive">Tesouro +$15B</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','cortar_orcamento_militar')">EXECUTAR</button>
            </div>
        </div>
        <p class="treasury-display">Tesouro disponível: <strong>$${treasury.toFixed(0)}B</strong></p>`;
    }

    getMilMobilizacaoHTML(nation) {
        const iso = nation.codigo_iso;
        const poder = (nation.militar?.poder_militar_global || 0).toFixed(0);
        const estab = (nation.estabilidade_politica || 0).toFixed(1);
        const chart = this.renderMiniChart(nation.historico?.poder_militar, '#ff3333', 'Poder Militar Global');
        return `
        ${chart}
        <div class="fiscal-summary">
            <div class="fiscal-item">
                <span class="fiscal-label">Poder Militar</span>
                <span class="fiscal-value">${poder}</span>
            </div>
            <div class="fiscal-item">
                <span class="fiscal-label">Estabilidade</span>
                <span class="fiscal-value">${estab}%</span>
            </div>
            <div class="fiscal-item">
                <span class="fiscal-label">Orçamento</span>
                <span class="fiscal-value">$${(nation.militar?.orcamento_militar_bilhoes || 0).toFixed(1)}B</span>
            </div>
        </div>
        <div class="action-options" style="grid-template-columns:1fr 1fr">
            <div class="option-card">
                <div class="option-badge" style="background:rgba(255,51,51,0.12);color:var(--accent-threat);border:1px solid rgba(255,51,51,0.3)">Grátis</div>
                <h4>Mobilização Total</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">Budget +10%</span>
                    <span class="effect-tag negative">Estabilidade −2%</span>
                </div>
                <button class="action-btn small" style="border-color:var(--accent-threat);color:var(--accent-threat)"
                    onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','mobilizar')">MOBILIZAR</button>
            </div>
            <div class="option-card">
                <div class="option-badge free">Grátis</div>
                <h4>Desmobilização</h4>
                <div class="option-effects">
                    <span class="effect-tag negative">Budget −10%</span>
                    <span class="effect-tag positive">Estabilidade +3%</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','desmobilizar')">DESMOBILIZAR</button>
            </div>
        </div>`;
    }

    getMilArmamentoHTML(nation) {
        const iso = nation.codigo_iso;
        const treasury = nation.tesouro || 0;
        const nukes = nation.militar?.armas_nucleares || 0;
        const poder = (nation.militar?.poder_militar_global || 0).toFixed(0);
        const defcon = this.engine.state.defcon || 5;
        const chart = this.renderMiniChart(nation.historico?.poder_militar, '#ff3333', 'Poder Militar Global');
        return `
        ${chart}
        <div class="fiscal-summary">
            <div class="fiscal-item">
                <span class="fiscal-label">Poder Militar</span>
                <span class="fiscal-value">${poder}</span>
            </div>
            <div class="fiscal-item">
                <span class="fiscal-label">Arsenal Nuclear</span>
                <span class="fiscal-value" style="color:${nukes > 0 ? 'var(--accent-threat)' : 'var(--text-secondary)'}">
                    ${nukes > 0 ? nukes + ' ogiva' + (nukes > 1 ? 's' : '') : 'N/A'}
                </span>
            </div>
            <div class="fiscal-item">
                <span class="fiscal-label">DEFCON</span>
                <span class="fiscal-value" style="color:${defcon <= 2 ? 'var(--accent-threat)' : defcon <= 3 ? 'var(--accent-warning)' : 'var(--accent-secondary)'}">
                    DEFCON ${defcon}
                </span>
            </div>
        </div>
        <div class="action-options" style="grid-template-columns:1fr 1fr">
            <div class="option-card">
                <div class="option-badge cost">$40B</div>
                <h4>Construir Base Militar</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">Poder +10</span>
                    <span class="effect-tag negative">Estabilidade −2%</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','construir_base')">CONSTRUIR</button>
            </div>
            <div class="option-card">
                <div class="option-badge cost">$100B</div>
                <h4>Desenvolver Nuclear</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">+1 Ogiva Nuclear</span>
                    <span class="effect-tag negative">DEFCON −1</span>
                    <span class="effect-tag negative">Estabilidade −10%</span>
                </div>
                <button class="action-btn small" style="border-color:var(--accent-threat);color:var(--accent-threat)"
                    onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','desenvolver_nuclear')">DESENVOLVER</button>
            </div>
        </div>
        <p class="treasury-display">Tesouro disponível: <strong>$${treasury.toFixed(0)}B</strong></p>`;
    }

    getMilAjudaHTML(nation) {
        const iso = nation.codigo_iso;
        const treasury = nation.tesouro || 0;
        const allNations = Object.values(this.engine.data.nations).filter(n => n.codigo_iso !== iso);
        const sorted = [...allNations].sort((a,b) => {
            const ra = (nation.relacoes||{})[a.codigo_iso]||0;
            const rb = (nation.relacoes||{})[b.codigo_iso]||0;
            return rb - ra;
        });
        const options = sorted.map(n => {
            const rel = (nation.relacoes||{})[n.codigo_iso]||0;
            return `<option value="${n.codigo_iso}">${n.nome} (${rel>=0?'+':''}${rel})</option>`;
        }).join('');
        return `
        <p class="modal-current" style="margin-bottom:14px">
            Envia equipamento e suporte militar a um aliado. Melhora relações e aumenta o poder do parceiro.
        </p>
        <div class="form-row"><label>Nação Parceira</label><select id="ajuda-mil-target">${options}</select></div>
        <div class="action-options" style="grid-template-columns:1fr 1fr 1fr">
            <div class="option-card">
                <div class="option-badge cost">$20B</div>
                <h4>Pequena</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">Poder alvo +8</span>
                    <span class="effect-tag positive">Relações +15</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.enviarAjudaMilitar('${iso}',document.getElementById('ajuda-mil-target').value,20)">ENVIAR</button>
            </div>
            <div class="option-card">
                <div class="option-badge cost">$50B</div>
                <h4>Média</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">Poder alvo +20</span>
                    <span class="effect-tag positive">Relações +15</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.enviarAjudaMilitar('${iso}',document.getElementById('ajuda-mil-target').value,50)">ENVIAR</button>
            </div>
            <div class="option-card">
                <div class="option-badge cost">$80B</div>
                <h4>Grande</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">Poder alvo +35</span>
                    <span class="effect-tag positive">Relações +15</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.enviarAjudaMilitar('${iso}',document.getElementById('ajuda-mil-target').value,80)">ENVIAR</button>
            </div>
        </div>
        <p class="treasury-display">Tesouro disponível: <strong>$${treasury.toFixed(0)}B</strong></p>`;
    }

    getMilGuerraHTML(nation) {
        const iso = nation.codigo_iso;
        const allNations = Object.values(this.engine.data.nations).filter(n => n.codigo_iso !== iso);
        const sorted = [...allNations].sort((a,b) => {
            const ra = (nation.relacoes||{})[a.codigo_iso]||0;
            const rb = (nation.relacoes||{})[b.codigo_iso]||0;
            return ra - rb; // worst relations first
        });
        const options = sorted.map(n => {
            const rel = (nation.relacoes||{})[n.codigo_iso]||0;
            return `<option value="${n.codigo_iso}">${n.nome} (${rel>=0?'+':''}${rel})</option>`;
        }).join('');
        const defcon = this.engine.state.defcon || 5;
        return `
        <div style="background:rgba(255,51,51,0.08);border:1px solid rgba(255,51,51,0.3);padding:12px;border-radius:3px;margin-bottom:14px">
            <p style="color:var(--accent-threat);font-size:0.85rem;font-weight:700;margin-bottom:4px">⚠️ AÇÃO IRREVERSÍVEL</p>
            <p style="font-size:0.78rem;color:var(--text-secondary)">Declarar guerra causa: DEFCON −1, relações −100, resposta global. Use como último recurso estratégico.</p>
        </div>
        <div class="fiscal-summary" style="margin-bottom:14px">
            <div class="fiscal-item"><span class="fiscal-label">DEFCON Atual</span><span class="fiscal-value" style="color:${defcon<=2?'#ff4444':defcon<=3?'#ffaa00':'#8b949e'}">DEFCON ${defcon}</span></div>
            <div class="fiscal-item"><span class="fiscal-label">Após Declaração</span><span class="fiscal-value" style="color:#ff4444">DEFCON ${Math.max(1,defcon-1)}</span></div>
        </div>
        <div class="form-row"><label>Nação Alvo</label><select id="guerra-target">${options}</select></div>
        <button class="action-btn" style="border-color:var(--accent-threat);color:var(--accent-threat);background:rgba(255,51,51,0.1);margin-top:12px;width:100%"
            onclick="engine.ui.hideGovernmentModal();engine.declaraGuerra('${iso}',document.getElementById('guerra-target').value)">
            ⚔️ DECLARAR GUERRA
        </button>`;
    }

    getMilPazHTML(nation) {
        const iso = nation.codigo_iso;
        const emGuerra = (nation.em_guerra || []);
        if (!emGuerra.length) return `<p style="color:var(--text-dim)">Nenhuma guerra ativa.</p>`;
        const options = emGuerra.map(code => {
            const n = this.engine.data.nations[code];
            return `<option value="${code}">${n?.nome || code}</option>`;
        }).join('');
        return `
        <p class="modal-current" style="margin-bottom:14px">
            Propõe cessar-fogo e normalização diplomática com o inimigo selecionado. A aceitação depende das circunstâncias do conflito.
        </p>
        <div class="fiscal-summary" style="margin-bottom:14px">
            <div class="fiscal-item"><span class="fiscal-label">Efeito Relações</span><span class="fiscal-value" style="color:var(--accent-secondary)">+40</span></div>
            <div class="fiscal-item"><span class="fiscal-label">DEFCON</span><span class="fiscal-value" style="color:var(--accent-secondary)">+1</span></div>
        </div>
        <div class="form-row"><label>Nação em Guerra</label><select id="paz-target">${options}</select></div>
        <button class="action-btn" style="border-color:var(--accent-secondary);color:var(--accent-secondary);background:rgba(0,255,136,0.08);margin-top:12px;width:100%"
            onclick="engine.ui.hideGovernmentModal();engine.proporPaz('${iso}',document.getElementById('paz-target').value)">
            🕊️ PROPOR PAZ
        </button>`;
    }

    // ─── Aba ativa do painel de Economia ─────────────────────────────────────
    _ecoTab = 'nacional';

    renderEconomy(nation, container, tab) {
        const iso      = nation.codigo_iso;
        const isPlayer = this.engine.state.gameState === 'PLAYING' &&
                         this.engine.state.playerNation?.codigo_iso === iso;

        // Lembra a aba selecionada
        if (tab) this._ecoTab = tab;
        const activeTab = this._ecoTab || 'nacional';

        // ── Header com abas ────────────────────────────────────────────────
        const tabBtn = (id, label, icon) => `
            <button class="eco-tab-btn ${activeTab === id ? 'active' : ''}"
                    onclick="engine.ui.renderEconomy(engine.state.selectedNation, document.getElementById('dynamic-content'), '${id}')">
                ${icon} ${label}
            </button>`;

        container.innerHTML = `
            <div class="eco-tab-bar">
                ${tabBtn('nacional',  'Nacional',  '📊')}
                ${tabBtn('rotas',     'Rotas',     '🚢')}
                ${tabBtn('empresas',  'Empresas',  '🏢')}
                ${tabBtn('cripto',    'Cripto',    '₿')}
            </div>
            <div id="eco-tab-content"></div>
        `;

        const tabContent = document.getElementById('eco-tab-content');

        switch (activeTab) {
            case 'nacional':  this._renderEcoNacional(nation, tabContent, isPlayer, iso); break;
            case 'rotas':     this._renderEcoRoutes(nation, tabContent, isPlayer); break;
            case 'empresas':  this._renderEcoCompanies(tabContent, isPlayer); break;
            case 'cripto':    this._renderEcoCrypto(tabContent, isPlayer); break;
        }
    }

    // ── ABA NACIONAL (conteúdo original) ─────────────────────────────────────
    _renderEcoNacional(nation, container, isPlayer, iso) {
        const pib    = nation.pib_bilhoes_usd || 0;
        const pibT   = (pib / 1000).toFixed(2);
        const pop    = (nation.populacao || 0) / 1000000;

        // Financial system (quarterly = 1 turn) — use nation methods when available
        const taxRate    = nation.calcTaxRate   ? nation.calcTaxRate()   : 0.22;
        const receita    = nation.calcReceita   ? nation.calcReceita()   : pib * 0.22 / 4;
        const despesas   = nation.calcDespesas  ? nation.calcDespesas()  : (nation.militar?.orcamento_militar_bilhoes || 0) / 4 + pib * 0.10 / 4;
        const saldo      = nation.calcSaldo     ? nation.calcSaldo()     : receita - despesas;
        const tesouro    = nation.tesouro || 0;
        const saldoCol   = saldo >= 0 ? '#00ff88' : '#ff3333';
        const saldoLabel = saldo >= 0 ? 'Superávit' : 'Déficit';

        // Resources
        const recursos = nation.recursos || {};
        const resourceMeta = [
            { key: 'petroleo',      label: 'Petróleo',        color: '#ffaa00' },
            { key: 'gas_natural',   label: 'Gás Natural',     color: '#00d2ff' },
            { key: 'minerios_raros',label: 'Minérios Raros',  color: '#00ff88' },
            { key: 'uranio',        label: 'Urânio',          color: '#ff3333' },
            { key: 'ferro',         label: 'Ferro',           color: '#8b949e' },
            { key: 'terras_araveis',label: 'Terras Aráveis',  color: '#22c55e' }
        ];

        const resourceHTML = resourceMeta.map(({ key, label, color }) => {
            const val = recursos[key] || 0;
            const valClass = val >= 70 ? 'val-good' : val < 35 ? 'val-bad' : '';
            return `
            <div class="resource-row">
                <span class="resource-label">${label}</span>
                <div class="resource-bar-track">
                    <div class="resource-bar-fill" style="width:${val}%;background:${color}"></div>
                </div>
                <span class="resource-pct ${valClass}">${val}%</span>
            </div>`;
        }).join('');

        const actionsHTML = isPlayer ? `
        <div class="section-title">Gestão Econômica</div>
        <div class="gov-actions-grid">
            <button class="gov-action-btn eco-btn" onclick="engine.ui.showEcoModal('eco_infra','${iso}')">
                <span class="gov-action-name">Infraestrutura</span>
                <span class="gov-action-cost">$25 – $100B</span>
                <span class="gov-action-effect">PIB ↑</span>
            </button>
            <button class="gov-action-btn eco-btn" onclick="engine.ui.showEcoModal('eco_comercio','${iso}')">
                <span class="gov-action-name">Política Comercial</span>
                <span class="gov-action-cost">Grátis / $30B</span>
                <span class="gov-action-effect">Exportações ↑</span>
            </button>
            <button class="gov-action-btn eco-btn" onclick="engine.ui.showEcoModal('eco_privat','${iso}')">
                <span class="gov-action-name">Empresas</span>
                <span class="gov-action-cost">$40B / +$30B</span>
                <span class="gov-action-effect">PIB / Tesouro</span>
            </button>
            <button class="gov-action-btn eco-btn" onclick="engine.ui.showEcoModal('eco_recurso','${iso}')">
                <span class="gov-action-name">Recursos</span>
                <span class="gov-action-cost">$20B</span>
                <span class="gov-action-effect">Reservas ↑</span>
            </button>
        </div>
        <p class="treasury-info">Tesouro disponível: <strong class="treasury-val">$${tesouro.toFixed(0)}B</strong></p>
        ` : '';

        container.innerHTML = `
        <div class="section-title">Indicadores Econômicos</div>
        <div class="data-grid">
            <div class="data-card">
                <span class="label">PIB Total</span>
                <span class="value">$${pibT}T</span>
                ${this.getSparkline(nation.historico?.pib, '#00ff88')}
            </div>
            <div class="data-card">
                <span class="label">População</span>
                <span class="value">${pop.toFixed(1)}M</span>
                ${this.getSparkline(nation.historico?.populacao, '#00d2ff')}
            </div>
            <div class="data-card">
                <span class="label">Tesouro</span>
                <span class="value" style="color:${tesouro >= 0 ? 'var(--accent-secondary)' : 'var(--accent-threat)'}">$${tesouro >= 1000 ? (tesouro/1000).toFixed(1)+'T' : tesouro.toFixed(0)+'B'}</span>
                ${this.getSparkline(nation.historico?.tesouro, '#00ff88')}
            </div>
        </div>

        <div class="section-title">Sistema Financeiro <span style="font-size:0.6rem;color:var(--text-dim)">(por trimestre)</span></div>
        <div class="finance-grid">
            <div class="finance-card income">
                <span class="finance-label">Receita Fiscal</span>
                <span class="finance-value">+$${receita.toFixed(0)}B</span>
                <span class="finance-sub">${(taxRate*100).toFixed(0)}% PIB</span>
            </div>
            <div class="finance-card expense">
                <span class="finance-label">Despesas</span>
                <span class="finance-value">-$${despesas.toFixed(0)}B</span>
                <span class="finance-sub">Gov + Militar</span>
            </div>
            <div class="finance-card ${saldo >= 0 ? 'surplus' : 'deficit'}">
                <span class="finance-label">${saldoLabel}</span>
                <span class="finance-value" style="color:${saldoCol}">${saldo >= 0 ? '+' : '-'}$${Math.abs(saldo).toFixed(0)}B</span>
                <span class="finance-sub">${Math.abs((saldo / receita) * 100).toFixed(1)}% receita</span>
            </div>
            <div class="finance-card ${tesouro > 200 ? 'surplus' : 'income'}">
                <span class="finance-label">Tesouro Acumulado</span>
                <span class="finance-value" style="color:var(--accent-secondary)">$${tesouro.toFixed(0)}B</span>
                <span class="finance-sub">${((tesouro/pib)*100).toFixed(1)}% PIB</span>
            </div>
        </div>

        <div class="section-title">Reservas Estratégicas</div>
        <div class="resources-list">
            ${resourceHTML}
        </div>

        ${actionsHTML}
        `;
    }

    // ── ABA ROTAS COMERCIAIS ─────────────────────────────────────────────────
    _renderEcoRoutes(nation, container, isPlayer) {
        const eco    = this.engine.economy;
        if (!eco) { container.innerHTML = '<p class="text-danger">Sistema de rotas não inicializado.</p>'; return; }

        const iso    = nation.codigo_iso;
        const routes = eco.getRoutesForNation(iso);
        const income = eco.getExportIncome(iso);

        const typeColors = { energia:'#ffaa00', alimentos:'#22c55e', minerios:'#a78bfa', manufatura:'#00d2ff', financas:'#fbbf24' };

        const routeCards = routes.map(r => {
            const isExporter = r.from === iso;
            const partner = this.engine.data.nations[isExporter ? r.to : r.from];
            const partnerName = partner?.nome ?? (isExporter ? r.to : r.from);
            const col = typeColors[r.type] || '#8b949e';
            const dir = isExporter ? '↗ Exporta' : '↙ Importa';
            const dirCol = isExporter ? '#00ff88' : '#ff8844';
            return `
            <div class="route-card">
                <div class="route-card-top">
                    <span class="route-type-badge" style="background:${col}22;color:${col};border:1px solid ${col}44">${eco.typeLabel(r.type)}</span>
                    <span class="route-dir" style="color:${dirCol}">${dir}</span>
                </div>
                <div class="route-commodity">${r.commodity}</div>
                <div class="route-partner">⇔ ${partnerName}</div>
                <div class="route-desc">${r.desc}</div>
                <div class="route-value">Vol. anual estimado: <strong>$${r.valor}B</strong></div>
            </div>`;
        }).join('');

        container.innerHTML = `
            <div class="eco-summary-row">
                <div class="eco-summary-card">
                    <span class="eco-sl">Rotas Ativas</span>
                    <span class="eco-sv">${routes.length}</span>
                </div>
                <div class="eco-summary-card">
                    <span class="eco-sl">Receita Export/Trim.</span>
                    <span class="eco-sv" style="color:#00ff88">+$${income.toFixed(1)}B</span>
                </div>
                <div class="eco-summary-card">
                    <span class="eco-sl">Preço Petróleo</span>
                    <span class="eco-sv" style="color:#ffaa00">${eco.commodityPrices.petroleo.toFixed(0)}</span>
                </div>
            </div>
            <div class="section-title" style="margin-top:12px">Rotas Comerciais — ${nation.nome}</div>
            ${routes.length === 0
                ? `<div class="eco-empty">Nenhuma rota comercial mapeada para esta nação.</div>`
                : `<div class="route-grid">${routeCards}</div>`
            }
            <div class="section-title" style="margin-top:14px">Preços Globais de Commodities</div>
            <div class="commodity-board">
                ${Object.entries(eco.commodityPrices).map(([k, v]) => {
                    const col = v > 120 ? '#ff4444' : v < 80 ? '#00ff88' : '#8b949e';
                    const label = { petroleo:'Petróleo', gas_natural:'Gás Natural', 'minérios':'Minerais', alimentos:'Alimentos', metais:'Metais', tecnologia:'Tecnologia' }[k] || k;
                    return `<div class="commodity-item">
                        <span class="commodity-label">${label}</span>
                        <span class="commodity-val" style="color:${col}">${v.toFixed(0)}</span>
                        <div class="commodity-bar"><div style="width:${Math.min(100,v/2)}%;background:${col};height:100%;border-radius:2px;transition:width 0.4s"></div></div>
                    </div>`;
                }).join('')}
            </div>
        `;
    }

    // ── ABA EMPRESAS ─────────────────────────────────────────────────────────
    _renderEcoCompanies(container, isPlayer) {
        const eco = this.engine.economy;
        if (!eco) { container.innerHTML = '<p class="text-danger">Sistema de empresas não inicializado.</p>'; return; }

        const sectors   = ['all', ...eco.sectors];
        const activeSec = this._ecoCompSector || 'all';

        const filterHTML = sectors.map(s => `
            <button class="news-filter-btn ${activeSec===s?'active':''}"
                    onclick="engine.ui._ecoCompSector='${s}';engine.ui.renderEconomy(engine.state.selectedNation,document.getElementById('dynamic-content'))">
                ${s === 'all' ? 'Todos' : s}
            </button>`).join('');

        const portfolio = eco.portfolio;
        const portVal   = eco.portfolioValue;
        const portRet   = eco.portfolioReturn;

        const companiesHTML = eco.getCompaniesBySector(activeSec).map(co => {
            const pos        = portfolio[co.id];
            const posVal     = pos ? (pos.shares * co.preco).toFixed(1) : null;
            const riskCol    = eco.riskColor(co.risco);
            return `
            <div class="company-card ${pos ? 'owned' : ''}">
                <div class="company-header">
                    <span class="company-icon">${co.sIcone}</span>
                    <div class="company-name-block">
                        <span class="company-name">${co.nome}</span>
                        <span class="company-sector" style="color:${riskCol}">${co.setor} · Risco ${co.risco}</span>
                    </div>
                    <span class="company-trend">${eco.trendArrow(co.tendencia)}</span>
                </div>
                <p class="company-desc">${co.desc}</p>
                <div class="company-stats">
                    <div class="cstat"><span class="csl">Val. Mercado</span><span class="csv">${eco.fmtBillions(co.valorMercado)}</span></div>
                    <div class="cstat"><span class="csl">Receita/ano</span><span class="csv">${eco.fmtBillions(co.receita)}</span></div>
                    <div class="cstat"><span class="csl">Margem</span><span class="csv">${co.margem}%</span></div>
                    ${pos ? `<div class="cstat"><span class="csl">Minha posição</span><span class="csv" style="color:#00ff88">$${posVal}B</span></div>` : ''}
                </div>
                ${isPlayer ? `
                <div class="company-actions">
                    <button class="eco-invest-btn" onclick="engine.ui.showInvestModal('${co.id}')">Investir</button>
                    ${pos ? `<button class="eco-invest-btn sell" onclick="engine.ui.showDivestModal('${co.id}')">Vender</button>` : ''}
                </div>` : ''}
            </div>`;
        }).join('');

        container.innerHTML = `
            <div class="eco-summary-row">
                <div class="eco-summary-card">
                    <span class="eco-sl">Portfólio Total</span>
                    <span class="eco-sv" style="color:#00d2ff">${eco.fmtBillions(portVal)}</span>
                </div>
                <div class="eco-summary-card">
                    <span class="eco-sl">Retorno</span>
                    <span class="eco-sv" style="color:${portRet>=0?'#00ff88':'#ff4444'}">${portRet>=0?'+':''}${portRet.toFixed(1)}%</span>
                </div>
            </div>
            <div class="news-filter-bar" style="margin:10px 0 12px">${filterHTML}</div>
            <div class="company-list">${companiesHTML}</div>
        `;
    }

    // ── ABA CRIPTO ───────────────────────────────────────────────────────────
    _renderEcoCrypto(container, isPlayer) {
        const eco = this.engine.economy;
        if (!eco) { container.innerHTML = '<p class="text-danger">Sistema cripto não inicializado.</p>'; return; }

        const walletVal = eco.walletValue;

        const cryptoHTML = eco.cryptos.map(c => {
            const holding = eco.cryptoWallet[c.id] || 0;
            const holdVal = (holding * c.preco) / 1e9;
            return `
            <div class="crypto-card">
                <div class="crypto-header">
                    <span class="crypto-icon" style="color:${c.cor}">${c.icone}</span>
                    <div class="crypto-info">
                        <span class="crypto-nome">${c.nome}</span>
                        <span class="crypto-simbolo" style="color:${c.cor}">${c.simbolo}</span>
                    </div>
                    <div class="crypto-price-block">
                        <span class="crypto-price">${eco.fmtPrice(c.preco)}</span>
                        <span class="crypto-trend">${eco.trendArrow(c.tendencia)}</span>
                    </div>
                </div>
                <p class="crypto-desc">${c.desc}</p>
                <div class="crypto-stats">
                    <div class="cstat"><span class="csl">Supply</span><span class="csv">${(c.supply/1e6).toFixed(1)}M</span></div>
                    <div class="cstat"><span class="csl">Mkt Cap</span><span class="csv">$${((c.preco*c.supply)/1e12).toFixed(2)}T</span></div>
                    <div class="cstat"><span class="csl">Volatilidade</span><span class="csv">${(c.volatilidade*100).toFixed(0)}%/turno</span></div>
                    ${holding > 0 ? `<div class="cstat"><span class="csl">Carteira</span><span class="csv" style="color:#00ff88">$${holdVal.toFixed(2)}B</span></div>` : ''}
                </div>
                ${isPlayer ? `
                <div class="company-actions">
                    <button class="eco-invest-btn" onclick="engine.ui.showCryptoBuyModal('${c.id}')">Comprar</button>
                    ${holding > 0 ? `<button class="eco-invest-btn sell" onclick="engine.ui.showCryptoSellModal('${c.id}')">Vender</button>` : ''}
                </div>` : ''}
            </div>`;
        }).join('');

        container.innerHTML = `
            <div class="eco-summary-row">
                <div class="eco-summary-card">
                    <span class="eco-sl">Carteira Cripto</span>
                    <span class="eco-sv" style="color:#fbbf24">${eco.fmtBillions(walletVal)}</span>
                </div>
                <div class="eco-summary-card">
                    <span class="eco-sl">Ativos Digitais</span>
                    <span class="eco-sv">${Object.keys(eco.cryptoWallet).filter(k=>eco.cryptoWallet[k]>0).length} / ${eco.cryptos.length}</span>
                </div>
            </div>
            <div class="section-title" style="margin-top:10px">Mercado Cripto Global</div>
            <div class="crypto-list">${cryptoHTML}</div>
        `;
    }

    // ── MODAIS DE INVESTIMENTO ────────────────────────────────────────────────
    showInvestModal(companyId) {
        const eco = this.engine.economy;
        const co  = eco?.getCompany(companyId);
        if (!co) return;
        const tesouro = this.engine.state.playerNation?.tesouro || 0;

        this._showEcoActionModal(
            `Investir em ${co.sIcone} ${co.nome}`,
            `<p class="modal-current">Valor de mercado: <strong>${eco.fmtBillions(co.valorMercado)}</strong> · Margem: ${co.margem}% · Risco: <span style="color:${eco.riskColor(co.risco)}">${co.risco}</span></p>
             <p class="modal-current">${co.desc}</p>
             <div class="form-row" style="margin-top:12px">
                 <label>Valor a investir ($B)</label>
                 <input id="eco-invest-val" type="number" min="1" max="${tesouro.toFixed(0)}" value="10" style="background:rgba(255,255,255,0.05);border:1px solid var(--glass-border);border-radius:6px;color:var(--text-primary);padding:8px;font-size:0.85rem;width:100%">
             </div>
             <p style="font-size:0.68rem;color:var(--text-secondary);margin-top:6px">Tesouro disponível: $${tesouro.toFixed(0)}B</p>`,
            `engine.ui._doInvest('${companyId}')`
        );
    }

    _doInvest(companyId) {
        const val = parseFloat(document.getElementById('eco-invest-val')?.value || 0);
        const res = this.engine.economy.invest(companyId, val);
        this.hideGovernmentModal();
        this.showNotification(res.msg, res.ok ? 'info' : 'threat');
        if (res.ok) this.renderEconomy(this.engine.state.selectedNation, document.getElementById('dynamic-content'), 'empresas');
    }

    showDivestModal(companyId) {
        const eco  = this.engine.economy;
        const co   = eco?.getCompany(companyId);
        const port = eco?.portfolio[companyId];
        if (!co || !port) return;
        const currVal = (port.shares * co.preco).toFixed(1);

        this._showEcoActionModal(
            `Vender posição — ${co.sIcone} ${co.nome}`,
            `<p class="modal-current">Posição atual: <strong>$${currVal}B</strong></p>
             <div class="form-row" style="margin-top:12px">
                 <label>% a vender</label>
                 <input id="eco-divest-pct" type="number" min="1" max="100" value="50" style="background:rgba(255,255,255,0.05);border:1px solid var(--glass-border);border-radius:6px;color:var(--text-primary);padding:8px;font-size:0.85rem;width:100%">
             </div>`,
            `engine.ui._doDivest('${companyId}')`
        );
    }

    _doDivest(companyId) {
        const pct = parseFloat(document.getElementById('eco-divest-pct')?.value || 50);
        const res = this.engine.economy.divest(companyId, pct);
        this.hideGovernmentModal();
        this.showNotification(res.msg, res.ok ? 'info' : 'threat');
        if (res.ok) this.renderEconomy(this.engine.state.selectedNation, document.getElementById('dynamic-content'), 'empresas');
    }

    showCryptoBuyModal(cryptoId) {
        const eco    = this.engine.economy;
        const crypto = eco?.getCrypto(cryptoId);
        if (!crypto) return;
        const tesouro = this.engine.state.playerNation?.tesouro || 0;

        this._showEcoActionModal(
            `Comprar ${crypto.icone} ${crypto.nome} (${crypto.simbolo})`,
            `<p class="modal-current">Preço unitário: <strong>${eco.fmtPrice(crypto.preco)}</strong> · Vol. ${(crypto.volatilidade*100).toFixed(0)}%/turno</p>
             <p class="modal-current" style="margin-bottom:10px">${crypto.desc}</p>
             <div class="form-row">
                 <label>Investir ($B do tesouro)</label>
                 <input id="eco-crypto-val" type="number" min="0.1" step="0.1" max="${tesouro.toFixed(1)}" value="5" style="background:rgba(255,255,255,0.05);border:1px solid var(--glass-border);border-radius:6px;color:var(--text-primary);padding:8px;font-size:0.85rem;width:100%">
             </div>
             <p style="font-size:0.68rem;color:var(--text-secondary);margin-top:6px">Tesouro disponível: $${tesouro.toFixed(0)}B</p>`,
            `engine.ui._doBuyCrypto('${cryptoId}')`
        );
    }

    _doBuyCrypto(cryptoId) {
        const val = parseFloat(document.getElementById('eco-crypto-val')?.value || 0);
        const res = this.engine.economy.buyCrypto(cryptoId, val);
        this.hideGovernmentModal();
        this.showNotification(res.msg, res.ok ? 'info' : 'threat');
        if (res.ok) this.renderEconomy(this.engine.state.selectedNation, document.getElementById('dynamic-content'), 'cripto');
    }

    showCryptoSellModal(cryptoId) {
        const eco     = this.engine.economy;
        const crypto  = eco?.getCrypto(cryptoId);
        const holding = eco?.cryptoWallet[cryptoId] || 0;
        if (!crypto || holding <= 0) return;
        const val = ((holding * crypto.preco) / 1e9).toFixed(2);

        this._showEcoActionModal(
            `Vender ${crypto.icone} ${crypto.nome}`,
            `<p class="modal-current">Saldo: <strong>${holding.toFixed(4)} ${crypto.simbolo}</strong> ≈ <strong>$${val}B</strong></p>
             <div class="form-row" style="margin-top:12px">
                 <label>% a vender</label>
                 <input id="eco-crypto-sell-pct" type="number" min="1" max="100" value="50" style="background:rgba(255,255,255,0.05);border:1px solid var(--glass-border);border-radius:6px;color:var(--text-primary);padding:8px;font-size:0.85rem;width:100%">
             </div>`,
            `engine.ui._doSellCrypto('${cryptoId}')`
        );
    }

    _doSellCrypto(cryptoId) {
        const pct = parseFloat(document.getElementById('eco-crypto-sell-pct')?.value || 50);
        const res = this.engine.economy.sellCrypto(cryptoId, pct);
        this.hideGovernmentModal();
        this.showNotification(res.msg, res.ok ? 'info' : 'threat');
        if (res.ok) this.renderEconomy(this.engine.state.selectedNation, document.getElementById('dynamic-content'), 'cripto');
    }

    _showEcoActionModal(title, bodyHTML, confirmCall) {
        const modal   = document.getElementById('gov-modal');
        const titleEl = document.getElementById('gov-modal-title');
        const content = document.getElementById('gov-modal-content');
        if (!modal || !titleEl || !content) return;

        titleEl.textContent = title;
        content.innerHTML   = `
            ${bodyHTML}
            <div style="display:flex;gap:10px;margin-top:16px">
                <button class="action-btn" style="background:var(--accent-secondary);color:var(--bg-deep);border:none;flex:1"
                        onclick="${confirmCall}">CONFIRMAR</button>
                <button class="action-btn" style="flex:1" onclick="engine.ui.hideGovernmentModal()">CANCELAR</button>
            </div>`;
        modal.classList.add('active');
    }

    showEcoModal(action, nation) {
        const modal = document.getElementById('gov-modal');
        const title = document.getElementById('gov-modal-title');
        const content = document.getElementById('gov-modal-content');
        if (!modal || !title || !content) return;

        const nationObj = typeof nation === 'string' ? this.engine.data.nations[nation] : nation;
        if (!nationObj) return;

        const names = {
            'eco_infra':    '🏗️ Investimento em Infraestrutura',
            'eco_comercio': '📦 Política Comercial',
            'eco_privat':   '🏭 Gestão de Empresas',
            'eco_recurso':  '⛏️ Exploração de Recursos'
        };
        title.textContent = names[action] || 'Política Econômica';

        let html = '';
        switch(action) {
            case 'eco_infra':    html = this.getEcoInfraHTML(nationObj);   break;
            case 'eco_comercio': html = this.getEcoComercionHTML(nationObj); break;
            case 'eco_privat':   html = this.getEcoPrivatHTML(nationObj);   break;
            case 'eco_recurso':  html = this.getEcoRecursoHTML(nationObj);  break;
            default: html = `<p style="color:var(--text-dim)">Ação não disponível.</p>`;
        }
        content.innerHTML = html;
        modal.classList.add('active');
    }

    getEcoInfraHTML(nation) {
        const iso = nation.codigo_iso;
        const pibT = (nation.pib_bilhoes_usd / 1000).toFixed(2);
        const treasury = nation.tesouro || 0;
        const chart = this.renderMiniChart(nation.historico?.pib, '#00ff88', 'PIB ($B)');
        return `
        ${chart}
        <p class="modal-current">PIB atual: <strong style="color:var(--accent-secondary)">$${pibT}T</strong></p>
        <div class="action-options">
            <div class="option-card">
                <div class="option-badge cost">$25B</div>
                <h4>Infraestrutura Básica</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">PIB +0.5%</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','invest_infra_leve')">EXECUTAR</button>
            </div>
            <div class="option-card">
                <div class="option-badge cost">$50B</div>
                <h4>Infraestrutura Padrão</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">PIB +1%</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','invest_infra')">EXECUTAR</button>
            </div>
            <div class="option-card">
                <div class="option-badge cost">$100B</div>
                <h4>Megaprojeto</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">PIB +2.5%</span>
                    <span class="effect-tag negative">Estabilidade −2%</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','invest_infra_massivo')">EXECUTAR</button>
            </div>
        </div>
        <p class="treasury-display">Tesouro disponível: <strong>$${treasury.toFixed(0)}B</strong></p>`;
    }

    getEcoComercionHTML(nation) {
        const iso = nation.codigo_iso;
        const treasury = nation.tesouro || 0;
        const chart = this.renderMiniChart(nation.historico?.pib, '#00ff88', 'PIB ($B)');
        return `
        ${chart}
        <div class="action-options" style="grid-template-columns:1fr 1fr">
            <div class="option-card">
                <div class="option-badge cost">$30B</div>
                <h4>Liberalização Comercial</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">PIB +1%</span>
                    <span class="effect-tag positive">Felicidade +2%</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','livre_comercio_interno')">EXECUTAR</button>
            </div>
            <div class="option-card">
                <div class="option-badge income">+$20B</div>
                <h4>Protecionismo</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">Tesouro +$20B</span>
                    <span class="effect-tag negative">PIB −0.5%</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','protecionismo')">EXECUTAR</button>
            </div>
        </div>
        <p class="treasury-display">Tesouro disponível: <strong>$${treasury.toFixed(0)}B</strong></p>`;
    }

    getEcoPrivatHTML(nation) {
        const iso = nation.codigo_iso;
        const treasury = nation.tesouro || 0;
        const chart = this.renderMiniChart(nation.historico?.pib, '#00ff88', 'PIB ($B)');
        return `
        ${chart}
        <div class="action-options" style="grid-template-columns:1fr 1fr">
            <div class="option-card">
                <div class="option-badge income">+$30B</div>
                <h4>Privatização</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">Tesouro +$30B</span>
                    <span class="effect-tag negative">PIB −0.3%</span>
                    <span class="effect-tag negative">Felicidade −3%</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','privatizar')">EXECUTAR</button>
            </div>
            <div class="option-card">
                <div class="option-badge cost">$40B</div>
                <h4>Subsídios Setoriais</h4>
                <div class="option-effects">
                    <span class="effect-tag positive">PIB +1.5%</span>
                    <span class="effect-tag negative">Corrupção +3%</span>
                </div>
                <button class="action-btn small" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','subsidios_setor')">EXECUTAR</button>
            </div>
        </div>
        <p class="treasury-display">Tesouro disponível: <strong>$${treasury.toFixed(0)}B</strong></p>`;
    }

    getEcoRecursoHTML(nation) {
        const iso = nation.codigo_iso;
        const treasury = nation.tesouro || 0;
        const recursos = nation.recursos || {};
        const resourceMeta = [
            { key: 'petroleo',      label: 'Petróleo',        color: '#ffaa00' },
            { key: 'gas_natural',   label: 'Gás Natural',     color: '#00d2ff' },
            { key: 'minerios_raros',label: 'Minérios Raros',  color: '#00ff88' },
            { key: 'uranio',        label: 'Urânio',          color: '#ff3333' },
            { key: 'ferro',         label: 'Ferro',           color: '#8b949e' },
            { key: 'terras_araveis',label: 'Terras Aráveis',  color: '#22c55e' }
        ];
        const bars = resourceMeta.map(({ key, label, color }) => {
            const val = recursos[key] || 0;
            const valClass = val >= 70 ? 'val-good' : val < 35 ? 'val-bad' : '';
            return `
            <div class="resource-row">
                <span class="resource-label">${label}</span>
                <div class="resource-bar-track"><div class="resource-bar-fill" style="width:${val}%;background:${color}"></div></div>
                <span class="resource-pct ${valClass}">${val}%</span>
            </div>`;
        }).join('');
        return `
        <p class="modal-current" style="margin-bottom:12px">Investimento automático no recurso mais escasso <strong style="color:var(--accent-warning)">($20B → +15%)</strong></p>
        <div class="resources-list" style="margin-bottom:14px">${bars}</div>
        <button class="action-btn" onclick="engine.ui.hideGovernmentModal();engine.executeAction('${iso}','explorar_recursos')">INVESTIR EM RECURSO ESCASSO — $20B</button>
        <p class="treasury-display">Tesouro disponível: <strong>$${treasury.toFixed(0)}B</strong></p>`;
    }

    renderTech(nation, container) {
        if (this.engine.state.gameState === 'SELECTING') {
            this.renderSelectionPreview(nation);
            return;
        }

        if (!this.engine.data.technologies || !this.engine.data.technologies.length) {
            container.innerHTML = `<p style="color:var(--text-dim)">Sistemas de Pesquisa em Manutenção...</p>`;
            return;
        }

        const completed  = nation.tecnologias_concluidas || [];
        const current    = nation.pesquisa_atual;
        const allTechs   = this.engine.data.technologies;
        const iso        = nation.codigo_iso;
        const treasury   = nation.tesouro || 0;
        const isPlayer   = this.engine.state.gameState === 'PLAYING' &&
                           this.engine.state.playerNation?.codigo_iso === iso;

        const catColors  = {
            MILITAR:  '#ff4444',
            DIGITAL:  '#00d2ff',
            ENERGIA:  '#ffaa00',
            SOCIAL:   '#00ff88',
            ESPACIAL: '#b478ff'
        };
        const tierColors = { 1:'#8b949e', 2:'#58a6ff', 3:'#ffaa00', 4:'#ff4444' };
        const tierLabel  = { 1:'Básico', 2:'Intermediário', 3:'Avançado', 4:'Elite' };

        const filter     = this.techFilter || 'ALL';
        const categories = ['ALL','MILITAR','DIGITAL','ENERGIA','SOCIAL','ESPACIAL'];

        // Research progress bar
        let researchBar = '';
        if (current) {
            const tech = allTechs.find(t => t.id === current.id);
            if (tech) {
                const speed = nation.velocidade_pesquisa || 1;
                const pct   = Math.min(100, (current.progresso / tech.tempo_turnos) * 100).toFixed(0);
                const turnsLeft = Math.ceil((tech.tempo_turnos - current.progresso) / speed);
                researchBar = `
                <div class="tech-research-status">
                    <div class="tech-research-header">
                        <span style="color:var(--accent-primary)">Pesquisa ativa:</span>
                        <span style="color:var(--accent-warning);font-family:var(--font-data)">${tech.nome}</span>
                    </div>
                    <div class="progress-container" style="margin:6px 0">
                        <div class="progress-bar" style="width:${pct}%;background:${catColors[tech.categoria]||'var(--accent-primary)'}"></div>
                    </div>
                    <div style="display:flex;justify-content:space-between;font-size:0.65rem;color:var(--text-secondary)">
                        <span>${pct}% concluído — ~${turnsLeft} turnos restantes</span>
                        <span>Vel. pesquisa: ×${(nation.velocidade_pesquisa||1).toFixed(2)}</span>
                    </div>
                </div>`;
            }
        }

        // Category tabs
        const filterTabs = categories.map(cat => {
            const active = cat === filter;
            const col    = catColors[cat] || 'var(--accent-primary)';
            const count  = cat === 'ALL' ? allTechs.length : allTechs.filter(t => t.categoria === cat).length;
            const owned  = cat === 'ALL' ? completed.length : completed.filter(id => allTechs.find(t=>t.id===id&&t.categoria===cat)).length;
            return `<button class="tech-filter-btn ${active ? 'active' : ''}"
                style="${active ? `background:${col};color:#000;border-color:${col}` : ''}"
                onclick="engine.ui.switchTechFilter('${cat}')">
                ${cat === 'ALL' ? '🌐 Todos' : cat} <span style="font-size:0.55rem;opacity:0.7">${owned}/${count}</span>
            </button>`;
        }).join('');

        // Tech cards
        const filtered = filter === 'ALL' ? allTechs : allTechs.filter(t => t.categoria === filter);
        const sortedFiltered = [...filtered].sort((a, b) => {
            if (a.tier !== b.tier) return a.tier - b.tier;
            const aComp = completed.includes(a.id) ? 0 : 1;
            const bComp = completed.includes(b.id) ? 0 : 1;
            return aComp - bComp;
        });

        const techCards = sortedFiltered.map(tech => {
            const isCompleted   = completed.includes(tech.id);
            const isResearching = current && current.id === tech.id;
            const pct           = isResearching ? Math.min(100, (current.progresso / tech.tempo_turnos) * 100) : 0;
            const hasPreReqs    = !tech.pre_requisitos?.length || tech.pre_requisitos.every(p => completed.includes(p));
            const catColor      = catColors[tech.categoria] || 'var(--accent-primary)';
            const tierCol       = tierColors[tech.tier] || '#8b949e';
            const canAfford     = treasury >= tech.custo;
            const meetsGDP      = !tech.requisito_pib_minimo || (nation.pib_bilhoes_usd || 0) >= tech.requisito_pib_minimo;
            const meetsStab     = !tech.requisito_estabilidade || (nation.estabilidade_politica || 0) >= tech.requisito_estabilidade;
            const canStart      = hasPreReqs && meetsGDP && meetsStab && !nation.pesquisa_atual;

            // Effects display
            const ef = tech.efeitos || {};
            const effTags = [
                ef.bonus_pib_pct        ? `<span class="effect-tag positive">PIB +${ef.bonus_pib_pct}%</span>` : '',
                ef.pib_fator            ? `<span class="effect-tag positive">PIB ×${ef.pib_fator}</span>` : '',
                ef.poder_militar_bonus  ? `<span class="effect-tag positive">⚔ +${ef.poder_militar_bonus}</span>` : '',
                ef.bonus_militar_defesa ? `<span class="effect-tag positive">🛡 +${ef.bonus_militar_defesa}</span>` : '',
                ef.estabilidade_fator   ? `<span class="effect-tag ${ef.estabilidade_fator > 0 ? 'positive' : 'negative'}">Est. ${ef.estabilidade_fator > 0 ? '+' : ''}${ef.estabilidade_fator}</span>` : '',
                ef.bonus_intel          ? `<span class="effect-tag positive">🔎 +${ef.bonus_intel}</span>` : '',
                ef.bonus_ciencia        ? `<span class="effect-tag positive">🔬 ×${(1+ef.bonus_ciencia).toFixed(2)} pesq.</span>` : '',
                ef.bonus_diplomacia     ? `<span class="effect-tag positive">🤝 +${ef.bonus_diplomacia}</span>` : '',
                ef.populacao_fator      ? `<span class="effect-tag positive">👥 ×${ef.populacao_fator}</span>` : '',
            ].filter(Boolean).join('');

            // Owners flag line
            const owners = (tech.posse_atual || []);
            const isNationOwner = owners.includes(iso);
            const ownerLine = owners.length > 0 ? `
                <div class="tech-owners">
                    <span class="tech-owners-label">Detentores hoje (${owners.length}):</span>
                    <span class="tech-owners-list">${owners.slice(0,8).join(' · ')}${owners.length > 8 ? ` +${owners.length-8}` : ''}</span>
                </div>` : `<div class="tech-owners"><span class="tech-owners-label" style="color:var(--accent-warning)">★ Nenhuma nação possui ainda</span></div>`;

            // Requirements line
            const reqItems = [];
            if (tech.pre_requisitos?.length) {
                const missing = tech.pre_requisitos.filter(p => !completed.includes(p));
                if (missing.length) {
                    const missingNames = missing.map(id => allTechs.find(t=>t.id===id)?.nome || id);
                    reqItems.push(`<span class="req-item fail">🔒 Requer: ${missingNames.join(', ')}</span>`);
                } else {
                    reqItems.push(`<span class="req-item ok">✓ Pré-requisitos OK</span>`);
                }
            }
            if (tech.requisito_pib_minimo) {
                reqItems.push(`<span class="req-item ${meetsGDP?'ok':'fail'}">PIB ≥ $${tech.requisito_pib_minimo}B ${meetsGDP?'✓':'✗'}</span>`);
            }
            if (tech.requisito_estabilidade) {
                reqItems.push(`<span class="req-item ${meetsStab?'ok':'fail'}">Est. ≥ ${tech.requisito_estabilidade}% ${meetsStab?'✓':'✗'}</span>`);
            }

            let footerHTML = '';
            if (isCompleted) {
                footerHTML = `<span class="status-tag success">✓ CONCLUÍDO${isNationOwner ? '' : ' (adquirido)'}</span>`;
            } else if (isResearching) {
                footerHTML = `
                <div class="progress-container"><div class="progress-bar" style="width:${pct}%;background:${catColor}"></div></div>
                <span style="font-size:0.6rem;color:var(--text-secondary)">${pct.toFixed(0)}% — ${current.progresso}/${tech.tempo_turnos} turnos</span>`;
            } else if (!isPlayer) {
                footerHTML = `<span class="status-tag" style="color:var(--text-dim)">Selecione sua nação para pesquisar</span>`;
            } else {
                const blockMsg = !hasPreReqs ? 'Pré-requisitos faltando' : !meetsGDP ? 'PIB insuficiente' : !meetsStab ? 'Instabilidade política' : nation.pesquisa_atual ? 'Pesquisa em andamento' : '';
                footerHTML = `<button class="action-btn small ${!canStart||!canAfford ? 'btn-disabled' : ''}"
                    onclick="engine.startResearch('${iso}','${tech.id}')"
                    ${!canStart||!canAfford ? `disabled title="${blockMsg||'Tesouro insuficiente'}"` : ''}>
                    PESQUISAR — $${tech.custo}B
                </button>`;
            }

            return `
            <div class="tech-card ${isCompleted ? 'completed' : ''} ${!hasPreReqs ? 'locked' : ''}">
                <div class="tech-header">
                    <span class="tech-category" style="background:${catColor}20;color:${catColor};border:1px solid ${catColor}40">${tech.categoria}</span>
                    <span class="tech-tier" style="background:${tierCol}20;color:${tierCol};border:1px solid ${tierCol}40">Tier ${tech.tier} — ${tierLabel[tech.tier]||''}</span>
                </div>
                <h4 class="tech-name">${tech.nome}</h4>
                <p class="tech-desc">${tech.descricao}</p>
                ${tech.referencia_real ? `<p class="tech-reference">📎 ${tech.referencia_real}</p>` : ''}
                ${ownerLine}
                <div class="tech-effects">${effTags}</div>
                ${reqItems.length ? `<div class="tech-reqs">${reqItems.join('')}</div>` : ''}
                <div class="tech-meta">
                    <span class="tech-meta-item">⏱ ${tech.tempo_turnos} turnos</span>
                    <span class="tech-meta-item">💰 $${tech.custo}B</span>
                </div>
                <div class="tech-footer">${footerHTML}</div>
            </div>`;
        }).join('');

        // Nation tech summary
        const intelScore = nation.intel_score || 0;
        const researchSpeed = (nation.velocidade_pesquisa || 1).toFixed(2);
        const milBonus = nation.militar?.bonus_defesa_tech || 0;

        container.innerHTML = `
        <div class="tech-overview">
            <div class="tech-progress-summary">
                <span style="color:var(--accent-secondary);font-family:var(--font-data);font-size:0.8rem">${completed.length} / ${allTechs.length}</span>
                <span style="color:var(--text-secondary);font-size:0.7rem"> tecnologias concluídas</span>
            </div>
            <div class="tech-nation-stats">
                <div class="tns-item"><span class="tns-label">Intel Score</span><span class="tns-val">${intelScore}</span></div>
                <div class="tns-item"><span class="tns-label">Vel. Pesquisa</span><span class="tns-val">×${researchSpeed}</span></div>
                <div class="tns-item"><span class="tns-label">Escudo Tech</span><span class="tns-val">+${milBonus}</span></div>
                <div class="tns-item"><span class="tns-label">Bônus Dipl.</span><span class="tns-val">+${nation.diplomacia_bonus||0}</span></div>
            </div>
            ${researchBar}
        </div>

        <div class="section-title" style="margin-top:12px">Filtrar por Categoria</div>
        <div class="tech-filter-row">${filterTabs}</div>

        <div class="section-title" style="margin-top:12px">Árvore Tecnológica</div>
        <div class="tech-grid">${techCards}</div>
        `;
    }

    switchTechFilter(filter) {
        this.techFilter = filter;
        if (this.engine.state.selectedNation) {
            this.renderTech(this.engine.state.selectedNation, document.getElementById('dynamic-content'));
        }
    }

    renderDiplomacy(nation, container) {
        if (!this.engine.diplomacy) {
            container.innerHTML = `<p style="color: var(--text-dim)">Sistema diplomático em inicialização...</p>`;
            return;
        }

        const iso      = nation.codigo_iso;
        const isPlayer = this.engine.state.gameState === 'PLAYING' &&
                         this.engine.state.playerNation?.codigo_iso === iso;
        const treasury = nation.tesouro || 0;

        const treaties  = this.engine.diplomacy.getTreatiesForNation(iso);
        const proposals = this.engine.diplomacy.getProposalsForNation(iso);

        // Relations dashboard
        const relations = Object.entries(nation.relacoes || {})
            .map(([code, val]) => ({ code, val, nome: this.engine.data.nations[code]?.nome || code }))
            .sort((a, b) => b.val - a.val);

        const allies  = relations.filter(r => r.val > 0).slice(0, 4);
        const rivals  = [...relations].sort((a, b) => a.val - b.val).filter(r => r.val < 0).slice(0, 4);

        const relCard = (r, isAlly) => {
            const col   = isAlly ? '#00ff88' : '#ff3333';
            const pct   = Math.abs(r.val);
            const sign  = r.val >= 0 ? '+' : '';
            return `
            <div class="relation-item">
                <span class="relation-name">${r.nome}</span>
                <div class="relation-bar-track">
                    <div class="relation-bar-fill" style="width:${pct}%;background:${col}"></div>
                </div>
                <span class="relation-val" style="color:${col}">${sign}${r.val}</span>
            </div>`;
        };

        const alliesHTML = allies.length
            ? allies.map(r => relCard(r, true)).join('')
            : `<p style="color:var(--text-dim);font-size:0.75rem">Sem aliados estabelecidos.</p>`;
        const rivalsHTML = rivals.length
            ? rivals.map(r => relCard(r, false)).join('')
            : `<p style="color:var(--text-dim);font-size:0.75rem">Sem rivais ativos.</p>`;

        // Proposals
        const proposalsHTML = proposals.length === 0
            ? `<p style="color:var(--text-dim)">Nenhuma proposta pendente.</p>`
            : proposals.map(p => {
                const proposerName = this.engine.data.nations[p.proposer]?.nome || p.proposer;
                const type = this.engine.diplomacy.getTreatyType(p.treatyTypeId) || {};
                const effs = type.efeitos || {};
                const effTags = [
                    effs.modificador_pib       ? `<span class="effect-tag positive">PIB ${effs.modificador_pib > 0 ? '+' : ''}${(effs.modificador_pib*100).toFixed(0)}%</span>` : '',
                    effs.bonus_forca_militar   ? `<span class="effect-tag ${effs.bonus_forca_militar > 0 ? 'positive' : 'negative'}">Militar ${effs.bonus_forca_militar > 0 ? '+' : ''}${(effs.bonus_forca_militar*100).toFixed(0)}%</span>` : '',
                    effs.modificador_estabilidade ? `<span class="effect-tag positive">Est. +${(effs.modificador_estabilidade*100).toFixed(0)}%</span>` : '',
                    effs.velocidade_pesquisa   ? `<span class="effect-tag positive">Pesquisa +${(effs.velocidade_pesquisa*100).toFixed(0)}%</span>` : '',
                    effs.bonus_tesouro         ? `<span class="effect-tag positive">Tesouro +${(effs.bonus_tesouro*100).toFixed(0)}%PIB</span>` : ''
                ].filter(Boolean).join('');
                return `
                <div class="proposal-card">
                    <div class="proposal-header">
                        <span class="proposal-type">${type.nome || p.treatyTypeId}</span>
                        <span class="proposal-from">De: ${proposerName}</span>
                    </div>
                    <p class="proposal-desc">${type.descricao || ''}</p>
                    <div class="option-effects" style="flex-direction:row;flex-wrap:wrap;gap:4px;margin-bottom:8px">${effTags}</div>
                    <div class="proposal-actions">
                        <button class="action-btn small accept" onclick="engine.diplomacy.playerAcceptProposal('${p.id}');engine.ui.renderPanel('diplomacy',engine.state.selectedNation)">ACEITAR</button>
                        <button class="action-btn small reject" onclick="engine.diplomacy.playerRejectProposal('${p.id}');engine.ui.renderPanel('diplomacy',engine.state.selectedNation)">REJEITAR</button>
                    </div>
                </div>`;
            }).join('');

        // Active treaties
        const treatiesHTML = treaties.length === 0
            ? `<p style="color:var(--text-dim)">Nenhum tratado ativo.</p>`
            : treaties.map(t => {
                const type = this.engine.diplomacy.getTreatyType(t.type) || {};
                const others = t.signatories.filter(c => c !== iso);
                const effs = type.efeitos || {};
                const effTags = [
                    effs.modificador_pib       ? `<span class="effect-tag positive">PIB ${effs.modificador_pib > 0 ? '+' : ''}${(effs.modificador_pib*100).toFixed(0)}%/turno</span>` : '',
                    effs.bonus_forca_militar   ? `<span class="effect-tag ${effs.bonus_forca_militar > 0 ? 'positive' : 'negative'}">Militar ${effs.bonus_forca_militar > 0 ? '+' : ''}${(effs.bonus_forca_militar*100).toFixed(0)}%</span>` : '',
                    effs.velocidade_pesquisa   ? `<span class="effect-tag positive">Pesquisa +${(effs.velocidade_pesquisa*100).toFixed(0)}%</span>` : '',
                    effs.bonus_tesouro         ? `<span class="effect-tag positive">Tesouro +${(effs.bonus_tesouro*100).toFixed(0)}%PIB/turno</span>` : ''
                ].filter(Boolean).join('');
                const remaining = t.expirationTurn === Infinity ? '∞' : Math.max(0, t.expirationTurn - this.engine.state.currentTurn) + ' turnos';
                return `
                <div class="treaty-card">
                    <div class="treaty-header">
                        <span class="treaty-type">${type.nome || t.type}</span>
                        <span class="treaty-status">${t.status.toUpperCase()}</span>
                    </div>
                    <p class="treaty-desc">${type.descricao || ''}</p>
                    <div class="option-effects" style="flex-direction:row;flex-wrap:wrap;gap:4px;margin-bottom:6px">${effTags}</div>
                    <div class="treaty-details">
                        <span class="label">Com:</span> ${others.map(c => this.engine.data.nations[c]?.nome || c).join(', ')}&nbsp;&nbsp;
                        <span class="label">Resta:</span> ${remaining}
                    </div>
                    ${isPlayer ? `<button class="action-btn small" style="border-color:var(--accent-threat);color:var(--accent-threat);margin-top:6px" onclick="engine.diplomacy.playerBreakTreaty('${t.id}');engine.ui.renderPanel('diplomacy',engine.state.selectedNation)">ROMPER</button>` : ''}
                </div>`;
            }).join('');

        // Proposal form + diplomatic actions
        const treatyTypes   = Object.values(this.engine.diplomacy.treatyTypes || {});
        const treatyOptions = treatyTypes.map(tt => `<option value="${tt.id}">${tt.nome}</option>`).join('');
        const otherNations  = Object.values(this.engine.data.nations).filter(n => n.codigo_iso !== iso);
        const nationOptions = otherNations.map(n => {
            const rel = (nation.relacoes || {})[n.codigo_iso] || 0;
            const sign = rel >= 0 ? '+' : '';
            return `<option value="${n.codigo_iso}">${n.nome} (${sign}${rel})</option>`;
        }).join('');

        const diploActionsHTML = isPlayer ? `
        <div class="section-title">Ações Diplomáticas</div>
        <div class="gov-actions-grid">
            <button class="gov-action-btn" onclick="engine.ui.showDiploModal('diplo_envoy','${iso}')">
                <span class="gov-action-name">Enviar Embaixada</span>
                <span class="gov-action-cost">$15B</span>
                <span class="gov-action-effect">Relações +15</span>
            </button>
            <button class="gov-action-btn" style="border-color:rgba(255,51,51,0.3)" onclick="engine.ui.showDiploModal('diplo_sancao','${iso}')">
                <span class="gov-action-name">Sanções</span>
                <span class="gov-action-cost">Grátis</span>
                <span class="gov-action-effect">Relações −25</span>
            </button>
        </div>
        <div class="section-title">Propor Tratado</div>
        <div class="proposal-form">
            <div class="form-row">
                <label>Nação Alvo</label>
                <select id="diplomacy-target">${nationOptions}</select>
            </div>
            <div class="form-row">
                <label>Tipo de Tratado</label>
                <select id="diplomacy-type">${treatyOptions}</select>
            </div>
            <button class="action-btn" onclick="engine.ui.sendProposal('${iso}')">ENVIAR PROPOSTA</button>
        </div>
        <p class="treasury-info">Tesouro disponível: <strong class="treasury-val">$${treasury.toFixed(0)}B</strong></p>
        ` : '';

        container.innerHTML = `
        <div class="diplo-relations-grid">
            <div>
                <div class="section-title" style="margin-top:0">Aliados</div>
                ${alliesHTML}
            </div>
            <div>
                <div class="section-title" style="margin-top:0">Rivais</div>
                ${rivalsHTML}
            </div>
        </div>

        <div class="section-title">Propostas Pendentes <span class="badge-count">${proposals.length}</span></div>
        <div class="proposal-grid">${proposalsHTML}</div>

        <div class="section-title">Tratados Ativos <span class="badge-count">${treaties.length}</span></div>
        <div class="treaty-grid">${treatiesHTML}</div>

        ${diploActionsHTML}
        `;
    }

    showDiploModal(action, nation) {
        const modal = document.getElementById('gov-modal');
        const title = document.getElementById('gov-modal-title');
        const content = document.getElementById('gov-modal-content');
        if (!modal || !title || !content) return;

        const nationObj = typeof nation === 'string' ? this.engine.data.nations[nation] : nation;
        if (!nationObj) return;

        const names = {
            'diplo_envoy':  '🤝 Enviar Embaixada',
            'diplo_sancao': '🚫 Impor Sanções Econômicas'
        };
        title.textContent = names[action] || 'Ação Diplomática';

        const otherNations = Object.values(this.engine.data.nations).filter(n => n.codigo_iso !== nationObj.codigo_iso);
        const relationMap  = nationObj.relacoes || {};
        const sorted = [...otherNations].sort((a, b) => {
            const ra = relationMap[a.codigo_iso] || 0;
            const rb = relationMap[b.codigo_iso] || 0;
            return action === 'diplo_sancao' ? ra - rb : rb - ra;
        });
        const nationOptions = sorted.map(n => {
            const rel  = relationMap[n.codigo_iso] || 0;
            const sign = rel >= 0 ? '+' : '';
            return `<option value="${n.codigo_iso}">${n.nome} (${sign}${rel})</option>`;
        }).join('');

        const treasury = nationObj.tesouro || 0;
        const isEnvoy  = action === 'diplo_envoy';

        content.innerHTML = `
        <p class="modal-current" style="margin-bottom:14px">
            ${isEnvoy
                ? `Custo: <strong style="color:var(--accent-warning)">$15B</strong> — Melhora relações bilaterais em <strong style="color:var(--accent-secondary)">+15</strong> com a nação escolhida.`
                : `Custo: <strong style="color:var(--accent-secondary)">Grátis</strong> — Impõe pressão econômica. Relações <strong style="color:var(--accent-threat)">−25</strong>, PIB alvo <strong style="color:var(--accent-threat)">−2%</strong>.`}
        </p>
        <div class="form-row" style="margin-bottom:16px">
            <label>Selecionar Nação Alvo</label>
            <select id="diplo-modal-target">${nationOptions}</select>
        </div>
        <button class="action-btn" style="${!isEnvoy ? 'border-color:var(--accent-threat);color:var(--accent-threat)' : ''}"
            onclick="engine.ui.sendDiplomaticAction('${nationObj.codigo_iso}','${action === 'diplo_envoy' ? 'enviar_embaixada' : 'sancoes_economicas'}')">
            ${isEnvoy ? '✉️ ENVIAR EMBAIXADA' : '🚫 IMPOR SANÇÕES'}
        </button>
        <p class="treasury-display">Tesouro disponível: <strong>$${treasury.toFixed(0)}B</strong></p>`;

        modal.classList.add('active');
    }

    sendDiplomaticAction(fromCode, actionType) {
        const targetSelect = document.getElementById('diplo-modal-target');
        if (!targetSelect || !targetSelect.value) return;
        const targetCode = targetSelect.value;
        this.hideGovernmentModal();
        this.engine.executeTargetedAction(fromCode, actionType, targetCode);
    }

    sendProposal(proposerNationCode) {
        const targetSelect = document.getElementById('diplomacy-target');
        const typeSelect = document.getElementById('diplomacy-type');
        if (!targetSelect || !typeSelect) {
            console.error('Elementos do formulário de proposta não encontrados.');
            return;
        }
        const targetNationCode = targetSelect.value;
        const treatyTypeId = typeSelect.value;
        if (!targetNationCode || !treatyTypeId) {
            alert('Selecione uma nação alvo e um tipo de tratado.');
            return;
        }
        const proposal = this.engine.proposeTreaty(proposerNationCode, targetNationCode, treatyTypeId);
        if (proposal) {
            this.showNotification(`Proposta de tratado enviada para ${targetNationCode}.`, 'info');
            // Refresh the diplomacy panel
            if (this.engine.state.selectedNation) {
                this.renderDiplomacy(this.engine.state.selectedNation, document.getElementById('dynamic-content'));
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // PAINEL ESPIONAGEM — Operações de Inteligência
    // ═══════════════════════════════════════════════════════════

    renderEspionagem(nation, container) {
        const playerNation = this.engine.state.playerNation;
        const iso          = nation.codigo_iso;
        const isPlayer     = this.engine.state.gameState === 'PLAYING' &&
                             playerNation?.codigo_iso === iso;
        const isSelf       = isPlayer;
        const player       = playerNation;
        const tab          = this._spyTab || 'operacoes';

        const tabBtn = (id, label, icon) => `
            <button class="eco-tab-btn ${tab === id ? 'active' : ''}"
                    onclick="engine.ui._spyTab='${id}';engine.ui.renderPanel('espionagem',engine.state.selectedNation,document.getElementById('dynamic-content'))">
                ${icon} ${label}
            </button>`;

        container.innerHTML = `
            <div class="eco-tab-bar">
                ${tabBtn('operacoes',      'Operações',         '🕵️')}
                ${tabBtn('contraintel',    'Contra-Intel',      '🛡️')}
                ${tabBtn('dossie',         'Dossiê',            '📁')}
                ${tabBtn('historico',      'Histórico',         '📋')}
            </div>
            <div id="spy-tab-content"></div>`;

        const tabEl = document.getElementById('spy-tab-content');
        if (!tabEl) return;

        switch(tab) {
            case 'operacoes':    this._renderSpyOps(nation, tabEl, player, isSelf); break;
            case 'contraintel':  this._renderCounterIntel(tabEl, player, isSelf);   break;
            case 'dossie':       this._renderSpyDossier(nation, tabEl, player);     break;
            case 'historico':    this._renderSpyLog(tabEl, player);                 break;
        }
    }

    _renderSpyOps(target, container, player, isSelf) {
        const OPS = [
            { id:'infiltrar_governo',      nome:'Infiltrar Governo',              icon:'🏛️', custo:30,  success:65, tipo:'intel',     desc:'Coleta dados políticos sigilosos: estabilidade, apoio e corrupção reais.', efeito:'Revela métricas políticas' },
            { id:'infiltrar_militar',      nome:'Infiltrar Forças Armadas',       icon:'🎖️', custo:45,  success:55, tipo:'intel',     desc:'Mapeia capacidades militares, arsenal nuclear e efetivo real.', efeito:'Revela capacidade militar' },
            { id:'roubar_tecnologia',      nome:'Roubo de Propriedade Intelectual',icon:'💾', custo:70,  success:40, tipo:'tech',      desc:'Extração de dados de P&D via espionagem cibernética avançada.', efeito:'Pesquisa atual +3 turnos' },
            { id:'campanha_desinformacao', nome:'Campanha de Desinformação',      icon:'📡', custo:25,  success:75, tipo:'influencia', desc:'Operações de influência via mídia social e agentes de informação.', efeito:'Apoio popular alvo −10%' },
            { id:'fomentar_protestos',     nome:'Fomentar Instabilidade Civil',   icon:'✊', custo:35,  success:60, tipo:'sabotagem', desc:'Financiamento de oposição, agitadores e mídia alternativa hostil.', efeito:'Estabilidade −12, Apoio −8' },
            { id:'sabotar_infraestrutura', nome:'Sabotagem de Infraestrutura',    icon:'💥', custo:55,  success:50, tipo:'sabotagem', desc:'Ataques cibernéticos e físicos a usinas, oleodutos e nós logísticos.', efeito:'PIB −2%, Estabilidade −5' },
            { id:'assassinar_lider',       nome:'Neutralização de Líder',         icon:'🎯', custo:90,  success:30, tipo:'sabotagem', desc:'Eliminação de lideranças científicas, militares ou políticas chave.', efeito:'Pesquisa pausada 4 turnos, Est −15' },
            { id:'tentar_golpe',           nome:'Apoio a Golpe de Estado',        icon:'⚡', custo:130, success:20, tipo:'golpe',     desc:'Suporte a facções golpistas. Requer instabilidade prévia do alvo (Est < 40%).', efeito:'Muda regime, Est −30%' },
        ];

        const typeColors = { intel:'#00d2ff', tech:'#b478ff', influencia:'#ffaa00', sabotagem:'#ff8844', golpe:'#ff4444' };

        const playerIntel = player?.intel_score || 0;
        const targetSec   = (target.seguranca_intel || 1) * 10;
        const treasury    = player?.tesouro || 0;

        const noPlayerMsg = !player ? `<div class="spy-empty">Selecione sua nação para executar operações.</div>` : '';
        const selfMsg     = isSelf  ? `<div class="spy-empty">Não é possível realizar operações contra si mesmo.<br>Selecione uma nação no mapa como alvo.</div>` : '';

        if (!player || isSelf) { container.innerHTML = noPlayerMsg || selfMsg; return; }

        const opsHTML = OPS.map(op => {
            const adjSuccess = Math.min(90, Math.max(10, op.success + playerIntel * 0.1 - targetSec));
            const canAfford  = treasury >= op.custo;
            const col        = typeColors[op.tipo] || '#8b949e';
            return `
            <div class="spy-op-card">
                <div class="spy-op-header">
                    <span class="spy-op-icon">${op.icon}</span>
                    <div class="spy-op-info">
                        <span class="spy-op-name">${op.nome}</span>
                        <span class="spy-op-tipo" style="color:${col}">${op.tipo.toUpperCase()}</span>
                    </div>
                    <span class="spy-op-cost">$${op.custo}B</span>
                </div>
                <p class="spy-op-desc">${op.desc}</p>
                <div class="spy-op-meta">
                    <span class="spy-meta-item">🎯 Efeito: ${op.efeito}</span>
                    <span class="spy-meta-item spy-success-rate" style="color:${adjSuccess>60?'#00ff88':adjSuccess>40?'#ffaa00':'#ff4444'}">
                        ✦ Êxito: ${adjSuccess.toFixed(0)}%
                    </span>
                </div>
                <button class="spy-exec-btn ${!canAfford?'spy-exec-disabled':''}"
                    onclick="engine.ui.confirmSpyOp('${player.codigo_iso}','${op.id}','${target.codigo_iso}','${op.nome}')"
                    ${!canAfford?'disabled':''}
                    title="${!canAfford?'Fundos insuficientes':'Executar operação'}">
                    ${canAfford?'EXECUTAR':'FUNDOS INSUFICIENTES'}
                </button>
            </div>`;
        }).join('');

        container.innerHTML = `
            <div class="spy-target-banner">
                <span class="spy-target-label">🎯 Alvo:</span>
                <span class="spy-target-name">${target.nome}</span>
                <span class="spy-target-stats">Est. ${Math.floor(target.estabilidade_politica||0)}% · Seg. Intel: Nv.${target.seguranca_intel||1}</span>
            </div>
            <div class="spy-intel-bar">
                <div class="spy-intel-item"><span>Sua Intel Score</span><span style="color:var(--accent-primary)">${playerIntel}</span></div>
                <div class="spy-intel-item"><span>Segurança Alvo</span><span style="color:#ff8844">${targetSec}pts</span></div>
                <div class="spy-intel-item"><span>Tesouro</span><span style="color:var(--accent-eco)">$${treasury.toFixed(0)}B</span></div>
            </div>
            <div class="spy-ops-grid">${opsHTML}</div>`;
    }

    confirmSpyOp(fromCode, opId, targetCode, opName) {
        const target = this.engine.data.nations[targetCode];
        const OPS_DATA = GameEngine.SPY_OPS;
        const op = OPS_DATA[opId];
        if (!op) return;
        this._showEcoActionModal(
            `🕵️ Confirmar: ${opName}`,
            `<p class="modal-current">Alvo: <strong>${target?.nome}</strong></p>
             <p class="modal-current">Custo: <strong style="color:var(--accent-warning)">$${op.custo}B</strong></p>
             <p style="font-size:0.72rem;color:var(--text-secondary);margin-top:8px">Agentes detectados causam −30 relações bilaterais. Taxa de captura: ~40% em caso de falha.</p>`,
            `engine.ui.hideGovernmentModal();engine.executeSpyOp('${fromCode}','${opId}','${targetCode}')`
        );
    }

    _renderCounterIntel(container, player, isSelf) {
        if (!player) { container.innerHTML = `<div class="spy-empty">Sem nação ativa.</div>`; return; }
        if (!isSelf) {
            // Viewing another nation's counter-intel
            container.innerHTML = `<div class="spy-empty">Contra-inteligência disponível apenas para sua própria nação.</div>`;
            return;
        }

        const lvl = player.seguranca_intel || 1;
        const lvls = [
            { id:1, nome:'Padrão',    desc:'Agências básicas de segurança. Baixa detecção.',     custo:0,   detectBonus:0  },
            { id:2, nome:'Reforçada', desc:'Contra-espionagem ativa. Detecção moderada.',         custo:15,  detectBonus:15 },
            { id:3, nome:'SIGINT',    desc:'Interceptação de sinais e análise de metadados.',      custo:30,  detectBonus:25 },
            { id:4, nome:'HUMINT',    desc:'Rede global de informantes. Alta taxa de detecção.',   custo:50,  detectBonus:35 },
        ];
        const cost = lvls.find(l=>l.id===lvl+1)?.custo || 0;

        const lvlCards = lvls.map(l => `
            <div class="ci-level-card ${l.id === lvl ? 'ci-active' : ''}">
                <div class="ci-level-header">
                    <span class="ci-level-num">Nv.${l.id}</span>
                    <span class="ci-level-name">${l.nome}</span>
                    ${l.id === lvl ? '<span class="ci-level-badge">ATIVO</span>' : ''}
                </div>
                <p class="ci-level-desc">${l.desc}</p>
                <span class="ci-level-bonus">+${l.detectBonus} Detecção / Custo: ${l.id===1?'Grátis':'$'+l.custo+'B/turno'}</span>
            </div>`).join('');

        container.innerHTML = `
            <div class="section-title">Nível de Segurança de Inteligência</div>
            <div class="ci-levels">${lvlCards}</div>
            ${lvl < 4 ? `
            <div style="margin-top:14px;text-align:center">
                <button class="spy-exec-btn" onclick="engine.ui.upgradeCounterIntel('${player.codigo_iso}')">
                    ↑ ELEVAR PARA Nv.${lvl+1} — $${cost}B/turno
                </button>
            </div>` : '<p style="text-align:center;color:var(--accent-eco);font-size:0.78rem;margin-top:14px">✓ Segurança Intel máxima atingida.</p>'}
            <div class="section-title" style="margin-top:16px">Intel Score</div>
            <div class="spy-intel-bar">
                <div class="spy-intel-item"><span>Score Atual</span><span style="color:var(--accent-primary)">${player.intel_score||0}</span></div>
                <div class="spy-intel-item"><span>Vel. Pesquisa</span><span style="color:var(--accent-eco)">×${(player.velocidade_pesquisa||1).toFixed(2)}</span></div>
                <div class="spy-intel-item"><span>Bônus Dipl.</span><span style="color:#b478ff">+${player.diplomacia_bonus||0}</span></div>
            </div>`;
    }

    upgradeCounterIntel(isoCode) {
        const nation = this.engine.data.nations[isoCode];
        if (!nation) return;
        const lvl  = nation.seguranca_intel || 1;
        if (lvl >= 4) { this.showNotification('Segurança máxima já atingida.', 'info'); return; }
        const costs = { 1:15, 2:30, 3:50 };
        const cost  = costs[lvl] || 0;
        if ((nation.tesouro || 0) < cost) { this.showNotification('Fundos insuficientes.', 'threat'); return; }
        nation.tesouro -= cost;
        nation.seguranca_intel = lvl + 1;
        this.showNotification(`Segurança Intel elevada para Nível ${lvl+1}.`, 'info');
        this.renderPanel('espionagem', this.engine.state.selectedNation);
    }

    _renderSpyDossier(target, container, player) {
        if (!player) { container.innerHTML = `<div class="spy-empty">Sem nação ativa.</div>`; return; }
        const intel   = player.intel_data?.[target.codigo_iso];
        const hasIntel = !!intel;

        const classified = (val, suffix='') => hasIntel && val !== undefined
            ? `<span style="color:var(--accent-eco)">${typeof val==='number'?val.toFixed(1):val}${suffix}</span>`
            : `<span style="color:#ff4444;font-family:var(--font-data);letter-spacing:2px">CLASSIFIED</span>`;

        const turnInfo = intel ? `<span style="color:var(--text-secondary);font-size:0.6rem">Coletado no Turno ${intel.turn}</span>` : '';

        const fmtK = v => v >= 1000 ? (v/1000).toFixed(0)+'K' : String(v||0);

        container.innerHTML = `
            <div class="spy-target-banner">
                <span class="spy-target-label">📁 Dossiê:</span>
                <span class="spy-target-name">${target.nome}</span>
                ${turnInfo}
            </div>
            ${!hasIntel ? `<div class="spy-empty" style="margin-top:16px">Nenhuma inteligência coletada sobre ${target.nome}.<br>Execute operações de infiltração primeiro.</div>` : ''}

            <div class="section-title" style="margin-top:14px">Dados Públicos</div>
            <div class="spy-dossier-grid">
                <div class="spy-dos-item"><span class="spy-dos-label">PIB</span><span>$${((target.pib_bilhoes_usd||0)/1000).toFixed(2)}T</span></div>
                <div class="spy-dos-item"><span class="spy-dos-label">Regime</span><span>${target.regime_politico||'—'}</span></div>
                <div class="spy-dos-item"><span class="spy-dos-label">Capital</span><span>${target.capital||'—'}</span></div>
                <div class="spy-dos-item"><span class="spy-dos-label">Ideologia</span><span>${target.ideologia_dominante||'—'}</span></div>
                <div class="spy-dos-item"><span class="spy-dos-label">Nukes</span><span style="color:${(target.militar?.armas_nucleares||0)>0?'#ff4444':'#8b949e'}">${target.militar?.armas_nucleares||0}</span></div>
                <div class="spy-dos-item"><span class="spy-dos-label">Techs</span><span>${(target.tecnologias_concluidas||[]).length}</span></div>
            </div>

            <div class="section-title" style="margin-top:12px">Dados Classificados (via Infiltração)</div>
            <div class="spy-dossier-grid">
                <div class="spy-dos-item"><span class="spy-dos-label">Estabilidade Real</span>${classified(intel?.estabilidade, '%')}</div>
                <div class="spy-dos-item"><span class="spy-dos-label">Apoio Popular</span>${classified(intel?.apoio, '%')}</div>
                <div class="spy-dos-item"><span class="spy-dos-label">Corrupção</span>${classified(intel?.corrupcao, '%')}</div>
                <div class="spy-dos-item"><span class="spy-dos-label">Felicidade</span>${classified(intel?.felicidade, '%')}</div>
                <div class="spy-dos-item"><span class="spy-dos-label">Poder Militar</span>${classified(intel?.poder_militar)}</div>
                <div class="spy-dos-item"><span class="spy-dos-label">Orçamento Mil.</span>${classified(intel?.orcamento_mil, 'B')}</div>
                ${intel?.unidades ? `
                <div class="spy-dos-item"><span class="spy-dos-label">Infantaria</span><span style="color:var(--accent-eco)">${fmtK(intel.unidades.infantaria)}</span></div>
                <div class="spy-dos-item"><span class="spy-dos-label">Tanques</span><span style="color:var(--accent-eco)">${fmtK(intel.unidades.tanques)}</span></div>
                <div class="spy-dos-item"><span class="spy-dos-label">Aviões</span><span style="color:var(--accent-eco)">${fmtK(intel.unidades.avioes)}</span></div>
                <div class="spy-dos-item"><span class="spy-dos-label">Navios</span><span style="color:var(--accent-eco)">${fmtK(intel.unidades.navios)}</span></div>` : ''}
            </div>`;
    }

    _renderSpyLog(container, player) {
        if (!player) { container.innerHTML = `<div class="spy-empty">Sem nação ativa.</div>`; return; }
        const log = (player.spy_ops_log || []).slice(0, 30);
        if (!log.length) {
            container.innerHTML = `<div class="spy-empty">Nenhuma operação executada ainda.</div>`;
            return;
        }
        const opNames = {
            infiltrar_governo:'Infiltração no Governo', infiltrar_militar:'Infiltração Militar',
            roubar_tecnologia:'Roubo Tecnológico', sabotar_infraestrutura:'Sabotagem de Infraestrutura',
            fomentar_protestos:'Fomento de Protestos', assassinar_lider:'Neutralização de Líder',
            tentar_golpe:'Apoio a Golpe', campanha_desinformacao:'Campanha de Desinformação'
        };
        const rows = log.map(entry => {
            const col   = entry.success ? '#00ff88' : entry.caught ? '#ff4444' : '#ffaa00';
            const label = entry.success ? '✅ ÊXITO' : entry.caught ? '❌ CAPTURADO' : '⚠️ FALHOU';
            return `<div class="spy-log-row">
                <span class="spy-log-turn">T${entry.turn}</span>
                <span class="spy-log-op">${opNames[entry.op]||entry.op}</span>
                <span class="spy-log-target">→ ${entry.target}</span>
                <span class="spy-log-result" style="color:${col}">${label}</span>
            </div>`;
        }).join('');
        container.innerHTML = `<div class="spy-log">${rows}</div>`;
    }

    renderSelectionPreview(nation) {
        const details = document.getElementById('nation-details');
        if (!details) return;

        details.innerHTML = `
            <div id="panel-content" style="animation: fadeIn 0.5s ease-out;">
                <h2 style="color: var(--accent-secondary);">${nation.nome}</h2>
                <p style="color: var(--text-secondary); margin-bottom: 20px;">Dossiê de Seleção Nacional</p>
                
                <div class="data-grid">
                    <div class="data-card"><span class="label">PIB</span><span class="value">$${((nation.pib_bilhoes_usd || 0) / 1000).toFixed(2)}T</span></div>
                    <div class="data-card"><span class="label">População</span><span class="value">${((nation.populacao || 0) / 1000000).toFixed(1)}M</span></div>
                    <div class="data-card"><span class="label">Poder Militar</span><span class="value">${(nation.militar ? nation.militar.poder_militar_global : 0)}</span></div>
                    <div class="data-card"><span class="label">Estabilidade</span><span class="value">${nation.estabilidade_politica || 0}%</span></div>
                </div>

                <div class="section-title">Análise Estratégica</div>
                <p style="font-size: 0.8rem; line-height: 1.5; color: var(--text-dim); margin-bottom: 20px;">
                    Assumir o comando da <strong>${nation.nome}</strong> exigirá um equilíbrio entre crescimento econômico e manutenção da estabilidade regional.
                </p>

                <button class="action-btn" style="background: var(--accent-secondary); color: var(--bg-deep); border: none;" onclick="engine.confirmNation('${nation.codigo_iso}')">ASSUMIR COMANDO</button>
            </div>
        `;
    }

    showNotification(msg, type = 'info') {
        let toast = document.getElementById('game-toast');
        if (!toast) {
            toast = document.createElement('div');
            toast.id = 'game-toast';
            toast.style.cssText = `
                position:fixed; bottom:60px; left:50%; transform:translateX(-50%);
                max-width:600px; width:90%; padding:10px 18px;
                font-family:var(--font-data); font-size:0.75rem; letter-spacing:1px;
                border-radius:3px; border-left:3px solid;
                backdrop-filter:blur(10px);
                z-index:9999; pointer-events:none;
                transition:opacity 0.3s ease; opacity:0;
            `;
            document.body.appendChild(toast);
        }
        const colors = {
            info:    { bg:'rgba(0,210,255,0.12)',  border:'var(--accent-primary)', text:'var(--accent-primary)' },
            threat:  { bg:'rgba(255,51,51,0.12)',  border:'var(--accent-threat)',  text:'var(--accent-threat)'  },
            success: { bg:'rgba(0,255,136,0.12)',  border:'var(--accent-eco)',     text:'var(--accent-eco)'     },
        };
        const c = colors[type] || colors.info;
        toast.style.background   = c.bg;
        toast.style.borderColor  = c.border;
        toast.style.color        = c.text;
        toast.textContent = msg;
        toast.style.opacity = '1';
        clearTimeout(this._toastTimer);
        this._toastTimer = setTimeout(() => { toast.style.opacity = '0'; }, 4000);
    }

    /**
     * Shows a choice-based event modal to the player.
     * @param {Object} event - The event object with choices[]
     * @param {Function} onChoice - Callback(choiceIndex)
     */
    showEventChoiceModal(event, onChoice) {
        // Remove any existing event modal
        const existing = document.getElementById('event-choice-modal');
        if (existing) existing.remove();

        const modal = document.createElement('div');
        modal.id = 'event-choice-modal';
        modal.style.cssText = `
            position:fixed;inset:0;background:rgba(0,0,0,0.85);
            display:flex;align-items:center;justify-content:center;
            z-index:9990;opacity:0;transition:opacity 0.4s ease;
        `;

        const choicesHTML = (event.choices || []).map((c, i) => {
            const efStr = c.efeitos ? Object.entries(c.efeitos).map(([k,v]) => {
                const val = typeof v === 'number' ? (v > 0 ? `+${v}` : v) : v;
                return `<span class="ecm-eff">${k}: ${val}</span>`;
            }).join('') : '';
            return `
            <button class="ecm-choice" onclick="
                document.getElementById('event-choice-modal').remove();
                window.__eventChoiceCb(${i});
            ">
                <div class="ecm-choice-label">${c.label || c.texto || `Opção ${i+1}`}</div>
                ${efStr ? `<div class="ecm-effects">${efStr}</div>` : ''}
            </button>`;
        }).join('');

        modal.innerHTML = `
        <div style="background:#0d1117;border:1px solid rgba(0,210,255,0.2);border-radius:6px;
            padding:36px 40px;max-width:540px;width:90%;position:relative;overflow:hidden;">
            <div style="position:absolute;inset:0;background:repeating-linear-gradient(0deg,transparent,transparent 3px,rgba(0,0,0,0.1) 3px,rgba(0,0,0,0.1) 4px);pointer-events:none"></div>
            <div style="font-family:var(--font-data);font-size:0.6rem;letter-spacing:3px;color:var(--accent-primary);margin-bottom:8px">⚡ EVENTO CRÍTICO</div>
            <h3 style="color:#fff;font-size:1.1rem;margin-bottom:12px;font-family:var(--font-data)">${event.nome}</h3>
            <p style="color:var(--text-secondary);font-size:0.82rem;line-height:1.6;margin-bottom:20px;border-bottom:1px solid rgba(255,255,255,0.07);padding-bottom:16px">
                ${event.descricao || event.texto || ''}
            </p>
            <div style="display:flex;flex-direction:column;gap:8px">${choicesHTML}</div>
        </div>`;

        document.body.appendChild(modal);
        window.__eventChoiceCb = onChoice;
        requestAnimationFrame(() => { modal.style.opacity = '1'; });
    }
}
