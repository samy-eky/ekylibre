# -*- coding: utf-8 -*-
module Ekylibre
  DEMOS = [:general_ledger, :entities, :buildings, :products, :animals, :land_parcels, :productions, :analyses, :sales, :deliveries, :interventions]
  DEMOS_INTERVENTION = [:buildings, :products, :land_parcels, :productions, :deliveries, :interventions]

  MAX = -1

  class FixtureCountExceeded < StandardError
  end

  class Fixturize
    attr_reader :count

    def initialize(max = -1)
      @count = 0
      @max = max
    end

    def check_point(increment = 1)
      @count += increment
      print "." if (@count - increment).to_i != @count.to_i
      if @max > 0
        raise FixtureCountExceeded.new if @count >= @max
      end
    end
  end

  def self.fixturize(name, options = {}, &block)
    STDOUT.sync = true
    max = (options[:max] || ENV["max"]).to_i
    max = MAX if max.zero?
    f = Fixturize.new(max)
    start = Time.now
    label_size = options[:label_size] || 32
    label = name.to_s.humanize.rjust(label_size)
    if label.size > label_size
      first = ((label_size - 3).to_f / 2).round
      label = label[0..(first-1)] + "..." + label[-(label_size - first - 3)..-1]
      # label = "..." + label[(-label_size + 3)..-1]
    end
    # ActiveRecord::Base.transaction do
    print "#{label}: "
    begin
      yield(f)
      print " " * (max - f.count) if max != MAX and f.count < max
      print "  "
    rescue FixtureCountExceeded => e
      print "! "
    end
    # end
    puts "#{(Time.now - start).round(2).to_s.rjust(6)}s"
  end

end

require 'ostruct'
require 'pathname'

# Build a task with a transaction
def demo(name, &block)
  task(name => :environment) do
    ActiveRecord::Base.transaction(&block)
  end
end

namespace :db do
  task :demo do
    Rake::Task["demo"].invoke
  end
end

desc "Build demo data"
namespace :demo do
  for demo in Ekylibre::DEMOS
    require Pathname.new(__FILE__).dirname.join("demo", demo.to_s).to_s
  end

  desc "Create demo data for interventions/operations purpose only"
  task :operations => :environment do
    ActiveRecord::Base.transaction do
      for demo in Ekylibre::DEMOS_INTERVENTION
        Rake::Task["demo:#{demo}"].invoke
      end
    end
  end

end

desc "Create demo data -- also available " + Ekylibre::DEMOS.collect{|c| "demo:#{c}"}.join(", ")
task :demo => :environment do
  ActiveRecord::Base.transaction do
    for demo in Ekylibre::DEMOS
      Rake::Task["demo:#{demo}"].invoke
    end
  end
end

desc "Create demo data independently -- also available " + Ekylibre::DEMOS.collect{|c| "demo:#{c}"}.join(", ")
task :demos => :environment do
  for demo in Ekylibre::DEMOS
    puts " * Execute demo:#{demo} task"
    Rake::Task["demo:#{demo}"].invoke
  end
end

