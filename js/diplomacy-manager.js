/**
 * DiplomacyManager handles treaty creation, negotiation, and effects.
 */
class DiplomacyManager {
    constructor(engine) {
        this.engine = engine;
        this.treaties = []; // active treaties
        this.treatyTypes = {};
        this.proposals = []; // pending proposals
        // loadTreatyTypes() é chamado explicitamente (com await) no game-engine.js init()
        this.loadTreaties();
    }

    /**
     * Load treaty type definitions from JSON.
     */
    async loadTreatyTypes() {
        try {
            const response = await fetch('data/treaty-types.json');
            const data = await response.json();
            this.treatyTypes = data.tiposTratado.reduce((acc, type) => {
                acc[type.id] = type;
                return acc;
            }, {});
            console.log(`> ${Object.keys(this.treatyTypes).length} tipos de tratado carregados.`);
        } catch (error) {
            console.error("Erro ao carregar tipos de tratado:", error);
            this.treatyTypes = {};
        }
    }

    /**
     * Load saved treaties from localStorage.
     */
    loadTreaties() {
        const saved = localStorage.getItem('worldOrder_treaties');
        if (saved) {
            try {
                const data = JSON.parse(saved);
                this.treaties = data.map(t => Treaty.fromJSON(t));
                console.log(`> ${this.treaties.length} tratados carregados.`);
            } catch (e) {
                console.error("Erro ao carregar tratados:", e);
                this.treaties = [];
            }
        }
    }

    /**
     * Save treaties to localStorage.
     */
    saveTreaties() {
        const data = this.treaties.map(t => t.toJSON());
        localStorage.setItem('worldOrder_treaties', JSON.stringify(data));
    }

    /**
     * Get treaty type by ID.
     * @param {string} id
     * @returns {Object}
     */
    getTreatyType(id) {
        return this.treatyTypes[id];
    }

    /**
     * Create a new treaty proposal.
     * @param {string} proposerNationCode - ISO code of proposing nation
     * @param {string} targetNationCode - ISO code of target nation
     * @param {string} treatyTypeId - ID from treaty-types.json
     * @param {Object} customTerms - optional custom terms (duration, specific bonuses)
     * @returns {Object} proposal object
     */
    proposeTreaty(proposerNationCode, targetNationCode, treatyTypeId, customTerms = {}) {
        const type = this.getTreatyType(treatyTypeId);
        if (!type) {
            console.error(`Tipo de tratado desconhecido: ${treatyTypeId}`);
            return null;
        }

        const proposal = {
            id: `proposal_${Date.now()}_${Math.random().toString(36).substr(2, 5)}`,
            proposer: proposerNationCode,
            target: targetNationCode,
            treatyTypeId,
            terms: {
                ...customTerms,
                duration: customTerms.duration || this.calculateDuration(type)
            },
            turn: this.engine.state.currentTurn,
            status: 'pending' // pending, accepted, rejected
        };

        // If proposer is AI, evaluate immediately? Actually we need AI decision.
        // For now, add to pending list.
        this.proposals.push(proposal);
        console.log(`Proposta de tratado criada: ${proposal.id}`, proposal);
        // Notify player if target is player
        if (this.engine.ui && targetNationCode === this.engine.state.playerNation?.codigo_iso) {
            const proposerName = this.engine.data.nations[proposerNationCode]?.nome || proposerNationCode;
            const treatyName = type.nome || treatyTypeId;
            this.engine.ui.showNotification(
                `${proposerName} propôs um tratado de ${treatyName}. Verifique a aba Diplomacia.`,
                'info'
            );
        }
        return proposal;
    }

    /**
     * Calculate default duration based on treaty type range.
     * @param {Object} type
     * @returns {number} duration in turns
     */
    calculateDuration(type) {
        if (type.duracao_min === 0 && type.duracao_max === 0) return 0; // indefinite
        const min = type.duracao_min || 10;
        const max = type.duracao_max || 30;
        return min + Math.floor(Math.random() * (max - min + 1));
    }

    /**
     * Evaluate a proposal from AI perspective.
     * @param {Object} proposal
     * @returns {boolean} true if AI accepts
     */
    evaluateProposal(proposal) {
        const targetNation = this.engine.data.nations[proposal.target];
        if (!targetNation) return false;

        // Use AI manager if available
        const ai = this.engine.aiManager;
        if (!ai) {
            // fallback: accept based on relation
            const relation = targetNation.relacoes?.[proposal.proposer] || 0;
            return relation > 30;
        }

        // Compute utility based on personality, relations, treaty type
        const personality = ai.getPersonality(targetNation);
        let score = 0;

        // Base weight from personality (if defined)
        const personalityWeights = personality.pesos_tratado || {};
        const weight = personalityWeights[proposal.treatyTypeId] || 0.5;
        score += weight * 100;

        // Relation modifier: better relations increase acceptance
        const relation = targetNation.relacoes?.[proposal.proposer] || 0;
        score += relation * 0.5;

        // Context: if nation is isolated, more likely to accept alliances
        if (proposal.treatyTypeId === 'alianca_militar') {
            const allies = this.treaties.filter(t => 
                t.signatories.includes(proposal.target) && t.type === 'alianca_militar'
            ).length;
            if (allies === 0) score += 30; // no allies, wants one
        }

        // Random factor ±20
        score += (Math.random() - 0.5) * 40;

        // Acceptance threshold
        return score > 50;
    }

    /**
     * Process pending proposals (AI decisions) and create treaties if accepted.
     */
    processProposals() {
        const remaining = [];
        this.proposals.forEach(proposal => {
            if (proposal.status !== 'pending') {
                remaining.push(proposal);
                return;
            }

            // If target is AI, evaluate
            const isPlayer = proposal.target === this.engine.state.playerNation?.codigo_iso;
            if (!isPlayer) {
                const accept = this.evaluateProposal(proposal);
                if (accept) {
                    this.acceptProposal(proposal);
                } else {
                    this.rejectProposal(proposal);
                }
            } else {
                // Player proposals stay pending until UI action
                remaining.push(proposal);
            }
        });
        this.proposals = remaining;
    }

    /**
     * Accept a proposal and create a treaty.
     * @param {Object} proposal
     */
    acceptProposal(proposal) {
        proposal.status = 'accepted';
        const type = this.getTreatyType(proposal.treatyTypeId);
        const treaty = new Treaty({
            id: `treaty_${Date.now()}_${Math.random().toString(36).substr(2, 5)}`,
            type: proposal.treatyTypeId,
            typeData: type,
            signatories: [proposal.proposer, proposal.target],
            terms: proposal.terms,
            createdTurn: this.engine.state.currentTurn,
            status: 'active'
        });
        this.treaties.push(treaty);
        console.log(`Tratado aceito e criado: ${treaty.id}`);
        this.saveTreaties();
        // Notify UI
        if (this.engine.ui) {
            this.engine.ui.showNotification(
                `Tratado de ${type.nome} entre ${proposal.proposer} e ${proposal.target} foi estabelecido.`,
                "info"
            );
        }
    }

    /**
     * Reject a proposal.
     * @param {Object} proposal
     */
    rejectProposal(proposal) {
        proposal.status = 'rejected';
        console.log(`Proposta ${proposal.id} rejeitada.`);
        // Optionally notify UI
    }

    /**
     * Process treaty effects for all active treaties.
     * Called each turn.
     */
    processTreaties() {
        const conflictData = this.buildConflictMap();
        this.treaties.forEach(treaty => {
            treaty.applyEffects(this.engine.data.nations, this.engine);
            treaty.expire(this.engine.state.currentTurn);
            // Check for violations
            if (treaty.isActive() && treaty.checkViolation(conflictData)) {
                // Violation detected, apply rupture penalty
                this.applyRupturePenalty(treaty);
                // Notify UI
                if (this.engine.ui) {
                    this.engine.ui.showNotification(
                        `Tratado ${treaty.type} violado por conflito entre signatários.`,
                        'threat'
                    );
                }
            }
        });
        // Remove expired treaties
        this.treaties = this.treaties.filter(t => t.isActive());
        this.saveTreaties();
    }

    /**
     * Get active treaties involving a specific nation.
     * @param {string} nationCode
     * @returns {Array<Treaty>}
     */
    getTreatiesForNation(nationCode) {
        return this.treaties.filter(t => t.signatories.includes(nationCode));
    }

    /**
     * Get pending proposals targeting a specific nation.
     * @param {string} nationCode
     * @returns {Array<Object>}
     */
    getProposalsForNation(nationCode) {
        return this.proposals.filter(p => p.target === nationCode && p.status === 'pending');
    }

    /**
     * Player accepts a pending proposal.
     * @param {string} proposalId
     */
    playerAcceptProposal(proposalId) {
        const proposal = this.proposals.find(p => p.id === proposalId);
        if (proposal && proposal.status === 'pending') {
            this.acceptProposal(proposal);
            this.proposals = this.proposals.filter(p => p.id !== proposalId);
        }
    }

    /**
     * Player rejects a pending proposal.
     * @param {string} proposalId
     */
    playerRejectProposal(proposalId) {
        const proposal = this.proposals.find(p => p.id === proposalId);
        if (proposal && proposal.status === 'pending') {
            this.rejectProposal(proposal);
            this.proposals = this.proposals.filter(p => p.id !== proposalId);
        }
    }

    /**
     * Player breaks an active treaty (voluntary rupture).
     * @param {string} treatyId
     */
    playerBreakTreaty(treatyId) {
        const treaty = this.treaties.find(t => t.id === treatyId);
        if (!treaty) {
            console.error(`Tratado ${treatyId} não encontrado.`);
            return;
        }
        treaty.status = 'violated';
        // Apply rupture penalties (could be relation penalty)
        this.applyRupturePenalty(treaty);
        console.log(`Tratado ${treatyId} rompido pelo jogador.`);
        this.saveTreaties();
        // Notify UI
        const type = this.getTreatyType(treaty.type);
        if (this.engine.ui) {
            this.engine.ui.showNotification(`Tratado ${type?.nome || treaty.type} rompido.`, 'threat');
        }
    }

    /**
     * Apply rupture penalty to relations between signatories.
     * @param {Treaty} treaty
     */
    applyRupturePenalty(treaty) {
        const type = this.getTreatyType(treaty.type);
        if (!type || !type.efeitos || !type.efeitos.penalidade_relacao_quebra) return;
        const penalty = type.efeitos.penalidade_relacao_quebra; // negative value
        const signatories = treaty.signatories;
        for (let i = 0; i < signatories.length; i++) {
            for (let j = i + 1; j < signatories.length; j++) {
                const a = signatories[i];
                const b = signatories[j];
                const nationA = this.engine.data.nations[a];
                const nationB = this.engine.data.nations[b];
                if (nationA && nationB) {
                    // Ensure relations exist
                    if (nationA.relacoes[b] === undefined) nationA.relacoes[b] = 0;
                    if (nationB.relacoes[a] === undefined) nationB.relacoes[a] = 0;
                    // Apply penalty (both directions)
                    nationA.relacoes[b] += penalty;
                    nationB.relacoes[a] += penalty;
                    // Clamp between -100 and 100
                    if (nationA.relacoes[b] > 100) nationA.relacoes[b] = 100;
                    if (nationA.relacoes[b] < -100) nationA.relacoes[b] = -100;
                    if (nationB.relacoes[a] > 100) nationB.relacoes[a] = 100;
                    if (nationB.relacoes[a] < -100) nationB.relacoes[a] = -100;
                }
            }
        }
    }

    /**
     * Build conflict data mapping for treaty violation detection.
     * @returns {Object} mapping of pair code (e.g., "RU_UA") to conflict object with turn.
     */
    buildConflictMap() {
        const map = {};
        map.turn = this.engine.state.currentTurn;
        const conflicts = this.engine.data.conflicts || [];
        conflicts.forEach(conflict => {
            const attackers = conflict.beligerantes.atacante || [];
            const defenders = conflict.beligerantes.defensor || [];
            const allParties = [...attackers, ...defenders];
            // Generate all pairs among parties
            for (let i = 0; i < allParties.length; i++) {
                for (let j = i + 1; j < allParties.length; j++) {
                    const pair = [allParties[i], allParties[j]].sort().join('_');
                    map[pair] = true;
                }
            }
        });
        return map;
    }

    /**
     * Generate treaty proposals from AI nations.
     * Called each turn.
     */
    generateAIProposals() {
        const playerNationCode = this.engine.state.playerNation?.codigo_iso;
        const nations = this.engine.data.nations;
        const aiNations = Object.keys(nations).filter(code => code !== playerNationCode);
        if (aiNations.length === 0) return;

        aiNations.forEach(proposerCode => {
            // Chance to propose a treaty each turn (e.g., 15%)
            if (Math.random() > 0.15) return;

            // Select target nation (excluding self)
            const possibleTargets = Object.keys(nations).filter(code => code !== proposerCode);
            if (possibleTargets.length === 0) return;
            const targetCode = possibleTargets[Math.floor(Math.random() * possibleTargets.length)];

            // Determine treaty type based on personality weights
            const proposerNation = nations[proposerCode];
            const personality = this.engine.aiManager?.getPersonality(proposerNation);
            const treatyWeights = personality?.pesos_tratado || {};
            const availableTreatyTypes = Object.keys(this.treatyTypes);
            const treatyTypes = Object.keys(treatyWeights).length > 0
                ? Object.keys(treatyWeights)
                : availableTreatyTypes;
            if (treatyTypes.length === 0) return;
            // Weighted random selection
            const totalWeight = treatyTypes.reduce((sum, type) => sum + (treatyWeights[type] || 0), 0);
            let random = Math.random() * totalWeight;
            let selectedType = treatyTypes[0];
            for (const type of treatyTypes) {
                random -= treatyWeights[type] || 0;
                if (random <= 0) {
                    selectedType = type;
                    break;
                }
            }

            // Propose treaty
            this.proposeTreaty(proposerCode, targetCode, selectedType);
        });
    }
    
    /**
     * Main turn processing.
     */
    processTurn() {
        this.generateAIProposals();
        this.processProposals();
        this.processTreaties();
    }
}