# This migration comes from annotator_store (originally 20190430143309)
class AddAnnotatorLanguage < ActiveRecord::Migration[5.2]
  def change


    create_table :annotator_store_languages do |t|
      t.string :name, null: false
      t.string :locale, null: false
      t.timestamps
    end



  end
end
