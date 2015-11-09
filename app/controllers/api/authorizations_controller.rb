class Api::AuthorizationsController < ApplicationController
	before_action :verify_slack_token, only: :use_uber
	before_action :require_authorization, only: :use_uber

  def echo
    render json: params
  end

  def authorize
    # render nil if params[:token] != ENV[slack_token]
    # if auth.nil?
    # 	# find the user
    # 	# validate if user has uber tokens
    # 	# if so, there should be location info
    # 	# call a car for user
    # 	use_uber
    # end
  end

  # this is only for new user, connecting its slack acc w/ uber acc
  # this is the callback for authorizing new user
  def connect_uber
    post_params = {
      'client_secret' => ENV['uber_client_secret'],
      'client_id' 		=> ENV['uber_client_id'],
      'grant_type' 		=> 'authorization_code',
      'redirect_uri' 	=> ENV['uber_callback_url'],
      'code' 					=> params[:code]
    }
    # post request to uber
    resp = RestClient.post('https://login.uber.com/oauth/v2/token', post_params)

    access_token = JSON.parse(resp.body)['access_token']

    if access_token.nil?
    	# error handling
    	render json: resp.body
    else
	    Authorization.find_by(session_token: session[:session_token])
                 	 .update(uber_auth_token: access_token)

     # sign up success, prompt user that they can order uber now
			response_url = session[:slack_response_url]
			slack_response_params = {
				text: 'You can now order an Uber from Slack!'
			}
			RestClient.post(response_url, slack_response_params)
	    render text: "Successfully connected!"
	  end
  end

  def use_uber
  	# here order car
  	render text: "ready to pickup"
  end

  def establish_session
  	auth = Authorization.find_by(slack_user_id: params[:user_id])
  	session[:session_token] = Authorization.create_session_token
		session[:slack_response_url] = slack_params[:response_url]

  	auth.update(session_token: session[:session_token])

  	redirect_to "https://login.uber.com/oauth/v2/authorize?response_type=code&client_id=#{ENV['uber_client_id']}"
  end

  def connect_slack
		slack_auth_params = {
			client_secret: ENV['slack_client_secret'],
			client_id: ENV['slack_client_id'],
			redirect_uri: ENV['slack_redirect'],
			code: slack_params[:code]
		}

		resp = Net::HTTP.post_form(URI.parse('https://slack.com/api/oauth.access'), slack_auth_params)

		access_token = resp['access_token']

		render text: "slack auth success, access_token: #{resp.body}"
	end

  private

  def verify_slack_token
		unless slack_params[:token] == ENV['slack_app_token']
			render json: slack_params
		end
	end

	def slack_params
		params.permit(:user_id, :code, :token, :text, :response_url)
	end

  def require_authorization
  	auth = Authorization.find_by(slack_user_id: params[:user_id])

  	return if auth && auth.uber_registered?

  	if auth.nil?
  		auth = register_new_user
  	end

  	if !auth.uber_registered?
  		render text: uber_oauth_str_url(auth.slack_user_id)
  	end
  end

  def register_new_user
  	auth = Authorization.new(slack_user_id: params[:user_id])
		auth.save!
		auth
  end

  def uber_oauth_str_url(slack_user_id)
  	username = params[:user_name]
  	url = "#{api_activate_url}?user_id=#{slack_user_id}"
  	"Hey @#{username}! Looks like this is your first ride from Slack. Go <#{url}|here> to activate."
  end
end
