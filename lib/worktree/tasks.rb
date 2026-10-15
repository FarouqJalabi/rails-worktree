namespace :worktree do
  desc "Install bin/worktree, .worktree.yml, .worktreeinclude, the AGENTS.md block and the herdr plugin"
  task :install do
    RailsWorktree::Installer.install(Dir.pwd, replace: ENV["FORCE"] == "1", quiet: false)

    puts "✓ rails-worktree is installed"
    puts "Usage: bin/worktree create <name> <base-branch>"
    puts "Link the herdr plugin once with: herdr plugin link #{RailsWorktree::Installer::HERDR_DIR}"
  end

  desc "Uninstall worktree binstub from bin/worktree"
  task :uninstall do
    binstub_path = File.join(Dir.pwd, "bin/worktree")

    if File.exist?(binstub_path)
      File.delete(binstub_path)
      puts "✓ Worktree binstub removed from bin/worktree"
    else
      puts "Binstub not found at bin/worktree"
    end
  end
end
