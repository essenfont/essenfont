# Donor Font Attributions

Every glyph in essenfont is sourced from the donor fonts below. This
file is the canonical attribution record. It is auto-referenced by
`LICENSE-SOURCES.md` at release time.

## FSung (Full-Sung) — Taiwan 全宋體

| Field | Value |
|---|---|
| **Font family** | Full-Sung (FSung) |
| **Author** | F.G. Wang (fgwang.blogspot.com) — expert CJK fontographer |
| **Initial source** | Taiwan Ministry of Education (教育部) — provided the 全宋體 style + base glyph sources |
| **First announced** | http://fgwang.blogspot.com/2021/12/blog-post.html (2021-12) |
| **Latest news** | https://fgwang.blogspot.com/2025/09/unicode-17.html |
| **Download** | https://drive.google.com/file/d/1m0-WYAXbEz3lxJrti25ZvWv6LkHjMp2X/view?usp=sharing |
| **Mirror** | https://github.com/lxs602/FSung-font (lxs602) |
| **License** | **Custom NON-COMMERCIAL share + use.** NOT OFL. Commercial use prohibited by the author. See `License statement` row below. |
| **License statement (zh)** | 現將此成果無條件分享出來，樂見學術研究、教育工作、個人閱讀這方面的運用，但請勿用做任何形式的商業營利行為。希望「全宋體」這個大型字庫以及「部件檢索」這個檢字工具，能在漢字文化的整理、研究上幫上一點小忙。 |
| **Unicode version** | 17.0 (full coverage of CJK Unified Ideographs Ext A–J) |
| **Files** | FSung-m.ttf (BMP), FSung-2.ttf (SIP), FSung-3.ttf (TIP+Ext J), FSung-X.ttf (Plane 3), FSung-1.ttf, FSung-F.ttf (PUA), FSung-p.ttf |
| **Coverage** | CJK Unified Ideographs (all extensions A–J), CJK symbols, ~430 BMP ranges |

**License and redistribution note (important):**

FSung's license is a custom non-commercial share + use grant from
F.G. Wang — it is **NOT OFL**. The grant permits academic research,
educational use, and personal reading; commercial use is prohibited.

essenfont, which is publicly redistributed under SIL OFL 1.1, embeds
FSung-derived glyphs. Downstream users must therefore respect F.G.
Wang's no-commercial-use restriction on the FSung-derived portion of
essenfont. The FSung-derived glyphs are NOT reusable in commercial
products without F.G. Wang's separate permission.

Covers CJK Unified Ideographs Extension J (U+31350..U+323AF) — Unicode
17 additions that no other freely-redistributable font covers.

## Noto Sans (universal fallback)

| Field | Value |
|---|---|
| **Font family** | Noto Sans |
| **Author** | Google + Monotype + Adobe |
| **Source** | https://github.com/notofonts/notofonts.github.io |
| **License** | OFL |
| **File** | NotoSans-Regular.ttf |
| **Coverage** | Latin, Latin-1 Supplement, Latin Extended-A/B, IPA Extensions, Spacing Modifier Letters, Combining Diacritical Marks, Greek and Coptic, Cyrillic, + ~250 blocks |

## Noto Serif Tangut

| Field | Value |
|---|---|
| **Font family** | Noto Serif Tangut |
| **Author** | Google (Noto Project) |
| **Source** | https://notofonts.github.io/tangut/fonts/NotoSerifTangut/full/otf/NotoSerifTangut-Regular.otf |
| **License** | OFL |
| **File** | NotoSerifTangut-Regular.otf |
| **Coverage** | Tangut (U+17000..U+187FF, 6136/6144), Tangut Components (U+18800..U+18AFF, 768/768), Tangut Supplement (U+18D00..U+18D7F, 9/128) |
| **Note** | Replaces Noto Sans Tangut (which was never published by Noto). OTF (CFF outlines). |

## Kelly Tolong (Tolong Siki)

| Field | Value |
|---|---|
| **Font family** | Kelly Tolong |
| **Author** | Tolong Siki community (tolongsiki.com) |
| **Source** | https://www.tolongsiki.com/downloads/kellytolong4.ttf |
| **License** | OFL |
| **File** | kellytolong4.ttf |
| **Coverage** | Tolong Siki (U+11DB0..U+11DEF) — planned; requires codepoint remap |
| **Note** | Keyboard-mapping font: glyphs are encoded at ASCII codepoints (U+20..U+B7). Disabled in v0.1.0 until `sources/remaps/kellytolong4.yml` remap table is derived via visual-match against the Unicode code chart. |

## Noto Sans Sharada

| Field | Value |
|---|---|
| **Font family** | Noto Sans Sharada |
| **Author** | Google (Noto Project) |
| **Source** | https://github.com/notofonts/notofonts.github.io/tree/main/fonts/NotoSansSharada |
| **License** | OFL |
| **File** | NotoSansSharada-Regular.ttf |
| **Coverage** | Sharada Supplement (U+11B60..U+11B7F) |

## Noto Sans Math

| Field | Value |
|---|---|
| **Font family** | Noto Sans Math |
| **Author** | Google (Noto Project) |
| **Source** | https://github.com/notofonts/notofonts.github.io/tree/main/fonts/NotoSansMath |
| **License** | OFL |
| **File** | NotoSansMath-Regular.ttf |
| **Coverage** | Mathematical Operators, Supplemental Mathematical Operators, Mathematical Alphanumeric Symbols, Miscellaneous Mathematical Symbols-A/B |

## Noto Music

| Field | Value |
|---|---|
| **Font family** | Noto Music |
| **Author** | Google (Noto Project) |
| **Source** | https://github.com/notofonts/notofonts.github.io/tree/main/fonts/NotoMusic |
| **License** | OFL |
| **File** | NotoMusic-Regular.ttf |
| **Coverage** | Musical Symbols |

## Noto Sans Symbols

| Field | Value |
|---|---|
| **Font family** | Noto Sans Symbols |
| **Author** | Google (Noto Project) |
| **Source** | https://github.com/notofonts/notofonts.github.io/tree/main/fonts/NotoSansSymbols |
| **License** | OFL |
| **File** | NotoSansSymbols-Regular.ttf |
| **Coverage** | Miscellaneous Symbols, Miscellaneous Technical, Alchemical Symbols |

## Noto Sans Symbols 2

| Field | Value |
|---|---|
| **Font family** | Noto Sans Symbols 2 |
| **Author** | Google (Noto Project) |
| **Source** | https://github.com/notofonts/notofonts.github.io/tree/main/fonts/NotoSansSymbols2 |
| **License** | OFL |
| **File** | NotoSansSymbols2-Regular.ttf |
| **Coverage** | Miscellaneous Symbols and Pictographs, Supplemental Symbols and Pictographs, Transport and Map Symbols, Chess Symbols, Symbols and Pictographs Extended-A, Symbols for Legacy Computing |

## Noto Color Emoji

| Field | Value |
|---|---|
| **Font family** | Noto Color Emoji |
| **Author** | Google (Noto Project) |
| **Source** | https://github.com/googlefonts/noto-emoji |
| **License** | OFL |
| **File** | NotoColorEmoji.ttf |
| **Coverage** | Emoticons (U+1F600..U+1F64F, 80/80), many other emoji ranges |
| **Note** | Color bitmap emoji (CBDT/CBLC tables). Requires fontisan 0.4+ for Stitcher passthrough (single-CBDT-source mode). |

## Lentariso

| Field | Value |
|---|---|
| **Font family** | Lentariso |
| **Author** | Bryndan W. Meyerholt (Bry10022) |
| **Source** | https://github.com/Bry10022/Lentariso |
| **License** | OFL |
| **File** | Lentariso-Regular.ttf (extracted from repo TTFs/) |
| **Coverage** | Imperial Aramaic (U+10840..U+1085F, 31/32), Phoenician (U+10900..U+1091F, 29/32), Beria Erfe (U+10940..U+1095F, 26/32) |
| **Note** | Does NOT cover Sidetic (U+10920..U+1093F) — no OFL donor exists for this Unicode 17 block; covered via code-chart extraction in v0.2.0. |

## Kedebideri

| Field | Value |
|---|---|
| **Font family** | Kedebideri |
| **Author** | SIL International |
| **Source** | https://software.sil.org/kedebideri/ |
| **License** | OFL |
| **File** | Kedebideri-Regular.ttf |
| **Coverage** | Beria Erfe (U+16EA0..U+16EDF, UC17) |

## Egyptian Text (Microsoft font-tools)

| Field | Value |
|---|---|
| **Font family** | Egyptian Text |
| **Author** | Microsoft Corporation |
| **Source** | https://github.com/microsoft/font-tools (EgyptianOpenType/) |
| **License** | OFL (font); MIT (repo) |
| **Files** | egyptiantext-COLR.ttf, eot.ttf |
| **Coverage** | Egyptian Hieroglyphs (U+13000..U+1342F, 1072/1072), Format Controls (U+13430..U+1345F, 38/48), partial Ext-A Extended (21/4000) |

## UniHieroglyphica

| Field | Value |
|---|---|
| **Font family** | UniHieroglyphica |
| **Author** | Michel Suignard (suignard.com) |
| **Source** | https://suignard.com/Ptolemaic/UniHieroglyphica.ttf |
| **License** | OFL |
| **File** | UniHieroglyphica.ttf |
| **Coverage** | Egyptian Hieroglyphs Ext-A Extended (U+13460..U+143FF, 3995/4000) — primary Ext-A Extended donor. Also covers core (1072/1072) and Format Controls (38/48), redundant with eot.ttf. |
| **Note** | Does NOT cover Egyptian Hieroglyphs Ext-B (U+16A40..U+16A8F) — Unicode 17 addition, no OFL donor exists; covered via code-chart extraction in v0.2.0. |

## NewGardiner

| Field | Value |
|---|---|
| **Font family** | NewGardiner |
| **Author** | Mark Jan Nederhof |
| **Source** | https://github.com/nederhof/newgardiner |
| **License** | OFL |
| **Files** | NewGardiner.ttf, NewGardinerNonCore.ttf |
| **Coverage** | Defense-in-depth secondary for Egyptian Hieroglyphs core (1072/1072) and Ext-A Extended (3427/4000). Subsumed by eot.ttf + UniHieroglyphica. |

## Symbola

| Field | Value |
|---|---|
| **Font family** | Symbola |
| **Author** | George Douros |
| **Source** | https://github.com/zhm/symbola (mirror; original at dn-works.com/ufas — no longer publicly downloadable) |
| **License** | OFL |
| **File** | Symbola.ttf |
| **Coverage** | Supplemental Arrows-C (U+1CF00..U+1CFCF, UC17) |

## Last Resort Font HE

| Field | Value |
|---|---|
| **Font family** | Last Resort HE |
| **Author** | Unicode, Inc. |
| **Source** | https://github.com/unicode-org/last-resort-font |
| **License** | OFL |
| **File** | LastResortHE-Regular.ttf |
| **Coverage** | Fallback only — tofu-box placeholder glyphs for codepoints no other donor covered |
| **Note** | Deferred in v0.1.0: LastResortHE v17.000 uses cmap format 13; fontisan's `unicode_mappings` returns 0 entries. Re-enable after fontisan gains format 13 support. |

## Still needed (deferred to v0.2.0)

These donors are acquired but disabled in the manifest, or require
new pipeline work before they can contribute coverage:

| Donor | Status |
|---|---|
| Kelly Tolong 4 | Acquired. Disabled: keyboard-mapping font needs codepoint_remap table. |
| Noto Serif Tai Yo | Acquired. Disabled: PUA-encoded glyphs need codepoint_remap table. |
| Noto Color Emoji | Re-enabled: fontisan 0.4 added single-source CBDT/CBLC passthrough. |
| LastResort HE v17 | Deferred: fontisan returns 0 entries from cmap format 13. |
| Sidetic (U+10920..U+1093F) | No OFL donor. Cover via `ucode` code-chart extraction (proposal: `ucode/REQ-code-chart-svg-extraction.md`). |
| Egyptian Hieroglyphs Ext-B (U+16A40..U+16A8F) | Same: cover via code-chart extraction. |
| Beria Erfe tail (6 codepoints) | Same: code-chart extraction. |
| Egyptian Ext-A Extended tail (~5 codepoints) | Same: code-chart extraction. |
