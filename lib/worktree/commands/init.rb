require "fileutils"

module RailsWorktree
  module Commands
    # Provisions the current checkout at a level: minimal (configuration files),
    # test (minimal plus an isolated test setup) or full (minimal plus own
    # development and test databases). Safe to repeat.
    class Init
      ENV_FILES = {"development" => ".env.development.local", "test" => ".env.test.local"}.freeze

      attr_reader :root, :main_worktree, :name, :level

      def initialize(args, level: nil, seed: false, base: nil, force: false, skip_seeds: nil)
        @requested_name = args[0]
        @requested_level = level
        @seed = seed
        @base = base
        @force = force
      end

      def run
        @context = Context.new
        @root = @context.root
        @main_worktree = main_worktree_path
        raise Error, "Run init inside a linked worktree, not the main checkout #{@main_worktree}." if @root == @main_worktree

        @config = Config.load(File.exist?(File.join(@root, Config::FILE)) ? @root : @main_worktree)
        @name = @requested_name || File.basename(@root)
        @level = @requested_level || @config.level
        raise Error, "Unknown level #{@level}; use #{Config::LEVELS.join(", ")}." unless Config::LEVELS.include?(@level)

        puts "Provisioning #{@root} (#{@level}) from #{@main_worktree}"
        Dir.chdir(@root) do
          record_base if @base
          copy_files
          create_directories
          touch_files
          link_node_modules
          case @level
          when "test" then setup_test
          when "full" then setup_databases
          end
        end
        puts "✓ Worktree #{@name} provisioned (#{@level})"
      end

      def development_database = "#{database_prefix}_#{database_slug}_development"
      def test_database = "#{database_prefix}_#{database_slug}_test"

      private

      def main_worktree_path
        output = @context.git(@root, "worktree", "list", "--porcelain")
        File.realpath(output.lines.grep(/^worktree /).first.delete_prefix("worktree ").strip)
      end

      def record_base
        output, error, status = Open3.capture3(Context::GIT_ENVIRONMENT, "git", "-C", @root, "rev-parse", "--verify", "--end-of-options", "#{@base}^{commit}")
        raise Error, "Invalid base #{@base}: #{error.strip}" unless status.success?
        branch = @context.git(@root, "branch", "--show-current").strip
        raise Error, "Cannot record a base on a detached HEAD." if branch.empty?
        @context.record(@base, output.strip, branch)
        @context.verify
        Launcher.install(@root, replace: true)
        PushHook.install(@root)
        puts "Recorded base #{@base} for branch #{branch}"
      end

      def copy_files
        @config.copy_patterns.each do |pattern|
          Dir.glob(pattern, base: @main_worktree).sort.each do |relative|
            source = File.join(@main_worktree, relative)
            next unless File.file?(source)
            next if File.exist?(relative) && !@force

            FileUtils.mkdir_p(File.dirname(relative))
            FileUtils.cp(source, relative)
            puts "  copied #{relative}"
          end
        end
      end

      def create_directories
        @config.directories.each { |directory| FileUtils.mkdir_p(directory) }
      end

      def touch_files
        @config.touch.each do |file|
          FileUtils.mkdir_p(File.dirname(file))
          FileUtils.touch(file)
        end
      end

      def link_node_modules
        source = File.join(@main_worktree, "node_modules")
        return if @config.node_modules == "skip" || !Dir.exist?(source) || File.exist?("node_modules") || File.symlink?("node_modules")

        if @config.node_modules == "link"
          File.symlink(source, "node_modules")
          puts "  linked node_modules to the main checkout"
        else
          FileUtils.cp_r(source, "node_modules")
          puts "  copied node_modules"
        end
      end

      def setup_test
        if @config.test_command
          puts "Running #{@config.test_command}..."
          run_command(@context.environment, *@config.test_command.split(" ")) || raise(Error, "#{@config.test_command} failed")
        else
          write_env_file("test", test_database)
          prepare_schema("test", test_database)
        end
      end

      def setup_databases
        unless File.executable?("bin/rails")
          puts "Warning: bin/rails not found; skipping database setup"
          return
        end

        cloned = @config.template? && clone_development_database
        write_env_file("development", development_database)
        write_env_file("test", test_database)
        if cloned
          rails("development", development_database, "db:migrate") || puts("Warning: migrations failed")
        else
          prepare_schema("development", development_database)
        end
        prepare_schema("test", test_database)
        return unless @seed

        puts "Seeding #{development_database}..."
        rails("development", development_database, "db:seed") || puts("Warning: seeding failed")
      end

      # Runs without the worktree database override so the configured development
      # database is the main checkout's, then clones it. Returns false on failure.
      def clone_development_database
        return false if File.exist?(ENV_FILES["development"]) && !@force

        puts "Cloning the development database into #{development_database}..."
        script = File.expand_path("../clone_database.rb", __dir__)
        return true if run_command(@context.environment.merge("RAILS_ENV" => "development"), "bin/rails", "runner", script, development_database)

        puts "Warning: template clone failed (is the main development database in use?); loading the schema instead"
        false
      end

      def prepare_schema(environment, database)
        return unless File.executable?("bin/rails")

        puts "Preparing #{database}..."
        rails(environment, database, "db:create") || puts("Warning: could not create #{database}")
        rails(environment, database, "db:schema:load") || puts("Warning: could not load the schema into #{database}")
      end

      def write_env_file(environment, database)
        variable = environment == "test" ? @config.test_variable : @config.development_variable
        path = ENV_FILES.fetch(environment)
        content = File.exist?(path) ? File.read(path) : "# Written by bin/worktree init; dotenv loads it in the #{environment} environment only.\n"
        line = "#{variable}=#{database}"
        if content.match?(/^#{Regexp.escape(variable)}=/)
          content = content.gsub(/^#{Regexp.escape(variable)}=.*$/, line)
        else
          content += "\n" unless content.end_with?("\n")
          content += "#{line}\n"
        end
        File.write(path, content)
      end

      def rails(environment, database, *arguments)
        variable = environment == "test" ? @config.test_variable : @config.development_variable
        env = @context.environment.merge("RAILS_ENV" => environment, variable => database, "DISABLE_DATABASE_ENVIRONMENT_CHECK" => "1")
        run_command(env, "bin/rails", *arguments)
      end

      def run_command(environment, *arguments)
        command = @context.command(arguments)
        system(environment, *command, unsetenv_others: true)
      end

      def database_prefix
        @database_prefix ||= begin
          database_yml = File.join(@main_worktree, "config/database.yml")
          match = File.exist?(database_yml) && File.read(database_yml).match(/(\w+)_development\b/)
          match ? match[1] : File.basename(@main_worktree).gsub(/[^A-Za-z0-9_]/, "_")
        end
      end

      def database_slug
        @name.gsub(/[^A-Za-z0-9_]/, "_")
      end
    end
  end
end
