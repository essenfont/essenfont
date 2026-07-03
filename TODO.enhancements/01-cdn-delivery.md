# 01 — CDN Delivery via jsDelivr

## Goal

Web authors currently have to download WOFF2s and self-host. CDN
delivery lets them embed essenfont with a one-line CSS rule, no
download step.

## Provider

[jsDelivr](https://www.jsdelivr.com/) mirrors GitHub Releases for
free, auto-updates on new tags, and serves with global CDN + SRI
support. No infra to maintain.

URL pattern:

```
https://cdn.jsdelivr.net/gh/essenfont/essenfont@<tag>/<asset>
```

Examples:

```
https://cdn.jsdelivr.net/gh/essenfont/essenfont@v0.2/Essenfont-BMP.woff2
https://cdn.jsdelivr.net/gh/essenfont/essenfont@v0.2/Essenfont-SIP.woff2
```

jsDelivr auto-detects the latest tag via `@latest`:

```
https://cdn.jsdelivr.net/gh/essenfont/essenfont@latest/Essenfont-BMP.woff2
```

## Implementation

### DownloadPage updates

Add a "via CDN" tab to the Web Embed section (III). Show:

```css
@font-face {
  font-family: 'essenfont';
  src: url('https://cdn.jsdelivr.net/gh/essenfont/essenfont@latest/Essenfont-BMP.woff2') format('woff2');
  font-display: swap;
  unicode-range: U+0000-FFFF;
}
```

Toggle: `Self-host` vs `CDN (jsDelivr)`. Self-host shows the GH
release URL; CDN shows the jsDelivr URL.

### SRI (Subresource Integrity) hashes

Add `<asset>.sri` file to each release artifact. Format:

```
 Essenfont-BMP.woff2=sha384-<base64>
```

Build step in `release.yml`:

```bash
for f in Essenfont-*.woff2 Essenfont-*.woff; do
  hash=$(openssl dgst -sha384 -binary "$f" | openssl base64 -A)
  echo "$f=sha384-$hash" >> sri.txt
done
```

SRI in CSS:

```html
<link rel="stylesheet" href="... essenfont.css"
      integrity="sha384-..." crossorigin="anonymous">
```

### /docs/css page

The new /docs/css guide (see 06-docs-pages.md) includes a "via CDN"
section with copy-paste snippets for both `@font-face` and `<link>`
forms.

## Acceptance

- DownloadPage "Web embed" section has a Self-host/CDN toggle
- /docs/css includes CDN snippets
- Each release artifact has SRI hashes in `sri.txt`
- jsDelivr URL resolves (test after first v* tag ships the assets)
