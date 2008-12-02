#  Schema Information
# Schema version: 20080819191919
#
# Table name: journal_periods
#
#  id               :integer       not null, primary key
#  journal_id       :integer       not null
#  financialyear_id :integer       not null
#  started_on       :date          not null
#  stopped_on       :date          not null
#  closed           :boolean       
#  debit            :decimal(16, 2 default(0.0), not null
#  credit           :decimal(16, 2 default(0.0), not null
#  balance          :decimal(16, 2 default(0.0), not null
#  company_id       :integer       not null
#  created_at       :datetime      not null
#  updated_at       :datetime      not null
#  created_by       :integer       
#  updated_by       :integer       
#  lock_version     :integer       default(0), not null
#

class JournalPeriod < ActiveRecord::Base
  validates_uniqueness_of [:started_on, :stopped_on], 
                          :scope=> :journal_id

  def validate
    errors.add lc(:error_period) if self.started_on > self.stopped_on
    errors.add lc(:error_closed_journal) if self.stopped_on > self.journal.closed_on
    errors.add lc(:error_closed_financialyear) if self.financialyear.closed
    
    self.started_on.upto(self.stopped_on) do |date|
      
      if [self.financialyear.started_on, self.financialyear.stopped_on].include? date
        errors.add lc(:error_limited_financialyear) 
      end
      
    end
  end
  
  
  def close(date)
    self.update_attributes(:stopped_on => date, :closed => true)
    self.journal_records.each do |record|
      record.close(date)
    end
    
  end    

end
