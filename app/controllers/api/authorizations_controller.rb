class Api::AuthorizationsController < ApplicationController
	before_action :verify_slack_token, only: :use_uber
	before_action :require_authorization, only: :use_uber

  def echo
    render json: params
  end

  def use_uber
  	# here order car
		render text: "ready to pickup"
  end


  def connect_uber
		# After user has clicked "yes" on Uber OAuth page
    post_params = {
      'client_secret' => ENV['uber_client_secret'],
      'client_id' 		=> ENV['uber_client_id'],
      'grant_type' 		=> 'authorization_code',
      'redirect_uri' 	=> ENV['uber_callback_url'],
      'code' 					=> params[:code]
    }
    # post request to uber to trade code for user access token
    resp = RestClient.post('https://login.uber.com/oauth/v2/token', post_params)
    access_token = JSON.parse(resp.body)['access_token']

    if access_token.nil?
    	render json: {status: "Error: no access token", body: resp.body}
    else
	    Authorization.find_by(session_token: session[:session_token])
        .update(uber_auth_token: access_token)

     # sign up success, prompt user that they can order uber now
			au = Authorization.find_by(session_token: session[:session_token])
	    render json: {status: "success", user:au}
	  end
  end

  def establish_session
	# when authorizing with Uber:  first save session_token, then redirect to Uber OAuth page.
  	auth = Authorization.find_by(slack_user_id: params[:user_id])
  	session[:session_token] = Authorization.create_session_token

  	auth.update(session_token: session[:session_token])

  	redirect_to "https://login.uber.com/oauth/v2/authorize?response_type=code&client_id=#{ENV['uber_client_id']}"
  end

  def connect_slack
		# First channel admin agrees to use app
		slack_auth_params = {
			client_secret: ENV['slack_client_secret'],
			client_id: ENV['slack_client_id'],
			redirect_uri: ENV['slack_redirect'],
			code: slack_params[:code]
		}

		resp = RestClient.post('https://slack.com/api/oauth.access', slack_auth_params)

		access_token = resp['access_token']

		render text: "slack auth success, access_token: #{resp.body}"
	end

  private

  def verify_slack_token
		#verify request to use_uber is from slack.
		unless slack_params[:token] == ENV['slack_app_token']
			render json: {error: "Missing slack_app_token", params: slack_params}
		end
	end

	def slack_params
		params.permit(:user_id, :code, :token)
	end

  def require_authorization
		# if user is not signed up, give a link to sign up.
  	auth = Authorization.find_by(slack_user_id: params[:user_id])
  	return if auth && auth.uber_registered?

		auth = register_new_user if auth.nil?
		render text: uber_oauth_str_url(auth.slack_user_id)
  end

  def register_new_user
  	auth = Authorization.create!(slack_user_id: params[:user_id])
  end

  def uber_oauth_str_url(slack_user_id)
  	username = params[:user_name]
  	url = "#{api_activate_url}?user_id=#{slack_user_id}"
  	"Hey @#{username}! Looks like this is your first ride from Slack. Go <#{url}|here> to activate."
  end
end
