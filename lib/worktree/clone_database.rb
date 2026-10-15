# Runs inside `bin/rails runner` in the worktree, without the worktree database
# override, so the configured development database is the main checkout's.
# Usage: bin/rails runner clone_database.rb TARGET
# RAILS_WORKTREE_TEMPLATE_MAX_BYTES caps the source size; a larger database is not cloned.
target = ARGV.fetch(0)
max_bytes = ENV.fetch("RAILS_WORKTREE_TEMPLATE_MAX_BYTES", "0").to_i
config = ActiveRecord::Base.connection_db_config.configuration_hash
source = config[:database]
abort "Template cloning needs PostgreSQL (adapter #{config[:adapter]})." unless config[:adapter].to_s.include?("postg")
abort "Source and target databases are the same: #{source}" if source == target

ActiveRecord::Base.establish_connection(config.merge(database: "postgres"))
connection = ActiveRecord::Base.connection
if connection.select_value("SELECT 1 FROM pg_database WHERE datname = #{connection.quote(target)}")
  puts "Database #{target} already exists"
else
  size = connection.select_value("SELECT pg_database_size(#{connection.quote(source)})").to_i
  if max_bytes.positive? && size > max_bytes
    abort format("Source database %s is %.1f GB, above database.template_max_gb in .worktree.yml; not cloning.", source, size / 1024.0**3)
  end
  connection.execute("CREATE DATABASE #{connection.quote_table_name(target)} TEMPLATE #{connection.quote_table_name(source)}")
  puts "Cloned #{source} into #{target}"
end
