module ReadingStorable
  extend ActiveSupport::Concern

  included do
    enumerize :indicator_name, in: Nomen::Indicators.all, default: Nomen::Indicators.default, predicates: {prefix: true}
    enumerize :indicator_datatype, in: Nomen::Indicators.datatype.choices, predicates: {prefix: true}
    enumerize :measure_value_unit, in: Nomen::Units.all, predicates: {prefix: true}

    composed_of :measure_value, class_name: "Measure", mapping: [%w(measure_value_value to_d), %w(measure_value_unit unit)]
    composed_of :absolute_measure_value, class_name: "Measure", mapping: [%w(absolute_measure_value_value to_d), %w(absolute_measure_value_unit unit)]
    # composed_of :reading, mapping: [%w(indicator_name name), %w(value value)]

    # set_rgeo_factory_for_column(:point_value, RGeo::Geographic.spherical_factory(srid: 4326))
    # set_rgeo_factory_for_column(:geometry_value, RGeo::Geographic.spherical_factory(srid: 4326))

    validates_inclusion_of :indicator_name, in: self.indicator_name.values
    validates_inclusion_of :indicator_datatype, in: self.indicator_datatype.values

    validates_inclusion_of :boolean_value, in: [true, false], :if => :indicator_datatype_boolean?
    validates_presence_of :choice_value,   :if => :indicator_datatype_choice?
    validates_presence_of :decimal_value,  :if => :indicator_datatype_decimal?
    validates_presence_of :geometry_value, :if => :indicator_datatype_geometry?
    validates_presence_of :integer_value,  :if => :indicator_datatype_integer?
    validates_presence_of :measure_value, :absolute_measure_value, :if => :indicator_datatype_measure?
    # validates_presence_of :multi_polygon_value, :if => :indicator_datatype_multi_polygon?
    validates_presence_of :point_value,    :if => :indicator_datatype_point?
    validates_presence_of :string_value,   :if => :indicator_datatype_string?

    # Keep this format to ensure inheritance
    before_validation :set_datatype
    before_validation :absolutize_measure
    validate :validate_value
  end

  def set_datatype
    self.indicator_datatype = self.indicator.datatype
  end

  def absolutize_measure
    if self.indicator_datatype_measure? and self.measure_value.is_a?(Measure)
      self.absolute_measure_value = self.measure_value.in(self.indicator.unit)
    end
  end

  def validate_value
    if self.indicator_datatype_measure?
      # TODO Check unit
      # errors.add(:unit, :invalid) if unit.dimension != indicator.unit.dimension
    end
  end

  # Read value from good place
  def value
    datatype = self.indicator_datatype || self.indicator.datatype
    self.send(datatype.to_s + '_value')
  end

  # Write value into good place
  def value=(object)
    datatype = (self.indicator_datatype || self.indicator.datatype).to_sym
    if object.is_a?(String)
      if datatype == :measure
        object = Measure.new(object)
      elsif datatype == :boolean
        object = ["1", "ok", "t", "true", "y", "yes"].include?(object.to_s.strip.downcase)
      elsif datatype == :geometry
        if object =~ /\A[A-F0-9]+\z/
          srid =  LandParcel.connection.select_value("SELECT ST_SRID(ST_GeomFromEWKB(E'\\\\x#{object}'))").to_i
          srid = 2154 if srid.zero?
          wkt =   LandParcel.connection.select_value("SELECT ST_AsText(ST_Force_2D(ST_GeomFromEWKB(E'\\\\x#{object}')))")
          object = ::RGeo::Cartesian.preferred_factory(srid: srid).parse_wkt(wkt)
          puts "SRID: #{srid.inspect}, WKT: #{wkt.inspect}" if object.nil?
        else
          raise "Cannot parse #{object.inspect}"
        end
      elsif datatype == :decimal
        object = object.to_d
      elsif datatype == :integer
        object = object.to_i
      end
    end
    if object and datatype == :geometry
      # factory = RGeo::Geographic.spherical_factory(srid: 4326, proj4: wgs84_proj4, coord_sys: wgs84_wkt)
      # puts object.factory.proj4.inspect
      factory = RGeo::Geographic.simple_mercator_factory
      if new_object = RGeo::Feature.cast(object, factory: factory, project: true)
        object = new_object
      else
        puts "--- " + object.inspect
        puts "+++ " + new_object.inspect
      end
      # raise "Stop"
    end
    self.send("#{datatype}_value=", object)
  end

  # # Retrieve datatype from nomenclature NOT from database
  # def theoric_datatype
  #   self.indicator.datatype.to_sym
  # end

  def indicator
    Nomen::Indicators[self.indicator_name]
  end

  def indicator=(item)
    self.indicator_name = item.name
  end

  def indicator_human_name
    self.indicator.human_name
  end

  # methods defined here are going to extend the class, not the instance of it
  module ClassMethods

    def value_column(indicator_name)
      unless indicator = Nomen::Indicators[indicator_name]
        raise ArgumentError, "Expecting an indicator name. Got #{indicator_name.inspect}."
      end
      return {measure: :measure_value_value}[indicator.datatype] || "#{indicator.datatype}_value".to_sym
    end

    def indicator_table_name(indicator_name)
      table_name
    end

  end

end