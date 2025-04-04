class CreateOrders < ActiveRecord::Migration[7.1]
  def change
    create_table :orders do |t|
      t.string :type
      t.integer :user_id, null: false
      t.integer :status, default: 0
      t.float :amount
      t.boolean :flag
      t.integer :priority

      t.timestamps
    end
  end

  def down
    drop_table :orders if ActiveRecord::Base.connection.table_exists?(:orders)
  end
end
