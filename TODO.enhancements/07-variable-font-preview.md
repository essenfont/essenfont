# 07 — Variable Font Preview

## Status

**Blocked.** Requires building a variable variant of essenfont first,
which is not yet implemented. This spec captures the UX design so
the build work has a target.

## Why variable

A variable font encodes weight (and other axes) as a continuous
space. One file replaces N static files (currently: essenfont ships
only Regular; a variable variant could ship 100-900 in one file).

Variable Essenfont would:
- Halve the download for users who want multiple weights
- Enable `font-weight: 350` rendering in CSS without multiple files
- Future-proof against weight-axis expectations

## Prerequisite: build the variable variant

Donors that ship multiple weights (Noto Sans Regular + Bold + Light,
etc.) can be merged into a variable font via fontisan's CFF2+vsindex
support (already implemented, see fontisan/docs/CFF2_SUPPORT.adoc).

Pipeline sketch:

1. Group donors by family (Noto Sans, Noto Serif, etc.)
2. For each family, identify which weights are available
3. Per codepoint: collect the same glyph at multiple weights
4. Build a CFF2 charstring with `blend` operators that interpolate
5. Emit `fvar` (axes), `gvar`/`CFF2` variations, HVAR, MVAR
6. Wrap in OTC (5 plane subfonts, each variable)

Output: `Essenfont-VF-Regular.otc` — single OTC, weight axis 100-900.

Coverage limits: only codepoints where ≥2 weights of the same donor
exist can become variable. Codepoints with a single weight stay
static (still in the same OTC, just no variation).

Estimated effort: 1-2 weeks. Out of scope for this iteration.

## UI: Variable Font Preview

Once the variable variant ships, add a preview UI:

### HomePage: "Variable" pill in hero badges

```
[ Unicode 17 ] [ OTC · 5 subfonts ] [ Variable weight ] [ 131k glyphs ]
```

### /playground (new page, see 04-site-search successor)

Multi-mode type tester with a **weight slider** (100-900, step 10).
Live preview of the text at the chosen weight. Toggle between
"Static Regular" and "Variable".

```
┌────────────────────────────────────────────┐
│  Weight:  ▮▮▮▮▮▮▮▮░░░░░░░░░░░░  450        │
│  Sample:  The quick brown fox              │
│                                              │
│              The quick brown fox            │
│              (rendered at weight 450)       │
│                                              │
│  [Static Regular] [Variable]                │
└────────────────────────────────────────────┘
```

CSS:

```css
.type-tester-output {
  font-family: 'Essenfont VF', 'Essenfont', sans-serif;
  font-variation-settings: 'wght' 450;
  font-size: 4rem;
}
```

### Per-character: weight scrubber

On UnicodeCharPage, a slider under the glyph that scrubs the weight
axis. Shows the glyph morphing in real time. Useful for type
designers studying weight response.

### /docs/css: variable section

Add a "Variable variant" section explaining `font-variation-settings`,
the `wght` axis, browser support (Chrome 62+, Firefox 53+, Safari 11+).

## Acceptance (post-build)

- Essenfont-VF-Regular.otc ships in the release
- HomePage hero badge includes "Variable"
- /playground page exists with weight slider
- Per-character page shows weight scrubber for variable glyphs
- /docs/css documents the variable CSS recipe

## What this iteration ships

Spec only. The build prerequisite (variable variant) is tracked
separately as a fontisan/essenfont joint work item.
