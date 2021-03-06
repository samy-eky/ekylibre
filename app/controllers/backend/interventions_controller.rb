# == License
# Ekylibre - Simple agricultural ERP
# Copyright (C) 2013 Brice Texier
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
class Backend::InterventionsController < Backend::BaseController
  manage_restfully t3e: {procedure_name: "RECORD.reference.human_name".c}

  respond_to :pdf, :odt, :docx, :xml, :json, :html, :csv

  unroll

  # params:
  #   :q Text search
  #   :state State search
  #   :campaign_id
  #   :product_nature_id
  #   :storage_id
  def self.interventions_conditions
    code = ""
    code = search_conditions(:interventions => [:state, :number], :activities => [:name], :campaigns => [:name], :productions => [:name], :products => [:name]) + " ||= []\n"
    code << "unless params[:state].blank?\n"
    code << "  c[0] << ' AND #{Intervention.table_name}.state IN (?)'\n"
    code << "  c << params[:state].flatten\n"
    code << "end\n"
    code << "unless params[:reference_name].blank?\n"
    code << "  c[0] << ' AND #{Intervention.table_name}.reference_name IN (?)'\n"
    code << "  c << params[:reference_name]\n"
    code << "end\n"
    code << "c[0] << ' AND ' + params[:nature].join(' AND ') unless params[:nature].blank?\n"
    # code << "if params[:campaign_id].to_i > 0\n"
    # code << "  c[0] << ' AND #{Intervention.table_name}.production_id IN (SELECT id FROM #{Production.table_name} WHERE campaign_id IN (?))'\n"
    # code << "  c << params[:campaign_id].to_i\n"
    # code << "end\n"
    code << "if current_campaign\n"
    code << "  c[0] << \" AND #{Intervention.table_name}.production_id IN (SELECT id FROM #{Production.table_name} WHERE campaign_id IN (?))\"\n"
    code << "  c << current_campaign.id\n"
    code << "end\n"
    code << "if params[:storage_id].to_i > 0\n"
    code << "  c[0] << ' AND production_support_id IN (SELECT id FROM #{ProductionSupport.table_name} WHERE storage_id IN (?))'\n"
    code << "  c << params[:storage_id].to_i\n"
    code << "end\n"
    code << "c\n "
    return code.c
  end

  # INDEX
  # @TODO conditions: interventions_conditions, joins: [:production, :activity, :campaign, :storage]

  list(conditions: interventions_conditions, joins: [:production, :activity, :campaign, :storage], order: {started_at: :desc}, line_class: :status) do |t|
    t.action :run,  if: :runnable?, method: :post, confirm: true
    t.action :edit, if: :updateable?
    t.action :destroy, if: :destroyable?
    t.column :name, sort: :reference_name, url: true
    t.column :production, url: true, hidden: true
    t.column :campaign, url: true
    t.column :activity, url: true, hidden: true
    t.column :state, hidden: true
    t.column :started_at
    t.column :duration
    t.column :stopped_at, hidden: true
    t.status
    t.column :issue, url: true
    t.column :casting, hidden: true
  end

  before_action only: [:index] do
    unless Production.any?
      notify :a_production_must_be_opened
      redirect_to controller: :productions, action: :index
    end
  end

  # SHOW

  list(:casts, model: :intervention_casts, conditions: {intervention_id: 'params[:id]'.c}, order: {created_at: :desc}) do |t|
    t.column :name, sort: :reference_name
    t.column :actor, url: true
    t.column :human_roles, sort: :roles, label: :roles
    t.column :population
    t.column :unit_name, through: :variant
    t.column :shape, hidden: true
    t.column :variant, url: true
  end

  list(:operations, conditions: {intervention_id: 'params[:id]'.c}, order: :started_at) do |t|
    t.column :reference_name
    t.column :description
    # t.column :name, url: true
    t.column :started_at
    t.column :stopped_at
    t.column :duration
  end

  # Show one intervention with params_id
  def show
    return unless @intervention = find_and_check
    t3e @intervention, procedure_name: @intervention.name
    if params[:mode] == "spraying"
      render "spraying"
      return
    end
    respond_with(@intervention, :methods => [:cost, :earn, :status, :name, :duration],
                :include => [{:casts => {:methods => [:variable_name, :default_name], :include => {:actor => {:methods => [:picture_path, :nature_name, :unit_name]}}}}, {:storage => {}}, :recommender, :prescription],
                procs: Proc.new{|options| options[:builder].tag!(:url, backend_intervention_url(@intervention))}
                )
  end


  def set
    return unless @intervention = find_and_check
  end

  def run
    return unless intervention = find_and_check
    if intervention.need_parameters? and !params[:parameters]
      redirect_to action: :set, id: intervention.id
      return
    end
    intervention.run!({}, params[:parameters])
    redirect_to backend_intervention_url(intervention)
  end

  # Computes reverberation of a updated value in an intervention input context
  # Converts handlers and updates others things in cascade
  def compute
    unless procedure = Procedo[params[:procedure]]
      head :not_found
      return
    end
    begin
      updates = procedure.impact(params[:casting], params[:global], params[:updater])
      respond_to do |format|
        format.xml  { render xml: updates.to_xml }
        format.json { render json: updates.to_json }
      end
    rescue Procedo::Error => e
      respond_to do |format|
        format.xml  { render xml:  {errors: e.message}, status: 500 }
        format.json { render json: {errors: e.message}, status: 500 }
      end
    end
  end

end
