class CreateSyncRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :sync_runs do |t|
      t.string :source, null: false, default: "artikon"
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.string :feed_etag
      t.string :feed_last_modified
      t.integer :items_seen, null: false, default: 0
      t.integer :items_created, null: false, default: 0
      t.integer :items_updated, null: false, default: 0
      t.integer :items_deactivated, null: false, default: 0
      t.integer :categories_created, null: false, default: 0
      t.integer :manufacturers_created, null: false, default: 0
      t.string :status, null: false, default: "running"
      t.jsonb :errors_log, null: false, default: []
      t.timestamps
    end
    add_index :sync_runs, :started_at
    add_index :sync_runs, [:source, :status]
  end
end
