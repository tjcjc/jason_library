#encoding: utf-8
require 'opml-handler'
tables = Array.new

def parse_table table_name, columns, indexes
    {columns: columns, name: table_name, indexes: indexes}
end

def parse_type type
    column_type = Hash.new
    if s = type.match(/\(([\d|\,]+)\)/)
        column_type[:limit] = s[1]
        if not column_type[:limit].index(",")
            column_type[:limit] = s[1].to_i
        end
    end
    column_type[:type] = type.split("(")[0]
    case column_type[:type]
    when "tinyint"
        column_type[:type] = "integer"
        column_type[:limit] = 1
    when "smallint"
        column_type[:type] = "integer"
        column_type[:limit] = 2
    when "mediumint"
        column_type[:type] = "integer"
        column_type[:limit] = 3
    when "bigint"
        column_type[:type] = "integer"
    when "int"
        column_type[:type] = "integer"
        column_type[:limit] = 4
    when "decimal", "float", "double"
        a = column_type[:limit].split(",")
        column_type[:type] = "decimal"
        column_type[:limit] = nil
        column_type[:precision] = a[0].to_i
        column_type[:scale] = a[1].to_i
    when "varchar"
        column_type[:type] = "string"
    when "text,", "text"
        column_type[:type] = "text"
    when "char"
        column_type[:type] = "string"
    when "blob", "blob,"
        column_type[:type] = "binary"
    when "date"
    when "longtext"
        column_type[:limit] = 4294967295
        column_type[:type] = "text"
    else
    end
    column_type
end

def parse_column line
    column = Hash.new
    s = line.match(/`([\w|_]+)` ([\w|\(|\)|\d|\,]+)/)
    column_type = parse_type s[2]
    column_type.each do |k, v|
        column[k] = v
    end
    column[:name] = s[1]
    if line.match(/NOT NULL/)
        column[:null] = false
    end
    if default = line.match(/DEFAULT '([\w|_|\d|\s]+)'/)
        column[:default] = default[1]
        if not column[:default] =~ /\d/
            column[:default] = "''"
        end
    end
    column
end

def parse_index line
    index = Hash.new
    if s = line.match(/PRIMARY KEY \(([`|\w|\,]+)\)/)
        index[:primary] = true
        index[:columns] = s[1].split(",").map do |key|
            key = key[1...-1]
            key
        end
    elsif s = line.match(/KEY `([\w|_]+)` \(([`|\w|\,|\(|\)|\d]+)\)/)
        if line.match(/UNIQUE KEY/)
            index[:uniq] = true
        end
        index[:name] = s[1]
        index[:columns] = s[2].split(",").map do |key|
            if l = key.match(/`([\w|_]+)`\((\d+)\)/)
                key_name = l[1]
                index[:length] ||= Hash.new
                index[:length][key_name] = l[2].to_i
                key = key_name
            else
                key = key[1...-1]
            end
            key
        end
    end
    index
end

def create_table file, table_name, tables
    columns = []
    indexes = []
    while line = file.gets do
        if line.match(/PRIMARY KEY/)
            indexes << parse_index(line)
        elsif line.match(/KEY/)
            indexes << parse_index(line)
        elsif line.match(/^\) ENGINE=/)
            break
        else
            columns << parse_column(line)
        end

    end

    tables << parse_table(table_name, columns, indexes)
end

File.open("./init.sql") do |f|
    while (line = f.gets) do
            if s = line.match(/CREATE TABLE IF NOT EXISTS `([\w|_]+)`/)
                create_table(f, s[1], tables)
            end
        end
    end

    keys = [:limit, :default, :precision, :scale]

    create_strs = ""
    tables.each do |table|
        indexes = []
        options = ""
        columns = []
        table[:indexes].each do |index|
            if index[:primary]
                if index[:columns].count == 1
                    columns << "t.primary_key :#{index[:columns][0]}"
                    table[:columns].delete_if do |c|
                        index[:columns][0] == c[:name]
                    end
                else
                    strs = index[:columns].map{|i|":#{i}"}.join(", ")
                    indexes << "add_index(:#{table[:name]}, [#{strs}], unique:true)"
                end
                options += ",id: false"
            else
                uniq_str = index[:uniq] ? "true" : "false"
                lenght_str = ""
                if index[:length]
                    lenght_str = ", length: #{index[:length].each do |k, v|
                                "#{k}: #{v}"
                    end}"
                end
                strs = index[:columns].map{|i|":#{i}"}.join(", ")
                indexes << "add_index(:#{table[:name]}, [#{strs}], unique:#{uniq_str} #{lenght_str})"
            end
        end
        columns << table[:columns].map do |c|
            if c[:type] == "integer"
                s = "\tt.column :#{c[:name]}, 'integer unsigned'"
            else
                s = "\tt.#{c[:type]} :#{c[:name]}"
            end
            keys.each do |k|
                s << ", #{k.to_s}:#{c[k]}" if c[k]
            end
            s
        end
        create_strs += <<-EOF
create_table :#{table[:name]} #{options} do |t|
    #{columns.join("\n")}
end
    EOF
    create_strs += indexes.join("\n")
    create_strs += "\n"
end

f = File.open("new_data.rb", "w")
f.puts create_strs
f.close

nodes = Array.new
tables.each do |table|
    node = {text:table[:name].gsub("dgg_", "")}
    children = Array.new
    columns = table[:columns].map do |column|
        {text: column[:name], children:[]}
    end
    indexes = table[:indexes].map do |index|
        {text: (index[:primary] ? "主键" : index[:name]), _node: index[:columns].join(","), children:[]}
    end
    children << {text: "字段", children: columns}
    children << {text: "索引", children: indexes}
    node[:children] = children
    nodes << node
end
opml = OpmlHandler::Opml.new(outlines_attributes: nodes, title: "藏村数据库结构")

f = File.new("database.opml", "w")
f.puts opml.to_xml
f.close
