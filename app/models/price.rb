# == Schema Information
# Schema version: 20081127140043
#
# Table name: prices
#
#  id                :integer       not null, primary key
#  amount            :decimal(16, 4 not null
#  amount_with_taxes :decimal(16, 4 not null
#  started_on        :date          not null
#  stopped_on        :date          
#  deleted           :boolean       not null
#  use_range         :boolean       not null
#  quantity_min      :decimal(16, 2 default(0.0), not null
#  quantity_max      :decimal(16, 2 default(0.0), not null
#  product_id        :integer       not null
#  list_id           :integer       not null
#  company_id        :integer       not null
#  created_at        :datetime      not null
#  updated_at        :datetime      not null
#  created_by        :integer       
#  updated_by        :integer       
#  lock_version      :integer       default(0), not null
#

class Price < ActiveRecord::Base
end
