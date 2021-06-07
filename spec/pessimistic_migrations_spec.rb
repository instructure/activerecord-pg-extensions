# frozen_string_literal: true

describe ActiveRecord::PGExtensions::PessimisticMigrations do
  around do |example|
    connection.dont_execute(&example)
  end

  describe "#change_column_null" do
    it "does nothing extra when changing a column to nullable" do
      connection.change_column_null(:table, :column, true)
      expect(connection.executed_statements).to eq ['ALTER TABLE "table" ALTER COLUMN "column" DROP NOT NULL']
    end

    it "pre-warms the cache" do
      connection.change_column_null(:table, :column, false)
      expect(connection.executed_statements).to eq(
        ["BEGIN",
         "SET LOCAL enable_indexscan=off",
         "SET LOCAL enable_bitmapscan=off",
         'SELECT COUNT(*) FROM "table" WHERE "column" IS NULL',
         "ROLLBACK",
         'ALTER TABLE "table" ALTER COLUMN "column" SET NOT NULL']
      )
    end

    it "does nothing extra if a transaction is already active" do
      connection.transaction do
        connection.change_column_null(:table, :column, false)
      end
      expect(connection.executed_statements).to eq(
        ["BEGIN",
         'ALTER TABLE "table" ALTER COLUMN "column" SET NOT NULL',
         "COMMIT"]
      )
    end
  end
end
