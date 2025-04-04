require 'rails_helper'
require 'csv'

RSpec.describe OrderProcessingService do
  # Create test doubles
  let(:api_client) { instance_double("ApiClient") }
  let(:service) { described_class.new(api_client) }
  let(:user_id) { 1 }
  
  # Create a mock API response
  let(:successful_response) { double("ApiResponse", status: 'success', data: 60) }
  let(:failed_response) { double("ApiResponse", status: 'error', data: 0) }

  # Define test helpers
  def create_order(type, attrs = {})
    attrs[:type] = type
    attrs[:user_id] ||= user_id
    attrs[:status] ||= :initial
    attrs[:amount] ||= 100.0
    attrs[:flag] = false if attrs[:flag].nil?
    attrs[:priority] ||= :low
    
    instance_double("Order", attrs.merge(
      update: true,
      save!: true
    ))
  end

  # Clean up test files
  before do
    # Delete any CSV files from previous tests
    Dir.glob("orders_type_A_*.csv").each { |file| File.delete(file) if File.exist?(file) }
  end
  
  describe '#initialize' do
    it 'stores the api client' do
      expect(service.instance_variable_get(:@api_client)).to eq(api_client)
    end
  end

  describe '#process_orders' do
    context 'when no orders exist for user' do
      before do
        allow(Order).to receive(:where).with(user_id: user_id).and_return([])
      end

      it 'returns false' do
        expect(service.process_orders(user_id)).to be false
      end
    end

    context 'when orders exist for user' do
      let(:type_a_order) { create_order('A', id: 1) }
      let(:type_b_order) { create_order('B', id: 2, amount: 99) }
      let(:type_c_order) { create_order('C', id: 3) }
      let(:unknown_order) { create_order('Unknown', id: 4) }
      let(:orders) { [type_a_order, type_b_order, type_c_order, unknown_order] }

      before do
        allow(Order).to receive(:where).with(user_id: user_id).and_return(orders)
        
        # Setup CSV mock
        allow(CSV).to receive(:open).and_yield([])
        
        # Setup API client mock
        allow(api_client).to receive(:call_api).with(type_b_order.id).and_return(successful_response)
      end

      it 'processes all orders and returns true' do
        # Test expectations for each order type
        expect(type_a_order).to receive(:update).with(status: :exported)
        expect(type_a_order).to receive(:update).with(priority: :low)
        
        expect(type_b_order).to receive(:update).with(status: :processed)
        expect(type_b_order).to receive(:update).with(priority: :low)
        
        expect(type_c_order).to receive(:update).with(status: :in_progress)
        expect(type_c_order).to receive(:update).with(priority: :low)
        
        expect(unknown_order).to receive(:update).with(status: :unknown_type)
        expect(unknown_order).to receive(:update).with(priority: :low)
        
        # Ensure all orders are saved
        orders.each { |order| expect(order).to receive(:save!) }
        
        expect(service.process_orders(user_id)).to be true
      end
      
      it 'handles database exceptions when saving orders' do
        # Setup one order to throw DatabaseException
        expect(type_a_order).to receive(:save!).and_raise(DatabaseException)
        expect(type_a_order).to receive(:update).with(status: :db_error)
        
        # Ensure other orders are still processed
        expect(type_b_order).to receive(:save!)
        expect(type_c_order).to receive(:save!)
        expect(unknown_order).to receive(:save!)
        
        expect(service.process_orders(user_id)).to be true
      end

      it 'handles general exceptions and returns false' do
        allow(Order).to receive(:where).and_raise(StandardError)
        expect(service.process_orders(user_id)).to be false
      end
    end
  end

  describe 'type A order processing' do
    let(:type_a_order) { create_order('A', id: 5) }
    
    before do
      allow(Order).to receive(:where).with(user_id: user_id).and_return([type_a_order])
      allow(CSV).to receive(:open).and_yield([])
    end
    
    it 'creates a CSV file and marks order as exported' do
      csv_mock = []
      allow(CSV).to receive(:open) do |_file, _mode, &block|
        block.call(csv_mock)
      end
      
      expect(type_a_order).to receive(:update).with(status: :exported)
      expect(service.process_orders(user_id)).to be true
    end
    
    it 'adds a note for high value orders' do
      high_value_order = create_order('A', id: 6, amount: 175)
      allow(Order).to receive(:where).with(user_id: user_id).and_return([high_value_order])
      
      csv_rows = []
      allow(CSV).to receive(:open) do |_file, _mode, &block|
        block.call(csv_rows)
      end
      
      expect(high_value_order).to receive(:update).with(status: :exported)
      expect(service.process_orders(user_id)).to be true
      expect(csv_rows.size).to eq(3) # Header, order, and note
    end
    
    it 'marks order as export_failed when CSV creation fails' do
      allow(CSV).to receive(:open).and_raise(StandardError)
      
      expect(type_a_order).to receive(:update).with(status: :export_failed)
      expect(service.process_orders(user_id)).to be true
    end
  end
  
  describe 'type B order processing' do
    context 'with successful API response' do
      context 'when order amount < 100 and response data >= 50' do
        let(:order) { create_order('B', id: 7, amount: 75) }
        
        before do
          allow(Order).to receive(:where).with(user_id: user_id).and_return([order])
          allow(api_client).to receive(:call_api).with(order.id).and_return(successful_response)
        end
        
        it 'marks order as processed' do
          expect(order).to receive(:update).with(status: :processed)
          expect(service.process_orders(user_id)).to be true
        end
      end
      
      context 'when response data < 50' do
        let(:order) { create_order('B', id: 8, amount: 75) }
        let(:low_data_response) { double("ApiResponse", status: 'success', data: 40) }
        
        before do
          allow(Order).to receive(:where).with(user_id: user_id).and_return([order])
          allow(api_client).to receive(:call_api).with(order.id).and_return(low_data_response)
        end
        
        it 'marks order as pending' do
          expect(order).to receive(:update).with(status: :pending)
          expect(service.process_orders(user_id)).to be true
        end
      end
      
      context 'when order is flagged' do
        let(:flagged_order) { create_order('B', id: 9, flag: true) }
        
        before do
          allow(Order).to receive(:where).with(user_id: user_id).and_return([flagged_order])
          allow(api_client).to receive(:call_api).with(flagged_order.id).and_return(successful_response)
        end
        
        it 'marks order as pending regardless of response data' do
          expect(flagged_order).to receive(:update).with(status: :pending)
          expect(service.process_orders(user_id)).to be true
        end
      end
      
      context 'when amount >= 100 and data >= 50 and not flagged' do
        let(:order) { create_order('B', id: 10, amount: 150) }
        
        before do
          allow(Order).to receive(:where).with(user_id: user_id).and_return([order])
          allow(api_client).to receive(:call_api).with(order.id).and_return(successful_response)
        end
        
        it 'marks order as error' do
          expect(order).to receive(:update).with(status: :error)
          expect(service.process_orders(user_id)).to be true
        end
      end
    end
    
    context 'with failed API response' do
      let(:order) { create_order('B', id: 11) }
      
      before do
        allow(Order).to receive(:where).with(user_id: user_id).and_return([order])
        allow(api_client).to receive(:call_api).with(order.id).and_return(failed_response)
      end
      
      it 'marks order as api_error' do
        expect(order).to receive(:update).with(status: :api_error)
        expect(service.process_orders(user_id)).to be true
      end
    end
    
    context 'when API throws exception' do
      let(:order) { create_order('B', id: 12) }
      
      before do
        allow(Order).to receive(:where).with(user_id: user_id).and_return([order])
        allow(api_client).to receive(:call_api).with(order.id).and_raise(APIException)
      end
      
      it 'marks order as api_failure' do
        expect(order).to receive(:update).with(status: :api_failure)
        expect(service.process_orders(user_id)).to be true
      end
    end
  end
  
  describe 'type C order processing' do
    context 'when order is flagged' do
      let(:order) { create_order('C', id: 13, flag: true) }
      
      before do
        allow(Order).to receive(:where).with(user_id: user_id).and_return([order])
      end
      
      it 'marks order as completed' do
        expect(order).to receive(:update).with(status: :completed)
        expect(service.process_orders(user_id)).to be true
      end
    end
    
    context 'when order is not flagged' do
      let(:order) { create_order('C', id: 14, flag: false) }
      
      before do
        allow(Order).to receive(:where).with(user_id: user_id).and_return([order])
      end
      
      it 'marks order as in_progress' do
        expect(order).to receive(:update).with(status: :in_progress)
        expect(service.process_orders(user_id)).to be true
      end
    end
  end
  
  describe 'unknown type order processing' do
    let(:order) { create_order('X', id: 15) }
    
    before do
      allow(Order).to receive(:where).with(user_id: user_id).and_return([order])
    end
    
    it 'marks order as unknown_type' do
      expect(order).to receive(:update).with(status: :unknown_type)
      expect(service.process_orders(user_id)).to be true
    end
  end
  
  describe 'order priority processing' do
    context 'when amount > 200' do
      let(:order) { create_order('A', id: 16, amount: 250) }
      
      before do
        allow(Order).to receive(:where).with(user_id: user_id).and_return([order])
        allow(CSV).to receive(:open).and_yield([])
      end
      
      it 'sets priority to high' do
        expect(order).to receive(:update).with(priority: :high)
        expect(service.process_orders(user_id)).to be true
      end
    end
    
    context 'when amount <= 200' do
      let(:order) { create_order('A', id: 17, amount: 200) }
      
      before do
        allow(Order).to receive(:where).with(user_id: user_id).and_return([order])
        allow(CSV).to receive(:open).and_yield([])
      end
      
      it 'sets priority to low' do
        expect(order).to receive(:update).with(priority: :low)
        expect(service.process_orders(user_id)).to be true
      end
    end
  end
  
  describe 'database error handling' do
    let(:order) { create_order('A', id: 18) }
    
    before do
      allow(Order).to receive(:where).with(user_id: user_id).and_return([order])
      allow(CSV).to receive(:open).and_yield([])
      allow(order).to receive(:save!).and_raise(DatabaseException)
    end
    
    it 'updates status to db_error' do
      expect(order).to receive(:update).with(status: :db_error)
      expect(service.process_orders(user_id)).to be true
    end
  end
end