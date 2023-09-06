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

    it "does nothing if we're in a transaction" do
      connection.transaction do
        connection.change_column_null(:table, :column, true)
      end
      expect(connection.executed_statements).to eq ["BEGIN",
                                                    'ALTER TABLE "table" ALTER COLUMN "column" DROP NOT NULL',
                                                    "COMMIT"]
    end

    it "skips entirely if the column is already NOT NULL" do
      expect(connection).to receive(:columns).with(:table).and_return([double(name: "column", null: false)])
      connection.change_column_null(:table, :column, false)
      expect(connection.executed_statements).to eq([])
    end

    it "adds and removes a check constraint" do
      expect(connection).to receive(:columns).and_return([])
      allow(connection).to receive(:check_constraint_for!).and_return(double(name: "chk_rails_table_column_not_null"))
      connection.change_column_null(:table, :column, false)

      expect(connection.executed_statements).to eq [
        "SELECT convalidated FROM pg_constraint INNER JOIN pg_namespace ON pg_namespace.oid=connamespace WHERE conname='chk_rails_table_column_not_null' AND nspname=ANY (current_schemas(false))\n", # rubocop:disable Layout/LineLength
        %{ALTER TABLE "table" ADD CONSTRAINT chk_rails_table_column_not_null CHECK ("column" IS NOT NULL) NOT VALID},
        'ALTER TABLE "table" VALIDATE CONSTRAINT "chk_rails_table_column_not_null"',
        "BEGIN",
        'ALTER TABLE "table" ALTER COLUMN "column" SET NOT NULL',
        'ALTER TABLE "table" DROP CONSTRAINT "chk_rails_table_column_not_null"',
        "COMMIT"
      ]
    end

    it "verifies an existing check constraint" do
      expect(connection).to receive(:columns).and_return([])
      allow(connection).to receive(:check_constraint_for!).and_return(double(name: "chk_rails_table_column_not_null"))
      expect(connection).to receive(:select_value).and_return(false)
      connection.change_column_null(:table, :column, false)

      expect(connection.executed_statements).to eq [
        # stubbed out <check constraint valid>
        'ALTER TABLE "table" VALIDATE CONSTRAINT "chk_rails_table_column_not_null"',
        "BEGIN",
        'ALTER TABLE "table" ALTER COLUMN "column" SET NOT NULL',
        'ALTER TABLE "table" DROP CONSTRAINT "chk_rails_table_column_not_null"',
        "COMMIT"
      ]
    end
  end

  describe "#add_foreign_key" do
    it "does nothing extra if a transaction is already active" do
      connection.transaction do
        connection.add_foreign_key :emails, :users, delay_validation: true
      end
      expect(connection.executed_statements).to match(
        ["BEGIN",
         match(/\AALTER TABLE "emails" ADD CONSTRAINT "fk_rails_[0-9a-f]+".+REFERENCES "users" \("id"\)\s*\z/m),
         "COMMIT"]
      )
    end

    it "delays validation" do
      connection.add_foreign_key :emails, :users, delay_validation: true
      expect(connection.executed_statements).to match(
        [/convalidated/,
         match(/\AALTER TABLE "emails" ADD CONSTRAINT "[a-z0-9_]+".+REFERENCES "users" \("id"\)\s+NOT VALID\z/m),
         match(/^ALTER TABLE "emails" VALIDATE CONSTRAINT "fk_rails_[0-9a-f]+"/)]
      )
    end

    it "only validates if the constraint already exists, and is not valid" do
      expect(connection).to receive(:select_value).with(/convalidated/, "SCHEMA").and_return(false)
      connection.add_foreign_key :emails, :users, delay_validation: true
      expect(connection.executed_statements).to match(
        [match(/^ALTER TABLE "emails" VALIDATE CONSTRAINT "fk_rails_[0-9a-f]+"/)]
      )
    end

    it "does nothing if constraint already exists" do
      expect(connection).to receive(:select_value).with(/convalidated/, "SCHEMA").and_return(true)
      connection.add_foreign_key :emails, :users, if_not_exists: true
      expect(connection.executed_statements).to eq []
    end

    it "still tries if delay_validation is true but if_not_exists is false and it already exists" do
      expect(connection).to receive(:select_value).with(/convalidated/, "SCHEMA").and_return(true)
      connection.add_foreign_key :emails, :users, delay_validation: true
      expect(connection.executed_statements).to match(
        [match(/\AALTER TABLE "emails" ADD CONSTRAINT "[a-z0-9_]+".+REFERENCES "users" \("id"\)\s+NOT VALID\z/m),
         match(/^ALTER TABLE "emails" VALIDATE CONSTRAINT "fk_rails_[0-9a-f]+"/)]
      )
    end

    it "does nothing if_not_exists is true and it is NOT VALID" do
      expect(connection).to receive(:select_value).with(/convalidated/, "SCHEMA").and_return(false)
      connection.add_foreign_key :emails, :users, if_not_exists: true
      expect(connection.executed_statements).to eq []
    end
  end

  describe "#add_index" do
    it "removes a NOT VALID index before re-adding" do
      expect(connection).to receive(:select_value).with(/indisvalid/, "SCHEMA").and_return(false)
      expect(connection).to receive(:remove_index).with(:users, name: "index_users_on_name", algorithm: :concurrently)

      connection.add_index :users, :name, algorithm: :concurrently, if_not_exists: true
      expect(connection.executed_statements).to eq [
        'CREATE INDEX CONCURRENTLY IF NOT EXISTS "index_users_on_name" ON "users" ("name")'
      ]
    end

    it "does nothing if the index already exists" do
      expect(connection).not_to receive(:select_value)

      connection.add_index :users, :name, if_not_exists: true
      expect(connection.executed_statements).to eq [
        'CREATE INDEX IF NOT EXISTS "index_users_on_name" ON "users" ("name")'
      ]
    end
  end

  describe "#add_check_constraint" do
    it "supports if_not_exists" do
      expect(connection).to receive(:check_constraint_for).and_return(double(name: "chk_rails_users_name_not_null"))
      connection.add_check_constraint :users,
                                      "name IS NOT NULL",
                                      name: "chk_rails_users_name_not_null",
                                      if_not_exists: true
      expect(connection.executed_statements).to eq []
    end
  end

  describe "#remove_check_constraint" do
    it "supports if_exists" do
      expect(connection).to receive(:check_constraint_for).and_return(nil)
      connection.remove_check_constraint :users, name: "chk_rails_users_name_not_null", if_exists: true
      expect(connection.executed_statements).to eq []
    end
  end
end
