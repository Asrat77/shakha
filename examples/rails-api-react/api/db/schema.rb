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

ActiveRecord::Schema[8.1].define(version: 2026_10_03_051428) do
  create_table "shakha_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "exchange_code"
    t.datetime "exchange_code_expires_at"
    t.string "ip_address"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id"
    t.index ["created_at"], name: "index_shakha_sessions_on_created_at"
    t.index ["exchange_code"], name: "index_shakha_sessions_on_exchange_code", unique: true
    t.index ["token"], name: "index_shakha_sessions_on_token", unique: true
    t.index ["user_id"], name: "index_shakha_sessions_on_user_id"
  end

  create_table "shakha_users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name"
    t.string "picture"
    t.string "provider", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_shakha_users_on_email"
    t.index ["provider", "uid"], name: "index_shakha_users_on_provider_and_uid", unique: true
  end

  add_foreign_key "shakha_sessions", "shakha_users", column: "user_id"
end
