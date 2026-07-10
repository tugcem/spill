require "fileutils"
require "open3"

module Spill
  # Contract with narrator.swift: stdin carries one fact block per repo,
  # joined by ASCII Record Separator (RS, \x1E); stdout returns one summary
  # per block — same order, same count, same separator (a refused or failed
  # block comes back empty). Any nonzero exit (model unavailable, crash)
  # means "no summary" — the caller stays silent.
  module Narrator
    COMPILE_TIMEOUT_SECONDS = 120
    RECORD_SEPARATOR = "\u001E".freeze

    module_function

    def available?
      RUBY_PLATFORM.include?("darwin")
    end

    # Takes the per-repo fact blocks and returns a parallel array of
    # summaries (nil in a slot whose block failed), or nil if narration is
    # unavailable or the helper's reply doesn't line up block-for-block.
    def narrate(briefs, timeout: nil, binary: nil)
      return nil if briefs.nil? || briefs.empty?

      bin = binary || compiled_binary
      return nil if bin.nil?

      timeout ||= [ 30 + (10 * briefs.size), 120 ].min
      # Fact text must not be able to forge block boundaries: a stray RS or
      # invalid UTF-8 in a commit title would shift the count and silently
      # kill every repo's summary, not just its own.
      payload = briefs.map { |brief| brief.to_s.scrub(" ").tr(RECORD_SEPARATOR, " ") }
      output = run(bin, payload.join(RECORD_SEPARATOR), timeout)
      return nil if output.nil?

      summaries = output.split(RECORD_SEPARATOR, -1).map { |part| flatten(clean(part)) }
      return nil unless summaries.size == briefs.size

      summaries.any? ? summaries : nil
    rescue SystemCallError
      # A corrupt cached binary (disk trouble, truncated Mach-O) can fail at
      # exec and would otherwise fail every run. Drop it — and any stale
      # failure marker that would block the recompile — so the next run
      # starts fresh.
      if bin == cache_path
        FileUtils.rm_f(cache_path)
        FileUtils.rm_f(failure_marker(cache_path))
      end
      nil
    rescue StandardError
      nil
    end

    def compiled_binary
      path = cache_path
      return path if File.exist?(path)
      return nil if File.exist?(failure_marker(path))

      compile(path) ? path : nil
    end

    def cache_path
      cache_home = ENV["XDG_CACHE_HOME"] || File.expand_path("~/.cache")
      File.join(cache_home, "spill", "narrator-#{Spill::VERSION}")
    end

    def failure_marker(path)
      "#{path}.failed"
    end

    def swift_source
      File.join(__dir__, "narrator.swift")
    end

    # Compiles to a temp path and renames into place, so a concurrent or
    # interrupted run can never leave a half-written binary at the cache
    # path. A failed compile leaves a marker so we don't pay for swiftc on
    # every run; the marker is version-stamped along with the binary, so a
    # new spill version retries.
    def compile(path)
      FileUtils.mkdir_p(File.dirname(path))
      tmp = "#{path}.tmp#{Process.pid}"
      compiled = begin
        swiftc(tmp)
      rescue StandardError
        false
      end
      if compiled
        File.rename(tmp, path)
        # A marker from a concurrent failed compile must not outlive a
        # working binary — it would block recompiles after a self-heal.
        FileUtils.rm_f(failure_marker(path))
        true
      else
        FileUtils.rm_f(tmp)
        FileUtils.touch(failure_marker(path))
        false
      end
    rescue StandardError
      false
    end

    def swiftc(tmp, timeout: COMPILE_TIMEOUT_SECONDS)
      pid = Process.spawn(*compile_command(tmp), in: File::NULL, out: File::NULL, err: File::NULL)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      until Process.waitpid(pid, Process::WNOHANG)
        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          # KILL, not TERM: the compiler holds no state worth a graceful
          # shutdown, and a hung swiftc must not hang spill.
          begin
            Process.kill("KILL", pid)
          rescue Errno::ESRCH
            nil
          end
          Process.waitpid(pid)
          return false
        end
        sleep 0.05
      end
      Process.last_status.success?
    end

    def compile_command(tmp)
      [ "swiftc", swift_source, "-o", tmp ]
    end

    def run(bin, text, timeout)
      stdin, stdout, stderr, wait_thr = Open3.popen3(bin)
      write_input(stdin, text)
      if wait_thr.join(timeout)
        wait_thr.value.success? ? stdout.read : nil
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

    # Bare KILL on purpose: the helper is a one-shot stdin→stdout filter
    # with nothing to clean up, and a wedged model process must not stall
    # the report.
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

    # Each key point renders on one bullet line — a model reply that sneaks
    # in newlines or control characters must not be able to break or
    # overwrite the report layout.
    def flatten(str)
      str&.gsub(/[[:space:][:cntrl:]]+/, " ")&.strip
    end
  end
end
