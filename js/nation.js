/**
 * Nation class to manage individual country state
 */
class Nation {
    constructor(data) {
        Object.assign(this, data);
        // Initialize relations if not present
        if (!this.relacoes) this.relacoes = {};
        if (!this.recursos) this.recursos = {};
        if (!this.tecnologias_concluidas) this.tecnologias_concluidas = [];
        if (!this.pesquisa_atual) this.pesquisa_atual = null;
        if (!this.personalidade) this.personalidade = 'agressivo';
        if (!this.memoria) this.memoria = [];
        // Government internal metrics
        if (this.apoio_popular === undefined) this.apoio_popular = 50;
        if (this.corrupcao === undefined) this.corrupcao = 30;
        if (this.burocracia_eficiencia === undefined) this.burocracia_eficiencia = 70;
        if (this.proxima_eleicao_turno === undefined) this.proxima_eleicao_turno = null;
        if (this.intervalo_eleicoes === undefined) this.intervalo_eleicoes = 20;
        if (this.felicidade === undefined) this.felicidade = 60;
        // Spy / intel fields
        if (this.intel_score === undefined) this.intel_score = 0;
        if (this.seguranca_intel === undefined) this.seguranca_intel = 1;
        if (this.velocidade_pesquisa === undefined) this.velocidade_pesquisa = 1;
        if (!this.em_guerra) this.em_guerra = [];
        if (!this.intel_data) this.intel_data = {};
        if (!this.spy_ops_log) this.spy_ops_log = [];
        if (!this.gasto_social) this.gasto_social = { saude: 0, educacao: 0, previdencia: 0, seguranca: 0 };
        // Inflation & crisis tracking
        if (this.inflacao === undefined) this.inflacao = 5;
        if (this.revolucao_turnos === undefined) this.revolucao_turnos = 0;
        if (this.falencia_turnos === undefined) this.falencia_turnos = 0;

        // Historical data for charts (max 20 turns)
        if (!this.historico) this.historico = {
            estabilidade: [],
            apoio_popular: [],
            corrupcao: [],
            felicidade: [],
            burocracia: [],
            poder_militar: [],
            orcamento_militar: [],
            infantaria: [],
            tanques: [],
            avioes: [],
            navios: [],
            pib: [],
            populacao: [],
            tesouro: [],
            inflacao: []
        };
        // Tesouro inicial: 5% do PIB anual
        if (this.tesouro === undefined) this.tesouro = Math.round(this.pib_bilhoes_usd * 0.05);
        // Garante compatibilidade com saves antigos que não tinham historico.tesouro
        if (this.historico && !this.historico.tesouro) this.historico.tesouro = [];
        this.initializeElectionTimer();
    }

    updatePIB(globalEconomyFactor) {
        // Simple PIB growth logic
        const growth = (this.estabilidade_politica / 100) * globalEconomyFactor * 0.02;
        this.pib_bilhoes_usd *= (1 + growth);
    }

    updateApproval(events) {
        // Compute target from political indicators
        const target = (this.estabilidade_politica * 0.5 + this.felicidade * 0.5) - this.corrupcao * 0.2;
        const clampedTarget = Math.max(0, Math.min(100, target));
        // Gradual convergence: propaganda/actions create persistent effects that fade over turns
        this.apoio_popular = this.apoio_popular * 0.8 + clampedTarget * 0.2;
        // Apply event modifiers
        if (events && events.length) {
            events.forEach(ev => {
                if (ev.efeitos && ev.efeitos.apoio_popular) {
                    this.apoio_popular += ev.efeitos.apoio_popular;
                }
            });
        }
        this.apoio_popular = Math.max(0, Math.min(100, this.apoio_popular));
    }

    recordHistory() {
        const MAX = 20;
        const push = (arr, val) => {
            arr.push(parseFloat((val || 0).toFixed(1)));
            if (arr.length > MAX) arr.shift();
        };
        push(this.historico.estabilidade, this.estabilidade_politica);
        push(this.historico.apoio_popular, this.apoio_popular);
        push(this.historico.corrupcao, this.corrupcao);
        push(this.historico.felicidade, this.felicidade);
        push(this.historico.burocracia, this.burocracia_eficiencia);
        // Military
        const m = this.militar || {};
        const u = m.unidades || {};
        push(this.historico.poder_militar,    m.poder_militar_global       || 0);
        push(this.historico.orcamento_militar, m.orcamento_militar_bilhoes || 0);
        push(this.historico.infantaria, u.infantaria || 0);
        push(this.historico.tanques,    u.tanques    || 0);
        push(this.historico.avioes,     u.avioes     || 0);
        push(this.historico.navios,     u.navios     || 0);
        // Economy
        push(this.historico.pib,       this.pib_bilhoes_usd || 0);
        push(this.historico.populacao, (this.populacao || 0) / 1000000);
        push(this.historico.tesouro, this.tesouro || 0);
        if (this.historico.inflacao) push(this.historico.inflacao, this.inflacao || 0);
    }

    isDemocratic() {
        const regime = this.regime_politico || '';
        return regime.includes('DEMOCRACIA') || regime.includes('REPUBLICA') || regime.includes('PARLAMENTAR');
    }

    calcTaxRate() {
        const r = this.regime_politico || '';
        if (r.includes('COMUNIS')) return 0.35;
        if (r.includes('SOCIAL')) return 0.28;
        if (r.includes('DEMOCRA')) return 0.22;
        if (r.includes('AUTORITA')) return 0.18;
        return 0.20;
    }

    // Receita trimestral (1 turno = 1 trimestre)
    calcReceita() {
        const taxRate = this.calcTaxRate();
        const impostos = this.pib_bilhoes_usd * taxRate / 4;
        // Bônus de exportação de recursos (média dos recursos × 2% do PIB anual / 4)
        const recursos = this.recursos || {};
        const vals = Object.values(recursos);
        const avgResource = vals.length ? vals.reduce((a, b) => a + b, 0) / vals.length : 0;
        const exportBonus = this.pib_bilhoes_usd * (avgResource / 100) * 0.02 / 4;
        return impostos + exportBonus;
    }

    // Despesas trimestrais
    calcDespesas() {
        const milBudget = (this.militar?.orcamento_militar_bilhoes || 0) / 4;
        const govSpend  = this.pib_bilhoes_usd * 0.10 / 4;
        return milBudget + govSpend;
    }

    // Saldo líquido por turno
    calcSaldo() {
        return this.calcReceita() - this.calcDespesas();
    }

    // Atualizar tesouro ao final de cada turno
    processTurnFinances() {
        const saldo = this.calcSaldo();
        this.tesouro = Math.max(0, this.tesouro + saldo);
        // Teto: 25% do PIB anual (evita acúmulo ilimitado)
        this.tesouro = Math.min(this.tesouro, this.pib_bilhoes_usd * 0.25);

        // ── Inflação ────────────────────────────────────────────────────────────
        // Base: 2%. Piora com deficit, gastos militares acima de 5% do PIB, e guerras.
        const gdpQ = Math.max(1, this.pib_bilhoes_usd / 4);
        const deficitRatio = Math.max(0, -saldo) / gdpQ;          // 0-1+
        const milPct = (this.militar?.orcamento_militar_bilhoes || 0) / Math.max(1, this.pib_bilhoes_usd) * 100;
        const milPressure = Math.max(0, milPct - 5);               // above 5% GDP is inflationary
        const warPressure = (this.em_guerra?.length || 0) * 3;     // +3pp per active war
        const socialSpend = Object.values(this.gasto_social || {}).reduce((a, b) => a + b, 0);
        const socialPressure = Math.max(0, (socialSpend / gdpQ) - 0.5); // excess social spending

        const inflacaoTarget = 2 + deficitRatio * 25 + milPressure * 1.5 + warPressure + socialPressure * 10;
        this.inflacao = Math.max(0, Math.min(100,
            this.inflacao * 0.80 + inflacaoTarget * 0.20
        ));

        // High inflation erodes happiness and popular support
        if (this.inflacao > 15) {
            const penalty = (this.inflacao - 15) * 0.25;
            this.felicidade    = Math.max(0, (this.felicidade    || 60) - penalty);
            this.apoio_popular = Math.max(0, (this.apoio_popular || 50) - penalty * 0.8);
        }
    }

    initializeElectionTimer() {
        if (this.isDemocratic() && this.proxima_eleicao_turno === null) {
            this.proxima_eleicao_turno = this.intervalo_eleicoes;
        }
    }

    updateElections() {
        if (this.isDemocratic() && this.proxima_eleicao_turno !== null) {
            if (this.proxima_eleicao_turno > 0) {
                this.proxima_eleicao_turno--;
            } else {
                this.triggerElection();
            }
        }
    }

    triggerElection() {
        // Reset election timer
        this.proxima_eleicao_turno = this.intervalo_eleicoes;
        // Determine election outcome based on approval
        const chanceReeleicao = this.apoio_popular / 100;
        if (Math.random() < chanceReeleicao) {
            // Re-election success
            this.apoio_popular += 5;
            this.estabilidade_politica += 10;
        } else {
            // Government loses, opposition takes over (simplified)
            this.apoio_popular -= 20;
            this.estabilidade_politica -= 15;
            // Possibly change ideology? Not implemented yet
        }
        // Clamp values
        this.apoio_popular = Math.max(0, Math.min(100, this.apoio_popular));
        this.estabilidade_politica = Math.max(0, Math.min(100, this.estabilidade_politica));
    }

    updateGovernment(globalEconomyFactor) {
        // Update happiness based on economic growth and stability
        const growth = (this.pib_bilhoes_usd - (this.pib_bilhoes_usd / (1 + globalEconomyFactor))) / this.pib_bilhoes_usd;
        this.felicidade = Math.max(0, Math.min(100, this.felicidade + growth * 10 + (this.estabilidade_politica - 50) * 0.1));
        // Corruption may increase or decrease randomly
        if (Math.random() < 0.3) {
            this.corrupcao += Math.random() * 2 - 1; // small random change
        }
        // Bureaucracy efficiency slowly converges to 70
        this.burocracia_eficiencia += (70 - this.burocracia_eficiencia) * 0.05;
        // Clamp values
        this.corrupcao = Math.max(0, Math.min(100, this.corrupcao));
        this.burocracia_eficiencia = Math.max(0, Math.min(100, this.burocracia_eficiencia));
    }
}
