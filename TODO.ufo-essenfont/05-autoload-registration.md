# 05 — Autoload registration

## Current state (already correct)

`lib/essenfont.rb` uses autoload for all top-level modules.
`lib/essenfont/otc.rb` uses autoload for Otc sub-classes.
No `require_relative` anywhere in `lib/`. ✅

## New autoloads to add

### `lib/essenfont.rb` — add Ufo namespace

```ruby
module Essenfont
  autoload :Manifest,      "essenfont/manifest"
  autoload :CpMap,         "essenfont/cp_map"
  autoload :CoverageGate,  "essenfont/coverage_gate"
  autoload :DonorLoader,   "essenfont/donor_loader"
  autoload :OutlinePolicy, "essenfont/outline_policy"
  autoload :UcodeRef,      "essenfont/ucode_ref"
  autoload :Otc,           "essenfont/otc"
  autoload :Ufo,           "essenfont/ufo"      # ← NEW
end
```

### `lib/essenfont/ufo.rb` — NEW namespace file

```ruby
module Essenfont
  module Ufo
    autoload :Normalization, "essenfont/ufo/normalization"
  end
end
```

### `lib/essenfont/otc.rb` — add MetricsPass

```ruby
module Essenfont
  module Otc
    autoload :Build,       "essenfont/otc/build"
    autoload :Errors,      "essenfont/otc/errors"
    autoload :MetricsPass, "essenfont/otc/metrics_pass"  # ← NEW
    autoload :Naming,      "essenfont/otc/naming"
    autoload :Version,     "essenfont/otc/version"
  end
end
```

## Acceptance criteria

- [ ] `bin/console` loads without errors
- [ ] `Essenfont::Ufo::Normalization` resolves via autoload
- [ ] `Essenfont::Otc::MetricsPass` resolves via autoload
- [ ] No `require_relative` in any new file
