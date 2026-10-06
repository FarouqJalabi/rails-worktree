require "test_helper"

class InitTest < Minitest::Test
  include RepositoryFixture

  def setup
    build_repository
    write_main(".env", "SECRET=123\n")
    write_main(".env.test", "TEST=1\n")
    write_main("config/database.yml", "development:\n  database: <%= ENV.fetch(\"DATABASE_NAME\", \"myapp_development\") %>\n")
    write_main("config/credentials/test.key", "test-key")
    write_main("config/credentials/test.yml.enc", "encrypted")
    write_main("node_modules/left-pad/index.js", "module.exports = 1")
    [@main, @worktree].each do |root|
      FileUtils.mkdir_p(File.join(root, "bin"))
      File.write(File.join(root, "bin/rails"), "#!/bin/sh\nexit 0\n")
      File.chmod(0755, File.join(root, "bin/rails"))
    end
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_minimal_copies_configured_files_and_links_node_modules
    write_main(".worktree.yml", "directories: [tmp/pids]\ntouch: [tmp/caching-dev.txt]\n")
    FileUtils.cp(File.join(@main, ".worktree.yml"), @worktree)
    init = run_init(level: "minimal")

    assert_equal "SECRET=123\n", File.read(File.join(@worktree, ".env"))
    assert_equal "TEST=1\n", File.read(File.join(@worktree, ".env.test"))
    assert_equal "test-key", File.read(File.join(@worktree, "config/credentials/test.key"))
    refute File.exist?(File.join(@worktree, "config/credentials/test.yml.enc"))
    assert File.symlink?(File.join(@worktree, "node_modules"))
    assert File.directory?(File.join(@worktree, "tmp/pids"))
    assert File.file?(File.join(@worktree, "tmp/caching-dev.txt"))
    refute File.exist?(File.join(@worktree, ".env.development.local"))
    assert_empty init.calls
    assert_equal "feature-x", init.name
  end

  def test_minimal_keeps_existing_files_unless_forced
    File.write(File.join(@worktree, ".env"), "LOCAL=edit\n")
    run_init(level: "minimal")
    assert_equal "LOCAL=edit\n", File.read(File.join(@worktree, ".env"))

    run_init(level: "minimal", force: true)
    assert_equal "SECRET=123\n", File.read(File.join(@worktree, ".env"))
  end

  def test_node_modules_copy_and_skip_modes
    write_main(".worktree.yml", "node_modules: copy\n")
    run_init(level: "minimal")
    assert File.directory?(File.join(@worktree, "node_modules/left-pad"))
    refute File.symlink?(File.join(@worktree, "node_modules"))

    FileUtils.rm_rf(File.join(@worktree, "node_modules"))
    write_main(".worktree.yml", "node_modules: skip\n")
    run_init(level: "minimal")
    refute File.exist?(File.join(@worktree, "node_modules"))
  end

  def test_full_clones_the_development_database_and_prepares_the_test_database
    init = run_init(level: "full")

    assert_equal "DATABASE_NAME=myapp_feature_x_development", env_line(".env.development.local")
    assert_equal "DATABASE_NAME=myapp_feature_x_test", env_line(".env.test.local")
    commands = init.calls.map { |env, *command| [env["RAILS_ENV"], env["DATABASE_NAME"], command.drop(1)] }
    assert_equal ["development", nil, ["runner", File.expand_path("../../lib/worktree/clone_database.rb", __dir__), "myapp_feature_x_development"]], commands[0]
    assert_equal ["development", "myapp_feature_x_development", ["db:migrate"]], commands[1]
    assert_equal ["test", "myapp_feature_x_test", ["db:create"]], commands[2]
    assert_equal ["test", "myapp_feature_x_test", ["db:schema:load"]], commands[3]
    assert_equal 4, commands.length
    init.calls.each { |_env, command, *| assert_equal "bin/rails", command }
  end

  def test_full_loads_the_schema_when_the_clone_fails_and_seeds_on_request
    init = run_init(level: "full", seed: true, failing: ["runner"])

    tasks = init.calls.map { |env, *command| [env["RAILS_ENV"], command.last] }
    assert_equal [["development", "myapp_feature_x_development"], ["development", "db:create"], ["development", "db:schema:load"],
      ["test", "db:create"], ["test", "db:schema:load"], ["development", "db:seed"]], tasks
  end

  def test_full_uses_configured_variables_and_skips_the_template
    write_main(".worktree.yml", "database:\n  development_variable: DATABASE_NAME_DEVELOPMENT\n  test_variable: DATABASE_NAME_TEST\n  template: false\n")
    init = run_init(level: "full")

    assert_equal "DATABASE_NAME_DEVELOPMENT=myapp_feature_x_development", env_line(".env.development.local")
    assert_equal "DATABASE_NAME_TEST=myapp_feature_x_test", env_line(".env.test.local")
    refute_includes init.calls.flatten, "runner"
    assert_equal "myapp_feature_x_development", init.calls[0][0]["DATABASE_NAME_DEVELOPMENT"]
  end

  def test_full_replaces_an_existing_variable_in_the_local_env_file
    File.write(File.join(@worktree, ".env.development.local"), "OTHER=1\nDATABASE_NAME=old\n")
    run_init(level: "full", force: true)

    assert_equal "OTHER=1\nDATABASE_NAME=myapp_feature_x_development\n", File.read(File.join(@worktree, ".env.development.local"))
  end

  def test_full_without_bin_rails_only_copies_files
    File.delete(File.join(@worktree, "bin/rails"))
    init = run_init(level: "full")

    assert_empty init.calls
    refute File.exist?(File.join(@worktree, ".env.development.local"))
  end

  def test_test_level_runs_the_configured_command
    write_main(".worktree.yml", "test_command: bin/agent-test-setup --skip-assets\n")
    write_main("bin/agent-test-setup", "#!/bin/sh\n")
    File.chmod(0755, File.join(@main, "bin/agent-test-setup"))
    init = run_init(level: "test")

    assert_equal [["bin/agent-test-setup", "--skip-assets"]], init.calls.map { |_env, *command| command }
    refute File.exist?(File.join(@worktree, ".env.test.local"))
  end

  def test_test_level_without_a_command_prepares_an_own_test_database
    init = run_init(level: "test")

    assert_equal "DATABASE_NAME=myapp_feature_x_test", env_line(".env.test.local")
    refute File.exist?(File.join(@worktree, ".env.development.local"))
    assert_equal [["test", "db:create"], ["test", "db:schema:load"]], init.calls.map { |env, *command| [env["RAILS_ENV"], command.last] }
  end

  def test_level_defaults_to_the_configured_level
    write_main(".worktree.yml", "level: minimal\n")
    init = run_init
    assert_equal "minimal", init.level
    assert_empty init.calls
  end

  def test_rejects_the_main_checkout_and_unknown_levels
    Dir.chdir(@main) { assert_raises(RailsWorktree::Error) { RailsWorktree::Commands::Init.new([]).run } }
    Dir.chdir(@worktree) { assert_raises(RailsWorktree::Error) { RailsWorktree::Commands::Init.new([], level: "huge").run } }
  end

  private

  def env_line(file)
    File.read(File.join(@worktree, file)).lines.map(&:strip).reject { |line| line.empty? || line.start_with?("#") }.join("\n")
  end

  # Runs init in the worktree with system calls recorded instead of executed.
  def run_init(level: nil, seed: false, force: false, failing: [])
    init = RailsWorktree::Commands::Init.new([], level: level, seed: seed, force: force)
    calls = []
    init.define_singleton_method(:calls) { calls }
    init.define_singleton_method(:system) do |env, *command, **_options|
      calls << [env, *command]
      failing.none? { |task| command.include?(task) }
    end
    Dir.chdir(@worktree) { capture_io { init.run } }
    init
  end
end
