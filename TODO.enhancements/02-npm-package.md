# 02 — npm Package

## Goal

`npm install essenfont` → web devs `import "essenfont/css/all.css"`
and every Unicode 17 codepoint renders. No Ruby knowledge required,
no fontisan dependency, no manual download.

Reaches the largest single developer audience (JS/TS devs).

## Package shape

```
essenfont/
├── package.json
├── README.md
├── css/
│   ├── all.css              # imports every per-plane CSS file
│   ├── essenfont-bmp.css    # @font-face for BMP, Self-host URL
│   ├── essenfont-smp.css
│   ├── essenfont-sip.css
│   ├── essenfont-tip.css
│   └── essenfont-ssp.css
├── fonts/
│   ├── Essenfont-BMP.woff2
│   ├── Essenfont-SMP.woff2
│   ├── Essenfont-SIP.woff2
│   ├── Essenfont-TIP.woff2
│   └── Essenfont-SSP.woff2
└── package-lock.json
```

`package.json`:

```json
{
  "name": "essenfont",
  "version": "0.2.0",
  "description": "Universal Unicode 17 font — every assigned codepoint, real outlines.",
  "main": "css/all.css",
  "files": ["css/", "fonts/", "README.md"],
  "keywords": ["font", "unicode", "fallback", "otc", "unicode-17", "noto", "nofl"],
  "license": "OFL-1.1",
  "homepage": "https://essenfont.github.io",
  "repository": "essenfont/essenfont",
  "publishConfig": {
    "access": "public"
  }
}
```

## Build pipeline

New script: `scripts/build_npm_package.rb`

1. Read `Essenfont-{BMP,SMP,SIP,TIP,SSP}.woff2` from the build output
2. Copy to `npm/fonts/`
3. Emit `npm/css/essenfont-<plane>.css` per plane:

```css
/* essenfont-bmp.css — Self-host variant */
@font-face {
  font-family: 'Essenfont';
  src: url('../fonts/Essenfont-BMP.woff2') format('woff2');
  font-weight: 100 900;
  font-style: normal;
  font-display: swap;
  unicode-range: U+0000-FFFF;
}
```

4. Emit `npm/css/all.css`:

```css
@import url('./essenfont-bmp.css');
@import url('./essenfont-smp.css');
@import url('./essenfont-sip.css');
@import url('./essenfont-tip.css');
@import url('./essenfont-ssp.css');
```

5. Copy README.adoc → npm/README.md (or write a separate npm-focused README)

## Release

In `.github/workflows/release.yml`, after building the OTC + per-plane
assets:

```yaml
- name: Build npm package
  run: bundle exec ruby scripts/build_npm_package.rb

- name: Publish to npm
  if: startsWith(github.ref, 'refs/tags/v')
  run: |
    cd npm
    npm config set //registry.npmjs.org/:_authToken ${{ secrets.NPM_TOKEN }}
    npm publish --access public
```

`NPM_TOKEN` secret: an npm access token with publish rights on the
`essenfont` package. Generated at https://www.npmjs.com/settings/
essenfont/tokens (automation token, publish scope).

## Consumer usage

```bash
npm install essenfont
# or
yarn add essenfont
# or
pnpm add essenfont
```

In CSS / PostCSS / Tailwind / Sass:

```css
@import "essenfont/css/all.css";

body {
  font-family: -apple-system, system-ui, sans-serif, 'Essenfont';
}
```

In a JS bundler (webpack/vite/rollup):

```js
import 'essenfont/css/all.css'
```

In HTML:

```html
<link rel="stylesheet" href="node_modules/essenfont/css/all.css">
```

## Versioning

npm version tracks the GitHub Release tag. `npm install essenfont@^0.2`
gets the latest 0.2.x. `npm install essenfont@latest` gets the latest.

## Acceptance

- `npm pack` produces a tarball with the right files
- `npm publish --dry-run` shows the right files
- After tag push, the npm package is published automatically
- `npm install essenfont` in a fresh project works
- The /docs/css page on the website documents the npm install path
