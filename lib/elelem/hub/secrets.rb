# frozen_string_literal: true

module Elelem
  module Hub
    class Secrets
      def self.path
        File.join(ENV.fetch("XDG_CONFIG_HOME") { File.expand_path("~/.config") }, "elelem", "hub.json")
      end

      def initialize(path = Secrets.path)
        @path = path
      end

      def fetch(name) = all[name]

      def update(name)
        locked do
          before = all
          yield(before[name]).tap { |value| save(before.merge(name => value).compact) unless value == before[name] }
        end
      end

      private

      def all
        Hash(JSON.parse(File.read(@path)))
      rescue Errno::ENOENT
        {}
      rescue JSON::ParserError, TypeError
        raise IOError, "#{@path} is not a JSON object: fix it or remove it"
      end

      def locked
        own(File.dirname(@path))
        File.open("#{@path}.lock", File::CREAT | File::RDWR, 0o600) do |lock|
          lock.flock(File::LOCK_EX)
          yield
        end
      end

      def own(dir)
        FileUtils.mkdir_p(dir, mode: 0o700)
        File.chmod(0o700, dir)
      end

      def save(all)
        File.open("#{@path}.tmp", File::CREAT | File::TRUNC | File::WRONLY, 0o600) do |file|
          file.write(JSON.pretty_generate(all), "\n")
          file.fsync
        end
        File.rename("#{@path}.tmp", @path)
      end
    end
  end
end
