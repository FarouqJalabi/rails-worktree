require "test_helper"
require "rake"

class InstallerTest < Minitest::Test
  include RepositoryFixture

  def setup
    @root = Dir.mktmpdir("worktree-install")
    @gitignore = File.join(@root, ".gitignore")
    @launcher = File.join(@root, "bin/worktree")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_installs_launcher_and_ignores_local_worktrees
    RailsWorktree::Installer.install(@root)

    assert File.executable?(@launcher)
    assert_equal "/.worktrees/\n", File.read(@gitignore)
  end

  def test_preserves_existing_launcher_and_unterminated_ignore_entry
    FileUtils.mkdir_p(File.dirname(@launcher))
    File.write(@launcher, "existing launcher")
    File.write(@gitignore, "/log")

    2.times { RailsWorktree::Installer.install(@root) }

    assert_equal "existing launcher", File.read(@launcher)
    assert_equal "/log\n/.worktrees/\n", File.read(@gitignore)
  end

  def test_does_not_duplicate_existing_ignore_patterns
    %w[ .worktrees .worktrees/ /.worktrees /.worktrees/ ].each do |pattern|
      File.write(@gitignore, "#{pattern}\n")
      RailsWorktree::Installer.install(@root)
      assert_equal "#{pattern}\n", File.read(@gitignore)
    end
  end

  def test_force_replaces_launcher_and_updates_gitignore
    RailsWorktree::Installer.install(@root)
    File.write(@launcher, "old launcher")
    File.delete(@gitignore)

    RailsWorktree::Installer.install(@root, replace: true)

    assert_includes File.read(@launcher), "BUNDLE_GEMFILE"
    assert File.executable?(@launcher)
    assert_equal "/.worktrees/\n", File.read(@gitignore)
  end

  def test_writes_the_integration_files_once
    changes = RailsWorktree::Installer.install(@root)

    assert_equal RailsWorktree::Config::TEMPLATE, File.read(File.join(@root, ".worktree.yml"))
    include = File.read(File.join(@root, ".worktreeinclude"))
    assert_includes include, "# rails-worktree:start\n"
    assert_includes include, "\nconfig/credentials/*.key\n"
    agents = File.read(File.join(@root, "AGENTS.md"))
    assert_includes agents, "<!-- rails-worktree:start -->\n## Worktrees"
    assert_includes agents, "bin/worktree init"
    manifest = File.read(File.join(@root, ".worktree/herdr/herdr-plugin.toml"))
    assert_includes manifest, "on = \"worktree.created\""
    assert_includes manifest, "id = \"rails-worktree.#{File.basename(@root)}\""
    assert File.executable?(File.join(@root, ".worktree/herdr/provision"))
    assert_includes changes, "AGENTS.md"
    refute File.exist?(File.join(@root, "CLAUDE.md"))

    assert_empty RailsWorktree::Installer.install(@root)
  end

  def test_generates_worktreeinclude_from_the_configured_copy_list_and_keeps_other_lines
    File.write(File.join(@root, ".worktree.yml"), "copy: [.env, config/master.key]\n")
    File.write(File.join(@root, ".worktreeinclude"), ".secret\n")
    RailsWorktree::Installer.install(@root)

    include = File.read(File.join(@root, ".worktreeinclude"))
    assert include.start_with?(".secret\n\n# rails-worktree:start\n")
    assert_includes include, "\n.env\nconfig/master.key\n# rails-worktree:end\n"
    refute_includes include, "database.yml"
  end

  def test_updates_agents_and_claude_files_and_counts_a_symlink_once
    File.write(File.join(@root, "AGENTS.md"), "# App\n")
    File.symlink("AGENTS.md", File.join(@root, "CLAUDE.md"))
    RailsWorktree::Installer.install(@root)
    agents = File.read(File.join(@root, "AGENTS.md"))

    assert agents.start_with?("# App\n\n<!-- rails-worktree:start -->")
    assert_equal 1, agents.scan("rails-worktree:start").length

    File.delete(File.join(@root, "CLAUDE.md"))
    File.write(File.join(@root, "CLAUDE.md"), "# Claude\n")
    RailsWorktree::Installer.install(@root)
    assert_includes File.read(File.join(@root, "CLAUDE.md")), "## Worktrees"
    assert_equal 1, File.read(File.join(@root, "AGENTS.md")).scan("rails-worktree:start").length
  end

  def test_herdr_plugin_id_names_the_main_checkout_from_a_worktree
    main = File.join(@root, "myapp")
    child = File.join(@root, "feature")
    FileUtils.mkdir_p(main)
    git(main, "init", "--quiet", "--initial-branch=main")
    git(main, "config", "user.name", "Test")
    git(main, "config", "user.email", "test@example.test")
    File.write(File.join(main, "README.md"), "app\n")
    git(main, "add", ".")
    git(main, "commit", "--quiet", "-m", "base")
    git(main, "worktree", "add", "--quiet", "-b", "feature", child, "main")

    RailsWorktree::Installer.install(child)

    assert_includes File.read(File.join(child, ".worktree/herdr/herdr-plugin.toml")), "id = \"rails-worktree.myapp\""
  end

  def test_herdr_provision_reads_the_wrapped_event_and_runs_init
    main = File.join(@root, "myapp")
    child = File.join(@root, "feature")
    FileUtils.mkdir_p(main)
    git(main, "init", "--quiet", "--initial-branch=main")
    git(main, "config", "user.name", "Test")
    git(main, "config", "user.email", "test@example.test")
    FileUtils.mkdir_p(File.join(main, "bin"))
    File.write(File.join(main, "bin/worktree"), "#!/bin/sh\necho \"$@\" > provisioned\n")
    File.chmod(0755, File.join(main, "bin/worktree"))
    git(main, "add", ".")
    git(main, "commit", "--quiet", "-m", "base")
    git(main, "worktree", "add", "--quiet", "-b", "feature", child, "main")
    RailsWorktree::Installer.install(main)

    event = { event: "worktree_created", data: { worktree: { path: child, branch: "feature" } } }
    _output, error, status = Open3.capture3({ "HERDR_PLUGIN_EVENT_JSON" => JSON.generate(event) }, File.join(main, ".worktree/herdr/provision"))

    assert status.success?, error
    assert_equal "init --level minimal\n", File.read(File.join(child, "provisioned"))
  end

  def test_rake_install_updates_gitignore_when_launcher_exists_and_continues
    RailsWorktree::Launcher.install(@root)
    Rake.with_application do
      load File.expand_path("../lib/worktree/tasks.rb", __dir__)
      Dir.chdir(@root) do
        capture_io { Rake::Task["worktree:install"].invoke }
      end
    end

    assert_equal "/.worktrees/\n", File.read(@gitignore)
    assert File.file?(File.join(@root, ".worktreeinclude"))
  end
end
