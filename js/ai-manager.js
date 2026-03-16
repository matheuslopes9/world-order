/**
 * Gerenciador de IA para nações não‑jogador (NPC).
 * Utiliza personalidades para tomar decisões contextualizadas.
 */
class AIManager {
    constructor(engine) {
        this.engine = engine;
        this.personalities = {};
        // loadPersonalities() é chamado explicitamente (com await) no game-engine.js init()
    }

    /**
     * Carrega as personalidades do arquivo JSON.
     */
    async loadPersonalities() {
        try {
            const response = await fetch('data/personalities.json');
            const data = await response.json();
            this.personalities = data.personalities;
            console.log(`> ${Object.keys(this.personalities).length} personalidades carregadas.`);
        } catch (error) {
            console.error("Erro ao carregar personalidades:", error);
            this.personalities = {};
        }
    }

    /**
     * Retorna a personalidade de uma nação (padrão 'agressivo' se não definida).
     */
    getPersonality(nation) {
        const code = nation.codigo_iso;
        // Use real 2024 leader mapping first
        const leader2024 = this.personalities.leaders_2024?.[code];
        if (leader2024) {
            const p = this.personalities[leader2024.personalidade];
            if (p) return p;
        }
        const personalityId = nation.personalidade || 'agressivo';
        return this.personalities[personalityId] || this.personalities['agressivo'];
    }

    /** Returns leader name for display in UI */
    getLeaderName(nation) {
        const code = nation.codigo_iso;
        const leader2024 = this.personalities.leaders_2024?.[code];
        return leader2024?.lider || null;
    }

    /**
     * Calcula a utilidade de uma ação para uma determinada nação.
     * @param {Nation} nation - A nação NPC.
     * @param {string} actionId - ID da ação (ex: 'invest_infra').
     * @returns {number} Pontuação de utilidade (maior = mais desejável).
     */
    computeActionUtility(nation, actionId) {
        const personality = this.getPersonality(nation);
        const peso = (personality?.pesos_acao?.[actionId]) ?? 0.5;

        // Fatores contextuais
        let factor = 1.0;

        // Exemplo: se estabilidade baixa, reforma política ganha peso extra
        if (actionId === 'reforma_politica' && nation.estabilidade_politica < 60) {
            factor += (60 - nation.estabilidade_politica) / 100;
        }

        // Se relação muito negativa, ações militares ganham peso
        const relations = Object.values(nation.relacoes || {});
        const worstRelation = relations.length ? Math.min(...relations) : 0;
        if (actionId.includes('recrutar') && worstRelation < -70) {
            factor += Math.abs(worstRelation) / 100;
        }

        // Se tesouro da nação insuficiente, ações caras perdem peso
        const cost = this.getActionCost(actionId);
        if (cost > (nation.tesouro || 0)) {
            factor *= 0.3; // Penalidade forte
        }

        // Aleatoriedade controlada (variação de ±20%)
        const randomVariation = 0.8 + Math.random() * 0.4;
        return peso * factor * randomVariation;
    }

    /**
     * Retorna o custo em Tesouro Global de uma ação (valores hardcoded por enquanto).
     */
    getActionCost(actionId) {
        const costs = {
            invest_infra: 50,
            reforma_politica: 0,
            melhorar_relacoes: 0,
            recrutar_tanques: 5,
            recrutar_avioes: 10,
            mobilizar: 0
        };
        return costs[actionId] || 0;
    }

    /**
     * Lista de ações possíveis para NPCs (apenas as implementadas no GameEngine).
     */
    getPossibleActions() {
        return [
            'invest_infra',
            'reforma_politica',
            'melhorar_relacoes',
            'recrutar_tanques',
            'recrutar_avioes',
            'mobilizar'
        ];
    }

    /**
     * Escolhe a melhor ação para uma nação NPC.
     * @param {Nation} nation - A nação NPC.
     * @returns {string} ID da ação escolhida.
     */
    chooseAction(nation) {
        const actions = this.getPossibleActions();
        let bestAction = 'invest_infra'; // fallback
        let bestScore = -Infinity;

        for (const action of actions) {
            const score = this.computeActionUtility(nation, action);
            if (score > bestScore) {
                bestScore = score;
                bestAction = action;
            }
        }

        console.log(`IA ${nation.nome} (${this.getPersonality(nation).nome}) escolheu ${bestAction} (score ${bestScore.toFixed(2)})`);
        return bestAction;
    }

    /**
     * Executa a IA para todas as nações NPC (substitui runAINations).
     * @param {number} maxActors - Número máximo de nações que agem por turno (padrão 5).
     */
    run(maxActors = 5) {
        const codes = Object.keys(this.engine.data.nations)
            .filter(c => this.engine.data.nations[c] !== this.engine.state.playerNation);
        const actors = codes.sort(() => 0.5 - Math.random()).slice(0, maxActors);

        actors.forEach(code => {
            const nation = this.engine.data.nations[code];
            const action = this.chooseAction(nation);
            this.engine.executeAction(code, action);
        });
    }
}