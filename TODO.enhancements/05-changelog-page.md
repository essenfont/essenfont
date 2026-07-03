# 05 — /changelog + /changelog/:tag

## Goal

Dedicated changelog on the website, sourced from the GH Releases API.
One page per release with full notes; index page lists every release.

Currently the HomePage has a small "Latest release" strip; this
expands it into a first-class section.

## Data source

GH Releases API is already queried by the site CI
(`update-release.yml` writes `public/releases.json`). Extend that
script to also fetch the full body of each release:

```yaml
- name: Fetch full release notes
  run: |
    curl -fsSL https://api.github.com/repos/essenfont/essenfont/releases \
      | jq '[.[] | {tag, name, date: .published_at, url, body, assets: [.assets[] | {name, size, download_url}]}]' \
      > public/releases-full.json
```

## /changelog index

Lists every release in reverse chronological order:

```
v0.2.0  ·  2026-07-15
  Plane partition + OTC, CFF2 variant, donor provenance explorer.
  [Read full notes →]

v0.1.0  ·  2026-06-01
  Initial release. 96.67% Unicode 17 coverage. ~131k glyphs.
  [Read full notes →]
```

Each entry: tag, date, summary (first paragraph of body), full-notes
link, key assets (OTC + per-plane WOFF2s).

## /changelog/:tag detail

Full release page for one tag:

```
v0.2.0
released 2026-07-15

[Full GH release body, markdown-rendered]

Coverage: 96.7% (154,550 / 159,866)
Build size: OTC 47 MB · CFF2 31 MB · WOFF2 plane set 18 MB

Downloads:
  Essenfont-Regular.otc          47 MB
  Essenfont-CFF2-Regular.otc     31 MB
  Essenfont-BMP.woff2            6 MB
  ...

Donors changed since v0.1:
  + noto-sans-ottoman-siyaq (added)
  ~ fsung bumped 0.9.4 → 0.9.5
  - last-resort-he (replaced by Noto Last Resort)
```

## Markdown rendering

Use `markdown-it` (already commonly available) or `marked`. Sanitize
with DOMPurify. Render in a wide single-column layout that matches
the editorial aesthetic.

## Implementation

- New: `src/pages/ChangelogIndexPage.vue`
- New: `src/pages/ChangelogDetailPage.vue`
- Route additions in `src/router.ts`:
  - `/changelog` → ChangelogIndexPage
  - `/changelog/:tag` → ChangelogDetailPage
- Nav: add "Changelog" between "About" and "GitHub"
- HomePage "Latest release" strip: link the tag → /changelog/:tag
  (currently links to GH directly)

## Acceptance

- /changelog lists every release
- /changelog/v0.2.0 renders full notes for v0.2.0
- Markdown renders correctly (tables, code blocks, lists)
- HomePage release strip links to /changelog/v0.X.Y instead of GH
- Site CI auto-refreshes public/releases-full.json on every release
