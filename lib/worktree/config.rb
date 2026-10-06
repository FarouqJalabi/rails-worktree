require "yaml"

module RailsWorktree
  # Project configuration from .worktree.yml in the repository root.
  class Config
    FILE = ".worktree.yml".freeze
    LEVELS = %w[minimal test full].freeze
    NODE_MODULES_MODES = %w[link copy skip].freeze

    DEFAULTS = {
      "level" => "full",
      "copy" => [
        ".env",
        ".env.*",
        "config/database.yml",
        "config/master.key",
        "config/credentials/*.key",
        "Procfile.dev"
      ],
      "directories" => [],
      "touch" => [],
      "node_modules" => "link",
      "database" => {
        "development_variable" => "DATABASE_NAME",
        "test_variable" => "DATABASE_NAME",
        "template" => true
      },
      "test_command" => nil
    }.freeze

    TEMPLATE = <<~YAML.freeze
      # rails-worktree configuration. Every key is optional; these are the defaults.
      # Docs: https://github.com/FastTravelAS/rails-worktree

      # Provisioning level used by `bin/worktree create` and `bin/worktree init`
      # when --level is not given: minimal, test or full.
      level: full

      # Gitignored files to copy from the main checkout. Globs are relative to the
      # repository root. The same list generates .worktreeinclude for Claude Code.
      copy:
        - .env
        - .env.*
        - config/database.yml
        - config/master.key
        - config/credentials/*.key
        - Procfile.dev

      # Directories to create and files to touch in every provisioned checkout.
      directories: []
      touch: []

      # node_modules handling: link (symlink to the main checkout), copy or skip.
      node_modules: link

      database:
        # Environment variables that config/database.yml reads for the database
        # name. They are written to .env.development.local and .env.test.local.
        development_variable: DATABASE_NAME
        test_variable: DATABASE_NAME
        # Clone the main development database with CREATE DATABASE ... TEMPLATE
        # (PostgreSQL) instead of loading the schema. Falls back when it fails.
        template: true

      # Command for `--level test`, for example bin/agent-test-setup. Without it
      # the test level creates an own test database and loads the schema.
      test_command:
    YAML

    attr_reader :root, :data

    def self.load(root)
      path = File.join(root, FILE)
      data = File.file?(path) ? YAML.safe_load(File.read(path)) : nil
      raise Error, "#{FILE} must be a YAML mapping" if data && !data.is_a?(Hash)
      new(root, data || {})
    end

    def initialize(root, data = {})
      @root = root
      @data = deep_merge(DEFAULTS, data)
      validate
    end

    def level = @data["level"]
    def copy_patterns = Array(@data["copy"]).map(&:to_s)
    def directories = Array(@data["directories"]).map(&:to_s)
    def touch = Array(@data["touch"]).map(&:to_s)
    def node_modules = @data["node_modules"].to_s
    def development_variable = @data.dig("database", "development_variable").to_s
    def test_variable = @data.dig("database", "test_variable").to_s
    def template? = @data.dig("database", "template") ? true : false
    def test_command = @data["test_command"]&.to_s

    private

    def validate
      raise Error, "#{FILE}: level must be one of #{LEVELS.join(", ")}" unless LEVELS.include?(level)
      raise Error, "#{FILE}: node_modules must be one of #{NODE_MODULES_MODES.join(", ")}" unless NODE_MODULES_MODES.include?(node_modules)
      raise Error, "#{FILE}: database variables must be set" if development_variable.empty? || test_variable.empty?
    end

    def deep_merge(base, overrides)
      base.merge(overrides) do |_key, old, new|
        old.is_a?(Hash) && new.is_a?(Hash) ? deep_merge(old, new) : new
      end
    end
  end
end
