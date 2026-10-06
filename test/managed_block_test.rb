require "test_helper"

class ManagedBlockTest < Minitest::Test
  START = "<!-- x:start -->".freeze
  FINISH = "<!-- x:end -->".freeze

  def setup
    @root = Dir.mktmpdir("managed-block")
    @path = File.join(@root, "AGENTS.md")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_creates_appends_and_replaces
    assert RailsWorktree::ManagedBlock.write(@path, "one", start: START, finish: FINISH)
    assert_equal "#{START}\none\n#{FINISH}\n", File.read(@path)

    File.write(@path, "# Title\n")
    RailsWorktree::ManagedBlock.write(@path, "one\n", start: START, finish: FINISH)
    assert_equal "# Title\n\n#{START}\none\n#{FINISH}\n", File.read(@path)

    File.write(@path, File.read(@path) + "\nTrailing \\1 text\n")
    assert RailsWorktree::ManagedBlock.write(@path, "two\\0", start: START, finish: FINISH)
    assert_equal "# Title\n\n#{START}\ntwo\\0\n#{FINISH}\n\nTrailing \\1 text\n", File.read(@path)

    refute RailsWorktree::ManagedBlock.write(@path, "two\\0", start: START, finish: FINISH)
  end
end
