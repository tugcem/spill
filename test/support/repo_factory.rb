require "open3"

module RepoFactory
  module_function

  def init_repo(dir, email: "dev@example.com")
    FileUtils.mkdir_p(dir)
    run("git", "init", "-q", "-b", "main", dir)
    git(dir, "config", "user.email", email)
    git(dir, "config", "user.name", "Dev")
    dir
  end

  def commit(repo, subject, time: Time.now, email: nil)
    File.write(File.join(repo, "f-#{Time.now.to_f}-#{rand(10_000)}.txt"), subject)
    git(repo, "add", ".")
    stamp = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    env = { "GIT_AUTHOR_DATE" => stamp, "GIT_COMMITTER_DATE" => stamp }
    config = email ? [ "-c", "user.email=#{email}" ] : []
    run(env, "git", "-C", repo, *config, "commit", "-q", "-m", subject)
  end

  def add_bare_remote(repo, remotes_dir)
    bare = File.join(remotes_dir, "#{File.basename(repo)}.git")
    run("git", "init", "-q", "--bare", bare)
    git(repo, "remote", "add", "origin", bare)
    git(repo, "push", "-q", "-u", "origin", "main")
  end

  def git(repo, *args)
    run("git", "-C", repo, *args)
  end

  def run(*cmd)
    out, err, status = Open3.capture3(*cmd)
    raise "command failed: #{cmd.inspect}\n#{err}" unless status.success?
    out
  end
end
