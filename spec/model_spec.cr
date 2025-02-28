require "./spec_helper"

class NamedSpaced::Model < BaseModel
  table do
  end
end

private class QueryMe < BaseModel
  COLUMN_SQL = "users.id, users.created_at, users.updated_at, users.email, users.age"

  table :users do
    column email : CustomEmail
    column age : Int32
  end
end

private class EmptyModelCompilesOk < BaseModel
  table :no_fields do
  end
end

private class InferredTableNameModel < BaseModel
  COLUMN_SQL = "inferred_table_name_models.id, inferred_table_name_models.created_at, inferred_table_name_models.updated_at"

  table do
  end
end

describe Avram::Model do
  it "compares with id and model name, not just id" do
    user = UserBox.create
    post = PostBox.create

    user.id.should eq(post.id)
    user.should_not eq(post)
  end

  it "sets up initializers based on the columns" do
    now = Time.utc

    user = User.new id: 123_i64,
      name: "Name",
      age: 24,
      joined_at: now,
      created_at: now,
      updated_at: now,
      nickname: "nick",
      average_score: nil

    user.name.should eq "Name"
    user.age.should eq 24
    user.joined_at.should eq now
    user.updated_at.should eq now
    user.created_at.should eq now
    user.nickname.should eq "nick"
  end

  it "can be used for params" do
    now = Time.utc

    user = User.new id: 123_i64,
      name: "Name",
      age: 24,
      joined_at: now,
      created_at: now,
      updated_at: now,
      nickname: "nick",
      average_score: nil

    user.to_param.should eq "123"
  end

  it "sets up getters that parse the values" do
    user = QueryMe.new id: 123_i64,
      created_at: Time.utc,
      updated_at: Time.utc,
      age: 30,
      email: " Foo@bar.com "

    user.email.should be_a(CustomEmail)
    user.email.to_s.should eq "foo@bar.com"
  end

  it "sets up simple methods for equality" do
    query = QueryMe::BaseQuery.new.email("foo@bar.com").age(30)

    query.to_sql.should eq ["SELECT #{QueryMe::COLUMN_SQL} FROM users WHERE users.email = $1 AND users.age = $2", "foo@bar.com", "30"]
  end

  it "sets up advanced criteria methods" do
    query = QueryMe::BaseQuery.new.email.upper.eq("foo@bar.com").age.gt(30)

    query.to_sql.should eq ["SELECT #{QueryMe::COLUMN_SQL} FROM users WHERE UPPER(users.email) = $1 AND users.age > $2", "foo@bar.com", "30"]
  end

  it "parses values" do
    query = QueryMe::BaseQuery.new.email.upper.eq(" Foo@bar.com").age.gt(30)

    query.to_sql.should eq ["SELECT #{QueryMe::COLUMN_SQL} FROM users WHERE UPPER(users.email) = $1 AND users.age > $2", "foo@bar.com", "30"]
  end

  it "lets you order by columns" do
    query = QueryMe::BaseQuery.new.age.asc_order.email.desc_order

    query.to_sql.should eq ["SELECT #{QueryMe::COLUMN_SQL} FROM users ORDER BY users.age ASC, users.email DESC"]
  end

  it "can be deleted" do
    UserBox.create
    user = UserQuery.new.first

    user.delete

    User::BaseQuery.all.size.should eq 0
  end

  describe ".column_names" do
    it "returns list of mapped columns" do
      QueryMe.column_names.should eq [:id, :created_at, :updated_at, :email, :age]
    end
  end

  describe "models with uuids" do
    it "sets up initializers accepting uuid strings" do
      uuid = UUID.new("a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11")
      LineItem.new(uuid.to_s, Time.utc, Time.utc, "hello")
    end

    it "can be saved" do
      uuid_regexp = /\w+/
      LineItemBox.create

      item = LineItemQuery.new.first
      item.id.to_s.should match(uuid_regexp)
    end

    it "can be deleted" do
      LineItemBox.create

      item = LineItemQuery.new.first
      item.delete

      LineItem::BaseQuery.all.size.should eq 0
    end
  end

  it "can infer the table name when omitted" do
    InferredTableNameModel.table_name.should eq(:inferred_table_name_models)
  end

  it "can infer table name for namedspaced models" do
    NamedSpaced::Model.table_name.should eq(:named_spaced_models)
  end
end
