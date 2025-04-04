class Order < ApplicationRecord
  enum status: { initial: 0, exported: 1, export_failed: 2, processed: 3, pending: 4, error: 5, api_error: 6, api_failure: 7, completed: 8, in_progress: 9, unknown_type: 10, db_error: 11 }
  enum priority: { low: 0, high: 1 }
end
