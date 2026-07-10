#!/usr/bin/env ruby
# frozen_string_literal: true

# Build the essenfont npm package: stages per-plane WOFF2s into npm/
# and emits ready-to-import CSS files.
#
# Standalone entry point — delegates to Essenfont::Release::NpmPackage.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "essenfont"

ROOT = File.expand_path("..", __dir__)
publish = ARGV.delete("--publish")

Essenfont::Release::NpmPackage.build(out_dir: ROOT, publish: publish)
puts "npm package staged in npm/ (run `cd npm && npm publish` to publish)" unless publish
