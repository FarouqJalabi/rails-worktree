require "test_helper"

class CLITest < Minitest::Test
  def test_parses_options_and_positionals
    positional, options = RailsWorktree::CLI.new(["feature", "origin/main", "--level", "minimal", "--seed", "--base=main", "--force"]).send(:parse_options)

    assert_equal ["feature", "origin/main"], positional
    assert_equal({seed: true, force: true, level: "minimal", base: "main"}, options)
  end

  def test_rejects_unknown_options_and_missing_values
    assert_raises(RailsWorktree::Error) { RailsWorktree::CLI.new(["--bogus"]).send(:parse_options) }
    assert_raises(RailsWorktree::Error) { RailsWorktree::CLI.new(["--level"]).send(:parse_options) }
    assert_raises(RailsWorktree::Error) { RailsWorktree::CLI.new(["--level", "--seed"]).send(:parse_options) }
  end

  def test_help_prints_usage
    out, _err = capture_io { RailsWorktree::CLI.run(["--help"]) }
    assert_includes out, "worktree init [name]"
  end
end
