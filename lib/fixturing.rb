require 'active_record/fixtures'

module Fixturing
  class << self

    def current_version
      CSV.read(migrations_file).last.first.to_i
    end

    def directory
      Rails.root.join("test", "fixtures")
    end

    def migrations_file
      directory.join(migrations_table)
    end

    def migrations_table
      "schema_migrations"
    end

    def up_to_date?
      current_version == ActiveRecord::Migrator.last_version
    end

    def tables_from_files
      return Dir.glob(directory.join("*.yml")).collect do |f|
        Pathname.new(f).basename(".*").to_s
      end.sort
    end

    def restore(tenant)
      Apartment.connection.execute("DROP SCHEMA IF EXISTS \"#{tenant}\" CASCADE")
      Apartment.connection.execute("CREATE SCHEMA \"#{tenant}\"")
      Ekylibre::Tenant.add(tenant)
      Apartment.connection.execute("SET search_path TO '#{tenant}, postgis'")
      Ekylibre::Tenant.migrate(tenant, to: current_version)
      # table_names = Ekylibre::Record::Base.connection.tables.delete_if{ |t| %w(schema_migrations spatial_ref_sys).include?(t) }
      table_names = tables_from_files
      say "Load fixtures"
      Ekylibre::Tenant.switch!(tenant)
      ActiveRecord::FixtureSet.create_fixtures(directory, table_names)
      unless up_to_date?
        migrate(tenant)
      end
    end

    def reverse(tenant, steps = 1)
      restore(tenant)
      rollback(tenant, steps)
    end

    # Dump data of database into fixtures
    def dump(tenant)
      Ekylibre::Tenant.switch!(tenant)

      migrate(tenant) unless up_to_date?

      backup = "#{directory.to_s}~"
      FileUtils.rm_rf(backup)
      FileUtils.cp_r(directory, backup)
      Dir[directory.join("*.yml").to_s].each do |f|
        FileUtils.rm_rf(f)
      end

      # ActiveRecord::Base.establish_connection(:development)
      Ekylibre::Schema.tables.each do |table, columns|
        records = {}
        for row in ActiveRecord::Base.connection.select_all("SELECT * FROM #{table} ORDER BY id")
          record = {}
          for attribute, value in row.sort
            if columns[attribute]
              unless value.nil?
                type = columns[attribute].type
                type = columns[attribute].limit[:type] if columns[attribute].limit.is_a?(Hash)
                record[attribute] = convert_value(value, type.to_sym)
              end
            else
              puts "Cannot find column '#{attribute}' in #{table}. Run `rake clean:schema`.".red
            end
          end
          records["#{table}_#{row['id'].rjust(3, '0')}"] = record
        end

        File.open(directory.join("#{table}.yml"), "wb") do |f|
          f.write records.to_yaml.gsub(/[\ \t]+\n/, "\n")
        end
      end

      # Dump last schema_migrations into schema_migrations file
      File.open(migrations_file, "wb") do |f|
        f.write ActiveRecord::Base.connection.select_value("SELECT * FROM #{migrations_table} ORDER BY 1 DESC")
      end

      # Clean fixtures
      # reflectionize_keys
      beautify_fixture_ids
    end


    def migrate(tenant)
      target = ActiveRecord::Migrator.last_version
      origin = current_version
      if target != origin
        say "Migrate fixtures from " + origin.inspect + " to " + target.inspect
        Ekylibre::Tenant.switch(tenant) do
          ActiveRecord::Migrator.migrate(ActiveRecord::Migrator.migrations_paths, target)
        end
      else
        say "No more migrations", :green
      end
    end

    def rollback(tenant, steps = 1)
      say "Rollback (Steps count: #{steps})"
      Ekylibre::Tenant.switch(tenant) do
        ActiveRecord::Migrator.rollback(ActiveRecord::Migrator.migrations_paths, steps)
      end
    end

    def say(text, color = :yellow)
      size = text.size
      puts "== " + text.send(color) + " " + "=" * (79 - size - 4) + "\n\n"
    end


    # Convert reflection to hard representation in fixtures
    #   my_thing: things_001             => my_thing_id: 1
    #   my_polymorph: things_001 (Thing) => my_polymorph_id: 1
    #                                       my_polymorph_type: Thing
    def columnize_keys
      # Load and prepare fixtures
      data = {}
      Ekylibre::Schema.tables.each do |table, columns|
        records = YAML.load_file(directory.join("#{table}.yml"))
        ids = records.values.collect{|a| a["id"]}.compact.map(&:to_i)
        records.each do |record, attributes|
          unless attributes["id"]
            id = record.split("_").last.to_i
            attributes["id"] = ids.include?(id) ? (1..(ids.max + 10)).to_a.detect{|x| !ids.include?(x) } : id
            ids << attributes["id"]
          end
        end
        data[table.to_s] = records
      end

      # Convert
      Ekylibre::Schema.tables.each do |table, columns|
        columns.each do |column, definition|
          next unless references = definition[:references]
          if references.is_a?(Symbol)
            # Standard reflection case
            foreign_model = references.to_s.camelcase.constantize
            puts references.inspect.red unless data[foreign_model.table_name]
            data[table.to_s].each do |record, attributes|
              reflection = column.to_s.gsub(/\_id\z/, '')
              next unless fixture_id = attributes[reflection]
              if attrs = data[foreign_model.table_name][fixture_id]
                attributes[column.to_s] = attrs["id"]
              else
                raise "Cannot find #{fixture_id} for #{references} in #{table}##{record}"
              end
              attributes.delete(reflection)
            end
          else
            # Polymorphic reflection case
            data[table.to_s].each do |record, attributes|
              reflection = column.to_s.gsub(/\_id\z/, '')
              next unless attributes[reflection]
              type_column = reflection + "_type"
              fixture_id, class_name = attributes[reflection].split(/[\(\)\s]+/)[0..1]
              foreign_model = class_name.constantize
              if attrs = data[foreign_model.table_name][fixture_id]
                attributes[column.to_s] = attrs["id"]
                attributes[type_column] = foreign_model.name
              else
                raise "Cannot find #{fixture_id} for #{references} in #{table}##{record}"
              end
              attributes.delete(reflection)
            end
          end
        end
        data[table.to_s].each do |record, attributes|
          data[table.to_s][record] = attributes.sort{|a,b| a.first <=> b.first }.inject({}) do |hash, pair|
            hash[pair.first] = pair.second
            hash
          end
        end
      end

      # Write
      Ekylibre::Schema.tables.each do |table, columns|
        File.open(directory.join("#{table}.yml"), "wb") do |f|
          f.write data[table].to_yaml
        end
      end

      # Clean
      Clean::Annotations.run(only: :fixtures, verbose: false)
    end

    # Reverse of #columnize_keys
    # Fixtures are expected with ids !
    def reflectionize_keys
      # Load and prepare fixtures
      data = {}
      model_ids = {}
      Ekylibre::Schema.tables.each do |table, columns|
        records = YAML.load_file(directory.join("#{table}.yml"))
        base_model = table.to_s.classify
        counter = {}
        data[table.to_s] = records.values.sort{|a,b| [a["type"] || base_model, a["id"]] <=> [b["type"] || base_model, b["id"]] }.inject({}) do |hash, attributes|
          model = attributes["type"] ? attributes["type"].underscore.pluralize : table.to_s
          counter[model] ||= 0
          counter[model] += 1
          hash["#{model}_#{counter[model].to_s.rjust(3, '0')}"] = attributes
          hash
        end
      end

      # Convert
      Ekylibre::Schema.tables.each do |table, columns|
        columns.each do |column, definition|
          next unless references = definition[:references]
          if references.is_a?(Symbol)
            # Standard reflection case
            foreign_model = references.to_s.camelcase.constantize
            puts references.inspect.red unless data[foreign_model.table_name]
            data[table.to_s].each do |record, attributes|
              next unless fixture_id = attributes[column.to_s]
              if attrs = data[foreign_model.table_name].detect{|r, a| a["id"] == fixture_id}
                attributes[column.to_s.gsub(/\_id\z/, '')] = attrs.first
              else
                raise "Cannot find #{foreign_model.name} #{fixture_id} for #{column} in #{table}##{record}"
              end
              attributes.delete(column.to_s)
            end
          else
            # Polymorphic reflection case
            data[table.to_s].each do |record, attributes|
              type_column = column.to_s.gsub(/\_id\z/, '') + "_type"
              next unless fixture_id = attributes[column.to_s] and fixture_type = attributes[type_column]
              foreign_model = fixture_type.constantize
              if attrs = data[foreign_model.table_name].detect{|r,a| a["id"] == fixture_id and (a["type"] || foreign_model.name) == fixture_type}
                attributes[column.to_s.gsub(/\_id\z/, '')] = "#{attrs.first} (#{fixture_type})"
              else
                raise "Cannot find #{fixture_type}##{fixture_id} for #{column} in #{table}##{record} (#{attributes['id']})"
              end
              attributes.delete(column.to_s)
              attributes.delete(type_column)
            end
          end
        end
      end

      data.each do |table, records|
        records.each do |record, attributes|
          data[table][record] = attributes.delete_if{|k,v| k == "id" }.sort{|a,b| a.first <=> b.first }.inject({}) do |hash, pair|
            hash[pair.first] = pair.second
            hash
          end
        end
      end

      # Write
      Ekylibre::Schema.tables.each do |table, columns|
        File.open(directory.join("#{table}.yml"), "wb") do |f|
          f.write data[table].to_yaml
        end
      end

      # Clean
      Clean::Annotations.run(only: :fixtures, verbose: false)
    end










    # Adds model conform fixture ids
    def beautify_fixture_ids
      # Load and prepare fixtures
      data = {}
      model_ids = {}
      Ekylibre::Schema.tables.each do |table, columns|
        records = YAML.load_file(directory.join("#{table}.yml"))
        base_model = table.to_s.classify
        counter = {}
        data[table.to_s] = records.values.sort{|a,b| [a["type"] || base_model, a["id"]] <=> [b["type"] || base_model, b["id"]] }.inject({}) do |hash, attributes|
          model = attributes["type"] ? attributes["type"].underscore.pluralize : table.to_s
          counter[model] ||= 0
          counter[model] += 1
          hash["#{model}_#{counter[model].to_s.rjust(3, '0')}"] = attributes
          hash
        end
      end

      data.each do |table, records|
        records.each do |record, attributes|
          data[table][record] = attributes.sort{|a,b| a.first <=> b.first }.inject({}) do |hash, pair|
            hash[pair.first] = pair.second
            hash
          end
        end
      end

      # Write
      Ekylibre::Schema.tables.each do |table, columns|
        File.open(directory.join("#{table}.yml"), "wb") do |f|
          f.write data[table].to_yaml
        end
      end

      # Clean
      Clean::Annotations.run(only: :fixtures, verbose: false)
    end






    def yaml_escape(value, type = :string)
      value = value.to_s
      value = if type == :float or type == :decimal or type == :integer
                value
              elsif type == :boolean
                (['1', 't', 'T', 'true', 'yes', 'TRUE'].include?(value) ? 'true' : 'false')
              else
                value.to_yaml.gsub(/^\-\-\-\s*/, '').strip
              end
      return value
    end

    def convert_value(value, type = :string)
      value = value.to_s
      value = if type == :float
                value.to_f
              elsif type == :geometry or type == :point
                Charta::Geometry.new(value).to_ewkt
              elsif type == :decimal
                value.to_f
              elsif type == :integer
                value.to_i
              elsif type == :date
                value.to_date
              elsif type == :datetime
                value.to_time(:utc)
              elsif type == :boolean
                (['1', 't', 'T', 'true', 'yes', 'TRUE'].include?(value) ? true : false)
              else
                puts type.inspect.red unless type == :string or type == :text
                value =~ /\A\-\-\-(\s+|\z)/ ? YAML.load(value) : value
              end
      return value
    end

  end
end
