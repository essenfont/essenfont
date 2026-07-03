# 09 — Release Pipeline (GHA)

## Architecture

Two repos, two workflows, one trigger (`v*` tag in essenfont/essenfont).

```
┌─────────────────────────────────────────────┐
│ essenfont/essenfont                          │
│                                              │
│  dev pushes commit → main                    │
│  maintainer pushes tag v0.2.0                │
│                  │                           │
│                  ▼                           │
│  release.yml (tag trigger)                   │
│    • set up Ruby 3.2                         │
│    • fetch donors via ucode                  │
│    • build OTC + per-plane TTFs + WOFF2      │
│    • upload GH Release assets                │
│    • send repository_dispatch to website repo│
│                  │                           │
└──────────────────┼──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│ essenfont/essenfont.github.io                │
│                                              │
│  site.yml (repository_dispatch + schedule)   │
│    • download latest release assets          │
│    • fetch releases.json (GH API)            │
│    • npm ci                                  │
│    • npm run build (ViteSSG)                 │
│    • deploy to GitHub Pages                  │
│                                              │
└─────────────────────────────────────────────┘
```

## essenfont/essenfont — `.github/workflows/release.yml`

Triggers:
- `push: tags: ['v*']`
- `workflow_dispatch` (manual from a branch)

Steps:
1. Checkout
2. Set up Ruby 3.2 with `bundler-cache`
3. Acquire donor fonts:
   - Run `bundle exec ucode fetch fonts` (most Noto donors)
   - Download FSung files from a known Google Drive mirror (or skip
     if unavailable — Essenfont will build with reduced CJK coverage)
4. Build:
   - `bundle exec ruby scripts/build.rb --format=otc`
   - `bundle exec ruby scripts/build.rb --format=ttf-per-plane`
   - `bundle exec ruby scripts/encode-woff.rb` (per-plane WOFF2)
5. Emit coverage manifest:
   - `bundle exec ruby scripts/emit_coverage_manifest.rb > coverage.json`
6. Create GH Release with assets:
   - `Essenfont-Regular.otc`
   - `Essenfont-BMP.ttf`, `Essenfont-SMP.ttf`, `Essenfont-SIP.ttf`,
     `Essenfont-TIP.ttf`, `Essenfont-SSP.ttf`
   - `Essenfont-BMP.woff2`, ..., `Essenfont-SSP.woff2`
   - `Essenfont-BMP.woff`, ..., `Essenfont-SSP.woff`
   - `coverage.json`
7. Fire `repository_dispatch` event to `essenfont/essenfont.github.io`
   with payload `{ "tag": "v0.2.0", "release_url": "..." }`.

The workflow uses `softprops/action-gh-release@v2` (same as metfont).

## essenfont/essenfont — `.github/workflows/ci.yml`

Triggers:
- `push: branches: [main]`
- `pull_request`

Steps:
1. Checkout
2. Set up Ruby 3.2
3. `bundle install`
4. `bundle exec rspec` — run the spec suite
5. `bundle exec rubocop` — lint
6. Smoke-build a small donor subset (multani + adlam) to verify the
   OTC pipeline produces a valid `ttcf`-tagged file.

CI runs in ~2 min. Release builds in ~15 min.

## essenfont/essenfont.github.io — `.github/workflows/site.yml`

Triggers:
- `repository_dispatch` (event_type: `essenfont-release`)
- `push: branches: [main]` (on site-source changes)
- `schedule: cron "0 */6 * * *"` (catch up if dispatch missed)
- `workflow_dispatch`

Steps:
1. Checkout
2. Download latest release manifest:
   - `curl -sL https://api.github.com/repos/essenfont/essenfont/releases/latest`
3. For each asset in the release:
   - Download to `public/releases/v0.2.0/`
4. Build `public/coverage.json` symlink → `public/releases/v0.2.0/coverage.json`
5. Build `public/releases.json` (list of all releases for version history)
6. `npm ci`
7. `npm run build` (ViteSSG generates static site)
8. Upload Pages artifact
9. Deploy to GitHub Pages

## Secrets

The site workflow needs a `REPO_ACCESS_TOKEN` secret (PAT with `repo`
scope on essenfont/essenfont) to trigger `repository_dispatch` from
the build repo. Or, simpler: the site workflow polls the GH API on
schedule (every 6h) and rebuilds when `latest.tag_name` changes.

We pick the polling approach for simplicity. The 6-hour max staleness
is fine for a release flow that runs ~once a month.

## Version bump flow

Maintainer runs:

```bash
# Update VERSION file
echo "0.2.0" > VERSION

# Commit + tag + push
git add VERSION
git commit -m "chore: bump version to 0.2.0"
git tag v0.2.0
git push origin main v0.2.0
```

The `v0.2.0` tag push triggers `release.yml`. The site rebuilds on
the next schedule tick (or immediately if `workflow_dispatch` is used).

## Release notes generation

`release.yml` generates a Markdown body from:
- Git log since last tag (`git log --pretty=format:'- %s' v0.1.0..v0.2.0`)
- Coverage delta from previous release
- Donor changes (diff `sources/manifest.yml`)

The release body is uploaded as `release-notes.md` and used as the GH
Release description.

## Caching

- **Bundler cache** — keyed on `Gemfile.lock`
- **ucode cache** — `~/.cache/ucode` cached across runs; saves ~2 min
  of donor fetch
- **Donor font cache** — `references/input-fonts/` cached; restored
  from previous run if `manifest.yml` hash unchanged

## Failure modes

| Symptom                          | Recovery                                  |
|----------------------------------|-------------------------------------------|
| Donor fetch fails                | Retry once; abort release if still fails  |
| Build exceeds 65,535 cap         | Bug in partitioner; abort + notify        |
| CFF2 charstring compilation fails| Skip CFF2 variant; release glyf only      |
| Site deploy fails                | Retry via `workflow_dispatch`             |
| Wrong tag pushed                 | Delete tag + release; rebuild with correct tag |

## What we do NOT automate

- **Version bump commits.** Maintainer runs the bump locally; CI only
  reacts to tag pushes. (metfont has `bump-version.yml` for this;
  we skip — too easy to misuse.)
- **Pre-releases / canary builds.** Tags are stable releases. Beta
  artifacts are built locally.
- **Cross-posting to npm / PyPI / etc.** Essenfont is a font, not a
  package. No package registry.
- **Discord / Twitter announcements.** Manual; the release URL is
  enough to share.

## Audit trail

Every release tag has:
- The `release.yml` workflow run (15-min log)
- The GH Release with all binary assets
- The site rebuild workflow run (2-min log)
- A `releases.json` entry on the website (permanent link)

This makes regressions traceable: a user reporting "v0.2 broke Tangut"
links to the v0.2 release, the build log shows donor versions, and
the diff vs v0.1 is in the release notes.
