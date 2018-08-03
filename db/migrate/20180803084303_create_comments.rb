class CreateComments < ActiveRecord::Migration[5.1]
  def change
    create_table :comments do |t|
      t.string :body
      t.belongs_to :post, foreign_key: true

      t.timestamps
    end
  end
end
