require "rails/railtie"

module RailsWorktree
  class Railtie < Rails::Railtie
    railtie_name :worktree

    rake_tasks do
      load "worktree/tasks.rb"
    end

    initializer "worktree.install" do
      # Install the launcher and repository integration files when Rails loads in development.
      Installer.install(Rails.root.to_s) if Rails.env.development?
    end
  end
end
