RSpec.describe Buttress::Schema do
  it 'parses modern schema.rb table definitions' do
    schema = described_class.parse(<<~RUBY)
      ActiveRecord::Schema.define(version: 2020_01_01_000000) do
        create_table "users", force: :cascade do |t|
          t.string "name"
          t.integer "age"
          t.boolean "admin", default: false
          t.datetime "created_at", null: false
        end

        create_table "companies" do |t|
          t.text "description"
        end
      end
    RUBY

    expect(schema.columns_for('User')).to eq(
      name: :string, age: :integer, admin: :boolean, created_at: :datetime,
    )
    expect(schema.columns_for('Company')).to eq(description: :text)
  end

  it 'parses Rails 2-era t.column definitions' do
    schema = described_class.parse(<<~RUBY)
      ActiveRecord::Schema.define(:version => 20100101000000) do
        create_table "users", :force => true do |t|
          t.column "name", :string
          t.column "age", :integer
        end
      end
    RUBY

    expect(schema.columns_for('User')).to eq(name: :string, age: :integer)
  end

  it 'expands references into id columns' do
    schema = described_class.parse(<<~RUBY)
      ActiveRecord::Schema.define(version: 1) do
        create_table "posts" do |t|
          t.references "author"
          t.string "title"
        end
      end
    RUBY

    expect(schema.columns_for('Post')).to eq(author_id: :integer, title: :string)
  end

  it 'returns nil for classes without a table' do
    schema = described_class.parse('ActiveRecord::Schema.define(version: 1) {}')

    expect(schema.columns_for('Mystery')).to be_nil
  end

  it 'pluralizes table names from class names' do
    expect(Buttress::Inflector.tableize('User')).to eq('users')
    expect(Buttress::Inflector.tableize('Company')).to eq('companies')
    expect(Buttress::Inflector.tableize('Address')).to eq('addresses')
    expect(Buttress::Inflector.tableize('LineItem')).to eq('line_items')
  end
end
