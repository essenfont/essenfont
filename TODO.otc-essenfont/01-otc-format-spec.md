# 01 — OTC Format Spec

## What is an OTC?

An **OpenType Collection** is a single binary file containing two or
more OpenType fonts. Each contained font is called a **subfont** (or
"face"). All subfonts share their binary layout via the TTC header
and may share tables (e.g., `head`, `hhea`, `name`, `glyf` for
identical glyphs) to reduce file size.

OTC and TTC share the same binary container format (`ttcf` magic);
the distinction is convention:

- **TTC** — TrueType Collection; all subfonts use `glyf`+`loca` (TTF outlines)
- **OTC** — OpenType Collection; subfonts may mix `glyf` (TTF) and `CFF`/`CFF2` (OTF) outlines

## Binary structure

```
┌────────────────────────────────────────────┐
│ TTC Header (12 bytes)                      │
│   tag      "ttcf"                          │
│   majorVer uint16 (1 or 2)                 │
│   minorVer uint16 (0)                      │
│   numFonts uint32                          │
├────────────────────────────────────────────┤
│ Offset Table (4 × numFonts bytes)          │
│   fontOffsets uint32[numFonts]             │
├────────────────────────────────────────────┤
│ Font 0 Table Directory                     │
│   (sfnt_version + search params + entries) │
├────────────────────────────────────────────┤
│ Font 1 Table Directory                     │
│   ...                                      │
├────────────────────────────────────────────┤
│ ...                                        │
├────────────────────────────────────────────┤
│ Shared table data                          │
│   (one copy per unique table content)      │
├────────────────────────────────────────────┤
│ Per-font unique table data                 │
│   (glyf, loca, cmap, maxp, etc.)           │
└────────────────────────────────────────────┘
```

## fontisan API used

essenfont consumes three layers of fontisan's collection stack:

### Layer 1 — `Fontisan::Stitcher` (single subfont assembly)

```ruby
stitcher = Fontisan::Stitcher.new(deduplicate: true)
stitcher.add_source(:donor_label, donor_font)
stitcher.include_codepoints([0x41, 0x42], from: :donor_label, into: :plane_0)
stitcher.include_notdef(from: :donor_label, into: :plane_0)
```

The `into:` keyword (added in fontisan 0.4.6) assigns each glyph to
a named subfont. There is no implicit default — every glyph must be
assigned explicitly.

### Layer 2 — `Stitcher#write_to` (single subfont → temp TTF)

```ruby
stitcher.write_to("/tmp/plane_0.ttf", format: :ttf, subfont: :plane_0)
```

`Fontisan::Stitcher::GlyphLimit.check!` validates the subfont's
glyph count ≤ 65,535 before writing. Raises if exceeded.

### Layer 3 — `Fontisan::Collection::Builder` (subfonts → OTC)

```ruby
fonts = subfont_names.map do |name|
  # Write the subfont to a temp TTF, then load it back as a TrueTypeFont
  Tempfile.create(["#{name}-", ".ttf"]) do |io|
    stitcher.write_to(io.path, format: :ttf, subfont: name)
    Fontisan::FontLoader.load(io.path)
  end
end

Fontisan::Collection::Builder.new(fonts, format: :otc, optimize: true)
                              .build_to_file("Essenfont-Regular.otc")
```

`Collection::Builder` orchestrates `TableAnalyzer` →
`TableDeduplicator` → `OffsetCalculator` → `Writer`. The result is a
single `.otc` binary with shared `head`/`hhea`/`name` tables and
per-subfont `glyf`/`loca`/`cmap`/`maxp` tables.

### Why not `Stitcher#write_collection`?

`Stitcher#write_collection` is a thin wrapper around layers 2+3, but
its `collection_format_for` helper hardcodes the mapping:

```ruby
subfont_format == :ttf ? :ttc : :otc
```

essenfont wants TTF outline subfonts *inside* an OTC container (D1 in
`00-README.md`). To keep that flexibility without waiting on a
fontisan PR, we call layers 2 and 3 directly. The wrapper exists for
the common case (TTC of TTFs or OTC of OTFs); mixing is rare.

**Future fontisan PR:** add `collection_format:` keyword to
`Stitcher#write_collection` to let the caller override the container
format. When that lands, essenfont switches back to the wrapper.

## Table sharing semantics

fontisan's `TableDeduplicator` identifies shared tables by SHA-256 of
table bytes. Tables identical across subfonts are stored once and
referenced by offset.

For essenfont:

| Table      | Shared?        | Reason                                   |
|------------|----------------|------------------------------------------|
| `head`     | Yes            | Same font version, unitsPerEm, created/modified. |
| `hhea`     | Yes            | Same metrics layout.                     |
| `name`     | Mostly         | Family/PostScript names differ per subfont; non-shared. |
| `OS/2`     | Mostly         | usWinAscent/Descent + codepage ranges differ per subfont. |
| `maxp`     | No             | Per-subfont glyph count.                 |
| `cmap`     | No             | Per-subfont codepoint coverage.          |
| `glyf`+`loca` | No          | Per-subfont glyph data.                  |
| `post`     | Yes            | Same glyph naming convention.            |

Net space savings from sharing: ~30-40% vs N independent TTFs.

## Per-subfont identity

Each subfont gets unique identifying fields in its `name` table:

| nameID         | Field              | Value                      |
|----------------|--------------------|----------------------------|
| 1              | Family             | `essenfont`                |
| 2              | Subfamily          | `Regular`                  |
| 3              | Unique ID          | `essenfont;0.1;PLT`        |
| 4              | Full name          | `essenfont <Plane>`        |
| 5              | Version            | `Version 0.1`              |
| 6              | PostScript name    | `essenfont-<Plane>`        |

`<Plane>` ∈ {`BMP`, `SMP`, `SIP`, `TIP`, `SSP`}.

## Sanity checks

After writing, the build runs:

1. `fc-query Essenfont-Regular.otc` — confirms `nfonts = 5`.
2. Per-subfont `maxp.num_glyphs ≤ 65,535` — confirmed by loading
   each face via `Fontisan::FontLoader.load(path, font_index: i)`.
3. Union of all subfont `cmap` entries equals the input cp_map (no
   drops). This is the "no coverage regression" gate.

If any check fails, the build aborts with a diagnostic — no silent
fallback to a single TTF.
