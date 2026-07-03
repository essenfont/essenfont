# 06 — /docs/{install,css,api} guides

## Goal

Three long-form guides on the website for the three primary use
cases: install on a desktop, embed in CSS, drive via fontisan Ruby
API. Same editorial aesthetic as the rest of the site.

Currently /about has prose; these are structured how-to guides.

## /docs/install

Per-OS install instructions for the canonical OTC and per-plane
alternatives.

Sections:
1. macOS — Font Book workflow, double-click install, per-user vs
   system-wide, troubleshooting
2. Windows — Settings workflow, per-user vs all-users, font cache
   rebuild
3. Linux — fontconfig, `~/.local/share/fonts/`, `fc-cache -fv`,
   per-plane install for `fontconfig` setups that don't enumerate
   OTC faces
4. iOS / iPadOS — install via configuration profile (limitation: iOS
   doesn't enumerate OTC subfonts; use per-plane TTFs)
5. Android — sideload via Files app, per-app bundling
6. Browser as last-resort fallback — Chrome/Firefox/Safari font
   settings, the fontconfig-equivalent on each

Each section: numbered steps with screenshots, common pitfalls,
uninstall instructions.

## /docs/css

Embed essenfont in a website via three paths:

1. **Self-host** (canonical for production)
   - Download per-plane WOFF2s
   - `@font-face` per plane with `unicode-range`
   - `<link rel="preload">` for the BMP
   - Performance: ~6 MB BMP WOFF2 fetched only if user views BMP chars

2. **Via CDN** (jsDelivr) — see TODO 01
   - One-line CSS, no download
   - `integrity="sha384-..."` for security
   - Trade-off: external dependency, requires CDN trust

3. **Via npm** — see TODO 02
   - `npm install essenfont`
   - `@import "essenfont/css/all.css"`
   - Bundler-friendly (webpack/vite/rollup)

Plus: `font-display` strategy, `unicode-range` for fine-grained
per-block loading, fallback stack ordering, variable-font-age
forward compatibility.

## /docs/api

Drive essenfont via the fontisan Ruby API for programmatic use
(build pipelines, font tools, automated subsetting).

Quickstart:

```ruby
require "fontisan"
require "essenfont"

donors = EssenfontBuild.load_donors  # reads sources/manifest.yml
cp_map = EssenfontBuild.build_codepoint_map(donors)

Essenfont::Otc::Build.new(
  cp_map: cp_map,
  donors: donors,
  subfont_format: :otf2  # CFF2 outlines
).call(output_path: "Essenfont-Regular.otc")
```

Sections:
1. **Read the OTC** — `Fontisan::Collection::Reader.open(path)`
   iterating faces, getting per-face stats
2. **Subset per block** — `fontisan subset` CLI for per-block WOFF2
3. **Custom partitioning** — implement your own
   `PartitionStrategy::Base` subclass (by script? by license?)
4. **Donor manifest format** — `sources/manifest.yml` schema,
   adding a donor, `covers:` declarations
5. **Build pipeline internals** — cp_map shape, donor cmap mutation,
   PUA filter, codepoint remap

## Implementation

- Three new pages in `src/pages/docs/`:
  - `InstallPage.vue`
  - `CssPage.vue`
  - `ApiPage.vue`
- Routes: `/docs/install`, `/docs/css`, `/docs/api`
- Nav: add "Docs" with dropdown (or just `/docs` index that links
  to the three)
- Long-form content rendered in a wide single column (~720ch)
- Code blocks use the existing `--spec-term-bg` dark treatment
- Copy-to-clipboard on every code block (reuse the UnicodeCharPage
  ucp-copy component)

## /docs index

Optional: a `/docs` landing page that links to the three guides
plus the existing /about. If we don't add this, the nav "Docs" item
should go directly to /docs/install (the most common entry point).

## Acceptance

- Three pages exist at the URLs above
- Each is ~800-1500 words of original content
- Code blocks have copy buttons
- Pages render cleanly in SSG (no runtime errors)
- Mobile-responsive (single column on small screens)
