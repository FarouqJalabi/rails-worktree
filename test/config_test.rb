require "test_helper"

class ConfigTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("worktree-config")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_defaults_without_a_file
    config = RailsWorktree::Config.load(@root)

    assert_equal "full", config.level
    assert_includes config.copy_patterns, "config/credentials/*.key"
    assert_equal "link", config.node_modules
    assert_equal "DATABASE_NAME", config.development_variable
    assert config.template?
    assert_nil config.test_command
  end

  def test_overrides_merge_with_defaults
    File.write(File.join(@root, ".worktree.yml"), <<~YAML)
      level: minimal
      copy: [.env]
      directories: [tmp/pids]
      database:
        template: false
      test_command: bin/agent-test-setup
    YAML
    config = RailsWorktree::Config.load(@root)

    assert_equal "minimal", config.level
    assert_equal [".env"], config.copy_patterns
    assert_equal ["tmp/pids"], config.directories
    refute config.template?
    assert_equal "DATABASE_NAME", config.test_variable
    assert_equal "bin/agent-test-setup", config.test_command
  end

  def test_rejects_invalid_values
    File.write(File.join(@root, ".worktree.yml"), "level: huge\n")
    assert_raises(RailsWorktree::Error) { RailsWorktree::Config.load(@root) }
    File.write(File.join(@root, ".worktree.yml"), "node_modules: tarball\n")
    assert_raises(RailsWorktree::Error) { RailsWorktree::Config.load(@root) }
    File.write(File.join(@root, ".worktree.yml"), "- list\n")
    assert_raises(RailsWorktree::Error) { RailsWorktree::Config.load(@root) }
  end

  def test_template_parses_to_the_defaults
    File.write(File.join(@root, ".worktree.yml"), RailsWorktree::Config::TEMPLATE)
    assert_equal RailsWorktree::Config.new(@root).data, RailsWorktree::Config.load(@root).data
  end
end
