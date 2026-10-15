require "fileutils"
require "json"
require "open3"

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
          case database_mode(%w[test])
          when :files
            prepare_schema("test", nil)
          when :variable
            write_env_file("test", test_database)
            prepare_schema("test", test_database)
          end
        end
      end

      def setup_databases
        case database_mode(%w[development test])
        when :files then setup_sqlite_databases
        when :variable then setup_named_databases
        end
      end

      # How this checkout gets its own databases: :files when config/database.yml
      # points at SQLite files inside the checkout, :variable when it reads the
      # configured variable and dotenv loads .env.*.local. Otherwise nil, and the
      # checkout keeps sharing the main databases.
      def database_mode(environments)
        unless File.executable?("bin/rails")
          puts "Warning: bin/rails not found; skipping database setup"
          return
        end

        @probe = probe_databases(environments)
        unless @probe
          puts "Warning: could not read config/database.yml (see above); skipping database setup"
          return
        end

        configs = environments.to_h { |environment| [environment, @probe[environment]] }
        return :files if configs.values.all? { |config| sqlite_in_checkout?(config) }

        environment, config = configs.find { |name, config| config.nil? || config["override"] != database_for(name) }
        if environment
          puts "Warning: config/database.yml does not read #{variable_for(environment)} for the #{environment} database, " \
            "so this checkout would use #{config ? config["database"] : "no database"} like the main checkout. " \
            "Skipping database setup; see Databases in the rails-worktree README."
        elsif !@probe["dotenv"]
          puts "Warning: dotenv is not loaded, so Rails would ignore .env.development.local and .env.test.local " \
            "and use the main databases. Add gem \"dotenv-rails\" to the Gemfile. Skipping database setup."
        else
          :variable
        end
      end

      def probe_databases(environments)
        script = File.expand_path("../database_probe.rb", __dir__)
        arguments = environments.map { |environment| "#{environment}:#{variable_for(environment)}=#{database_for(environment)}" }
        env = @context.environment.merge("RAILS_ENV" => "development")
        output, status = Open3.capture2(env, *@context.command(["bin/rails", "runner", script, *arguments]), unsetenv_others: true)
        line = output.lines.grep(/\ARAILS_WORKTREE_PROBE /).last
        JSON.parse(line.delete_prefix("RAILS_WORKTREE_PROBE ")) if status.success? && line
      end

      def sqlite_in_checkout?(config)
        return false unless config && config["adapter"].include?("sqlite")
        return false if config["database"].empty? || config["database"].start_with?(":memory:", "file:")

        File.expand_path(config["database"], @root).start_with?(@root + File::SEPARATOR)
      end

      # SQLite files resolve inside each checkout, so the databases are separate
      # already. The development database starts as a copy of the main checkout's.
      def setup_sqlite_databases
        if @config.template? && copy_sqlite_database(@probe.dig("development", "database"))
          rails("development", nil, "db:migrate") || puts("Warning: migrations failed")
        else
          prepare_schema("development", nil)
        end
        prepare_schema("test", nil)
        seed(nil)
      end

      # Returns true when the checkout has its development database, copied now or before.
      def copy_sqlite_database(database)
        source = File.join(@main_worktree, database)
        target = File.expand_path(database, @root)
        return true if File.exist?(target)
        return false unless File.file?(source)
        if File.size(source) > @config.template_max_bytes
          puts "Warning: #{database} in the main checkout is above database.template_max_gb; loading the schema instead"
          return false
        end

        puts "Copying the development database #{database} from the main checkout..."
        FileUtils.mkdir_p(File.dirname(target))
        script = File.expand_path("../copy_sqlite.rb", __dir__)
        return true if run_command(@context.environment, "bundle", "exec", "ruby", script, source, target)

        puts "Warning: could not copy #{database} (see above); loading the schema instead"
        false
      end

      def setup_named_databases
        cloned = @config.template? && clone_development_database
        write_env_file("development", development_database)
        write_env_file("test", test_database)
        if cloned
          rails("development", development_database, "db:migrate") || puts("Warning: migrations failed")
        else
          prepare_schema("development", development_database)
        end
        prepare_schema("test", test_database)
        seed(development_database)
      end

      def seed(database)
        return unless @seed

        puts "Seeding #{database || "the development database"}..."
        rails("development", database, "db:seed") || puts("Warning: seeding failed")
      end

      # Runs without the worktree database override so the configured development
      # database is the main checkout's, then clones it. Returns false on failure.
      def clone_development_database
        return false if File.exist?(ENV_FILES["development"]) && !@force

        puts "Cloning the development database into #{development_database}..."
        script = File.expand_path("../clone_database.rb", __dir__)
        env = @context.environment.merge("RAILS_ENV" => "development", "RAILS_WORKTREE_TEMPLATE_MAX_BYTES" => @config.template_max_bytes.to_s)
        return true if run_command(env, "bin/rails", "runner", script, development_database)

        puts "Warning: the template clone did not run (see above; a database in use or above template_max_gb); loading the schema instead"
        false
      end

      # Creates the database and loads the schema, or runs the migrations in an
      # application without a schema file yet. A nil database uses database.yml as is.
      def prepare_schema(environment, database)
        label = database || "the #{environment} database"
        puts "Preparing #{label}..."
        rails(environment, database, "db:create") || puts("Warning: could not create #{label}")
        if %w[db/schema.rb db/structure.sql].any? { |file| File.file?(file) }
          rails(environment, database, "db:schema:load") || puts("Warning: could not load the schema into #{label}")
        else
          rails(environment, database, "db:migrate") || puts("Warning: could not migrate #{label}")
        end
      end

      def write_env_file(environment, database)
        variable = variable_for(environment)
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
        env = @context.environment.merge("RAILS_ENV" => environment, "DISABLE_DATABASE_ENVIRONMENT_CHECK" => "1")
        env[variable_for(environment)] = database if database
        run_command(env, "bin/rails", *arguments)
      end

      def variable_for(environment) = environment == "test" ? @config.test_variable : @config.development_variable
      def database_for(environment) = environment == "test" ? test_database : development_database

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
