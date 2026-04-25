module AdminHelper
  def status_badge_class(status)
    case status.to_s
    when "placed"     then "bg-amber-100 text-amber-800"
    when "processing" then "bg-blue-100 text-blue-800"
    when "shipped"    then "bg-indigo-100 text-indigo-800"
    when "delivered"  then "bg-emerald-100 text-emerald-800"
    when "cancelled"  then "bg-rose-100 text-rose-800"
    else "bg-slate-100 text-slate-700"
    end
  end

  def payment_badge_class(state)
    case state.to_s
    when "paid"       then "bg-emerald-100 text-emerald-800"
    when "authorized" then "bg-blue-100 text-blue-800"
    when "pending"    then "bg-amber-100 text-amber-800"
    when "failed"     then "bg-rose-100 text-rose-800"
    when "refunded"   then "bg-slate-200 text-slate-700"
    else "bg-slate-100 text-slate-700"
    end
  end

  def sync_status_badge_class(status)
    case status.to_s
    when "succeeded" then "bg-emerald-100 text-emerald-800"
    when "running"   then "bg-blue-100 text-blue-800"
    when "skipped"   then "bg-slate-100 text-slate-700"
    when "failed"    then "bg-rose-100 text-rose-800"
    else "bg-slate-100 text-slate-700"
    end
  end
end
