/**
 * MapRenderer — SVG world map with zoom/pan, trade routes, resource overlays.
 *
 * Coordinate spaces:
 *  • SVG viewBox  : 0 0 2000 1000  (internal coordinate space)
 *  • Screen pixels: actual rendered element dimensions (varies)
 *  • All pan/zoom math is done in SVG space; mouse events are converted first.
 *
 * Performance notes:
 *  • getBoundingClientRect() is cached and updated only on resize (avoids forced reflow per event).
 *  • applyTransform() only runs inside requestAnimationFrame via _scheduleRedraw().
 *  • will-change: transform on the main group hints compositor for GPU acceleration.
 */
class MapRenderer {
    constructor(svgId, selectCallback) {
        this.svg = document.getElementById(svgId);
        this.selectCallback = selectCallback;

        // SVG internal dimensions (must match viewBox)
        this.width  = 2000;
        this.height = 1000;

        // ── Zoom / pan state (all in SVG coordinate space) ──────────────────
        this.scale      = 1;
        this.translateX = 0;
        this.translateY = 0;
        this.minScale   = 1;   // never show space outside the world map
        this.maxScale   = 20;  // allows zooming into small islands

        // ── RAF flag ─────────────────────────────────────────────────────────
        this._pendingDraw = false;

        // ── Drag state ───────────────────────────────────────────────────────
        this.isDragging  = false;
        this.lastMouseX  = 0;
        this.lastMouseY  = 0;
        this.hasDragged  = false;   // distinguish click vs drag

        // ── Cached bounding rect (avoid per-event reflow) ───────────────────
        this._rect       = null;
        this._ratioX     = 1;   // width  / rect.width  ratio cache
        this._ratioY     = 1;   // height / rect.height ratio cache

        // ── DOM groups ───────────────────────────────────────────────────────
        this.transformGroup  = null;
        this.countryGroup    = null;
        this.routeGroup      = null;
        this.resourceGroup   = null;
        this.satelliteGroup  = null;
        this.capitalsGroup   = null;   // capital city markers
        this.warGroup        = null;   // war flash overlays

        // ── Data ─────────────────────────────────────────────────────────────
        this.countryCentroids = {};   // code → {x, y}
        this.countryBounds    = {};   // code → {minX,maxX,minY,maxY}
        this.currentMode      = 'normal';

        // ── Inertia / momentum ───────────────────────────────────────────────
        this._velX           = 0;
        this._velY           = 0;
        this._inertiaPending = false;
        this._lastMoveTime   = 0;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INIT
    // ═══════════════════════════════════════════════════════════════════════

    async init() {
        console.log('MapRenderer: carregando GeoJSON…');
        try {
            const res  = await fetch('data/world.json');
            const data = await res.json();
            this.render(data);
            this.enableZoomPan();
            console.log('MapRenderer: pronto.');
        } catch (err) {
            console.error('MapRenderer: falha ao carregar mapa', err);
            this.svg.innerHTML =
                '<text x="50%" y="50%" fill="#ff3333" font-family="monospace" text-anchor="middle">ERRO AO CARREGAR MAPA</text>';
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PROJECTION  (Equirectangular — matches existing data)
    // ═══════════════════════════════════════════════════════════════════════

    project(lon, lat) {
        const x = (lon + 180) * (this.width  / 360);
        const y = (90  - lat) * (this.height / 180);
        return [x, y];
    }

    computeCentroid(geometry) {
        const ring = geometry.type === 'Polygon'
            ? geometry.coordinates[0]
            : geometry.coordinates[0][0];
        let sLon = 0, sLat = 0;
        ring.forEach(c => { sLon += c[0]; sLat += c[1]; });
        return [sLon / ring.length, sLat / ring.length];
    }

    computeBounds(geometry) {
        let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
        const scan = ring => ring.forEach(c => {
            const [x, y] = this.project(c[0], c[1]);
            if (x < minX) minX = x; if (x > maxX) maxX = x;
            if (y < minY) minY = y; if (y > maxY) maxY = y;
        });
        if (geometry.type === 'Polygon') {
            scan(geometry.coordinates[0]);
        } else if (geometry.type === 'MultiPolygon') {
            geometry.coordinates.forEach(p => scan(p[0]));
        }
        return { minX, maxX, minY, maxY };
    }

    generatePath(geometry) {
        const ringToD = ring =>
            ring.map((c, i) => {
                const [x, y] = this.project(c[0], c[1]);
                return `${i === 0 ? 'M' : 'L'}${x.toFixed(1)},${y.toFixed(1)}`;
            }).join('') + 'Z';

        if (geometry.type === 'Polygon') {
            return geometry.coordinates.map(ringToD).join(' ');
        } else if (geometry.type === 'MultiPolygon') {
            return geometry.coordinates.map(poly => poly.map(ringToD).join(' ')).join(' ');
        }
        return null;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // RENDER
    // ═══════════════════════════════════════════════════════════════════════

    render(geoData) {
        const ns = 'http://www.w3.org/2000/svg';
        this.svg.innerHTML = '';

        // ── Defs ────────────────────────────────────────────────────────────
        const defs = document.createElementNS(ns, 'defs');
        defs.innerHTML = `
            <radialGradient id="ocean-grad" cx="50%" cy="50%" r="70%">
                <stop offset="0%"   stop-color="#0d2137"/>
                <stop offset="100%" stop-color="#050e18"/>
            </radialGradient>
            <filter id="glow" x="-30%" y="-30%" width="160%" height="160%">
                <feGaussianBlur stdDeviation="2.5" result="blur"/>
                <feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>
            </filter>
            <filter id="sat-filter" color-interpolation-filters="sRGB">
                <feColorMatrix type="matrix"
                    values="0.2 0.4 0.1 0 0
                            0.5 0.8 0.2 0 0.05
                            0.1 0.2 0.05 0 0
                            0   0   0   1 0"/>
            </filter>
        `;
        this.svg.appendChild(defs);

        // ── Main transform group ─────────────────────────────────────────────
        this.transformGroup = document.createElementNS(ns, 'g');
        this.transformGroup.id = 'map-transform';
        // hint to browser compositor for GPU compositing
        this.transformGroup.style.willChange = 'transform';
        this.svg.appendChild(this.transformGroup);

        // Ocean
        const ocean = document.createElementNS(ns, 'rect');
        ocean.setAttribute('width',  this.width);
        ocean.setAttribute('height', this.height);
        ocean.setAttribute('fill',   'url(#ocean-grad)');
        this.transformGroup.appendChild(ocean);

        // Lat/Lon grid
        this.transformGroup.appendChild(this._buildGrid(ns));

        // Countries
        this.countryGroup = document.createElementNS(ns, 'g');
        this.countryGroup.id = 'countries';
        this.transformGroup.appendChild(this.countryGroup);

        geoData.features.forEach(feature => {
            const d = this.generatePath(feature.geometry);
            if (!d) return;

            const code =
                feature.properties['ISO3166-1-Alpha-2'] ||
                feature.properties.iso_a2              ||
                feature.properties.ISO_A2              ||
                feature.id;

            // Centroid & bounds
            const [lon, lat] = this.computeCentroid(feature.geometry);
            const [cx, cy]   = this.project(lon, lat);
            this.countryCentroids[code] = { x: cx, y: cy };
            this.countryBounds[code]    = this.computeBounds(feature.geometry);

            const path = document.createElementNS(ns, 'path');
            path.setAttribute('d',         d);
            path.setAttribute('class',     'country-path');
            path.setAttribute('data-id',   code);
            path.setAttribute('data-name', feature.properties.name || '');

            // Distinguish click vs drag
            path.addEventListener('mousedown', () => { this.hasDragged = false; });
            path.addEventListener('click', () => {
                if (this.hasDragged) return;
                this.highlightCountry(code);
                if (this.selectCallback) this.selectCallback(code);
            });

            const title = document.createElementNS(ns, 'title');
            title.textContent = feature.properties.name || code;
            path.appendChild(title);

            this.countryGroup.appendChild(path);
        });

        // Trade routes layer (shown in 'normal' mode)
        this.routeGroup = document.createElementNS(ns, 'g');
        this.routeGroup.id = 'trade-routes';
        this.transformGroup.appendChild(this.routeGroup);

        // Resource overlays (shown in 'resources' mode)
        this.resourceGroup = document.createElementNS(ns, 'g');
        this.resourceGroup.id = 'resource-overlays';
        this.resourceGroup.style.display = 'none';
        this.transformGroup.appendChild(this.resourceGroup);

        // Satellite overlay (shown in 'satellite' mode)
        this.satelliteGroup = document.createElementNS(ns, 'g');
        this.satelliteGroup.id = 'satellite-overlay';
        this.satelliteGroup.style.display = 'none';
        this.transformGroup.appendChild(this.satelliteGroup);
        this._buildSatelliteLayer(ns);

        // War flash overlays (always on top of countries)
        this.warGroup = document.createElementNS(ns, 'g');
        this.warGroup.id = 'war-overlays';
        this.warGroup.setAttribute('pointer-events', 'none');
        this.transformGroup.appendChild(this.warGroup);

        // Capital cities (topmost layer — always visible)
        this.capitalsGroup = document.createElementNS(ns, 'g');
        this.capitalsGroup.id = 'capital-cities';
        this.transformGroup.appendChild(this.capitalsGroup);

        this.applyTransform();
    }

    _buildGrid(ns) {
        const g = document.createElementNS(ns, 'g');
        g.setAttribute('id', 'map-grid');
        g.setAttribute('pointer-events', 'none');

        const hline = (lat, opacity, width) => {
            const [, y] = this.project(0, lat);
            const l = document.createElementNS(ns, 'line');
            l.setAttribute('x1', 0); l.setAttribute('y1', y.toFixed(1));
            l.setAttribute('x2', this.width); l.setAttribute('y2', y.toFixed(1));
            l.setAttribute('stroke', `rgba(0,210,255,${opacity})`);
            l.setAttribute('stroke-width', width);
            g.appendChild(l);
        };
        const vline = (lon, opacity) => {
            const [x] = this.project(lon, 0);
            const l = document.createElementNS(ns, 'line');
            l.setAttribute('x1', x.toFixed(1)); l.setAttribute('y1', 0);
            l.setAttribute('x2', x.toFixed(1)); l.setAttribute('y2', this.height);
            l.setAttribute('stroke', `rgba(0,210,255,${opacity})`);
            l.setAttribute('stroke-width', '0.4');
            g.appendChild(l);
        };

        for (let lat = -60; lat <= 60; lat += 30) hline(lat, 0.07, '0.4');
        hline(0, 0.20, '0.8');   // equator
        hline(23.5,  0.10, '0.5');  // tropics
        hline(-23.5, 0.10, '0.5');
        for (let lon = -150; lon <= 180; lon += 30) vline(lon, 0.07);

        return g;
    }

    _buildSatelliteLayer(ns) {
        const W = this.width, H = this.height;
        const g = this.satelliteGroup;
        g.setAttribute('pointer-events', 'none');

        // Fine green grid
        for (let x = 0; x <= W; x += 100) {
            const l = document.createElementNS(ns, 'line');
            l.setAttribute('x1', x); l.setAttribute('y1', 0);
            l.setAttribute('x2', x); l.setAttribute('y2', H);
            l.setAttribute('stroke', 'rgba(0,255,80,0.07)');
            l.setAttribute('stroke-width', '0.5');
            g.appendChild(l);
        }
        for (let y = 0; y <= H; y += 100) {
            const l = document.createElementNS(ns, 'line');
            l.setAttribute('x1', 0); l.setAttribute('y1', y);
            l.setAttribute('x2', W); l.setAttribute('y2', y);
            l.setAttribute('stroke', 'rgba(0,255,80,0.07)');
            l.setAttribute('stroke-width', '0.5');
            g.appendChild(l);
        }

        // Crosshair markers at grid intersections
        const crosshair = (x, y) => {
            const size = 4;
            [0, 1].forEach(i => {
                const l = document.createElementNS(ns, 'line');
                if (i === 0) {
                    l.setAttribute('x1', x - size); l.setAttribute('y1', y);
                    l.setAttribute('x2', x + size); l.setAttribute('y2', y);
                } else {
                    l.setAttribute('x1', x); l.setAttribute('y1', y - size);
                    l.setAttribute('x2', x); l.setAttribute('y2', y + size);
                }
                l.setAttribute('stroke', 'rgba(0,255,80,0.25)');
                l.setAttribute('stroke-width', '0.6');
                g.appendChild(l);
            });
        };
        for (let x = 100; x < W; x += 200) {
            for (let y = 100; y < H; y += 200) crosshair(x, y);
        }

        // Animated scan line
        const scan = document.createElementNS(ns, 'rect');
        scan.setAttribute('x', 0); scan.setAttribute('y', 0);
        scan.setAttribute('width', W); scan.setAttribute('height', 3);
        scan.setAttribute('fill', 'rgba(0,255,80,0.18)');

        const anim = document.createElementNS(ns, 'animateTransform');
        anim.setAttribute('attributeName', 'transform');
        anim.setAttribute('type',          'translate');
        anim.setAttribute('from',          '0 0');
        anim.setAttribute('to',            `0 ${H}`);
        anim.setAttribute('dur',           '5s');
        anim.setAttribute('repeatCount',   'indefinite');
        scan.appendChild(anim);
        g.appendChild(scan);

        // Corner brackets
        const bracket = (x, y, dx, dy) => {
            const size = 30;
            const p = document.createElementNS(ns, 'path');
            p.setAttribute('d', `M${x},${y+size*dy} L${x},${y} L${x+size*dx},${y}`);
            p.setAttribute('fill', 'none');
            p.setAttribute('stroke', 'rgba(0,255,80,0.5)');
            p.setAttribute('stroke-width', '1.5');
            g.appendChild(p);
        };
        bracket(10,  10,   1,  1);
        bracket(W-10, 10,  -1,  1);
        bracket(10,  H-10,  1, -1);
        bracket(W-10, H-10, -1, -1);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ZOOM / PAN  (all in SVG coordinate space)
    // ═══════════════════════════════════════════════════════════════════════

    /** Refresh cached bounding rect — call once after init and on resize. */
    _updateRect() {
        this._rect   = this.svg.getBoundingClientRect();
        this._ratioX = this.width  / (this._rect.width  || 1);
        this._ratioY = this.height / (this._rect.height || 1);
    }

    /** Convert screen pixel position → SVG internal coordinate (uses cache, no reflow). */
    _toSVG(pixelX, pixelY) {
        return [ pixelX * this._ratioX, pixelY * this._ratioY ];
    }

    enableZoomPan() {
        const svg = this.svg;

        // Cache rect immediately after render
        // Use rAF to ensure layout is settled
        requestAnimationFrame(() => this._updateRect());

        // Keep cache fresh on resize
        window.addEventListener('resize', () => {
            this._updateRect();
            // Re-constrain on window resize (viewport changed)
            this._constrain();
            this._scheduleRedraw();
        });

        // ── Mouse wheel ──────────────────────────────────────────────────────
        svg.addEventListener('wheel', e => {
            e.preventDefault();
            const factor = e.deltaY > 0 ? 0.87 : 1.15;
            if (!this._rect) this._updateRect();
            this.zoom(factor, e.clientX - this._rect.left, e.clientY - this._rect.top);
        }, { passive: false });

        // ── Mouse drag ───────────────────────────────────────────────────────
        svg.addEventListener('mousedown', e => {
            if (e.button !== 0) return;
            e.preventDefault();
            this.isDragging = true;
            this.hasDragged = false;
            this.lastMouseX = e.clientX;
            this.lastMouseY = e.clientY;
            svg.style.cursor = 'grabbing';
        });

        window.addEventListener('mousemove', e => {
            if (!this.isDragging) return;
            const dx = e.clientX - this.lastMouseX;
            const dy = e.clientY - this.lastMouseY;
            if (Math.abs(dx) > 3 || Math.abs(dy) > 3) this.hasDragged = true;
            // Track velocity for inertia (EMA smoothing)
            this._velX = this._velX * 0.5 + dx * 0.5;
            this._velY = this._velY * 0.5 + dy * 0.5;
            this.lastMouseX = e.clientX;
            this.lastMouseY = e.clientY;
            this.pan(dx, dy);
        });

        window.addEventListener('mouseup', () => {
            if (!this.isDragging) return;
            this.isDragging = false;
            svg.style.cursor = 'crosshair';
            // Launch inertia scroll
            if (this.hasDragged) this._startInertia();
        });

        // ── Touch (pinch-to-zoom) ────────────────────────────────────────────
        let lastTouchDist = 0;
        let lastTouchMX   = 0;
        let lastTouchMY   = 0;

        svg.addEventListener('touchstart', e => {
            if (!this._rect) this._updateRect();
            if (e.touches.length === 2) {
                const t0 = e.touches[0], t1 = e.touches[1];
                lastTouchDist = Math.hypot(t1.clientX - t0.clientX, t1.clientY - t0.clientY);
                lastTouchMX   = (t0.clientX + t1.clientX) / 2;
                lastTouchMY   = (t0.clientY + t1.clientY) / 2;
            }
        }, { passive: true });

        svg.addEventListener('touchmove', e => {
            if (e.touches.length !== 2) return;
            e.preventDefault();
            const t0   = e.touches[0], t1 = e.touches[1];
            const dist = Math.hypot(t1.clientX - t0.clientX, t1.clientY - t0.clientY);
            const mx   = (t0.clientX + t1.clientX) / 2;
            const my   = (t0.clientY + t1.clientY) / 2;
            if (lastTouchDist > 0) {
                this.zoom(dist / lastTouchDist, mx - this._rect.left, my - this._rect.top);
                this.pan(mx - lastTouchMX, my - lastTouchMY);
            }
            lastTouchDist = dist;
            lastTouchMX   = mx;
            lastTouchMY   = my;
        }, { passive: false });
    }

    /**
     * Zoom centered on a screen-pixel position.
     * Keeps the point under the cursor fixed in world space.
     */
    zoom(factor, pixelX, pixelY) {
        const newScale = Math.max(this.minScale, Math.min(this.maxScale, this.scale * factor));
        if (newScale === this.scale) return;

        // Convert cursor to SVG space (no DOM read — uses cached ratios)
        const [svgX, svgY] = this._toSVG(pixelX, pixelY);

        // The world point under cursor
        const wx = (svgX - this.translateX) / this.scale;
        const wy = (svgY - this.translateY) / this.scale;

        this.scale      = newScale;
        this.translateX = svgX - wx * this.scale;
        this.translateY = svgY - wy * this.scale;

        this._constrain();
        this._scheduleRedraw();
    }

    /** Pan by screen-pixel delta (uses cached ratios — no DOM read). */
    pan(pixelDx, pixelDy) {
        this.translateX += pixelDx * this._ratioX;
        this.translateY += pixelDy * this._ratioY;
        this._constrain();
        this._scheduleRedraw();
    }

    /**
     * Clamp translation so the world map never reveals empty space.
     *
     * Transform: screen_coord = world_coord * scale + translate
     * Left  edge world=0   → translateX      must be ≤ 0
     * Right edge world=W   → W*scale+translateX must be ≥ W  → translateX ≥ W*(1-scale)
     */
    _constrain() {
        const W = this.width, H = this.height, s = this.scale;
        this.translateX = Math.max(W * (1 - s), Math.min(0, this.translateX));
        this.translateY = Math.max(H * (1 - s), Math.min(0, this.translateY));
    }

    _scheduleRedraw() {
        if (this._pendingDraw) return;
        this._pendingDraw = true;
        requestAnimationFrame(() => {
            this.applyTransform();
            this._pendingDraw = false;
        });
    }

    applyTransform() {
        if (!this.transformGroup) return;
        this.transformGroup.setAttribute(
            'transform',
            `translate(${this.translateX.toFixed(2)},${this.translateY.toFixed(2)}) scale(${this.scale.toFixed(4)})`
        );
    }

    // ── Public controls ──────────────────────────────────────────────────────

    zoomIn() {
        if (!this._rect) this._updateRect();
        this.zoom(1.35, this._rect.width / 2, this._rect.height / 2);
    }

    zoomOut() {
        if (!this._rect) this._updateRect();
        this.zoom(1 / 1.35, this._rect.width / 2, this._rect.height / 2);
    }

    resetView() {
        this.scale      = 1;
        this.translateX = 0;
        this.translateY = 0;
        this._velX = 0;
        this._velY = 0;
        this._scheduleRedraw();
    }

    _startInertia() {
        if (this._inertiaPending) return;
        this._inertiaPending = true;
        const tick = () => {
            this._velX *= 0.88;
            this._velY *= 0.88;
            if (Math.abs(this._velX) < 0.4 && Math.abs(this._velY) < 0.4) {
                this._inertiaPending = false;
                return;
            }
            this.pan(this._velX, this._velY);
            requestAnimationFrame(tick);
        };
        requestAnimationFrame(tick);
    }

    /**
     * Zoom to fit a country in the viewport.
     * Ensures the country is fully visible, map edges never go outside viewport.
     */
    zoomToNation(code) {
        const b = this.countryBounds[code];
        if (!b) return;

        const pad   = 40; // SVG units padding around the country
        const bw    = (b.maxX - b.minX) + pad * 2;
        const bh    = (b.maxY - b.minY) + pad * 2;
        const W     = this.width, H = this.height;

        // Scale to fit bounding box inside viewport
        const s = Math.min(this.maxScale, Math.max(this.minScale, Math.min(W / bw, H / bh)));

        // Center on country
        const cx = (b.minX + b.maxX) / 2;
        const cy = (b.minY + b.maxY) / 2;

        this.scale      = s;
        this.translateX = W / 2 - cx * s;
        this.translateY = H / 2 - cy * s;
        this._constrain();
        this._scheduleRedraw();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HIGHLIGHT
    // ═══════════════════════════════════════════════════════════════════════

    highlightCountry(code) {
        this.svg.querySelectorAll('.country-selected').forEach(el =>
            el.classList.remove('country-selected')
        );
        this.svg.querySelectorAll(`[data-id="${code}"]`).forEach(el => {
            el.classList.add('country-selected');
            el.parentElement?.appendChild(el); // bring to front
        });
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MAP MODES  (colour overlays)
    // ═══════════════════════════════════════════════════════════════════════

    updateColors(mode, nations) {
        this.currentMode = mode;

        // Show/hide layers
        if (this.resourceGroup)  this.resourceGroup.style.display  = mode === 'resources'  ? '' : 'none';
        if (this.satelliteGroup) this.satelliteGroup.style.display  = mode === 'satellite'  ? '' : 'none';
        if (this.routeGroup)     this.routeGroup.style.display      = (mode === 'normal' || mode === 'satellite') ? '' : 'none';
        // Capitals always visible; war overlays visible except resources-only mode
        if (this.capitalsGroup)  this.capitalsGroup.style.display   = mode === 'resources' ? 'none' : '';
        if (this.warGroup)       this.warGroup.style.display        = mode === 'resources' ? 'none' : '';

        // Satellite filter on country group
        if (this.countryGroup) {
            this.countryGroup.setAttribute('filter', mode === 'satellite' ? 'url(#sat-filter)' : '');
        }

        this.svg.querySelectorAll('.country-path').forEach(path => {
            const code   = path.getAttribute('data-id');
            const nation = nations[code];

            if (!nation || mode === 'normal' || mode === 'resources' || mode === 'satellite') {
                path.style.fill = '';
                return;
            }

            switch (mode) {
                case 'economy': {
                    const v = Math.min(0.85, nation.pib_bilhoes_usd / 30000 + 0.06);
                    path.style.fill = `rgba(0,255,136,${v.toFixed(2)})`;
                    break;
                }
                case 'military': {
                    const mil = nation.militar || {};
                    const v   = Math.min(0.85,
                        (mil.orcamento_militar_bilhoes || 0) / 900 +
                        (mil.armas_nucleares > 0 ? 0.3 : 0) + 0.05);
                    path.style.fill = `rgba(255,51,51,${v.toFixed(2)})`;
                    break;
                }
                case 'stability': {
                    const v = Math.max(0.05, (nation.estabilidade_politica || 0) / 100);
                    path.style.fill = `rgba(0,210,255,${v.toFixed(2)})`;
                    break;
                }
            }
        });

        if (mode === 'resources') this.updateResourceOverlays(nations);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // RESOURCE OVERLAYS — per-deposit real-world coordinates
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * Static database of mineral deposits with approximate real-world positions.
     * Each entry: { k, label, icon, color, lon, lat }
     * Countries not present here won't show a marker for that mineral.
     */
    static get MINERAL_DEPOSITS() {
        return [
            // ── Petróleo ────────────────────────────────────────────────────
            { k:'petroleo', label:'Petróleo',     icon:'🛢',  color:'#ffaa00', lon: 47,    lat: 26   }, // Gulf (SA/IR/IQ)
            { k:'petroleo', label:'Petróleo',     icon:'🛢',  color:'#ffaa00', lon:-61,    lat: 10   }, // Venezuela
            { k:'petroleo', label:'Petróleo',     icon:'🛢',  color:'#ffaa00', lon: 68,    lat: 57   }, // Russia Siberia
            { k:'petroleo', label:'Petróleo',     icon:'🛢',  color:'#ffaa00', lon:-95,    lat: 31   }, // USA Gulf
            { k:'petroleo', label:'Petróleo',     icon:'🛢',  color:'#ffaa00', lon: 14,    lat: 27   }, // Libya/Algeria
            { k:'petroleo', label:'Petróleo',     icon:'🛢',  color:'#ffaa00', lon: 8,     lat: 5    }, // Nigeria
            { k:'petroleo', label:'Petróleo',     icon:'🛢',  color:'#ffaa00', lon: 87,    lat: 43   }, // Kazakhstan
            { k:'petroleo', label:'Petróleo',     icon:'🛢',  color:'#ffaa00', lon:-55,    lat: -5   }, // Brazil pre-salt

            // ── Gás Natural ──────────────────────────────────────────────────
            { k:'gas',      label:'Gás Natural',  icon:'💨',  color:'#00d2ff', lon: 51,    lat: 25   }, // Qatar
            { k:'gas',      label:'Gás Natural',  icon:'💨',  color:'#00d2ff', lon: 60,    lat: 62   }, // Russia
            { k:'gas',      label:'Gás Natural',  icon:'💨',  color:'#00d2ff', lon: 132,   lat:-22   }, // Australia NW
            { k:'gas',      label:'Gás Natural',  icon:'💨',  color:'#00d2ff', lon:-98,    lat: 35   }, // USA
            { k:'gas',      label:'Gás Natural',  icon:'💨',  color:'#00d2ff', lon: 58,    lat: 38   }, // Turkmenistan
            { k:'gas',      label:'Gás Natural',  icon:'💨',  color:'#00d2ff', lon: 25,    lat: 28   }, // Egypt

            // ── Carvão ───────────────────────────────────────────────────────
            { k:'carvao',   label:'Carvão',        icon:'🪨',  color:'#6b7280', lon: 112,   lat: 38   }, // China Shanxi
            { k:'carvao',   label:'Carvão',        icon:'🪨',  color:'#6b7280', lon:-81,    lat: 38   }, // USA Appalachian
            { k:'carvao',   label:'Carvão',        icon:'🪨',  color:'#6b7280', lon: 83,    lat: 22   }, // India
            { k:'carvao',   label:'Carvão',        icon:'🪨',  color:'#6b7280', lon: 148,   lat:-32   }, // Australia
            { k:'carvao',   label:'Carvão',        icon:'🪨',  color:'#6b7280', lon: 61,    lat: 55   }, // Russia Urais
            { k:'carvao',   label:'Carvão',        icon:'🪨',  color:'#6b7280', lon: 29,    lat:-26   }, // South Africa
            { k:'carvao',   label:'Carvão',        icon:'🪨',  color:'#6b7280', lon: 14,    lat: 51   }, // Germany/Poland
            { k:'carvao',   label:'Carvão',        icon:'🪨',  color:'#6b7280', lon:-66,    lat:-23   }, // Bolivia/Arg

            // ── Ouro ─────────────────────────────────────────────────────────
            { k:'ouro',     label:'Ouro',          icon:'🟡',  color:'#fbbf24', lon: 28,    lat:-27   }, // S. Africa Rand
            { k:'ouro',     label:'Ouro',          icon:'🟡',  color:'#fbbf24', lon: 145,   lat:-27   }, // Australia
            { k:'ouro',     label:'Ouro',          icon:'🟡',  color:'#fbbf24', lon: 61,    lat: 57   }, // Russia
            { k:'ouro',     label:'Ouro',          icon:'🟡',  color:'#fbbf24', lon:-119,   lat: 39   }, // USA Nevada
            { k:'ouro',     label:'Ouro',          icon:'🟡',  color:'#fbbf24', lon: 111,   lat: 26   }, // China
            { k:'ouro',     label:'Ouro',          icon:'🟡',  color:'#fbbf24', lon:-2,     lat: 7    }, // Ghana
            { k:'ouro',     label:'Ouro',          icon:'🟡',  color:'#fbbf24', lon:-75,    lat: -9   }, // Peru
            { k:'ouro',     label:'Ouro',          icon:'🟡',  color:'#fbbf24', lon:-56,    lat: -8   }, // Brazil Pará
            { k:'ouro',     label:'Ouro',          icon:'🟡',  color:'#fbbf24', lon: 32,    lat: 16   }, // Sudan

            // ── Prata ─────────────────────────────────────────────────────────
            { k:'prata',    label:'Prata',          icon:'⚪',  color:'#d1d5db', lon:-99,    lat: 22   }, // Mexico
            { k:'prata',    label:'Prata',          icon:'⚪',  color:'#d1d5db', lon:-75,    lat:-13   }, // Peru
            { k:'prata',    label:'Prata',          icon:'⚪',  color:'#d1d5db', lon: 111,   lat: 31   }, // China
            { k:'prata',    label:'Prata',          icon:'⚪',  color:'#d1d5db', lon: 57,    lat: 56   }, // Russia
            { k:'prata',    label:'Prata',          icon:'⚪',  color:'#d1d5db', lon: 147,   lat:-32   }, // Australia
            { k:'prata',    label:'Prata',          icon:'⚪',  color:'#d1d5db', lon:-66,    lat:-24   }, // Bolivia

            // ── Lítio ─────────────────────────────────────────────────────────
            { k:'litio',    label:'Lítio',          icon:'🔋',  color:'#a78bfa', lon:-68,    lat:-23   }, // Chile Atacama
            { k:'litio',    label:'Lítio',          icon:'🔋',  color:'#a78bfa', lon: 137,   lat:-30   }, // Australia
            { k:'litio',    label:'Lítio',          icon:'🔋',  color:'#a78bfa', lon:-65,    lat:-22   }, // Argentina
            { k:'litio',    label:'Lítio',          icon:'🔋',  color:'#a78bfa', lon: 90,    lat: 33   }, // China Tibet
            { k:'litio',    label:'Lítio',          icon:'🔋',  color:'#a78bfa', lon: 36,    lat: 12   }, // Ethiopia
            { k:'litio',    label:'Lítio',          icon:'🔋',  color:'#a78bfa', lon:-80,    lat: 37   }, // USA N. Carolina
            { k:'litio',    label:'Lítio',          icon:'🔋',  color:'#a78bfa', lon:-67,    lat:-18   }, // Bolivia

            // ── Cobre ─────────────────────────────────────────────────────────
            { k:'cobre',    label:'Cobre',          icon:'🟤',  color:'#b45309', lon:-69,    lat:-28   }, // Chile
            { k:'cobre',    label:'Cobre',          icon:'🟤',  color:'#b45309', lon:-75,    lat: -9   }, // Peru
            { k:'cobre',    label:'Cobre',          icon:'🟤',  color:'#b45309', lon: 110,   lat: 26   }, // China
            { k:'cobre',    label:'Cobre',          icon:'🟤',  color:'#b45309', lon:-110,   lat: 34   }, // USA Arizona
            { k:'cobre',    label:'Cobre',          icon:'🟤',  color:'#b45309', lon: 135,   lat:-30   }, // Australia
            { k:'cobre',    label:'Cobre',          icon:'🟤',  color:'#b45309', lon: 27,    lat:-13   }, // DRC Zambia
            { k:'cobre',    label:'Cobre',          icon:'🟤',  color:'#b45309', lon: 61,    lat: 57   }, // Russia

            // ── Ferro ─────────────────────────────────────────────────────────
            { k:'ferro',    label:'Ferro',          icon:'⚙',   color:'#9ca3af', lon:-51,    lat:-13   }, // Brazil Carajás
            { k:'ferro',    label:'Ferro',          icon:'⚙',   color:'#9ca3af', lon: 119,   lat:-23   }, // Australia Pilbara
            { k:'ferro',    label:'Ferro',          icon:'⚙',   color:'#9ca3af', lon: 63,    lat: 63   }, // Russia
            { k:'ferro',    label:'Ferro',          icon:'⚙',   color:'#9ca3af', lon: 117,   lat: 34   }, // China
            { k:'ferro',    label:'Ferro',          icon:'⚙',   color:'#9ca3af', lon:-85,    lat: 47   }, // USA/Canada
            { k:'ferro',    label:'Ferro',          icon:'⚙',   color:'#9ca3af', lon: 18,    lat:-29   }, // S. Africa
            { k:'ferro',    label:'Ferro',          icon:'⚙',   color:'#9ca3af', lon:-11,    lat: 13   }, // Guinea

            // ── Urânio ───────────────────────────────────────────────────────
            { k:'uranio',   label:'Urânio',         icon:'☢',   color:'#ff3333', lon: 66,    lat: 49   }, // Kazakhstan
            { k:'uranio',   label:'Urânio',         icon:'☢',   color:'#ff3333', lon: 134,   lat:-26   }, // Australia
            { k:'uranio',   label:'Urânio',         icon:'☢',   color:'#ff3333', lon: 15,    lat: 16   }, // Niger
            { k:'uranio',   label:'Urânio',         icon:'☢',   color:'#ff3333', lon: 57,    lat: 56   }, // Russia
            { k:'uranio',   label:'Urânio',         icon:'☢',   color:'#ff3333', lon:-104,   lat: 44   }, // USA Wyoming
            { k:'uranio',   label:'Urânio',         icon:'☢',   color:'#ff3333', lon: 25,    lat:-12   }, // Namibia/Zambia
            { k:'uranio',   label:'Urânio',         icon:'☢',   color:'#ff3333', lon:-67,    lat:-27   }, // Argentina

            // ── Tungstênio ───────────────────────────────────────────────────
            { k:'tungstenio', label:'Tungstênio',   icon:'🔩',  color:'#60a5fa', lon: 114,   lat: 26   }, // China (80% world)
            { k:'tungstenio', label:'Tungstênio',   icon:'🔩',  color:'#60a5fa', lon: 61,    lat: 56   }, // Russia
            { k:'tungstenio', label:'Tungstênio',   icon:'🔩',  color:'#60a5fa', lon:-65,    lat:-17   }, // Bolivia
            { k:'tungstenio', label:'Tungstênio',   icon:'🔩',  color:'#60a5fa', lon: 106,   lat: 20   }, // Vietnam
            { k:'tungstenio', label:'Tungstênio',   icon:'🔩',  color:'#60a5fa', lon: 28,    lat:-29   }, // S. Africa
            { k:'tungstenio', label:'Tungstênio',   icon:'🔩',  color:'#60a5fa', lon: 26,    lat: 41   }, // Portugal/Spain

            // ── Silício (Quartzo) ─────────────────────────────────────────────
            { k:'silicio',  label:'Silício',         icon:'💻',  color:'#34d399', lon: 116,   lat: 36   }, // China
            { k:'silicio',  label:'Silício',         icon:'💻',  color:'#34d399', lon:-121,   lat: 37   }, // USA (Silicon)
            { k:'silicio',  label:'Silício',         icon:'💻',  color:'#34d399', lon: 10,    lat: 62   }, // Norway
            { k:'silicio',  label:'Silício',         icon:'💻',  color:'#34d399', lon: 146,   lat:-34   }, // Australia
            { k:'silicio',  label:'Silício',         icon:'💻',  color:'#34d399', lon:-46,    lat:-18   }, // Brazil
            { k:'silicio',  label:'Silício',         icon:'💻',  color:'#34d399', lon: 55,    lat: 55   }, // Russia

            // ── Terras Raras ─────────────────────────────────────────────────
            { k:'terras_raras', label:'Terras Raras', icon:'💎', color:'#f472b6', lon: 102,   lat: 32   }, // China (60%+)
            { k:'terras_raras', label:'Terras Raras', icon:'💎', color:'#f472b6', lon:-119,   lat: 35   }, // USA CA
            { k:'terras_raras', label:'Terras Raras', icon:'💎', color:'#f472b6', lon: 130,   lat:-28   }, // Australia
            { k:'terras_raras', label:'Terras Raras', icon:'💎', color:'#f472b6', lon: 80,    lat: 22   }, // India
            { k:'terras_raras', label:'Terras Raras', icon:'💎', color:'#f472b6', lon: 55,    lat: 57   }, // Russia
            { k:'terras_raras', label:'Terras Raras', icon:'💎', color:'#f472b6', lon:-12,    lat: 12   }, // Guinea
            { k:'terras_raras', label:'Terras Raras', icon:'💎', color:'#f472b6', lon: 26,    lat:-14   }, // Malawi/DRC

            // ── Diamantes ────────────────────────────────────────────────────
            { k:'diamantes', label:'Diamantes',      icon:'♦',   color:'#e0f7fa', lon: 25,    lat:-12   }, // DRC
            { k:'diamantes', label:'Diamantes',      icon:'♦',   color:'#e0f7fa', lon: 18,    lat:-23   }, // Botswana
            { k:'diamantes', label:'Diamantes',      icon:'♦',   color:'#e0f7fa', lon: 19,    lat:-29   }, // S. Africa
            { k:'diamantes', label:'Diamantes',      icon:'♦',   color:'#e0f7fa', lon: 62,    lat: 63   }, // Russia (Yakutia)
            { k:'diamantes', label:'Diamantes',      icon:'♦',   color:'#e0f7fa', lon: 128,   lat:-21   }, // Australia
            { k:'diamantes', label:'Diamantes',      icon:'♦',   color:'#e0f7fa', lon:-12,    lat: 9    }, // Sierra Leone/Guinea

            // ── Terras Aráveis ────────────────────────────────────────────────
            { k:'terras_araveis', label:'Terras Aráveis', icon:'🌾', color:'#22c55e', lon:-95,  lat: 42   }, // USA Midwest
            { k:'terras_araveis', label:'Terras Aráveis', icon:'🌾', color:'#22c55e', lon:-54,  lat:-14   }, // Brazil Cerrado
            { k:'terras_araveis', label:'Terras Aráveis', icon:'🌾', color:'#22c55e', lon: 55,  lat: 53   }, // Russia
            { k:'terras_araveis', label:'Terras Aráveis', icon:'🌾', color:'#22c55e', lon: 80,  lat: 26   }, // India
            { k:'terras_araveis', label:'Terras Aráveis', icon:'🌾', color:'#22c55e', lon: 115, lat: 35   }, // China
            { k:'terras_araveis', label:'Terras Aráveis', icon:'🌾', color:'#22c55e', lon: 31,  lat: 49   }, // Ukraine
            { k:'terras_araveis', label:'Terras Aráveis', icon:'🌾', color:'#22c55e', lon: 144, lat:-34   }, // Australia
            { k:'terras_araveis', label:'Terras Aráveis', icon:'🌾', color:'#22c55e', lon:-76,  lat: 4    }, // Colombia/Arg

            // ── Água Doce ─────────────────────────────────────────────────────
            { k:'agua_doce', label:'Água Doce',      icon:'💧',  color:'#4fc3f7', lon:-83,    lat: 46   }, // Great Lakes
            { k:'agua_doce', label:'Água Doce',      icon:'💧',  color:'#4fc3f7', lon:-60,    lat: -4   }, // Amazon
            { k:'agua_doce', label:'Água Doce',      icon:'💧',  color:'#4fc3f7', lon: 104,   lat: 54   }, // Lake Baikal
            { k:'agua_doce', label:'Água Doce',      icon:'💧',  color:'#4fc3f7', lon: 32,    lat: -2   }, // Great Lakes AF
            { k:'agua_doce', label:'Água Doce',      icon:'💧',  color:'#4fc3f7', lon: 137,   lat:-36   }, // Australia Murray
            { k:'agua_doce', label:'Água Doce',      icon:'💧',  color:'#4fc3f7', lon: 78,    lat: 29   }, // Himalayas
        ];
    }

    updateResourceOverlays(_nations) {
        if (!this.resourceGroup) return;
        this.resourceGroup.innerHTML = '';
        const ns = 'http://www.w3.org/2000/svg';

        // Deduplicated legend entries
        const legendMap = {};

        MapRenderer.MINERAL_DEPOSITS.forEach(dep => {
            const [svgX, svgY] = this.project(dep.lon, dep.lat);

            // Glow circle
            const circle = document.createElementNS(ns, 'circle');
            circle.setAttribute('cx',      svgX.toFixed(1));
            circle.setAttribute('cy',      svgY.toFixed(1));
            circle.setAttribute('r',       '5');
            circle.setAttribute('fill',    dep.color);
            circle.setAttribute('opacity', '0.20');
            circle.setAttribute('stroke',  dep.color);
            circle.setAttribute('stroke-width', '0.8');
            circle.setAttribute('stroke-opacity', '0.5');
            circle.setAttribute('pointer-events', 'none');
            this.resourceGroup.appendChild(circle);

            // Icon
            const text = document.createElementNS(ns, 'text');
            text.setAttribute('x',           svgX.toFixed(1));
            text.setAttribute('y',           (svgY + 3.5).toFixed(1));
            text.setAttribute('text-anchor', 'middle');
            text.setAttribute('font-size',   '8');
            text.setAttribute('class',       'resource-icon');
            text.setAttribute('pointer-events', 'all');
            text.textContent = dep.icon;

            const title = document.createElementNS(ns, 'title');
            title.textContent = dep.label;
            text.appendChild(title);
            this.resourceGroup.appendChild(text);

            // Collect for legend
            if (!legendMap[dep.k]) legendMap[dep.k] = { icon: dep.icon, label: dep.label, color: dep.color };
        });

        // Legend (2 rows to fit all minerals)
        this._buildResourceLegend(ns, Object.values(legendMap));
    }

    _buildResourceLegend(ns, entries) {
        const g = document.createElementNS(ns, 'g');
        g.setAttribute('transform', 'translate(10, 930)');
        g.setAttribute('pointer-events', 'none');

        const cols = Math.ceil(entries.length / 2);
        const colW = 125;
        const bgW  = cols * colW + 8;

        const bg = document.createElementNS(ns, 'rect');
        bg.setAttribute('x', -4); bg.setAttribute('y', -12);
        bg.setAttribute('width',  bgW);
        bg.setAttribute('height', 34);
        bg.setAttribute('rx', 3);
        bg.setAttribute('fill', 'rgba(5,7,10,0.82)');
        bg.setAttribute('stroke', 'rgba(0,210,255,0.2)');
        bg.setAttribute('stroke-width', '0.5');
        g.appendChild(bg);

        entries.forEach(({ icon, label, color }, i) => {
            const row = i < cols ? 0 : 1;
            const col = i % cols;
            const x   = col * colW;
            const y   = row * 14;

            const t = document.createElementNS(ns, 'text');
            t.setAttribute('x', x);
            t.setAttribute('y', y);
            t.setAttribute('font-size', '7.5');
            t.setAttribute('fill', color);
            t.setAttribute('font-family', 'monospace');
            t.textContent = `${icon} ${label}`;
            g.appendChild(t);
        });

        this.resourceGroup.appendChild(g);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CAPITAL CITIES
    // ═══════════════════════════════════════════════════════════════════════

    static get CAPITALS() {
        return {
            US: { name: 'Washington',  lon: -77.04,  lat:  38.91 },
            CN: { name: 'Pequim',      lon: 116.39,  lat:  39.92 },
            RU: { name: 'Moscou',      lon:  37.62,  lat:  55.75 },
            GB: { name: 'Londres',     lon:  -0.13,  lat:  51.51 },
            FR: { name: 'Paris',       lon:   2.35,  lat:  48.85 },
            DE: { name: 'Berlim',      lon:  13.40,  lat:  52.52 },
            JP: { name: 'Tóquio',      lon: 139.69,  lat:  35.69 },
            IN: { name: 'Nova Délhi',  lon:  77.21,  lat:  28.61 },
            BR: { name: 'Brasília',    lon: -47.93,  lat: -15.78 },
            CA: { name: 'Ottawa',      lon: -75.70,  lat:  45.42 },
            AU: { name: 'Camberra',    lon: 149.13,  lat: -35.31 },
            KR: { name: 'Seul',        lon: 126.98,  lat:  37.57 },
            MX: { name: 'Cidade do México', lon: -99.13, lat: 19.43 },
            ID: { name: 'Jacarta',     lon: 106.85,  lat:  -6.21 },
            TR: { name: 'Ancara',      lon:  32.86,  lat:  39.93 },
            SA: { name: 'Riade',       lon:  46.72,  lat:  24.69 },
            NG: { name: 'Abuja',       lon:   7.49,  lat:   9.06 },
            ZA: { name: 'Pretória',    lon:  28.19,  lat: -25.75 },
            AR: { name: 'Buenos Aires',lon: -58.38,  lat: -34.60 },
            EG: { name: 'Cairo',       lon:  31.24,  lat:  30.06 },
            PK: { name: 'Islamabad',   lon:  73.06,  lat:  33.72 },
            VN: { name: 'Hanói',       lon: 105.85,  lat:  21.03 },
            TH: { name: 'Bangkok',     lon: 100.52,  lat:  13.75 },
            IR: { name: 'Teerã',       lon:  51.39,  lat:  35.69 },
            IQ: { name: 'Bagdá',       lon:  44.36,  lat:  33.34 },
            IL: { name: 'Jerusalém',   lon:  35.22,  lat:  31.77 },
            UA: { name: 'Kiev',        lon:  30.52,  lat:  50.45 },
            PL: { name: 'Varsóvia',    lon:  21.01,  lat:  52.23 },
            IT: { name: 'Roma',        lon:  12.50,  lat:  41.90 },
            ES: { name: 'Madri',       lon:  -3.70,  lat:  40.42 },
            SE: { name: 'Estocolmo',   lon:  18.07,  lat:  59.33 },
            NL: { name: 'Amsterdã',    lon:   4.90,  lat:  52.37 },
            NO: { name: 'Oslo',        lon:  10.75,  lat:  59.91 },
            CH: { name: 'Berna',       lon:   7.45,  lat:  46.95 },
            PT: { name: 'Lisboa',      lon:  -9.14,  lat:  38.72 },
            GR: { name: 'Atenas',      lon:  23.73,  lat:  37.98 },
            CZ: { name: 'Praga',       lon:  14.42,  lat:  50.09 },
            RO: { name: 'Bucareste',   lon:  26.10,  lat:  44.44 },
            CO: { name: 'Bogotá',      lon: -74.08,  lat:   4.71 },
            CL: { name: 'Santiago',    lon: -70.67,  lat: -33.45 },
            PE: { name: 'Lima',        lon: -77.04,  lat: -12.04 },
            VE: { name: 'Caracas',     lon: -66.92,  lat:  10.48 },
            KE: { name: 'Nairóbi',     lon:  36.82,  lat:  -1.29 },
            ET: { name: 'Adis Abeba',  lon:  38.74,  lat:   9.02 },
            GH: { name: 'Acra',        lon:  -0.19,  lat:   5.56 },
            MA: { name: 'Rabat',       lon:  -6.85,  lat:  33.99 },
            DZ: { name: 'Argel',       lon:   3.04,  lat:  36.74 },
            LY: { name: 'Trípoli',     lon:  13.19,  lat:  32.88 },
            SD: { name: 'Cartum',      lon:  32.53,  lat:  15.56 },
            SY: { name: 'Damasco',     lon:  36.29,  lat:  33.51 },
            QA: { name: 'Doha',        lon:  51.53,  lat:  25.29 },
            AE: { name: 'Abu Dhabi',   lon:  54.37,  lat:  24.47 },
            AF: { name: 'Cabul',       lon:  69.18,  lat:  34.53 },
            MY: { name: 'Kuala Lumpur',lon: 101.69,  lat:   3.14 },
            SG: { name: 'Singapura',   lon: 103.82,  lat:   1.35 },
            BY: { name: 'Minsk',       lon:  27.57,  lat:  53.90 },
            RS: { name: 'Belgrado',    lon:  20.46,  lat:  44.80 },
            KZ: { name: 'Astana',      lon:  71.45,  lat:  51.18 },
            UZ: { name: 'Tashkent',    lon:  69.27,  lat:  41.30 },
            AZ: { name: 'Baku',        lon:  49.87,  lat:  40.41 },
            MM: { name: 'Naypyidaw',   lon:  96.13,  lat:  19.76 },
            BD: { name: 'Dhaka',       lon:  90.41,  lat:  23.72 },
            CU: { name: 'Havana',      lon: -82.37,  lat:  23.14 },
            NZ: { name: 'Wellington',  lon: 174.78,  lat: -41.29 },
            PH: { name: 'Manila',      lon: 120.98,  lat:  14.60 },
            MN: { name: 'Ulaanbaatar', lon: 106.92,  lat:  47.89 },
        };
    }

    updateCapitals(nations) {
        if (!this.capitalsGroup) return;
        this.capitalsGroup.innerHTML = '';
        const ns = 'http://www.w3.org/2000/svg';
        const caps = MapRenderer.CAPITALS;
        const playerCode = window.engine?.state?.playerNation?.codigo_iso || window.engine?.state?.playerNationCode;

        Object.entries(caps).forEach(([code, cap]) => {
            const nation = nations && nations[code];
            const [cx, cy] = this.project(cap.lon, cap.lat);
            const atWar = nation && (nation.em_guerra || []).length > 0;
            const isPlayer = code === playerCode;

            const g = document.createElementNS(ns, 'g');
            g.setAttribute('class', 'capital-marker');
            g.setAttribute('data-code', code);
            g.style.cursor = 'pointer';
            g.addEventListener('click', (e) => {
                e.stopPropagation();
                if (this.hasDragged) return;
                this.highlightCountry(code);
                if (this.selectCallback) this.selectCallback(code);
            });

            // War pulse ring
            if (atWar) {
                const pulse = document.createElementNS(ns, 'circle');
                pulse.setAttribute('cx', cx.toFixed(1));
                pulse.setAttribute('cy', cy.toFixed(1));
                pulse.setAttribute('r', '5');
                pulse.setAttribute('fill', 'none');
                pulse.setAttribute('stroke', '#ff3333');
                pulse.setAttribute('stroke-width', '1');

                const animR = document.createElementNS(ns, 'animate');
                animR.setAttribute('attributeName', 'r');
                animR.setAttribute('values', '4;12;4');
                animR.setAttribute('dur', '2s');
                animR.setAttribute('repeatCount', 'indefinite');
                pulse.appendChild(animR);

                const animO = document.createElementNS(ns, 'animate');
                animO.setAttribute('attributeName', 'opacity');
                animO.setAttribute('values', '0.8;0;0.8');
                animO.setAttribute('dur', '2s');
                animO.setAttribute('repeatCount', 'indefinite');
                pulse.appendChild(animO);
                g.appendChild(pulse);
            }

            // Capital dot
            const dot = document.createElementNS(ns, 'circle');
            dot.setAttribute('cx', cx.toFixed(1));
            dot.setAttribute('cy', cy.toFixed(1));
            dot.setAttribute('r', isPlayer ? '3.5' : '2.5');
            dot.setAttribute('fill', isPlayer ? '#00d2ff' : (atWar ? '#ff3333' : '#fbbf24'));
            dot.setAttribute('stroke', '#fff');
            dot.setAttribute('stroke-width', '0.7');
            g.appendChild(dot);

            // Cross hair marker
            const crossSize = 3;
            ['h','v'].forEach((dir, i) => {
                const line = document.createElementNS(ns, 'line');
                if (i === 0) {
                    line.setAttribute('x1', (cx - crossSize).toFixed(1));
                    line.setAttribute('y1', cy.toFixed(1));
                    line.setAttribute('x2', (cx + crossSize).toFixed(1));
                    line.setAttribute('y2', cy.toFixed(1));
                } else {
                    line.setAttribute('x1', cx.toFixed(1));
                    line.setAttribute('y1', (cy - crossSize).toFixed(1));
                    line.setAttribute('x2', cx.toFixed(1));
                    line.setAttribute('y2', (cy + crossSize).toFixed(1));
                }
                line.setAttribute('stroke', isPlayer ? '#00d2ff' : 'rgba(255,255,255,0.5)');
                line.setAttribute('stroke-width', '0.5');
                line.setAttribute('pointer-events', 'none');
                g.appendChild(line);
            });

            // City name label
            const label = document.createElementNS(ns, 'text');
            label.setAttribute('x', (cx + 4).toFixed(1));
            label.setAttribute('y', (cy + 2).toFixed(1));
            label.setAttribute('font-size', '5.5');
            label.setAttribute('font-family', 'monospace');
            label.setAttribute('fill', isPlayer ? '#00d2ff' : 'rgba(220,220,220,0.75)');
            label.setAttribute('pointer-events', 'none');
            label.textContent = cap.name.toUpperCase();
            g.appendChild(label);

            // Tooltip
            const title = document.createElementNS(ns, 'title');
            title.textContent = `${cap.name} (Capital de ${code})${atWar ? ' — EM GUERRA' : ''}`;
            g.appendChild(title);

            this.capitalsGroup.appendChild(g);
        });
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LIVE MAP  (trade routes, warships, aircraft, drones, war flashes)
    // ═══════════════════════════════════════════════════════════════════════

    updateTradeRoutes(nations, treaties) {
        if (!this.routeGroup) return;
        this.routeGroup.innerHTML = '';
        if (this.warGroup) this.warGroup.innerHTML = '';

        const ns      = 'http://www.w3.org/2000/svg';
        const xlinkNS = 'http://www.w3.org/1999/xlink';
        const drawnPaths = new Set();

        // ── Helper: create animated path + vehicle ───────────────────────────
        const addRoute = (a, b, color, dashLen, strokeOpacity, vehicleIcon, dur, bowFactor = 0.15) => {
            const ca = this.countryCentroids[a];
            const cb = this.countryCentroids[b];
            if (!ca || !cb) return;

            const uid  = [a, b].sort().join('~') + vehicleIcon;
            if (drawnPaths.has(uid)) return;
            drawnPaths.add(uid);

            const mx = (ca.x + cb.x) / 2;
            const my = (ca.y + cb.y) / 2 - Math.abs(cb.x - ca.x) * bowFactor;
            const pathId = `lr_${uid.replace(/[^a-zA-Z0-9]/g, '_')}`;

            // Route path (shared, referenced by mpath)
            const rp = document.createElementNS(ns, 'path');
            rp.setAttribute('id', pathId);
            rp.setAttribute('d', `M${ca.x.toFixed(1)},${ca.y.toFixed(1)} Q${mx.toFixed(1)},${my.toFixed(1)} ${cb.x.toFixed(1)},${cb.y.toFixed(1)}`);
            rp.setAttribute('fill', 'none');
            rp.setAttribute('stroke', color);
            rp.setAttribute('stroke-width', '0.7');
            rp.setAttribute('stroke-opacity', strokeOpacity);
            rp.setAttribute('stroke-dasharray', dashLen);
            rp.setAttribute('pointer-events', 'none');
            this.routeGroup.appendChild(rp);

            // Animated vehicle icon
            const icon = document.createElementNS(ns, 'text');
            icon.setAttribute('font-size', '7');
            icon.setAttribute('text-anchor', 'middle');
            icon.setAttribute('fill', color);
            icon.setAttribute('opacity', '0.9');
            icon.setAttribute('pointer-events', 'none');
            icon.textContent = vehicleIcon;

            const motion = document.createElementNS(ns, 'animateMotion');
            motion.setAttribute('dur', `${dur.toFixed(1)}s`);
            motion.setAttribute('repeatCount', 'indefinite');
            motion.setAttribute('rotate', 'auto');
            motion.setAttribute('begin', `${(Math.random() * dur).toFixed(1)}s`);

            const mpath = document.createElementNS(ns, 'mpath');
            mpath.setAttributeNS(xlinkNS, 'xlink:href', `#${pathId}`);
            motion.appendChild(mpath);
            icon.appendChild(motion);
            this.routeGroup.appendChild(icon);
        };

        // ── Helper: war flash effect on a nation centroid ────────────────────
        const addWarFlash = (code) => {
            const c = this.countryCentroids[code];
            if (!c || !this.warGroup) return;
            const g = document.createElementNS(ns, 'g');
            g.setAttribute('pointer-events', 'none');

            // Expanding shockwave ring
            const ring = document.createElementNS(ns, 'circle');
            ring.setAttribute('cx', c.x.toFixed(1));
            ring.setAttribute('cy', c.y.toFixed(1));
            ring.setAttribute('r', '8');
            ring.setAttribute('fill', 'none');
            ring.setAttribute('stroke', '#ff3333');
            ring.setAttribute('stroke-width', '1.5');

            const ar = document.createElementNS(ns, 'animate');
            ar.setAttribute('attributeName', 'r'); ar.setAttribute('values', '6;22;6');
            ar.setAttribute('dur', `${2.5 + Math.random()}s`); ar.setAttribute('repeatCount', 'indefinite');
            ring.appendChild(ar);

            const ao = document.createElementNS(ns, 'animate');
            ao.setAttribute('attributeName', 'stroke-opacity'); ao.setAttribute('values', '0.7;0;0.7');
            ao.setAttribute('dur', `${2.5 + Math.random()}s`); ao.setAttribute('repeatCount', 'indefinite');
            ring.appendChild(ao);
            g.appendChild(ring);

            // Explosion icon at centroid
            const cross = document.createElementNS(ns, 'text');
            cross.setAttribute('x', c.x.toFixed(1));
            cross.setAttribute('y', (c.y + 4).toFixed(1));
            cross.setAttribute('text-anchor', 'middle');
            cross.setAttribute('font-size', '10');
            cross.setAttribute('fill', '#ff6633');
            cross.setAttribute('opacity', '0.7');
            cross.textContent = '💥';

            const ac = document.createElementNS(ns, 'animate');
            ac.setAttribute('attributeName', 'opacity'); ac.setAttribute('values', '0.7;0.2;0.7');
            ac.setAttribute('dur', '1.8s'); ac.setAttribute('repeatCount', 'indefinite');
            cross.appendChild(ac);
            g.appendChild(cross);

            this.warGroup.appendChild(g);
        };

        const playerCode = window.engine?.state?.playerNation?.codigo_iso || window.engine?.state?.playerNationCode;

        // ── 1. MAJOR GLOBAL TRADE ROUTES (merchant ships) ───────────────────
        const TRADE_ROUTES = [
            ['US','CN'], ['US','GB'], ['US','DE'], ['US','JP'], ['US','MX'],
            ['US','CA'], ['US','BR'], ['US','KR'], ['US','FR'], ['US','AU'],
            ['CN','JP'], ['CN','KR'], ['CN','DE'], ['CN','AU'], ['CN','BR'],
            ['CN','IN'], ['CN','RU'], ['CN','SG'], ['CN','MY'],
            ['DE','FR'], ['DE','GB'], ['DE','IT'], ['DE','NL'], ['DE','PL'],
            ['GB','FR'], ['GB','NL'], ['GB','IN'],
            ['JP','KR'], ['JP','AU'], ['JP','IN'],
            ['RU','DE'], ['RU','CN'], ['RU','TR'],
            ['SA','CN'], ['SA','US'], ['SA','JP'], ['SA','IN'],
            ['AU','JP'], ['AU','CN'], ['AU','KR'], ['AU','IN'],
            ['BR','DE'], ['BR','CN'], ['BR','US'],
            ['IN','US'], ['IN','GB'], ['IN','SG'],
            ['TR','DE'], ['NG','CN'], ['NG','US'], ['EG','SA'],
            ['MX','US'], ['CA','US'],
        ];

        TRADE_ROUTES.forEach(([a, b]) => {
            const na = nations && nations[a];
            const nb = nations && nations[b];
            if (!na || !nb) return;
            const atWar = (na.em_guerra || []).includes(b) || (nb.em_guerra || []).includes(a);
            if (atWar) return;
            const dur = 12 + Math.random() * 10;
            addRoute(a, b, '#00d2ff', '5,4', '0.15', '🚢', dur);
        });

        // ── 2. TREATY ROUTES (military planes + diplomatic ships) ────────────
        if (treaties) {
            treaties.filter(t => t.status === 'active').forEach(treaty => {
                const sigs = treaty.signatories || [];
                const isMil = (treaty.type || '').includes('militar') || (treaty.type || '').includes('alianca');
                for (let i = 0; i < sigs.length - 1; i++) {
                    const a = sigs[i], b = sigs[i + 1];
                    if (isMil) {
                        addRoute(a, b, '#ff8844', '3,3', '0.45', '✈', 6 + Math.random() * 4, 0.12);
                    } else {
                        addRoute(a, b, '#00ff88', '6,3', '0.35', '🚢', 9 + Math.random() * 6);
                    }
                }
            });
        }

        // ── 3. WAR ROUTES (warships + drones + conflict flashes) ─────────────
        const warPairs = new Set();
        if (nations) {
            Object.entries(nations).forEach(([code, nation]) => {
                (nation.em_guerra || []).forEach(enemyCode => {
                    const key = [code, enemyCode].sort().join('~');
                    if (!warPairs.has(key)) {
                        warPairs.add(key);
                        addRoute(code, enemyCode, '#ff3333', '2,2', '0.6', '⚓', 4 + Math.random() * 3, 0.20);
                        // Extra drone route
                        if (code === playerCode || enemyCode === playerCode) {
                            addRoute(code, enemyCode, '#ff6600', '1,3', '0.4', '🔭', 7 + Math.random() * 4, -0.10);
                        }
                        addWarFlash(code);
                        addWarFlash(enemyCode);
                    }
                });
            });
        }

        // ── 4. Player's active spy/drone routes (if any) ─────────────────────
        if (playerCode && nations) {
            const player = nations[playerCode];
            if (player && player.spy_ops_log) {
                const recentOps = player.spy_ops_log.slice(-3);
                recentOps.forEach(op => {
                    if (op.target && op.target !== playerCode) {
                        addRoute(playerCode, op.target, '#a78bfa', '1,4', '0.35', '🔭', 9 + Math.random() * 5, -0.08);
                    }
                });
            }
        }

        // ── 5. Refresh capital markers ────────────────────────────────────────
        this.updateCapitals(nations || {});
    }

    renderPlaceholder() {
        this.svg.innerHTML =
            '<text x="50%" y="50%" fill="#ff3333" font-family="monospace" text-anchor="middle">ERRO AO CARREGAR MAPA</text>';
    }
}
