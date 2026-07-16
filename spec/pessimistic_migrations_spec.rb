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
      allow(connection).to receive(:max_identifier_length).and_return(63)

      connection.add_index :users, :name, algorithm: :concurrently, if_not_exists: true
      expect(connection.executed_statements).to eq [
        'CREATE INDEX CONCURRENTLY IF NOT EXISTS "index_users_on_name" ON "users" ("name")'
      ]
    end

    it "does nothing if the index already exists" do
      expect(connection).not_to receive(:select_value)
      allow(connection).to receive(:max_identifier_length).and_return(63)

      connection.add_index :users, :name, if_not_exists: true
      expect(connection.executed_statements).to eq [
        'CREATE INDEX IF NOT EXISTS "index_users_on_name" ON "users" ("name")'
      ]
    end
  end

  describe "#change_check_constraint" do
    before { allow(connection).to receive(:max_identifier_length).and_return(63) }

    it "drops the old constraint and adds the new one" do
      allow(connection).to receive(:check_constraint_for!).and_return(double(name: "chk_old"))
      connection.change_check_constraint(:users, from: "old_expr", to: "new_expr")
      expect(connection.executed_statements).to eq [
        'ALTER TABLE "users" DROP CONSTRAINT "chk_old"',
        'ALTER TABLE "users" ADD CONSTRAINT chk_rails_5fb2f20b36 CHECK (new_expr)'
      ]
    end

    it "accepts hashes with :expression and extra options for from and to" do
      allow(connection).to receive(:check_constraint_for!).and_return(double(name: "my_old"))
      connection.change_check_constraint(:users,
                                         from: { expression: "old_expr", name: "my_old" },
                                         to: { expression: "new_expr", name: "my_new" })
      expect(connection.executed_statements).to eq [
        'ALTER TABLE "users" DROP CONSTRAINT "my_old"',
        'ALTER TABLE "users" ADD CONSTRAINT my_new CHECK (new_expr)'
      ]
    end

    it "delays validation, dropping the old constraint only after the new one is validated" do
      allow(connection).to receive(:check_constraint_exists?) { |_table, **opts| opts[:name] == "chk_rails_6fa6c8b575" }
      allow(connection).to receive(:check_constraint_for!).and_return(double(name: "chk_rails_6fa6c8b575"))
      connection.change_check_constraint(:users, from: "old_expr", to: "new_expr", delay_validation: true)
      expect(connection.executed_statements).to eq [
        'ALTER TABLE "users" ADD CONSTRAINT chk_rails_5fb2f20b36 CHECK (new_expr) NOT VALID',
        'ALTER TABLE "users" VALIDATE CONSTRAINT "chk_rails_5fb2f20b36"',
        'ALTER TABLE "users" DROP CONSTRAINT "chk_rails_6fa6c8b575"'
      ]
    end

    it "renames the old constraint first when delaying validation and the names collide" do
      # the temporary name doesn't exist until we rename into it
      renamed = false
      allow(connection).to receive(:check_constraint_exists?) do |_table, name: nil, **|
        name == "same_to_be_replaced" && renamed
      end
      allow(connection).to receive(:check_constraint_for!).and_return(double(name: "same_to_be_replaced"))
      allow(connection).to receive(:rename_constraint).and_wrap_original do |original, *args, **kwargs|
        renamed = true
        original.call(*args, **kwargs)
      end
      connection.change_check_constraint(:users,
                                         from: { expression: "x", name: "same" },
                                         to: { expression: "y", name: "same" },
                                         delay_validation: true)
      expect(connection.executed_statements).to eq [
        'ALTER TABLE "users" RENAME CONSTRAINT "same" TO "same_to_be_replaced"',
        'ALTER TABLE "users" ADD CONSTRAINT same CHECK (y) NOT VALID',
        'ALTER TABLE "users" VALIDATE CONSTRAINT "same"',
        'ALTER TABLE "users" DROP CONSTRAINT "same_to_be_replaced"'
      ]
    end

    it "skips the rename when the temporary constraint name is already taken" do
      # a leftover "same_to_be_replaced" from a previously-interrupted run already exists, so the
      # idempotency guard skips the rename and proceeds straight to add/validate/drop
      allow(connection).to receive(:check_constraint_exists?) { |_table, name: nil, **| name == "same_to_be_replaced" }
      allow(connection).to receive(:check_constraint_for!).and_return(double(name: "same_to_be_replaced"))
      connection.change_check_constraint(:users,
                                         from: { expression: "x", name: "same" },
                                         to: { expression: "y", name: "same" },
                                         delay_validation: true)
      expect(connection.executed_statements).to eq [
        'ALTER TABLE "users" ADD CONSTRAINT same CHECK (y) NOT VALID',
        'ALTER TABLE "users" VALIDATE CONSTRAINT "same"',
        'ALTER TABLE "users" DROP CONSTRAINT "same_to_be_replaced"'
      ]
    end

    it "ignores delay_validation inside a transaction" do
      allow(connection).to receive(:check_constraint_for!).and_return(double(name: "chk_old"))
      connection.transaction do
        connection.change_check_constraint(:users, from: "old_expr", to: "new_expr", delay_validation: true)
      end
      expect(connection.executed_statements).to eq [
        "BEGIN",
        'ALTER TABLE "users" DROP CONSTRAINT "chk_old"',
        'ALTER TABLE "users" ADD CONSTRAINT chk_rails_5fb2f20b36 CHECK (new_expr)',
        "COMMIT"
      ]
    end

    it "is reversible by swapping from and to, keeping other arguments the same" do
      recorder = ActiveRecord::Migration::CommandRecorder.new(connection)
      recorder.revert do
        recorder.change_check_constraint(:users,
                                         from: "old_expr",
                                         to: "new_expr",
                                         if_exists: true,
                                         delay_validation: true)
      end
      expect(recorder.commands).to eq(
        [[:change_check_constraint,
          [:users, { from: "new_expr", to: "old_expr", if_exists: true, delay_validation: true }]]]
      )
    end
  end

  describe "#change_index" do
    before do
      allow(connection).to receive_messages(max_identifier_length: 63, select_value: nil, index_exists?: true)
      allow(connection).to receive(:index_name_for_remove) do |_table, column, options|
        options[:name] || "index_users_on_#{Array(column).join("_and_")}"
      end
    end

    it "drops the old index and adds the new one" do
      connection.change_index(:users, from: :a, to: :b)
      expect(connection.executed_statements).to eq [
        'DROP INDEX  "index_users_on_a"',
        'CREATE INDEX "index_users_on_b" ON "users" ("b")'
      ]
    end

    it "accepts hashes with :column and extra options for from and to" do
      connection.change_index(:users, from: { column: :a, name: "my_old" }, to: { column: :b, name: "my_new" })
      expect(connection.executed_statements).to eq [
        'DROP INDEX  "my_old"',
        'CREATE INDEX "my_new" ON "users" ("b")'
      ]
    end

    it "creates the new index concurrently, dropping the old one only afterward" do
      allow(connection).to receive(:index_name_exists?).and_return(false)
      connection.change_index(:users, from: :a, to: :b, algorithm: :concurrently)
      expect(connection.executed_statements).to eq [
        'CREATE INDEX CONCURRENTLY IF NOT EXISTS "index_users_on_b" ON "users" ("b")',
        'DROP INDEX CONCURRENTLY "index_users_on_a"'
      ]
    end

    it "renames the old index first when creating concurrently and the names collide" do
      allow(connection).to receive(:index_name_exists?).and_return(false)
      connection.change_index(:users,
                              from: { column: :a, name: "same" },
                              to: { column: :b, name: "same" },
                              algorithm: :concurrently)
      expect(connection.executed_statements).to eq [
        'ALTER INDEX "same" RENAME TO "same_to_be_replaced"',
        'CREATE INDEX CONCURRENTLY IF NOT EXISTS "same" ON "users" ("b")',
        'DROP INDEX CONCURRENTLY "same_to_be_replaced"'
      ]
    end

    it "skips the rename when the temporary index name is already taken" do
      allow(connection).to receive(:index_name_exists?).and_return(true)
      connection.change_index(:users,
                              from: { column: :a, name: "same" },
                              to: { column: :b, name: "same" },
                              algorithm: :concurrently)
      expect(connection.executed_statements).to eq [
        'CREATE INDEX CONCURRENTLY IF NOT EXISTS "same" ON "users" ("b")',
        'DROP INDEX CONCURRENTLY "same_to_be_replaced"'
      ]
    end

    it "keeps the temporary index name within the identifier length limit" do
      allow(connection).to receive(:index_name_exists?).and_return(false)
      long_name = "a" * 60 # "#{long_name}_old" would be 64 chars, over the 63-char limit
      connection.change_index(:users,
                              from: { column: :a, name: long_name },
                              to: { column: :b, name: long_name },
                              algorithm: :concurrently)
      temp_name = connection.executed_statements.first[/RENAME TO "([^"]+)"/, 1]
      expect(temp_name.bytesize).to be <= 63
      expect(temp_name).to start_with("a" * 52).and match(/_[0-9a-f]{10}\z/)
    end

    it "skips the rename and the drop when if_exists is set and the old index is missing" do
      allow(connection).to receive_messages(index_name_exists?: false, index_exists?: false)
      connection.change_index(:users,
                              from: { column: :a, name: "same" },
                              to: { column: :b, name: "same" },
                              if_exists: true,
                              algorithm: :concurrently)
      expect(connection.executed_statements).to eq [
        'CREATE INDEX CONCURRENTLY IF NOT EXISTS "same" ON "users" ("b")'
      ]
    end

    it "ignores algorithm: :concurrently inside a transaction" do
      connection.transaction do
        connection.change_index(:users, from: :a, to: :b, algorithm: :concurrently)
      end
      expect(connection.executed_statements).to eq [
        "BEGIN",
        'DROP INDEX  "index_users_on_a"',
        'CREATE INDEX "index_users_on_b" ON "users" ("b")',
        "COMMIT"
      ]
    end

    it "is reversible by swapping from and to, keeping other arguments the same" do
      recorder = ActiveRecord::Migration::CommandRecorder.new(connection)
      recorder.revert do
        recorder.change_index(:users, from: :a, to: :b, if_exists: true, algorithm: :concurrently)
      end
      expect(recorder.commands).to eq(
        [[:change_index, [:users, { from: :b, to: :a, if_exists: true, algorithm: :concurrently }]]]
      )
    end
  end
end
