#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BAKE DE PROVÍNCIAS (Bloco 0 do grand strategy) — offline, roda UMA vez.

Lê data/world.json (1 polígono por país) e gera data/provinces.json com N
províncias por país (N escala pela área), cada uma com:
  { id, owner_iso, nome, polygon(lon/lat), neighbors, centroid, pop_frac, pib_frac, is_capital }

Método: Voronoi (scipy) semeado dentro do mainland de cada país, cada célula
recortada ao contorno do país (Sutherland–Hodgman contra a casca convexa +
teste de contenção dos vértices). Adjacência sai das sementes que compartilham
aresta Voronoi. Coordenadas em lon/lat (o WorldMap reaplica a projeção própria).

Uso:  python tools/gen_provinces.py
Saída: data/provinces.json  +  um resumo no stdout.
"""
import json, math, os, sys, random
from collections import defaultdict

random.seed(42)  # determinístico — mesmo bake toda vez

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORLD = os.path.join(ROOT, "data", "world.json")
NATIONS = os.path.join(ROOT, "data", "nations.json")
OUT = os.path.join(ROOT, "data", "provinces.json")

# N de províncias por país: área/DIVISOR, limitado a [MIN, MAX].
# Divisor 200k dá granularidade de grand strategy: ~500 províncias, ~72 países
# subdivididos (França/Egito/Japão viram 2-3, grandes viram até 14). Ainda dentro
# do orçamento de render (~600-900 Polygon2D estimado seguro).
AREA_DIVISOR = 200_000.0
N_MIN, N_MAX = 1, 14

# ---------------------------------------------------------------- geometria

def ring_area(ring):
    """Área com sinal (shoelace) — magnitude serve pra comparar tamanho."""
    a = 0.0
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % n]
        a += x1 * y2 - x2 * y1
    return a / 2.0

def polygon_centroid(ring):
    a = 0.0; cx = 0.0; cy = 0.0
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % n]
        cross = x1 * y2 - x2 * y1
        a += cross; cx += (x1 + x2) * cross; cy += (y1 + y2) * cross
    a *= 0.5
    if abs(a) < 1e-12:
        # degenerate — média simples
        return [sum(p[0] for p in ring) / n, sum(p[1] for p in ring) / n]
    return [cx / (6 * a), cy / (6 * a)]

def point_in_ring(pt, ring):
    """Ray casting — ponto dentro do anel (polígono simples)."""
    x, y = pt
    inside = False
    n = len(ring)
    j = n - 1
    for i in range(n):
        xi, yi = ring[i]; xj, yj = ring[j]
        if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi + 1e-30) + xi):
            inside = not inside
        j = i
    return inside

def clip_convex(subject, clip_edge):
    """Um passo de Sutherland–Hodgman: recorta 'subject' pelo semiplano à
    ESQUERDA da aresta dirigida clip_edge=(a,b)."""
    (ax, ay), (bx, by) = clip_edge
    def inside(p):
        return (bx - ax) * (p[1] - ay) - (by - ay) * (p[0] - ax) >= -1e-12
    def intersect(p, q):
        (px, py), (qx, qy) = p, q
        d1 = (bx - ax) * (py - ay) - (by - ay) * (px - ax)
        d2 = (bx - ax) * (qy - ay) - (by - ay) * (qx - ax)
        t = d1 / (d1 - d2 + 1e-30)
        return [px + t * (qx - px), py + t * (qy - py)]
    out = []
    n = len(subject)
    if n == 0:
        return out
    for i in range(n):
        cur = subject[i]; prv = subject[i - 1]
        ci = inside(cur); pi = inside(prv)
        if ci:
            if not pi:
                out.append(intersect(prv, cur))
            out.append(cur)
        elif pi:
            out.append(intersect(prv, cur))
    return out

def clip_to_convex_hull(cell, hull_ccw):
    """Recorta a célula (convexa) por cada aresta da casca convexa (CCW)."""
    poly = cell[:]
    n = len(hull_ccw)
    for i in range(n):
        a = hull_ccw[i]; b = hull_ccw[(i + 1) % n]
        poly = clip_convex(poly, (a, b))
        if len(poly) < 3:
            return []
    return poly

def convex_hull(points):
    pts = sorted(set(map(tuple, points)))
    if len(pts) <= 2:
        return [list(p) for p in pts]
    def cross(o, a, b):
        return (a[0]-o[0])*(b[1]-o[1]) - (a[1]-o[1])*(b[0]-o[0])
    lower = []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    upper = []
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    hull = lower[:-1] + upper[:-1]
    return [list(p) for p in hull]  # CCW

# ------------------------------------------------------------ semeadura

def seed_points_in_ring(ring, k):
    """k pontos dentro do anel via rejeição no bounding box."""
    xs = [p[0] for p in ring]; ys = [p[1] for p in ring]
    minx, maxx, miny, maxy = min(xs), max(xs), min(ys), max(ys)
    pts = []
    tries = 0
    max_tries = k * 400 + 200
    while len(pts) < k and tries < max_tries:
        tries += 1
        p = [random.uniform(minx, maxx), random.uniform(miny, maxy)]
        if point_in_ring(p, ring):
            # espalha: rejeita se muito perto de outro
            if all((p[0]-q[0])**2 + (p[1]-q[1])**2 > ((maxx-minx)*(maxy-miny)/(k*6.0)) for q in pts):
                pts.append(p)
    # completa sem o critério de distância se faltou
    while len(pts) < k and tries < max_tries * 2:
        tries += 1
        p = [random.uniform(minx, maxx), random.uniform(miny, maxy)]
        if point_in_ring(p, ring):
            pts.append(p)
    if not pts:
        pts = [polygon_centroid(ring)]
    return pts

# ------------------------------------------------------------ main

def main():
    from scipy.spatial import Voronoi  # noqa

    world = json.load(open(WORLD, encoding="utf-8"))
    nations = json.load(open(NATIONS, encoding="utf-8"))["nations"]

    # maior ring (mainland) por ISO2
    mainland = {}
    for f in world["features"]:
        iso = f["properties"].get("ISO3166-1-Alpha-2", "")
        if not iso:
            continue
        geom = f["geometry"]; coords = geom["coordinates"]
        rings = []
        if geom["type"] == "Polygon":
            rings = [coords[0]]
        elif geom["type"] == "MultiPolygon":
            rings = [poly[0] for poly in coords if poly]
        if not rings:
            continue
        big = max(rings, key=lambda r: abs(ring_area(r)))
        # dedup ponto final == inicial
        if len(big) > 1 and big[0] == big[-1]:
            big = big[:-1]
        if len(big) >= 3:
            mainland[iso] = [[float(p[0]), float(p[1])] for p in big]

    provinces = []
    prov_index = {}   # (iso, seed_idx) -> province id
    per_country_counts = {}
    skipped = []

    for iso, ring in mainland.items():
        nat = nations.get(iso)
        if nat is None:
            continue  # só geramos províncias p/ nações jogáveis
        area = float(nat.get("geografia", {}).get("area_km2", 0) or 0)
        k = max(N_MIN, min(N_MAX, int(round(area / AREA_DIVISOR)))) if area > 0 else 1
        # país minúsculo ou ring pequeno: 1 província = o país inteiro
        if k <= 1 or len(ring) < 8:
            pid = "%s-1" % iso
            provinces.append({
                "id": pid, "owner_iso": iso, "core_iso": iso,
                "nome": "%s" % nat.get("nome", iso),
                "polygon": ring, "neighbors": [], "centroid": polygon_centroid(ring),
                "pop_frac": 1.0, "pib_frac": 1.0, "is_capital": True, "terreno": "plano",
            })
            per_country_counts[iso] = 1
            continue

        seeds = seed_points_in_ring(ring, k)
        if len(seeds) < 3:  # Voronoi precisa de >=3 pontos p/ simplex inicial
            pid = "%s-1" % iso
            provinces.append({
                "id": pid, "owner_iso": iso, "core_iso": iso, "nome": nat.get("nome", iso),
                "polygon": ring, "neighbors": [], "centroid": polygon_centroid(ring),
                "pop_frac": 1.0, "pib_frac": 1.0, "is_capital": True, "terreno": "plano",
            })
            per_country_counts[iso] = 1
            continue

        import numpy as np
        # TÉCNICA DAS SEMENTES-FANTASMA: adiciona pontos bem distantes ao redor
        # do país. Isso força TODAS as sementes reais a terem células FINITAS
        # (as infinitas passam a pertencer às fantasmas, que descartamos). Sem
        # isso, células de borda viravam quadrados gigantes cobrindo o país todo.
        xs = [p[0] for p in ring]; ys = [p[1] for p in ring]
        minx, maxx, miny, maxy = min(xs), max(xs), min(ys), max(ys)
        cx0 = (minx + maxx) / 2.0; cy0 = (miny + maxy) / 2.0
        rad = max(maxx - minx, maxy - miny) * 3.0 + 20.0
        n_real = len(seeds)
        ghosts = []
        for gi in range(12):
            ang = 2.0 * math.pi * gi / 12.0
            ghosts.append([cx0 + rad * math.cos(ang), cy0 + rad * math.sin(ang)])
        all_pts = seeds + ghosts

        vor = Voronoi(np.array(all_pts))
        # adjacência: só entre sementes REAIS (índices < n_real)
        adj = defaultdict(set)
        for (a, b) in vor.ridge_points:
            a, b = int(a), int(b)
            if a < n_real and b < n_real:
                adj[a].add(b); adj[b].add(a)

        # país em CCW p/ ser o SUBJECT do clip (subject côncavo é OK; clip convexo)
        ring_ccw = ring[:] if ring_area(ring) > 0 else ring[::-1]

        made = 0
        for si in range(n_real):
            region_idx = vor.point_region[si]
            region = vor.regions[region_idx]
            # com as fantasmas, a região de uma semente real é sempre FINITA
            if not region or -1 in region:
                continue
            cell = [list(vor.vertices[v]) for v in region]
            if len(cell) < 3:
                continue
            # célula em CCW (o clip espera esquerda = dentro)
            cc = polygon_centroid(cell)
            cell.sort(key=lambda p: math.atan2(p[1]-cc[1], p[0]-cc[0]))
            # INTERSEÇÃO país ∩ célula: clipa o contorno CÔNCAVO real do país
            # pela célula convexa (Sutherland–Hodgman aceita subject côncavo
            # com clip convexo). Assim a província segue a fronteira REAL do
            # país, não a casca convexa (que invadia oceano/vizinhos).
            clipped = clip_to_convex_hull(ring_ccw, cell)
            if len(clipped) < 3:
                continue
            made += 1
            pid = "%s-%d" % (iso, si + 1)
            prov_index[(iso, si)] = pid
            provinces.append({
                "id": pid, "owner_iso": iso, "core_iso": iso,
                "nome": "%s %d" % (nat.get("nome", iso), si + 1),
                "polygon": [[round(x, 4), round(y, 4)] for x, y in clipped],
                "neighbors": [], "centroid": [round(v, 4) for v in polygon_centroid(clipped)],
                "pop_frac": round(1.0 / len(seeds), 4), "pib_frac": round(1.0 / len(seeds), 4),
                "is_capital": (si == 0), "terreno": "plano",
                "_seed": si,
            })
        per_country_counts[iso] = made
        # resolve neighbors por id (dentro do país)
        for si in range(len(seeds)):
            if (iso, si) not in prov_index:
                continue
            pid = prov_index[(iso, si)]
            nbrs = [prov_index[(iso, o)] for o in adj.get(si, ()) if (iso, o) in prov_index]
            for pr in provinces:
                if pr["id"] == pid:
                    pr["neighbors"] = nbrs
                    break

    # nações sem polígono (FR, NO...) — 1 província sintética sem geometria
    for iso, nat in nations.items():
        if iso not in mainland:
            skipped.append(iso)
            provinces.append({
                "id": "%s-1" % iso, "owner_iso": iso, "core_iso": iso, "nome": nat.get("nome", iso),
                "polygon": [], "neighbors": [], "centroid": [0, 0],
                "pop_frac": 1.0, "pib_frac": 1.0, "is_capital": True, "terreno": "plano",
            })

    # limpa campo interno
    for p in provinces:
        p.pop("_seed", None)

    out = {"provinces": provinces, "meta": {
        "generator": "voronoi", "area_divisor": AREA_DIVISOR,
        "n_provinces": len(provinces),
    }}
    json.dump(out, open(OUT, "w", encoding="utf-8"), ensure_ascii=False)

    # -------- resumo / validação
    total = len(provinces)
    owners = set(p["owner_iso"] for p in provinces)
    with_geo = sum(1 for p in provinces if p["polygon"])
    multi = {iso: c for iso, c in per_country_counts.items() if c > 1}
    print("PROVÍNCIAS geradas: %d" % total)
    print("Nações cobertas: %d" % len(owners))
    print("Com geometria: %d | sem geometria (sintéticas): %d" % (with_geo, total - with_geo))
    print("Países subdivididos (N>1): %d" % len(multi))
    print("Exemplos:", ", ".join("%s=%d" % (k, v) for k, v in
          sorted(multi.items(), key=lambda kv: -kv[1])[:8]))
    print("Nações sem polígono (1 prov sintética):", ", ".join(skipped) if skipped else "nenhuma")
    # validação de adjacência recíproca
    by_id = {p["id"]: p for p in provinces}
    bad = 0
    for p in provinces:
        for nb in p["neighbors"]:
            if nb not in by_id or p["id"] not in by_id[nb]["neighbors"]:
                bad += 1
    print("Adjacências NÃO recíprocas: %d %s" % (bad, "(OK)" if bad == 0 else "(!)"))
    print("Escrito em: %s" % OUT)

if __name__ == "__main__":
    main()
