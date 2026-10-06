# Runs inside `bin/rails runner` in the worktree, without the worktree database
# override, so the configured development database is the main checkout's.
# Usage: bin/rails runner clone_database.rb TARGET
target = ARGV.fetch(0)
config = ActiveRecord::Base.connection_db_config.configuration_hash
source = config[:database]
abort "Template cloning needs PostgreSQL (adapter #{config[:adapter]})." unless config[:adapter].to_s.include?("postg")
abort "Source and target databases are the same: #{source}" if source == target

ActiveRecord::Base.establish_connection(config.merge(database: "postgres"))
connection = ActiveRecord::Base.connection
if connection.select_value("SELECT 1 FROM pg_database WHERE datname = #{connection.quote(target)}")
  puts "Database #{target} already exists"
else
  connection.execute("CREATE DATABASE #{connection.quote_table_name(target)} TEMPLATE #{connection.quote_table_name(source)}")
  puts "Cloned #{source} into #{target}"
end
