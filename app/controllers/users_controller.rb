class UsersController < ApplicationController
  def create
    @user = User.new(user_params)
    @user.invite_to_slack

    if @user.save
      login!(@user)
      redirect_to static_pages_slack_success_url
    else
      if @user.errors.messages == { :email=>["has already been taken"] }
        redirect_to static_pages_slack_resent_url
      else
        redirect_to static_pages_fail_url
      end
    end
  end

  private

  def user_params
    params.require(:user).permit(:email, :first_name, :last_name)
  end
end
