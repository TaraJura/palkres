namespace :artikon do
  desc "Run ARTIKON feed import synchronously (useful for bootstrap or ops check)"
  task sync: :environment do
    result = Artikon::FeedImporter.new.call
    puts "SyncRun ##{result.id}: status=#{result.status} seen=#{result.items_seen} created=#{result.items_created} updated=#{result.items_updated} deactivated=#{result.items_deactivated} duration=#{result.duration_seconds}s"
    if result.status == "failed"
      exit 1
    end
  end
end
