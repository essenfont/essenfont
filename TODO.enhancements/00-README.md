# TODO.enhancements — Epic Overview

Nine enhancements that turn essenfont from "downloadable font" into a
"font platform". Each spec is implementation-ready.

## Index

| # | Title | Effort | Status |
|---|-------|--------|--------|
| 01 | [CDN delivery via jsDelivr](01-cdn-delivery.md) | ~30 min | ready |
| 02 | [npm package](02-npm-package.md) | ~half day | ready |
| 03 | [Donor provenance explorer](03-donor-provenance.md) | ~1 day | ready |
| 04 | [Site-wide /search with Cmd+K](04-site-search.md) | ~1 day | ready |
| 05 | [/changelog + per-release pages](05-changelog-page.md) | ~half day | ready |
| 06 | [/docs/{install,css,api} guides](06-docs-pages.md) | ~1 day | ready |
| 07 | [Variable font preview](07-variable-font-preview.md) | blocked | spec only |
| 08 | [Per-block SVG export](08-per-block-svg-export.md) | ~half day | ready |
| 09 | [License attribution pack](09-license-attribution-pack.md) | ~half day | ready |

## Audience map

| Audience | Primary enhancements |
|----------|---------------------|
| Web authors | 01 CDN, 02 npm, 06 /docs/css |
| Desktop users | 06 /docs/install |
| Researchers / type designers | 03 provenance, 08 SVG export |
| Compliance / legal | 09 license pack |
| Power users (159k char browsing) | 04 search, 05 changelog |
| Developers (Ruby API) | 06 /docs/api |
| Variable-font enthusiasts | 07 VF preview (deferred) |

## What changes per repo

- **essenfont/essenfont**: new scripts (emit_svg_exports.rb,
  emit_license_pack.rb, build_npm_package.rb), release.yml additions,
  npm/ directory.
- **essenfont/essenfont.github.io**: new pages (/changelog, /docs/*,
  /provenance, /license, /search), new components (SiteSearch),
  updated DownloadPage (CDN URLs), updated UnicodeCharPage (real
  provenance + SVG link).
