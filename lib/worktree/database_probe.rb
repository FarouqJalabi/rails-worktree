# Runs inside `bin/rails runner` in the worktree. Prints how config/database.yml
# resolves the primary database of each environment, without the worktree
# variable and with it set, and whether dotenv is loaded to read .env.*.local.
# Usage: bin/rails runner database_probe.rb ENVIRONMENT:VARIABLE=VALUE ...
require "json"

def resolve(environment, variable, value)
  saved = ENV.to_h.slice(variable)
  ENV.delete(variable)
  ENV[variable] = value if value
  configurations = ActiveRecord::DatabaseConfigurations.new(Rails.application.config.database_configuration)
  config = configurations.configs_for(env_name: environment, name: "primary") || configurations.configs_for(env_name: environment).first
  config && {"adapter" => config.adapter.to_s, "database" => config.database.to_s}
ensure
  ENV.delete(variable)
  ENV.update(saved)
end

result = {"dotenv" => defined?(Dotenv) ? true : false}
ARGV.each do |argument|
  environment, assignment = argument.split(":", 2)
  variable, value = assignment.split("=", 2)
  default = resolve(environment, variable, nil)
  override = resolve(environment, variable, value)
  result[environment] = default && default.merge("override" => override && override["database"])
end
puts "RAILS_WORKTREE_PROBE #{JSON.generate(result)}"
