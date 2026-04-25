class ArtikonSyncJob < ApplicationJob
  queue_as :default

  def perform
    Artikon::FeedImporter.new.call
  end
end
