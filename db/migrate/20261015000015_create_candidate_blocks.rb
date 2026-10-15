class CreateCandidateBlocks < ActiveRecord::Migration[8.1]
  def change
    create_table :candidate_blocks do |t|
      t.timestamps
    end

    add_reference :nodes, :candidate_block, null: true, foreign_key: true
  end
end
