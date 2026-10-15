require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "rails-worktree"

module RepositoryFixture
  # A main checkout with a linked worktree, both committed, under a temporary directory.
  def build_repository(worktree: "feature-x")
    @directory = Dir.mktmpdir("rails-worktree")
    @main = File.join(@directory, "myapp")
    @worktree = File.join(@main, ".worktrees", worktree)
    FileUtils.mkdir_p(@main)
    git(@main, "init", "--quiet", "--initial-branch=main")
    git(@main, "config", "user.name", "Test")
    git(@main, "config", "user.email", "test@example.test")
    File.write(File.join(@main, ".gitignore"), "/.worktrees/\n/.env*\n/config/database.yml\n/node_modules/\n")
    File.write(File.join(@main, "README.md"), "app\n")
    git(@main, "add", ".")
    git(@main, "commit", "--quiet", "-m", "base")
    git(@main, "worktree", "add", "--quiet", "-b", worktree, @worktree, "main")
  end

  def write_main(relative, content = "")
    path = File.join(@main, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def git(directory, *arguments)
    output, error, status = Open3.capture3("git", "-C", directory, *arguments)
    raise error unless status.success?
    output
  end
end
