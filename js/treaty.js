/**
 * Treaty class representing a diplomatic agreement between nations.
 */
class Treaty {
    /**
     * @param {Object} options
     * @param {string} options.id - Unique identifier
     * @param {string} options.type - Treaty type ID (e.g., "alianca_militar")
     * @param {Array<string>} options.signatories - Array of nation codes
     * @param {Object} options.terms - Additional terms (duration, specific bonuses)
     * @param {number} options.createdTurn - Turn number when treaty was created
     * @param {string} options.status - "active", "violated", "expired"
     */
    constructor(options) {
        this.id = options.id || `treaty_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
        this.type = options.type; // treaty type ID
        this.typeData = options.typeData || null; // full treaty type definition (optional)
        this.signatories = options.signatories || [];
        this.terms = options.terms || {};
        this.createdTurn = options.createdTurn || 0;
        this.status = options.status || 'active';
        this.expirationTurn = options.expirationTurn || this.calculateExpiration();
        this.violations = []; // track violations
    }

    /**
     * Calculate expiration turn based on duration range from treaty type.
     * If indefinite (duration 0), returns Infinity.
     * @returns {number}
     */
    calculateExpiration() {
        // Use treaty type data if available
        if (this.typeData) {
            const min = this.typeData.duracao_min || 0;
            const max = this.typeData.duracao_max || 0;
            if (min === 0 && max === 0) return Infinity; // indefinite
            const duration = min + Math.floor(Math.random() * (max - min + 1));
            return this.createdTurn + duration;
        }
        // fallback to terms.duration
        if (this.terms.duration) {
            return this.createdTurn + this.terms.duration;
        }
        // Default to 20 turns
        return this.createdTurn + 20;
    }

    /**
     * Apply effects of this treaty to each signatory nation.
     * Called each turn.
     * @param {Object} nations - Map of nation code -> Nation object
     * @param {Object} engine - Optional game engine reference (for global treasury)
     */
    applyEffects(nations, engine = null) {
        if (this.status !== 'active') return;
        if (!this.typeData || !this.typeData.efeitos) return;

        const efeitos = this.typeData.efeitos;
        this.signatories.forEach(code => {
            const nation = nations[code];
            if (!nation) return;

            // Apply PIB modifier (percentage per turn)
            if (efeitos.modificador_pib) {
                nation.pib_bilhoes_usd *= (1 + efeitos.modificador_pib);
            }
            // Apply stability modifier (additive)
            if (efeitos.modificador_estabilidade) {
                nation.estabilidade_politica += efeitos.modificador_estabilidade;
                // Clamp stability between 0 and 100
                if (nation.estabilidade_politica > 100) nation.estabilidade_politica = 100;
                if (nation.estabilidade_politica < 0) nation.estabilidade_politica = 0;
            }
            // Apply military strength bonus (multiplicative to military power)
            if (efeitos.bonus_forca_militar) {
                // Assuming nation.militar.poder_militar_global exists
                if (nation.militar && nation.militar.poder_militar_global) {
                    nation.militar.poder_militar_global *= (1 + efeitos.bonus_forca_militar);
                }
            }
            // Apply research speed bonus (to be used in research calculations)
            // This is stored as a modifier on nation; we can add a property
            if (efeitos.velocidade_pesquisa) {
                nation.velocidade_pesquisa_bonus = (nation.velocidade_pesquisa_bonus || 0) + efeitos.velocidade_pesquisa;
            }
            // Apply treasury bonus (for free trade)
            if (efeitos.bonus_tesouro) {
                const bonusAmount = nation.pib_bilhoes_usd * efeitos.bonus_tesouro;
                nation.tesouro = (nation.tesouro || 0) + bonusAmount;
            }
            // Apply intelligence sharing (boolean)
            if (efeitos.compartilhamento_inteligencia) {
                nation.intelligence_sharing = true;
            }
            // Apply unit reduction (disarmament)
            if (efeitos.reducao_unidades && nation.militar && nation.militar.unidades) {
                const reduction = 1 - efeitos.reducao_unidades;
                nation.militar.unidades.infantaria *= reduction;
                nation.militar.unidades.tanques *= reduction;
                nation.militar.unidades.avioes *= reduction;
                nation.militar.unidades.navios *= reduction;
                // Ensure minimum of 0
                if (nation.militar.unidades.infantaria < 0) nation.militar.unidades.infantaria = 0;
                if (nation.militar.unidades.tanques < 0) nation.militar.unidades.tanques = 0;
                if (nation.militar.unidades.avioes < 0) nation.militar.unidades.avioes = 0;
                if (nation.militar.unidades.navios < 0) nation.militar.unidades.navios = 0;
            }
        });
    }

    /**
     * Check for violations (e.g., military aggression between signatories).
     * @param {Object} conflictData - Information about ongoing conflicts
     * @returns {boolean} true if violation detected
     */
    checkViolation(conflictData) {
        // If there is a conflict between any two signatories, treaty is violated.
        // This is a simplistic check.
        for (let i = 0; i < this.signatories.length; i++) {
            for (let j = i + 1; j < this.signatories.length; j++) {
                const pair = [this.signatories[i], this.signatories[j]].sort().join('_');
                if (conflictData[pair]) {
                    this.status = 'violated';
                    this.violations.push({
                        turn: conflictData.turn,
                        reason: 'armed conflict between signatories',
                        parties: [this.signatories[i], this.signatories[j]]
                    });
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * Mark treaty as expired (reached its expiration turn).
     * @param {number} currentTurn
     */
    expire(currentTurn) {
        if (this.status === 'active' && currentTurn >= this.expirationTurn) {
            this.status = 'expired';
        }
    }

    /**
     * Determine if treaty is still active.
     * @returns {boolean}
     */
    isActive() {
        return this.status === 'active';
    }

    /**
     * Get a human-readable description of the treaty.
     * @returns {string}
     */
    getDescription() {
        return `Treaty ${this.id} of type ${this.type} between ${this.signatories.join(', ')}`;
    }

    /**
     * Serialize treaty data for saving.
     * @returns {Object}
     */
    toJSON() {
        return {
            id: this.id,
            type: this.type,
            signatories: this.signatories,
            terms: this.terms,
            createdTurn: this.createdTurn,
            status: this.status,
            expirationTurn: this.expirationTurn,
            violations: this.violations
        };
    }

    /**
     * Restore treaty from serialized data.
     * @param {Object} data
     * @returns {Treaty}
     */
    static fromJSON(data) {
        return new Treaty(data);
    }
}