# frozen_string_literal: true

require "digest"
require "fontisan"

module Essenfont
  module Release
    # WoffEncoder: encodes per-plane WOFF + WOFF2 from per-plane TTFs.
    #
    # Uses fontisan's Ruby API (WoffWriter + Woff2Encoder). Cache-aware —
    # skips re-encoding when the source TTF's sha256 hasn't changed.
    module WoffEncoder
      module_function

      # @param out_dir [String] directory containing per-plane TTFs
      # @param cache [Essenfont::BuildCache, nil] optional file cache
      def encode(out_dir:, cache: Essenfont::BuildCache.new)
        Release::PLANES.each do |plane|
          ttf = File.join(out_dir, "Essenfont-#{plane}.ttf")
          next unless File.exist?(ttf)

          ttf_sha = Digest::SHA256.file(ttf).hexdigest[0, 16]
          woff_path = File.join(out_dir, "Essenfont-#{plane}.woff")
          woff2_path = File.join(out_dir, "Essenfont-#{plane}.woff2")

          woff_cached = encode_one(cache, "ttf-#{ttf_sha}", "Essenfont-#{plane}.woff",
                                   woff_path, ttf, :woff)
          woff2_cached = encode_one(cache, "ttf-#{ttf_sha}", "Essenfont-#{plane}.woff2",
                                    woff2_path, ttf, :woff2)

          puts "  #{plane}: #{woff_cached || woff2_cached ? 'cache' : 'encoded'}"
        end
      end

      def encode_one(cache, key, artifact, output_path, ttf_path, format)
        cache.fetch_or_build_file(key, artifact, output_path) do
          font = Fontisan::FontLoader.load(ttf_path)
          case format
          when :woff
            File.binwrite(output_path, Fontisan::Converters::WoffWriter.new.convert(font))
          when :woff2
            File.binwrite(output_path, Fontisan::Converters::Woff2Encoder.new.convert(font)[:woff2_binary])
          end
        end
      end
    end
  end
end
