FactoryBot.define do
  factory :order do
    user_id { 1 }
    status { :initial } # Use initial instead of new to avoid conflicts
    amount { 100.0 }
    flag { false }
    # Use the column name that's actually in your database schema
    # Adjust as needed if it's "priority" or "piority"
    priority { :low }
    
    # Define traits for types
    trait :type_a do
      type { 'A' }
    end
    
    trait :type_b do
      type { 'B' }
    end
    
    trait :type_c do
      type { 'C' }
    end
    
    # Common status traits
    trait :exported do
      status { :exported }
    end
    
    trait :export_failed do
      status { :export_failed }
    end
    
    # Amounts
    trait :high_amount do
      amount { 250.0 }
    end
    
    trait :medium_amount do
      amount { 175.0 }
    end
    
    # Flag
    trait :flagged do
      flag { true }
    end
  end
end