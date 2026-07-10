# frozen_string_literal: true

module Essenfont
  # BuildCache: file-based cache for expensive pipeline stages.
  #
  # Each cache entry is identified by a cache key (derived from inputs)
  # and an artifact name (filename in the cache directory). When the key
  # matches a stored key, the cached artifact is used directly — skipping
  # the expensive rebuild.
  #
  # Two usage patterns:
  #
  #   1. In-memory objects (UFOs, coverage data):
  #      ufo = cache.fetch_or_build(key, "fsung-m.marshal") do
  #        convert_and_normalize(donor_font)   # only runs on cache miss
  #      end
  #
  #   2. File/directory artifacts (SVG exports, coverage.json):
  #      cache.fetch_or_build_file(key, "coverage.json", output_path) do
  #        emit_coverage_from_otc(otc_path)    # only runs on cache miss
  #      end
  #
  # CI integration: GitHub Actions caches the cache_dir across runs.
  # On cache hit, the entire build skips donor conversion, WOFF2 encoding,
  # and SVG export — cutting build time from ~90 min to ~30-40 min.
  class BuildCache
    DEFAULT_DIR = File.expand_path("../../references/build-cache", __dir__)

    attr_reader :cache_dir

    def initialize(cache_dir: DEFAULT_DIR)
      @cache_dir = cache_dir.to_s
      FileUtils.mkdir_p(@cache_dir)
    end

    # Fetch an in-memory object from cache, or build it fresh.
    # Uses Marshal for serialization (fast, Ruby-native).
    #
    # @param key [String] cache key (uniquely identifies the inputs)
    # @param artifact [String] artifact name (filename in cache_dir)
    # @yield block that builds the object on cache miss
    # @return [Object] the cached or freshly-built object
    def fetch_or_build(key, artifact)
      key_path = key_file(artifact)
      art_path = artifact_path(artifact)

      if hit?(key, key_path) && File.exist?(art_path)
        Marshal.load(File.binread(art_path))
      else
        result = yield
        begin
          File.binwrite(art_path, Marshal.dump(result))
          File.write(key_path, key)
        rescue TypeError, RuntimeError => e
          # Object graph contains non-Marshal-able state (procs, Nokogiri
          # docs, circular refs). Skip caching — the build still works,
          # just without the cache benefit for this artifact.
          warn "  build-cache: skip #{artifact} (not serializable: #{e.message})"
        end
        result
      end
    end

    # Fetch a file/directory artifact from cache, or build it fresh.
    # On cache hit, copies the cached file to output_path.
    # On cache miss, yields, then copies output_path to cache.
    #
    # @param key [String] cache key
    # @param artifact [String] artifact name
    # @param output_path [String] where the artifact should live in the build output
    # @yield block that builds the artifact at output_path
    # @return [Boolean] true if cache hit, false if rebuilt
    def fetch_or_build_file(key, artifact, output_path)
      key_path = key_file(artifact)
      cached_path = artifact_path(artifact)

      if hit?(key, key_path) && File.exist?(cached_path)
        if File.directory?(cached_path)
          FileUtils.cp_r(cached_path, output_path)
        else
          FileUtils.cp(cached_path, output_path)
        end
        true
      else
        yield
        if File.exist?(output_path)
          if File.directory?(output_path)
            FileUtils.cp_r(output_path, cached_path)
          else
            FileUtils.cp(output_path, cached_path)
          end
        end
        File.write(key_path, key)
        false
      end
    end

    # Check if a cache entry exists without loading it.
    def cached?(key, artifact)
      hit?(key, key_file(artifact)) && File.exist?(artifact_path(artifact))
    end

    private

    def key_file(artifact)
      File.join(cache_dir, "#{artifact}.key")
    end

    def artifact_path(artifact)
      File.join(cache_dir, artifact)
    end

    def hit?(key, key_path)
      return false unless File.exist?(key_path)

      File.read(key_path).strip == key
    end
  end
end
