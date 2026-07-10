# 06 — Manifest: uni-hieroglyphica primary for Egyptian blocks

## Change

Edit `sources/manifest.yml`:

### uni-hieroglyphica (line ~406) — becomes primary

```yaml
- label: uni-hieroglyphica
  ...
  covers: [
    Egyptian_Hieroglyphs,              # ← ADD (was only Ext-A)
    Egyptian_Hieroglyph_Format_Controls, # ← ADD
    Egyptian_Hieroglyphs_Extended-A,
  ]
  notes: "Primary donor for all Egyptian Hieroglyphs blocks.
    By Michel Suignard (Unicode Egyptian Hieroglyphs co-editor).
    upm=1000 — matches Essenfont target, no scaling required."
```

### egyptian-text (line ~391) — demoted to defense-in-depth

```yaml
- label: egyptian-text
  ...
  covers: []   # was: [Egyptian_Hieroglyphs, Egyptian_Hieroglyph_Format_Controls]
  notes: "Defense-in-depth secondary. Microsoft font-tools reference.
    Core block redundant with uni-hieroglyphica."
```

## Why

- uni-hieroglyphica is at upm=1000 (no scaling needed)
- egyptian-text (eot.ttf) is at upm=2048 (requires 0.4883 scale — bug source)
- Author authority: Suignard co-edited the Unicode block
- Already in manifest, just needs covers: expanded

## CpMap ordering

CpMap iterates donors in manifest order. uni-hieroglyphica is at
line 406, egyptian-text at line 391. With egyptian-text's covers
emptied, CpMap's first-wins assigns Egyptian Hieroglyphs to
uni-hieroglyphica automatically.

## Acceptance criteria

- [ ] `cp_map.json[0x13080]` == `"uni-hieroglyphica"` (was: `"egyptian-text"`)
- [ ] `cp_map.json[0x13460]` == `"uni-hieroglyphica"` (Ext-A, unchanged)
- [ ] Essenfont SMP face U+13080 glyph bbox ≤ ±500 (fits 1000-upm)
