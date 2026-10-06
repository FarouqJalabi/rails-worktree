module RailsWorktree
  class CLI
    USAGE = <<~USAGE.freeze
      Usage: worktree create <name> <base> [--level LEVEL] [--seed]
             worktree <name> <base> [--level LEVEL] [--seed]
             worktree init [name] [--level LEVEL] [--seed] [--base REF] [--force]
             worktree close [name]
             worktree exec -- <command> [arguments]
             worktree verify [--push]
             worktree install [--force]

      Commands:
        create NAME BASE    Create .worktrees/NAME from BASE and provision it
        init [NAME]         Provision the current checkout, whoever created it (safe to repeat)
        close [NAME]        Drop the worktree-local databases, remove the checkout and its branch
        exec -- COMMAND     Run a command with verified worktree context
        verify              Check the recorded base and bundle root
        install             Write bin/worktree, .worktree.yml, .worktreeinclude, the AGENTS.md block
                            and the herdr plugin into this repository

      Options:
        --level LEVEL       minimal (config files), test (plus test setup) or full (plus own databases).
                            Default: the level in .worktree.yml, or full
        --seed              Seed the development database (full level)
        --base REF          Record REF as the base and install the push guard (init)
        --force             Overwrite copied files (init) or the launcher and plugin files (install)

      Examples:
        worktree create feature origin/main
        worktree create spike origin/main --level minimal
        worktree init --level minimal          # inside a herdr, Claude Code or Codex checkout
        worktree close feature
    USAGE

    def self.run(args)
      new(args).run
    end

    def initialize(args)
      @args = args.dup
    end

    def run
      command = @args.shift
      case command
      when nil, "--help", "-h", "help"
        puts USAGE
        exit 1 if command.nil?
      when "exec"
        Commands::Exec.new(@args).run
      when "verify"
        Context.new.verify(push: @args.include?("--push"))
      when "install"
        positional, options = parse_options
        raise Error, "install takes no arguments" unless positional.empty?
        Installer.install(Context.new.root, replace: options[:force], quiet: false)
        puts "✓ rails-worktree is installed. Link the herdr plugin once with: herdr plugin link #{Installer::HERDR_DIR}"
      when "create"
        positional, options = parse_options
        Commands::Create.new(positional, level: options[:level], seed: options[:seed]).run
      when "init", "--init"
        positional, options = parse_options
        Commands::Init.new(positional, level: options[:level], seed: options[:seed], base: options[:base], force: options[:force]).run
      when "close", "--close"
        positional, _options = parse_options
        Commands::Close.new(positional).run
      else
        @args.unshift(command)
        positional, options = parse_options
        Commands::Create.new(positional, level: options[:level], seed: options[:seed]).run
      end
    rescue Error => error
      warn "Error: #{error.message}"
      exit 1
    end

    private

    def parse_options
      positional = []
      options = {seed: false, force: false}
      until @args.empty?
        argument = @args.shift
        case argument
        when "--seed" then options[:seed] = true
        when "--skip-seeds" then options[:seed] = false
        when "--force" then options[:force] = true
        when /\A--(level|base)(?:=(.*))?\z/
          value = Regexp.last_match(2) || @args.shift
          raise Error, "#{argument} needs a value" if value.nil? || value.start_with?("--")
          options[Regexp.last_match(1).to_sym] = value
        when /\A--/
          raise Error, "Unknown option #{argument}"
        else
          positional << argument
        end
      end
      [positional, options]
    end
  end
end
