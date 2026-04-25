class SyncRun < ApplicationRecord
  STATUSES = %w[running succeeded failed skipped].freeze

  validates :status, inclusion: { in: STATUSES }

  def duration_seconds
    return nil unless started_at && finished_at
    (finished_at - started_at).to_i
  end

  def record_error!(message, context = {})
    self.errors_log = errors_log + [{ message: message, context: context, at: Time.current.iso8601 }]
    save!
  end
end
