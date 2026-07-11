# frozen_string_literal: true

require "digest"

module Essenfont
  module Release
    # SriHashes: SRI (Subresource Integrity) hashes for WOFF/WOFF2 files.
    #
    # Emits sri.txt with base64-encoded SHA-384 hashes for each per-plane
    # WOFF and WOFF2 file. Used by CDNs and <link integrity> consumers.
    module SriHashes
      module_function

      # @param out_dir [String] directory containing per-plane WOFF/WOFF2 files
      def emit(out_dir:)
        File.open(File.join(out_dir, "sri.txt"), "w") do |f|
          Release::PLANES.each do |plane|
            %w[woff woff2].each do |ext|
              file = File.join(out_dir, "Essenfont-#{plane}.#{ext}")
              next unless File.exist?(file)

              b64 = [Digest::SHA384.file(file).digest].pack("m0")
              f.puts "Essenfont-#{plane}.#{ext}=sha384-#{b64}"
            end
          end
        end
      end
    end
  end
end
