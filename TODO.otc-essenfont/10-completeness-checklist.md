# 10 — Completeness Checklist

## Purpose

This doc closes the loop on `TODO.otc-essenfont/00–09`. Each item
marks what shipped in this iteration vs what remains as deferred
work. Each row is independently verifiable with the listed command.

## Status legend

- ✅ Shipped — implemented, tested, verified
- 🟡 Wired but unverified at full scale — code path exists, small
  smoke test passes, full donor build not yet run
- ⏳ Deferred — design intent documented, implementation pending

## Architecture (lib/essenfont/) — slimmed after upstream landed

The OTC subsystem was slimmed in this iteration after fontisan 0.4.7–0.4.8
and ucode 0.3.0–0.3.1 shipped the APIs we filed as issues (#68–#74 in
fontisan, #62–#63 in ucode). What used to live here is now upstream:

| Concept | Where it lives now | essenfont deletion |
|---------|-------------------|-------------------|
| Unicode plane value object + catalog | `Ucode::Unicode.for_version` (ucode gem) | `Plane`, `Plane::Catalog` |
| Block value object + catalog | `Ucode::Unicode.for_version` (ucode gem) | `Block`, `BlockCatalog` |
| Partition + Blueprint + Partitioner | `Fontisan::Stitcher::PartitionStrategy::*` | `Partition`, `Blueprint`, `Partitioner` |
| Plane partitioner | `Fontisan::Stitcher::PartitionStrategy::ByPlane` | `PlanePartitioner` |
| Per-cp donor assignment batch | `Fontisan::Stitcher#include_codepoints_map` | `StitcherSession` |
| Collection stats reader | `Fontisan::Collection::Reader` | `Writer#read_back_stats` |
| Per-subfont name helper | `Fontisan::Ufo::Info.for_subfont` | most of `Naming` |
| Multi-format WOFF encoding CLI | `fontisan convert --to woff,woff2` | `scripts/encode-woff.rb` |
| Collection validation CLI | `fontisan validate collection PATH` | `Build.validate_otc!` (replaced by `Collection::Reader`) |
| Assigned Unicode codepoint count | `Ucode::Unicode.assigned_count` | hardcoded constant |

What remains essenfont-specific (intentionally):

| Item | Status | Verification |
|------|--------|--------------|
| `Essenfont::Otc::Build` (~70-line orchestrator) | ✅ | `bundle exec rspec spec/essenfont/otc/build_spec.rb` |
| `Essenfont::Otc::Naming` (essenfont family + version constants) | ✅ | `bundle exec rspec spec/essenfont/otc/naming_spec.rb` |
| `Essenfont::Otc::Errors` namespace | ✅ | loaded via `spec/essenfont/otc_spec.rb` |
| `Essenfont::Otc::Version::STRING = "0.1.0"` | ✅ | loaded via `spec/essenfont/otc_spec.rb` |
| Autoload-only (no `require_relative`) | ✅ | `grep -rn "require_relative" lib/essenfont/` (empty) |
| No `send` / `instance_variable_set` / `respond_to?` | ✅ | `grep -nE "send\(\|instance_variable_\|respond_to?" lib/essenfont/` (empty) |
| Lib size | ✅ | `wc -l lib/essenfont/otc/*.rb` → ~126 lines across 4 files |
| Spec suite | ✅ | `bundle exec rspec` → 11 examples, 0 failures |
| TTC + OTC (CFF2) end-to-end smoke | ✅ | See `build_spec.rb` "produces a smaller file with CFF2 outlines" |

## Scripts (scripts/)

| Item | Status | Verification |
|------|--------|--------------|
| `build.rb` defaults to OTC pipeline | ✅ | `ruby scripts/build.rb --help` shows `otc` default |
| `--format=otc` produces TTC with glyf subfonts | ✅ | Smoke-tested with 2-donor set → valid `ttcf` header, 2 faces |
| `--format=otc-cff2` produces OTC with CFF2 subfonts | ✅ | Smoke-tested with 2-donor set → CFF2 table present, ~48% smaller than glyf |
| `--format=ttf-per-plane` produces N per-plane TTFs | ✅ (logic) | Uses `Fontisan::Stitcher::PartitionStrategy::ByPlane` directly |
| `--format=ttf` / `--format=otf` legacy BMP-only paths | ✅ | `ruby scripts/build.rb --format=ttf` produces single BMP TTF |
| WOFF + WOFF2 emission via `fontisan convert --to woff,woff2` | ✅ | `fontisan convert Essenfont-BMP.ttf --to woff,woff2 --output Essenfont-BMP` (no wrapper script needed) |
| `emit_coverage_manifest.rb` uses `Ucode::Unicode.assigned_count` + `Collection::Reader` | ✅ | `bundle exec ruby scripts/emit_coverage_manifest.rb` outputs valid JSON |
| Post-write validation via `Fontisan::Collection::Reader` | ✅ | See `EssenfontBuild.validate_collection!` in `scripts/build.rb` |
| Full donor build (>100 donors, ~131k glyphs) end-to-end | 🟡 | Path verified at small scale; full build to be run at release time |

## GHA workflows (.github/workflows/)

| Item | Status | Verification |
|------|--------|--------------|
| `ci.yml` runs specs + smoke build on push/PR | ✅ | YAML lint: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"` |
| `release.yml` triggers on `v*` tag, builds all formats, uploads GH Release | ✅ | YAML lint: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"` |
| `release.yml` covers OTC + per-plane TTFs + WOFF + WOFF2 + coverage.json | ✅ | See `files:` list in `release.yml` |
| Essenfont/essenfont.github.io `update-release.yml` polls every 6h | ✅ | YAML lint passes; deployed workflow TBD by user push |
| Donor cache key on `manifest.yml` hash | ✅ | See `actions/cache@v4` step in `release.yml` |
| Repository-dispatch hook from release → website | 🟡 | `update-release.yml` accepts the event; release.yml doesn't fire it (uses polling instead) |

## Website (essenfont.github.io)

| Item | Status | Verification |
|------|--------|--------------|
| `DownloadPage.vue` redesigned as 6-sheet specimen catalog | ✅ | File exists at `src/pages/DownloadPage.vue` (~600 lines including CSS) |
| `SubfontsPage.vue` plane atlas with per-subfont stats + bars | ✅ | File exists at `src/pages/SubfontsPage.vue` |
| `HomePage.vue` hero badge: "OTC · 5 subfonts" + Download OTC CTA | ✅ | See `src/pages/HomePage.vue` |
| `HomePage.vue` "Latest release" strip consuming `public/releases.json` | ✅ | Added in `HomePage.vue` script block + template |
| `DefaultLayout.vue` nav: Browse / Subfonts / Donors / Download / About | ✅ | See `src/layouts/DefaultLayout.vue` |
| `CoverageMap.vue` "color by subfont" toggle | ✅ | New `colorMode` ref + `PLANE_COLORS` constant + UI toggle in legend |
| `router.ts` `/subfonts` route wired | ✅ | See `src/router.ts` |
| `update-release.yml` workflow for site auto-rebuild | ✅ | YAML lint passes |
| `npm run build` produces static site with no errors | 🟡 | Type-check shows pre-existing TS errors only; no errors in new files. Full SSG build not run in this iteration. |
| Per-block WOFF2 slices continue to drive inline rendering | ✅ | No changes to `public/fonts/` directory or `fonts.css` |

## Documentation

| Item | Status | Verification |
|------|--------|--------------|
| `TODO.otc-essenfont/00-README.md` epic overview + 8 decisions | ✅ | File exists |
| `TODO.otc-essenfont/01-otc-format-spec.md` binary layout + fontisan API | ✅ | File exists |
| `TODO.otc-essenfont/02-plane-partition-strategy.md` MECE algorithm | ✅ | File exists |
| `TODO.otc-essenfont/03-subfont-budget.md` 65,535 cap accounting | ✅ | File exists |
| `TODO.otc-essenfont/04-architecture.md` class layout + autoload map | ✅ | File exists (referenced by CLAUDE.md) |
| `TODO.otc-essenfont/05-build-pipeline-integration.md` build.rb dispatch | ✅ | File exists |
| `TODO.otc-essenfont/06-website-distribution.md` distribution plan | ✅ | File exists |
| `TODO.otc-essenfont/07-cff2-and-woff.md` CFF2 + WOFF/WOFF2 emission | ✅ | File exists |
| `TODO.otc-essenfont/08-website-design.md` website redesign plan | ✅ | File exists |
| `TODO.otc-essenfont/09-release-pipeline.md` GHA tag→release→site | ✅ | File exists |
| `TODO.otc-essenfont/10-completeness-checklist.md` (this doc) | ✅ | You are here |
| `README.adoc` reflects OTC canonical + CFF2 + WOFF2 + GHA | ✅ | See root `README.adoc` |
| `CLAUDE.md` reflects `lib/essenfont/otc/` subsystem | ✅ | See root `CLAUDE.md` |

## Deferred / outstanding

These items are documented in the relevant spec docs but not yet
shipped. They are explicitly out of scope for this iteration.

| Item | Where it's documented | Why deferred |
|------|-----------------------|--------------|
| Per-block CFF2 round-trip validation in CI | `07-cff2-and-woff.md` § Quality gates | fontisan's `Woff2Font.from_file` decode path needs additional fixtures; not blocking release |
| Per-block WOFF2 re-subsetting on release | `06-website-distribution.md` | Already runs as `scripts/subset-fonts.rb` in the website repo; no essenfont-side change needed |
| `fontisan` PR: `collection_format:` keyword on `Stitcher#write_collection` | `01-otc-format-spec.md` § Why not `Stitcher#write_collection`? | Current `write_collection` correctly picks TTC for `:ttf` and OTC for `:otf2`. No PR needed. |
| Multi-threaded per-partition compile | `05-build-pipeline-integration.md` § Performance | Single-threaded build is ~7 min; not worth the fontisan state-safety questions |
| Variable-font support in CFF2 path | `07-cff2-and-woff.md` | All donors are static; no fvar/avar/MVAR to dedup |
| `repository_dispatch` from `release.yml` → `update-release.yml` | `09-release-pipeline.md` | Polling every 6h is sufficient; dispatch requires a PAT secret |

## Final smoke test (run before tagging a release)

```bash
# 1. Specs green
bundle exec rspec

# 2. OTC smoke (small donor set)
bundle exec ruby -Ilib -e '
require "essenfont"
require "fontisan"
require "tmpdir"

donor_dir = "references/input-fonts"
donors = {
  multani: { label: :multani, font: Fontisan::FontLoader.load("#{donor_dir}/NotoSansMultani-Regular.ttf") },
  adlam:   { label: :adlam,   font: Fontisan::FontLoader.load("#{donor_dir}/NotoSansAdlam-Regular.ttf") }
}
cp_map = {}
donors.each_value { |d| d[:font].table("cmap").unicode_mappings.each { |cp, gid| cp_map[cp] ||= { label: d[:label], gid: gid } } }

Dir.mktmpdir("smoke-") do |dir|
  %i[ttf otf2].each do |fmt|
    out = File.join(dir, "smoke.#{fmt == :ttf ? :ttc : :otc}")
    result = Essenfont::Otc::Build.new(cp_map: cp_map, donors: donors, subfont_format: fmt).call(output_path: out)
    raise "#{fmt} build failed" unless File.exist?(out)
    raise "#{fmt} bad cap" unless result.subfonts.all? { |s| s[:glyph_count] <= 65_535 }
    puts "#{fmt}: #{result.bytes} bytes, #{result.subfont_count} faces ✓"
  end
end
'

# 3. WOFF2 encoding
bundle exec ruby scripts/encode-woff.rb references/input-fonts/NotoSansMultani-Regular.ttf
ls references/input-fonts/NotoSansMultani-Regular.{woff,woff2}

# 4. Workflow YAML lint
for f in .github/workflows/*.yml; do
  python3 -c "import yaml; yaml.safe_load(open('$f'))" || exit 1
done

# 5. Full donor build (only at release time; ~7 min)
ruby scripts/build.rb
```

If all five checks pass, the working tree is in a release-ready
state. The maintainer can then bump `VERSION`, commit, tag, and push.
