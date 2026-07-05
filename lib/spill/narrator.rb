require "fileutils"
require "open3"

module Spill
  module Narrator
    module_function

    def available?
      RUBY_PLATFORM.include?("darwin")
    end

    def narrate(text, timeout: 30, binary: nil)
      bin = binary || compiled_binary
      return nil if bin.nil?

      run(bin, text, timeout)
    rescue StandardError
      nil
    end

    def compiled_binary
      path = cache_path
      return path if File.exist?(path)

      compile(path) ? path : nil
    end

    def cache_path
      cache_home = ENV["XDG_CACHE_HOME"] || File.expand_path("~/.cache")
      File.join(cache_home, "spill", "narrator-#{Spill::VERSION}")
    end

    def swift_source
      File.join(__dir__, "narrator.swift")
    end

    def compile(path)
      FileUtils.mkdir_p(File.dirname(path))
      _out, _err, status = Open3.capture3("swiftc", swift_source, "-o", path)
      status.success?
    rescue StandardError
      false
    end

    def run(bin, text, timeout)
      stdin, stdout, stderr, wait_thr = Open3.popen3(bin)
      write_input(stdin, text)
      if wait_thr.join(timeout)
        wait_thr.value.success? ? clean(stdout.read) : nil
      else
        kill(wait_thr)
        nil
      end
    ensure
      [ stdin, stdout, stderr ].each { |io| io&.close unless io&.closed? }
    end

    def write_input(stdin, text)
      stdin.write(text)
      stdin.close
    rescue IOError, Errno::EPIPE
      nil
    end

    def kill(wait_thr)
      Process.kill("KILL", wait_thr.pid)
    rescue Errno::ESRCH
      nil
    ensure
      wait_thr.join
    end

    def clean(str)
      return nil if str.nil?

      stripped = str.strip
      stripped.empty? ? nil : stripped
    end
  end
end
