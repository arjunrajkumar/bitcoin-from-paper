# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_15_000012) do
  create_table "blocks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "header", default: {"transactions_hash" => nil, "created_at" => nil}, null: false
  end

  create_table "transactions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "public_key"
    t.text "digital_signature"
    t.integer "input_count"
    t.decimal "receiver_output_value", precision: 20, scale: 8
    t.json "input_transaction_ids", default: []
    t.integer "block_id"
    t.index ["block_id"], name: "index_transactions_on_block_id"
  end

  add_foreign_key "transactions", "blocks"
end
