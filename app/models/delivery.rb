# == Schema Information
# Schema version: 20081127140043
#
# Table name: deliveries
#
#  id                :integer       not null, primary key
#  order_id          :integer       not null
#  invoice_id        :integer       
#  shipped_on        :date          not null
#  delivered_on      :date          not null
#  amount            :decimal(16, 2 default(0.0), not null
#  amount_with_taxes :decimal(16, 2 default(0.0), not null
#  comment           :text          
#  company_id        :integer       not null
#  created_at        :datetime      not null
#  updated_at        :datetime      not null
#  created_by        :integer       
#  updated_by        :integer       
#  lock_version      :integer       default(0), not null
#

class Delivery < ActiveRecord::Base
end
