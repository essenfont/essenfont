# 08 — Website Design

## Reference: metfont.github.io

metfont ships a VitePress site that:
- Single landing page with hero, type tester, format matrix
- Downloads all formats directly from latest GitHub Release
- Site CI fetches latest release on every push to main, rebuilds VitePress static site

essenfont.github.io already uses Vue 3 + Vite (not VitePress). We
keep that stack — the existing site has substantial logic (Unicode
browser, donor pages, coverage map) that doesn't fit VitePress's
markdown-centric model.

## What changes

### 1. Download page (`/download`)

Today: 3 cards (TTF, OTF, WOFF2) all pointing at GitHub release URLs.
Tomorrow: 4 tiers, ordered by audience.

```
┌─────────────────────────────────────────────────────────────────┐
│  ESSENFONT · Universal Unicode 17 font                          │
│                                                                  │
│  ╔═══════════════════════════════════════════════════════════╗  │
│  ║  Download the OTC                                          ║  │
│  ║  OpenType Collection · 5 subfonts · ~50 MB · v0.2         ║  │
│  ║  [ Essenfont-Regular.otc ]    [ CFF2 variant (-35% size) ]║  │
│  ╚═══════════════════════════════════════════════════════════╝  │
│                                                                  │
│  ── Per-plane TTFs (legacy clients) ──                          │
│  BMP  U+0000..U+FFFF       (~12 MB)  → Essenfont-BMP.ttf        │
│  SMP  U+10000..U+1FFFF     (~3 MB)   → Essenfont-SMP.ttf        │
│  SIP  U+20000..U+2FFFF     (~14 MB)  → Essenfont-SIP.ttf        │
│  TIP  U+30000..U+3FFFF     (~2 MB)   → Essenfont-TIP.ttf        │
│  SSP  U+E0000..U+EFFFF     (<1 MB)   → Essenfont-SSP.ttf        │
│                                                                  │
│  ── Per-plane WOFF2 (web embed) ──                              │
│  Same planes, ~50% smaller, served as @font-face unicode-range  │
│                                                                  │
│  ── Per-block WOFF2 (this site uses them) ──                    │
│  214 files, ~80 KB each — see /unicode to browse                │
└─────────────────────────────────────────────────────────────────┘
```

Each tier collapses by default; user expands to see options. Default
card is the OTC (canonical). Per-plane and per-block tiers are clearly
labeled "advanced / legacy / web embed".

### 2. Home page hero

Update the hero badges to reflect OTC reality:

```
[ Unicode 17.0 ]   [ 5 subfonts · 5 planes ]   [ ~131k glyphs ]   [ OFL 1.1 ]
```

The "Type tester" stays — it's the killer demo. Replace the "TTF"
download button with "Download OTC".

### 3. New `/subfonts` page

Visualizes the 5-plane partition:

```
PLANE 0 · BMP       ─ 62,134 glyphs  ─ 430 blocks  ─ noto, fsung_m, ...
PLANE 1 · SMP       ─ 9,012 glyphs   ─ 87 blocks   ─ noto_emoji, ...
PLANE 2 · SIP       ─ 60,219 glyphs  ─ 7 blocks    ─ fsung_2
PLANE 3 · TIP       ─ 6,003 glyphs   ─ 4 blocks    ─ fsung_3, noto_tangut
PLANE 14 · SSP      ─ 99 glyphs      ─ 2 blocks    ─ noto
```

Each row links to `/unicode?plane=N` for browsing the plane's blocks.

### 4. Coverage map refresh

Existing `CoverageMap.vue` already shows per-block coverage. Color
plane headers to indicate which subfont carries the block:

- Plane-0 block → orange (BMP subfont)
- Plane-1 block → teal (SMP subfont)
- Plane-2 block → purple (SIP subfont)
- Plane-3 block → pink (TIP subfont)
- Plane-14 block → gold (SSP subfont)

Tooltip on a block now reads:
"BMP subfont covers 100% of CJK Unified Ideographs (20,992 / 20,992),
 donor: fsung_m."

### 5. Footer "Last release" strip

Every page footer shows:

```
v0.2.0 · released 2026-07-15 · Essenfont-Regular.otc · 47.3 MB ·
[full changelog]  [previous releases]
```

Data comes from `releases.json` (fetched by site CI from the GH API).

## Design language

The current site uses a "specimen card" aesthetic — serif display
typography, cream/rose palette, mono labels, generous whitespace.
The redesign keeps this language but:

- **Replaces the TTF-centric framing** with OTC framing (5 subfonts, planes)
- **Adds a "format picker"** that explains when each format is right
- **Surfaces donor provenance** at the subfont level (which donors
  contribute to which plane)

No wholesale redesign. The site's identity stays.

## Implementation steps

1. **Data layer** — `public/coverage.json` gains `subfonts` array (one
   entry per plane with `name`, `glyph_count`, `donors`, `ttf_url`,
   `woff2_url`).
2. **DownloadPage.vue** — rewrite to the 4-tier layout above. ~200 lines
   net (down from current ~330).
3. **HomePage.vue** — swap TTF references for OTC; add 5-plane hero badge.
4. **SubfontsPage.vue** — new page, ~150 lines.
5. **CoverageMap.vue** — add per-plane color logic; minor.
6. **Site CI** (see `09-release-pipeline.md`) — fetches `releases.json`
   + `coverage.json` from latest GH release on every build.

## Non-goals

- **Rewriting in VitePress.** The Vue 3 site has substantial interactivity
  that doesn't fit markdown-centric VitePress. Stack stays.
- **Variable font UI.** CFF2 in essenfont is static. No axes to expose.
- **Per-glyph preview**. Out of scope for the download page.
- **Live subfont build status.** The CI runs on tag; no real-time
  progress to surface. The release-notes page suffices.

## Success criteria

- A user landing on `/download` understands within 10 seconds that the
  OTC is the recommended download and per-plane/per-block options exist
  for special cases.
- A web author landing on `/download` finds the per-plane WOFF2 + CSS
  snippet within 30 seconds.
- The home page accurately reflects "5 subfonts, every plane" rather
  than the obsolete "one TTF" message.
