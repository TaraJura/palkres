class Account::ProfilesController < Account::BaseController
  def show
  end

  def update
    if Current.user.update(params.require(:user).permit(:first_name, :last_name, :phone))
      redirect_to account_profile_path, notice: "Profil byl uložen."
    else
      render :show, status: :unprocessable_entity
    end
  end
end
