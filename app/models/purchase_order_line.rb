# == Schema Information
# Schema version: 20081127140043
#
# Table name: purchase_order_lines
#
#  id                :integer       not null, primary key
#  order_id          :integer       not null
#  product_id        :integer       not null
#  unit_id           :integer       not null
#  quantity          :decimal(16, 2 default(1.0), not null
#  amount            :decimal(16, 2 default(0.0), not null
#  amount_with_taxes :decimal(16, 2 default(0.0), not null
#  position          :integer       
#  account_id        :integer       not null
#  company_id        :integer       not null
#  created_at        :datetime      not null
#  updated_at        :datetime      not null
#  created_by        :integer       
#  updated_by        :integer       
#  lock_version      :integer       default(0), not null
#

class PurchaseOrderLine < ActiveRecord::Base
end
