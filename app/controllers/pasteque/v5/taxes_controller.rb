class Pasteque::V5::TaxesController < Pasteque::V5::BaseController
  def index
    @records = Tax.available_natures
    render locals: {output_name: 'tax_categories', partial_path: 'taxes/tax_category', record: :tax_category}
  end

  def show
    @record = Nomen::TaxNatures.list.keep_if{|tax_nature| tax_nature.name == params[:id]}.first
    render partial: 'pasteque/v5/taxes/tax_category', locals: {tax_category: @record}
  end
end
