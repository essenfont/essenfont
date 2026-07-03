# 04 — Site-wide /search with Cmd+K

## Goal

With ~160,000 characters, ~346 blocks, ~150 donors, search is the
primary navigation tool. Add a Cmd+K-triggered overlay that jumps to
any codepoint / block / script / donor by name or hex.

## Why

Currently the only way to find U+1F600 is to navigate:
Browse → SMP → Emoticons → scroll to U+1F600. With search: Cmd+K,
type "1F600" or "grinning" → Enter → on the page.

Power users (the people who actually use this site) need this.

## Search index

Built during SSG from existing data, output as `public/search-index.json`.

```json
[
  { "t": "cp", "q": "1F600", "n": "GRINNING FACE", "u": "/unicode/char/1F600" },
  { "t": "cp", "q": "13000", "n": "EGYPTIAN HIEROGLYPH A001", "u": "/unicode/char/13000" },
  { "t": "blk", "q": "Emoticons", "n": "Emoticons", "u": "/unicode/block/emoticons" },
  { "t": "don", "q": "Noto Color Emoji", "n": "Noto Color Emoji", "u": "/donors/noto-color-emoji" },
  ...
]
```

Size: ~160k entries × ~80 bytes = ~13 MB. Gzipped ~3 MB. Loaded
on-demand only when the user opens search (not on initial page load).

Generator: `scripts/gen-search-index.mjs` in essenfont.github.io,
runs before SSG.

## Fuse.js for fuzzy search

Lightweight (~10 KB gzipped). Indexed in a Web Worker so the main
thread never blocks.

```ts
import Fuse from 'fuse.js'
import index from './search-index.json'

const fuse = new Fuse(index, {
  keys: ['q', 'n'],
  threshold: 0.3,
  ignoreLocation: true,
  minMatchCharLength: 2,
})
```

## UI: Cmd+K overlay

New component: `src/components/SiteSearch.vue`

- Triggers: Cmd+K (macOS) / Ctrl+K (others), `/` when not in an input
- Overlay: darkened backdrop + centered card with input + result list
- Result categories: Codepoints / Blocks / Donors (collapsible groups)
- Keyboard nav: ↑↓ to move, Enter to navigate, Esc to close
- Recent: persists last 5 searches in localStorage

Auto-mounted in DefaultLayout.vue (present on every page).

## /search?q= fallback route

For users without JS or arriving from external search engines:

```
/search?q=grinning
```

Server-side (SSG) renders a plain result list. Same Fuse.js index,
queried at build time for the q parameter.

## Implementation steps

1. Write `scripts/gen-search-index.mjs` (reads public/unicode-blocks.json
   + public/donors.json + per-block codepoint JSONs → emits
   public/search-index.json + public/search-index.json.gz)
2. Add the script to the site CI before SSG
3. Add SiteSearch.vue + mount in DefaultLayout
4. Add /search route + SearchPage.vue
5. Add search icon to nav (between Browse and Subfonts) for
   discoverability on touch devices

## Acceptance

- Cmd+K opens overlay anywhere on the site
- Typing "1F600" jumps to U+1F600 in <100ms
- Typing "grinning" finds GRINNING FACE
- Typing "Noto" finds all Noto donor pages
- Search works on mobile (tap icon to open)
- /search?q=... renders without JS
- Search index is < 5 MB compressed
