require "fileutils"

module RailsWorktree
  module Commands
    # Creates a worktree under .worktrees/ from an explicit base, then provisions it.
    class Create
      def initialize(args, level: nil, seed: false, force: false, skip_seeds: nil)
        @worktree_name = args[0]
        @base_branch = args[1]
        @level = level
        @seed = seed
      end

      def run
        raise Error, "Worktree name is required: bin/worktree create NAME BASE" unless @worktree_name
        raise Error, "Base branch required: bin/worktree create #{@worktree_name} BASE (for example origin/main)." unless @base_branch

        context = Context.new
        Dir.chdir(context.root) { create }
      end

      private

      def create
        _output, error, status = Open3.capture3(Context::GIT_ENVIRONMENT, "git", "check-ref-format", "--branch", @worktree_name)
        raise Error, "Invalid worktree branch: #{error.strip}" unless status.success?
        output, error, status = Open3.capture3(Context::GIT_ENVIRONMENT, "git", "rev-parse", "--verify", "--end-of-options", "#{@base_branch}^{commit}")
        raise Error, "Invalid base #{@base_branch}: #{error.strip}" unless status.success?
        base_commit = output.strip
        worktree_dir = ".worktrees"
        worktree_path = "#{worktree_dir}/#{@worktree_name}"
        absolute_path = File.expand_path(worktree_path)

        raise Error, "Worktree name must stay inside .worktrees" unless absolute_path.start_with?(File.expand_path(worktree_dir) + File::SEPARATOR)

        Installer.ignore_worktrees(Dir.pwd)
        FileUtils.mkdir_p(worktree_dir)

        puts "Creating worktree '#{@worktree_name}' from #{@base_branch} at #{worktree_path}..."
        unless system(Context::GIT_ENVIRONMENT, "git", "worktree", "add", "-b", @worktree_name, worktree_path, base_commit)
          raise Error, "Failed to create worktree"
        end

        Dir.chdir(worktree_path) do
          Init.new([@worktree_name], level: @level, seed: @seed, base: @base_branch).run
        end

        puts ""
        puts "To switch to the new worktree:"
        puts "  cd #{absolute_path}"
      end
    end
  end
end
