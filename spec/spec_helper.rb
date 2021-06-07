# frozen_string_literal: true

require "activerecord-pg-extensions"
require "byebug"
require "active_record/railtie"
require "active_record/pg_extensions/all"

ActiveRecord::Base # rubocop:disable Lint/Void
Rails.env = "test"

class Application < Rails::Application
  config.eager_load = false
end
Application.initialize!

ActiveRecord::Tasks::DatabaseTasks.create_all

module StatementCaptureConnection
  def dont_execute
    @dont_execute = true
    yield
  ensure
    @dont_execute = false
  end

  def executed_statements
    @executed_statements ||= []
  end

  def execute(statement, *)
    materialize_transactions # this still needs to get called, even if we skip actually executing
    executed_statements << statement
    super unless @dont_execute
  end
end
ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.prepend(StatementCaptureConnection)

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  def connection
    ActiveRecord::Base.connection
  end

  config.before do
    connection.executed_statements.clear
  end
end
