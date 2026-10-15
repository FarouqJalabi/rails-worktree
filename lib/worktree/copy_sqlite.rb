# Copies a SQLite database consistently, also while it is in use.
# Usage: ruby copy_sqlite.rb SOURCE TARGET
require "sqlite3"

source, target = ARGV.fetch(0), ARGV.fetch(1)
SQLite3::Database.new(source, readonly: true) { |database| database.execute("VACUUM INTO ?", [target]) }
puts "Copied #{source} into #{target}"
