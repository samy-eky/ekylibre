require 'coveralls'
Coveralls.wear!('rails')
ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'
require 'capybara/rails'

# Permits to test locales
if ENV['LOCALE']
  I18n.locale = ENV['LOCALE']
end

# Configure tenants.yml
Ekylibre::Tenant.setup!("sekindovall")
Ekylibre::Tenant.setup!("test", keep_files: true)

class FixtureRetriever
  ROLES = %w(zeroth first second third fourth fifth sixth seventh eighth nineth tenth)
  @@truc = {}

  def initialize(model, options = {}, fixture_options = nil)
    if model and model < Ekylibre::Record::Base
      fixture_options ||= {}
      @model  = fixture_options.delete(:model)  || model
      @prefix = fixture_options.delete(:prefix) || @model.name.underscore.pluralize
      @table  = fixture_options.delete(:table)  || @model.table_name
      if options and !options.is_a?(Hash)
        options = {first: normalize(options)}
      end
      @options = options || {}
    end
  end

  def retrieve(role = :first, default_value = nil)
    if @model
      "#{@table}(#{normalize(@options[role] || default_value || role).inspect})"
    else
      raise "No valid model given, cannot retrieve fixture from that"
    end
  end

  protected

  def normalize(value)
    if value.is_a?(Integer)
      unless @@truc[@table]
        @@truc[@table] = YAML.load_file(Rails.root.join("test", "fixtures", "#{@table}.yml")).inject({}) do |hash, pair|
          hash[pair.second["id"].to_i] = pair.first.to_sym
          hash
        end
      end
      unless name = @@truc[@table][value]
        raise "Cannot find fixture in #{@table} with id=#{value.inspect}"
      end
      return name
    elsif value.is_a?(Symbol)
      if ROLES.include?(value.to_s)
        return "#{@prefix}_#{ROLES.index(value.to_s).to_s.rjust(3, '0')}".to_sym
      elsif value.to_s =~ /^\d+$/
        return "#{@prefix}_#{value.to_s.rjust(3, '0')}".to_sym
      else
        return value
      end
    elsif value.is_a?(CodeString)
      return value
    else
      raise "What kind of value (#{value.class.name}:#{value.inspect})"
    end
  end

end


class ActiveSupport::TestCase
  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  # Add more helper methods to be used by all tests here...

  # Returns ID of the given label
  def self.identify(label)
    # ActiveRecord::FixtureSet.identify(label)
    elements = label.to_s.split("_")
    id = elements.delete_at(-1)
    model = elements.join("_").classify.constantize
    @@fixtures ||= {}
    @@fixtures[model.table_name] ||= YAML.load_file(Rails.root.join("test", "fixtures", "#{model.table_name}.yml"))
    unless attrs = @@fixtures[model.table_name][label.to_s]
      raise "Unknown fixture #{label}"
    end
    return attrs['id'].to_i
  end

end


class HashCollector

  def initialize
    @hash = {}
  end

  def to_hash
    return @hash
  end

  def method_missing(method_name, *args, &block)
    @hash[method_name.to_sym] = args.first
  end

end


class ActionController::TestCase
  include Devise::TestHelpers

  class << self

    def test_restfully_pasteque_actions(options = {})
      # test_restfully_all_actions({strictness: :api, params: {format: :json, user: "admin@ekylibre.org", password: "12345678"}, sign_in: false}.deep_merge(options))
    end



    def test_restfully_all_actions(options = {}, &block)
      controller_name = self.controller_class.controller_name
      controller_path = self.controller_class.controller_path
      table_name = options.delete(:table_name) || controller_name
      model_name = options.delete(:class_name) || table_name.classify
      model = model_name.constantize rescue nil
      record = model_name.underscore
      other_record = "other_#{record}"
      attributes = nil
      file_columns = {}
      if model and model < ActiveRecord::Base
        table_name = model.table_name
        if model.respond_to?(:attachment_definitions)
          unless model.attachment_definitions.nil?
            file_columns = model.attachment_definitions
          end
        end
        attributes = model.content_columns.map(&:name).map(&:to_sym).delete_if{|c|
          [:depth, :lft, :rgt].include?(c)
        }
        attributes += options.delete(:other_attributes) || []
        attributes = ("{" + attributes.map(&:to_sym).uniq.collect do |a|
                        if file_columns[a]
                          "#{a}: fixture_file_upload('files/sample_image.png')"
                        else
                          "#{a}: #{record}.#{a}"
                        end
                      end.join(", ")+ "}").c
      end

      if block_given?
        collector = HashCollector.new
        yield collector
        options.update(collector.to_hash)
      end

      code  = ""

      code << "setup do\n"
      code << "  Ekylibre::Tenant.switch!('test')\n"
      # Check locale
      # code << "  @locale = I18n.locale = ENV['LOCALE'] || I18n.default_locale\n"
      code << "  @locale = ENV['LOCALE'] || I18n.default_locale\n"
      # code << "  assert_not_nil I18n.locale\n"
      # code << "  assert_equal I18n.locale, I18n.locale, I18n.locale.inspect\n"
      # Check document templates
      # code << "  DocumentTemplate.load_defaults(locale: I18n.locale)\n"
      unless options[:sign_in].is_a?(FalseClass)
        # Connect user
        code << "  @user = users(:users_001)\n"
        code << "  sign_in(@user)\n"
      end
      # Setup finished!
      code << "end\n"
      code << "\n"

      unless options[:sign_in].is_a?(FalseClass)
        code << "teardown do\n"
        code << "  sign_out(@user)\n"
        code << "end\n"
        code << "\n"
      end

      code << "def beautify(value, back = true)\n"
      code << "  if value.is_a?(Hash)\n"
      code << "    (back ? \"\\n\" : '') + value.map{|k,v| \"\#{k.to_s.yellow}: \#{beautify(v)}\"}.join(\"\\n\").dig\n"
      code << "  elsif value.is_a?(Array)\n"
      code << "    (back ? \"\\n\" : '') + value.map{|v| \"- \#{beautify(v)}\"}.join(\"\\n\").dig\n"
      code << "  elsif value.is_a?(ActiveRecord::Base)\n"
      code << "    \"\#{value.class.name} #\#{value.id}\" + (value.errors.any? ? '. Errors: ' + value.errors.full_messages.to_sentence.red : '')"
      code << "  else\n"
      code << "    value.inspect\n"
      code << "  end\n"
      code << "end\n"
      code << "\n"

      actions = self.controller_class.action_methods.to_a.map(&:to_sym)
      actions &= [options.delete(:only)].flatten if options[:only]
      actions -= [options.delete(:except)].flatten if options[:except]

      ignored = self.controller_class.action_methods.to_a.map(&:to_sym) - actions
      puts "Ignore in #{controller_path}: " + ignored.join(', ') if ignored.any?

      infos = []
      infos << '"Response code: " + @response.response_code.to_s'
      infos << '"Locale: " + I18n.locale.to_s'
      infos << '(flash[:notifications].is_a?(Hash) ? "Notifications are:\n" + flash[:notifications].collect{|k,v| "[#{k.to_s.upcase.yellow}] " + v.to_sentence(locale: :eng)}.join("\n").dig : "No notifications.")'
      infos << '(assigns.any? ? "Assigns are:" + beautify(assigns) : "No assigns.")'

      code << "def show_context\n"
      code << infos.join(" +\n  \"\\n\" + ").dig
      code << "end\n\n"

      context = "show_context"
      # context = infos.join(' + "\n" + ')

      default_params = options[:params] || {}
      strictness = options[:strictness] || :default

      actions.sort.each do |action|
        action_label = "#{controller_path}##{action}"

        params, mode = {}.merge(default_params), options[action]
        if mode.is_a?(Hash)
          if mode[:params].is_a?(Hash)
            params.update mode[:params]
            mode = mode.delete(:mode)
          else
            mode = mode.delete(:mode)
            params.update(options[action])
          end
        end
        mode ||= choose_mode(action_label)

        params.deep_symbolize_keys!
        fixtures_to_use = FixtureRetriever.new(model, params.delete(:fixture), params.delete(:fixture_options))
        test_code = ""

        sanitized_params = Proc.new { |p = {}|
          p.deep_symbolize_keys
            .merge(locale: "@locale".c)
            .deep_merge(params)
            .inspect
            .gsub('OTHER_RECORD', other_record)
            .gsub('RECORD', record)
        }
        if mode == :index
          test_code << "get :#{action}, #{sanitized_params[]}\n"
          test_code << "assert_response :success, 'Try to get action: #{action} #{sanitized_params[]}. ' + #{context}\n"
          test_code << "get :#{action}, #{sanitized_params[q: 'abc']}\n"
          test_code << "assert_response :success, 'Try to get action: #{action} #{sanitized_params[]}. ' + #{context}\n"
          if params[:format] == :json
          # TODO: JSON parsing test
          else
            test_code << "assert_select('html body #main #content', 1, 'Cannot find #main #content element')\n"
          end
        elsif mode == :new_product
          test_code << "get :#{action}, #{sanitized_params[]}\n"
          test_code << "if ProductNatureVariant.of_variety('#{model_name.underscore}').any?\n"
          test_code << "  assert_response :success, #{context}\n"
          test_code << "else\n"
          test_code << "  assert_response :redirect, #{context}\n"
          test_code << "end\n"
        elsif mode == :show_sti_record
          test_code << "get :#{action}, #{sanitized_params[id: 'NaID', redirect: 'root_url'.c]}\n"
          test_code << "assert_redirected_to root_url\n"
          test_code << "#{model}.limit(5).find_each do |record|\n"
          test_code << "  get :#{action}, #{sanitized_params[id: 'record.id'.c, redirect: 'root_url'.c]}\n"
          test_code << "  if record.type and record.type != '#{model.name}'\n"
          test_code << "    assert_redirected_to({controller: record.class.name.tableize, action: :show, id: record.id})\n" # , #{context}
          test_code << "  else\n"
          test_code << "    assert_response :success, #{context}\n"
          test_code << "    assert_not_nil assigns(:#{record})\n"
          test_code << "  end\n"
          test_code << "end\n"
        elsif mode == :show
          test_code << "get :#{action}, #{sanitized_params[id: 'NaID', redirect: 'root_url'.c]}\n"
          if strictness == :api
            test_code << "assert_response 404\n" # , #{context}
          else
            test_code << "assert_redirected_to root_url\n" # , #{context}
          end
          if model
            test_code << "#{model}.limit(5).find_each do |record|\n"
            test_code << "  get :#{action}, #{sanitized_params[id: 'record.id'.c]}\n"
            test_code << "  assert_response :success\n" # , #{context}
            test_code << "  assert_not_nil assigns(:#{record})\n"
            test_code << "end\n"
          end
        elsif mode == :picture
          test_code << "#{record} = #{fixtures_to_use.retrieve(:first)}\n"
          test_code << "assert_equal 1, #{model_name}.where(id: #{record}.id).count\n"
          test_code << "get :#{action}, #{sanitized_params[id: 'RECORD.id'.c]}\n"
          test_code << "if #{record}.picture.file?\n"
          test_code << "  assert_response :success, #{context}\n"
          test_code << "  assert_not_nil assigns(:#{record})\n"
          test_code << "end\n"
        elsif mode == :list_things
          test_code << "#{record} = #{fixtures_to_use.retrieve(:first)}\n"
          test_code << "assert_equal 1, #{model_name}.where(id: #{record}.id).count\n"
          test_code << "get :#{action}, #{sanitized_params[id: 'RECORD.id'.c]}\n"
          test_code << "assert_response :success, #{context}\n"
          for format in [:csv, :ods] # :xcsv,
            test_code << "get :#{action}, #{sanitized_params[id: 'RECORD.id'.c, format: format]}\n"
            test_code << "assert_response :success, 'Action #{action} does not export in format #{format}'\n"
          end
        elsif mode == :create
          test_code << "#{record} = #{fixtures_to_use.retrieve(:first)}\n"
          test_code << "post :#{action}, #{sanitized_params[record => attributes]}\n"
        elsif mode == :update
          test_code << "#{record} = #{fixtures_to_use.retrieve(:first)}\n"
          test_code << "patch :#{action}, #{sanitized_params[id: 'RECORD.id'.c, record => attributes]}\n"
          test_code << "assert_response :redirect, \"After update on record ID=\#{#{record}.id} we should be redirected to another page. \" + #{context}\n"
        elsif mode == :destroy
          test_code << "#{record} = #{fixtures_to_use.retrieve(:first, :second)}\n"
          test_code << "delete :#{action}, #{sanitized_params[id: 'RECORD.id'.c]}\n"
          test_code << "assert_response :redirect, #{context}\n"
        elsif mode == :list
          test_code << "get :#{action}, #{sanitized_params[]}\n"
          test_code << "assert_response :success, \"The action #{action.inspect} does not seem to support GET method \#{redirect_to_url} / \#{flash.inspect}\"\n"
          for format in [:csv, :ods] # , :xcsv
            test_code << "get :#{action}, #{sanitized_params[format: format]}\n"
            test_code << "assert_response :success, 'Action #{action} does not export in format #{format}'\n"
          end
        elsif mode == :touch
          test_code << "post :#{action}, #{sanitized_params[id: 'NaID']}\n"
          test_code << "#{record} = #{fixtures_to_use.retrieve(:first)}\n"
          test_code << "post :#{action}, #{sanitized_params[id: 'RECORD.id'.c]}\n"
          test_code << "assert_response :redirect, #{context}\n"
        elsif mode == :evolve
          test_code << "#{record} = #{fixtures_to_use.retrieve(:first)}\n"
          model.state_machine.states.each do |state|
            test_code << "patch :#{action}, #{sanitized_params[id: 'RECORD.id'.c, state: state.name]}\n"
            test_code << "assert_response :redirect, #{context}\n"
          end
        elsif mode == :take
          test_code << "post :#{action}, #{sanitized_params[id: 'NaID', format: :json]}\n"
          test_code << "assert_response :redirect, #{context}\n"
          test_code << "#{record} = #{fixtures_to_use.retrieve(:first)}\n"
          test_code << "post :#{action}, #{sanitized_params[id: 'RECORD.id'.c, format: :json]}\n"
          test_code << "assert_response :unprocessable_entity\n"
          test_code << "post :#{action}, #{sanitized_params[id: 'RECORD.id'.c, format: :json, indicator: 'population']}\n"
          test_code << "assert_response :success, #{context}\n"
        elsif mode == :soft_touch
          test_code << "post :#{action}, #{sanitized_params[]}\n"
          test_code << "assert_response :success, #{context}\n"
        elsif mode == :multi_touch
          test_code << "post :#{action}, #{sanitized_params[id: 'NaID']}\n"
          test_code << "#{record} = #{fixtures_to_use.retrieve(:first)}\n"
          test_code << "post :#{action}, #{sanitized_params[id: 'RECORD.id'.c]}\n"
          test_code << "assert_response :redirect, #{context}\n"
          # Multi IDS
          test_code << "#{other_record} = #{fixtures_to_use.retrieve(:second)}\n"
          test_code << "post :#{action}, " + sanitized_params[id: '[RECORD.id, OTHER_RECORD.id].join(", ")'.c] + "\n"
          test_code << "assert_response :redirect, #{context}\n"
        elsif mode == :redirected_get # with ID
          test_code << "#{record} = #{fixtures_to_use.retrieve(:first)}\n"
          test_code << "get :#{action}, #{sanitized_params[id: 'RECORD.id'.c]}\n"
          test_code << "assert_response :redirect, #{context}\n"
        elsif mode == :get_and_post # with ID
          test_code << "get :#{action}, #{sanitized_params[id: 'NaID']}\n"
          test_code << "#{record} = #{fixtures_to_use.retrieve(:first)}\n"
          test_code << "get :#{action}, #{sanitized_params[id: 'RECORD.id'.c]}\n"
          test_code << "assert_response :success, #{context}\n"
        elsif mode == :index_xhr
          test_code << "get :#{action}, #{sanitized_params[]}\n"
          test_code << "assert_response :redirect, #{context}\n"
          test_code << "xhr :get, :#{action}, #{sanitized_params[]}\n"
          test_code << "assert_response :success, #{context}\n"
        elsif mode == :show_xhr
          test_code << "#{record} = #{fixtures_to_use.retrieve(:first)}\n"
          test_code << "get :#{action}, #{sanitized_params[id: 'RECORD.id'.c]}\n"
          test_code << "assert_response :redirect, #{context}\n"
          test_code << "xhr :get, :#{action}, #{sanitized_params[id: 'RECORD.id'.c]}\n"
          test_code << "assert_not_nil assigns(:#{record})\n"
        elsif mode == :unroll
          test_code << "xhr :get, :#{action}, #{sanitized_params[]}\n"
          test_code << "assert_response :success, #{context}\n"
          test_code << "xhr :get, :#{action}, #{sanitized_params[q: 'foo)bar']}\n"
          test_code << "assert_response :success, #{context}\n"
          test_code << "xhr :get, :#{action}, #{sanitized_params[q: 'foo(bar']}\n"
          test_code << "assert_response :success, #{context}\n"
          test_code << "xhr :get, :#{action}, #{sanitized_params[q: 'foo"bar\'qux']}\n"
          test_code << "assert_response :success, #{context}\n"
          test_code << "xhr :get, :#{action}, #{sanitized_params[q: '"; DROP TABLE ' + model.table_name + ';']}\n"
          test_code << "assert_response :success, #{context}\n"
          test_code << "xhr :get, :#{action}, #{sanitized_params[q: 'foo bar qux']}\n"
          test_code << "assert_response :success, #{context}\n"
          test_code << "xhr :get, :#{action}, #{sanitized_params[format: :json]}\n"
          test_code << "assert_response :success, #{context}\n"
          test_code << "xhr :get, :#{action}, #{sanitized_params[format: :xml]}\n"
          test_code << "assert_response :success, #{context}\n"
          if model
            test_code << "#{record} = #{fixtures_to_use.retrieve(:first)}\n"
            test_code << "xhr :get, :#{action}, #{sanitized_params[id: 'RECORD.id'.c]}\n"
            test_code << "assert_response :success, #{context}\n"
            for scope in model.simple_scopes
              test_code << "xhr :get, :#{action}, #{sanitized_params[scopes: scope.name]}\n"
              test_code << "assert_response :success, #{context}\n"
              test_code << "xhr :get, :#{action}, #{sanitized_params[scopes: scope.name, format: :json]}\n"
              test_code << "assert_response :success, #{context}\n"
              test_code << "xhr :get, :#{action}, #{sanitized_params[scopes: scope.name, format: :xml]}\n"
              test_code << "assert_response :success, #{context}\n"
              test_code << "xhr :get, :#{action}, #{sanitized_params[scopes: scope.name, id: 'RECORD.id'.c]}\n"
              test_code << "assert_response :success, #{context}\n"
            end
            # TODO test complex scopes
          end
        elsif mode == :get
          test_code << "get :#{action}, #{sanitized_params[]}\n"
          test_code << "assert_response :success, #{context}\n"
        elsif mode == :post
          test_code << "post :#{action}, #{sanitized_params[]}\n"
          test_code << "assert_response :success, #{context}\n"
        elsif mode == :post_and_redirect
          test_code << "post :#{action}, #{sanitized_params[]}\n"
          test_code << "assert_response :redirect, #{context}\n"
        elsif mode == :redirect
          test_code << "get :#{action}, #{sanitized_params[]}\n"
          test_code << "assert_response :redirect, #{context}\n"
        else
          test_code << "raise StandardError, 'What is this mode? #{mode.inspect}'\n"
        end

        if action != mode
          code << "test '#{action} action in #{mode} mode' do\n"
        else
          code << "test '#{action} action' do\n"
        end
        # code << "  puts '#{controller_path.to_s.yellow}##{action.to_s.red}'\n"
        code << test_code.dig
        code << "end\n\n"
      end
      # code << "end\n"

      file = Rails.root.join("tmp", "code", "test", "#{controller_path}.rb")
      FileUtils.mkdir_p(file.dirname)
      File.open(file, "wb") do |f|
        f.write(code)
      end

      class_eval(code, "(test) #{controller_path}") # :#{__LINE__}
    end

    MODES = {
      /\Abackend\/cells\/.*\#show\z/ => :get,
      # /\Abackend\/cells\/.*\#list\z/ => :index_xhr,
      /\#(index|new|pick|set)\z/   => :index,
      /\#(show|edit|detail)\z/   => :show,
      /\#picture\z/       => :picture,
      /\#list\_\w+\z/     => :list_things,
      /\#list\z/          => :list,
      /\#(create|load|incorporate)\z/ => :create,
      /\#update\z/        => :update,
      /\#evolve\z/        => :evolve,
      /\#destroy\z/       => :destroy,
      /\#(decrement|duplicate|down|lock|toggle|unlock|up|increment|propose|confirm|refuse|invoice|abort|correct|finish|propose_and_invoice|sort|run|qualify|evaluate|quote|negociate|win|lose|reset|start|prospect)\z/ => :touch,
      /\#take\z/          => :take,
      /\#unroll\z/        => :unroll
    }

    def choose_mode(action)
      array = action.to_s.split('#')
      action_name = array.last.to_sym
      if action_name == :new
        model = array.first.split(/\//).last.classify.constantize rescue nil
        return :new_product if model and model <= Product
      elsif action_name == :show
        model = array.first.split(/\//).last.classify.constantize rescue nil
        return :show_sti_record if model and (model <= Product or model <= Affair)
      end
      for exp, mode in MODES
        return mode if action =~ exp
      end
      return :get
    end


  end
end


# Cheat Sheet
# https://gist.github.com/zhengjia/428105

# Capybara.register_driver :poltergeist do |app|
#   Capybara::Poltergeist::Driver.new(app, debug: true, inspector: true)
# end

Capybara.default_driver    = (ENV["DRIVER"] == "webkit" ? :webkit : :selenium)
Capybara.current_driver    = Capybara.default_driver
Capybara.javascript_driver = Capybara.default_driver
# Capybara.default_wait_time = 5
# Capybara.server_port = 3333


Capybara::Webkit.configure do |config|
  config.allow_url 'a.tile.openstreetmap.fr'
  config.allow_url 'b.tile.openstreetmap.fr'
  config.allow_url 'c.tile.openstreetmap.fr'
  config.allow_url 'server.arcgisonline.com'
  config.allow_url 'secure.gravatar.com'
end


class CapybaraIntegrationTest < ActionDispatch::IntegrationTest
  include Capybara::DSL
  # include Capybara::Screenshot
  include Warden::Test::Helpers
  Warden.test_mode!

  def wait_for_ajax
    sleep(Capybara.default_wait_time * 0.5)
    # Timeout.timeout(Capybara.default_wait_time) do
    #   loop if active_ajax_requests?
    # end
  end

  def active_ajax_requests?
    # puts page.evaluate_script('$.active').inspect.red
    sleep(0.1)
    page.evaluate_script('$.turbo.isReady') && page.evaluate_script('jQuery.active').zero?
  end

  def shoot_screen(name = nil)
    name ||= current_url.split(/\:\d+\//).last
    file = Rails.root.join("tmp", "screenshots", "#{name}.png")
    FileUtils.mkdir_p(file.dirname) unless file.dirname.exist?
    wait_for_ajax
    save_page file.to_s.gsub(/\.png\z/, '.html')
    save_screenshot file # , full: true
  end

  def resize_window(width, height)
    driver = Capybara.current_driver
    if driver == :webkit
      page.current_window.resize_to(width, height)
    elsif driver == :selenium
      page.driver.browser.manage.window.resize_to(width, height)
    else
      raise NotImplemented, "Not implemented for #{driver.inspect}"
    end
  end

  # Add a method to test unroll in form
  # FIXME : add an AJAX helpers to capybara for testing unroll field
  # http://stackoverflow.com/questions/13187753/rails3-jquery-autocomplete-how-to-test-with-rspec-and-capybara/13213185#13213185
  # http://jackhq.tumblr.com/post/3728330919/testing-jquery-autocomplete-using-capybara
  def fill_unroll(field, options = {})
    fill_in(field, with: options[:with])

    if options[:name]
      shoot_screen "#{options[:name]}/unroll-before"
    end

    wait_for_ajax

    script  = "$('input##{field}').next().next().find('.items-list .item"
    script << (options[:select] ? "[data-item-label~=\"#{options[:select]}\"]" : ":first-child")
    script << "').mouseenter().click();"

    page.execute_script script
    wait_for_ajax
    if options[:name]
      shoot_screen "#{options[:name]}/unroll-after"
    end
  end

end
