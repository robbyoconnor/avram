class Avram::QueryBuilder
  alias ColumnName = Symbol | String
  getter table
  @limit : Int32?
  @offset : Int32?
  @wheres = [] of Avram::Where::SqlClause
  @raw_wheres = [] of Avram::Where::Raw
  @joins = [] of Avram::Join::SqlClause
  @orders = [] of Avram::OrderBy
  @groups = [] of ColumnName
  @selections : String = "*"
  @prepared_statement_placeholder = 0
  @distinct : Bool = false
  @delete : Bool = false
  @distinct_on : String | Symbol | Nil = nil

  def initialize(@table : Symbol)
  end

  def to_sql
    [statement] + args
  end

  # Merges the wheres, raw wheres, joins, and orders from the passed in query
  def merge(query_to_merge : Avram::QueryBuilder)
    query_to_merge.wheres.each do |where|
      where(where)
    end

    query_to_merge.raw_wheres.each do |where|
      raw_where(where)
    end

    query_to_merge.joins.each do |join|
      join(join)
    end

    query_to_merge.orders.each do |order|
      order_by(order)
    end

    query_to_merge.groups.each do |group|
      group_by(group)
    end
  end

  # Similar to `merge`, but includes ALL query parts
  def clone(query_to_merge : Avram::QueryBuilder)
    merge(query_to_merge)
    self.select(query_to_merge.selects)
    limit(query_to_merge.limit)
    offset(query_to_merge.offset)
  end

  def statement
    join_sql [@delete ? delete_sql : select_sql] + sql_condition_clauses
  end

  def statement_for_update(params)
    join_sql ["UPDATE #{table}", set_sql_clause(params)] + sql_condition_clauses + ["RETURNING #{@selections}"]
  end

  def args_for_update(params)
    param_values(params) + prepared_statement_values
  end

  private def param_values(params)
    params.values.map do |value|
      case value
      when Nil
        nil
      when JSON::Any
        value.to_json
      else
        value.to_s
      end
    end.to_a
  end

  private def set_sql_clause(params)
    "SET " + params.map do |key, value|
      "#{key} = #{next_prepared_statement_placeholder}"
    end.join(", ")
  end

  private def join_sql(clauses)
    clauses.reject do |clause|
      clause.nil? || clause.blank?
    end.join(" ")
  end

  def args
    prepared_statement_values
  end

  private def sql_condition_clauses
    [joins_sql, wheres_sql, group_sql, order_sql, limit_sql, offset_sql]
  end

  def delete
    @delete = true
    self
  end

  def distinct
    @distinct = true
    self
  end

  def distinct_on(column : Symbol | String)
    @distinct_on = column
    self
  end

  private def distinct?
    @distinct || @distinct_on
  end

  def limit
    @limit
  end

  def limit(@limit)
    self
  end

  def offset
    @offset
  end

  def offset(@offset)
    self
  end

  def order_by(order : OrderBy)
    @orders << order
    self
  end

  def reset_order
    @orders.clear
  end

  def reverse_order
    @orders = @orders.map(&.reversed).reverse
    self
  end

  def order_sql
    if ordered?
      "ORDER BY " + orders.map(&.prepare).join(", ")
    end
  end

  def orders
    @orders.uniq!(&.column)
  end

  def group_by(column : ColumnName)
    @groups << column
    self
  end

  def group_sql
    if grouped?
      "GROUP BY " + groups.join(", ")
    end
  end

  def groups
    @groups
  end

  def grouped?
    @groups.any?
  end

  def select_count
    add_aggregate "COUNT(*)"
  end

  def select_min(column : ColumnName)
    add_aggregate "MIN(#{column})"
  end

  def select_max(column : ColumnName)
    add_aggregate "MAX(#{column})"
  end

  def select_average(column : ColumnName)
    add_aggregate "AVG(#{column})"
  end

  def select_sum(column : ColumnName)
    add_aggregate "SUM(#{column})"
  end

  private def add_aggregate(sql : String)
    raise_if_query_has_unsupported_statements
    @selections = sql
    reset_order
    self
  end

  private def raise_if_query_has_unsupported_statements
    if has_unsupported_clauses?
      raise Avram::UnsupportedQueryError.new(<<-ERROR
        Can't use aggregates (count, min, etc.) with limit or offset.

        Try calling 'results' on your query and use the Array and Enumerable
        methods in Crystal instead of using the database.
        ERROR
      )
    end
  end

  private def has_unsupported_clauses?
    @limit || @offset
  end

  def selects
    @selections
      .split(", ")
      .map { |column| column.split(".").last }
  end

  def select(selection : Array(Symbol | String))
    @selections = selection
      .map { |column| "#{@table}.#{column}" }
      .join(", ")
    self
  end

  def ordered?
    @orders.any?
  end

  private def select_sql
    String.build do |sql|
      sql << "SELECT "
      sql << "DISTINCT " if distinct?
      sql << "ON (#{@distinct_on}) " if @distinct_on
      sql << @selections
      sql << " FROM "
      sql << table
    end
  end

  private def limit_sql
    if @limit
      "LIMIT #{@limit}"
    end
  end

  private def offset_sql
    if @offset
      "OFFSET #{@offset}"
    end
  end

  def join(join_clause : Avram::Join::SqlClause)
    @joins << join_clause
    self
  end

  def joins
    @joins.uniq(&.to_sql)
  end

  private def joins_sql
    joins.map(&.to_sql).join(" ")
  end

  def where(where_clause : Avram::Where::SqlClause)
    @wheres << where_clause
    self
  end

  def raw_where(where_clause : Avram::Where::Raw)
    @raw_wheres << where_clause
    self
  end

  @_wheres_sql : String?

  private def wheres_sql
    @_wheres_sql ||= joined_wheres_queries
  end

  private def joined_wheres_queries
    if wheres.any? || raw_wheres.any?
      statements = wheres.map do |sql_clause|
        if sql_clause.is_a?(Avram::Where::NullSqlClause)
          sql_clause.prepare
        else
          sql_clause.prepare(next_prepared_statement_placeholder)
        end
      end
      statements += raw_wheres.map(&.to_sql)

      "WHERE " + statements.join(" AND ")
    end
  end

  def wheres
    @wheres.uniq { |where| where.prepare(prepared_statement_placeholder: "unused") + where.value.to_s }
  end

  def raw_wheres
    @raw_wheres.uniq(&.to_sql)
  end

  private def prepared_statement_values
    wheres.compact_map do |sql_clause|
      sql_clause.value unless sql_clause.is_a?(Avram::Where::NullSqlClause)
    end
  end

  private def next_prepared_statement_placeholder
    @prepared_statement_placeholder += 1
    "$#{@prepared_statement_placeholder}"
  end

  private def delete_sql
    "DELETE FROM #{table}"
  end
end
