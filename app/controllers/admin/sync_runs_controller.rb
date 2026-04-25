class Admin::SyncRunsController < Admin::BaseController
  def index
    @pagy, @sync_runs = pagy(SyncRun.order(started_at: :desc), limit: 50)
  end

  def show
    @sync_run = SyncRun.find(params[:id])
  end

  def run_now
    ArtikonSyncJob.perform_later
    redirect_to admin_sync_runs_path, notice: "Sync naplánován."
  end
end
