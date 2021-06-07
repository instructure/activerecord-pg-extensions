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

  %w[execute exec_no_cache exec_cache].each do |method|
    class_eval <<-RUBY, __FILE__, __LINE__ + 1
      def #{method}(statement, *)
        materialize_transactions # this still needs to get called, even if we skip actually executing
        executed_statements << statement
        return empty_pg_result if @dont_execute

        super
      end
    RUBY
  end

  # we can't actually generate a dummy one of these, so we just query the db with something
  # that won't return anything
  def empty_pg_result
    @connection.async_exec("SELECT 0 WHERE FALSE")
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
