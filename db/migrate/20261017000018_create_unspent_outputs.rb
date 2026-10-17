class CreateUnspentOutputs < ActiveRecord::Migration[8.1]
  def up
    if connection.select_value("SELECT COUNT(*) FROM transactions").positive?
      raise ActiveRecord::MigrationError, "Unspent output migration requires an empty transactions table"
    end

    create_table :unspent_outputs, primary_key: [:transaction_id, :output_index], options: "WITHOUT ROWID" do |t|
      t.string :transaction_id, limit: 64, null: false
      t.integer :output_index, null: false
      t.foreign_key :transactions, on_delete: :cascade
      t.check_constraint "typeof(output_index) = 'integer' AND output_index BETWEEN 0 AND 4294967295", name: "unspent_outputs_position"
    end
  end

  def down
    drop_table :unspent_outputs
  end
end
