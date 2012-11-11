require 'oauth2'
require 'json'
require 'yaml'
require 'singleton'
require 'eventmachine'
require 'time'
require_relative 'MqttProxy.rb'
# Load Config
CONFIG = YAML.load_file("config.yml") unless defined? CONFIG

class Calendar
	include Singleton
	def initialize()
		puts "(ThreadID #{Thread.current.object_id}) Initializing calendar proxy"

		@client_id = CONFIG['googlecalendar']['apiKey']
		@client_secret = CONFIG['googlecalendar']['apiSecret']		
		@refreshToken = CONFIG['googlecalendar']['refreshToken'] # Optional
		@scope =  "https://www.googleapis.com/auth/calendar"
		@accessToken = nil
		@calendarID = CONFIG['googlecalendar']['calendarID']


		raise "Missing googlecalendar:apiKey config parameter" if @client_id.to_s.empty?
		raise "Missing googlecalendar:apiSecret config parameter" if @client_secret.to_s.empty?
		raise "Missing googlecalendar:calendarID config parameter" if @calendarID.to_s.empty?
	end

	def run()
		calendarPollPeriodically()
	end

	def calendarPollPeriodically(interval = 2)
		puts "Polling periodically every #{interval} seconds"
		@pollIntervall = interval
		 timer = EventMachine::PeriodicTimer.new(interval) do
			getNextEvent()
		 end
	end

	def getNextEvent() 
		# Test to get list of calendars
		# getQuery("/calendar/v3/users/me/calendarList")

		# Formats minimal start date of events according to te wishes of the Google Calendar API (2012-10-12T11:50:00+02:00) and URL escapes ':' and '+' characters
		startTime = "#{Time.now.strftime('%Y-%m-%dT%H%%3A%M%%3A%S%:z').sub( "+", "%2B" ).sub(":", "%3A")}"
		query = "calendar/v3/calendars/alr.st_t4do0ippogfurs00brmpgfhre0%40group.calendar.google.com/events?singleEvents=true&fields=items(description%2Cstart%2Cend%2Csummary)&orderBy=startTime&timeMin=#{startTime}"
		result = getQuery(query)	
		items = JSON.parse(result.body)['items'];
		
		return if items.nil?

		items.each do |event|

			startTimeStr = event["start"]["dateTime"];
			endTimeStr = event["end"]["dateTime"];
			device = event['summary']
			description = event['description'];

			next if description.nil?

			descriptionJSON=JSON.parse(description);

 			startTimediff = Time.parse(startTimeStr) - Time.now()
 			endTimediff = Time.parse(endTimeStr) - Time.now()



 			if (startTimediff > 0) then
 				puts "Start events in #{startTimediff.to_i}s/#{(startTimediff/60).to_i}m :"
 				descriptionJSON["start"].each do |event| 
 					puts "#{event.keys[0]}:#{event.values[0]}"
 				end
 			end

			if (endTimediff > 0) then
 				puts "End events in #{endTimediff.to_i}s/#{(endTimediff/60).to_i}m :"
 				descriptionJSON["end"].each do |event| 
 					puts "#{event.keys[0]}:#{event.values[0]}"
 				end
 			end

			if (startTimediff.abs() < @pollIntervall) then
 				descriptionJSON["start"].each do |event| 
 					puts "Publishing #{event.keys[0]}:#{event.values[0]}"
 					MqttProxy.instance().publish(event.keys[0], event.values[0])	#Publish twice just in case
 					MqttProxy.instance().publish(event.keys[0], event.values[0])
 				end
			end

			if (endTimediff.abs() < @pollIntervall) then
 				descriptionJSON["end"].each do |event| 
 					puts "Publishing #{event.keys[0]}:#{event.values[0]}"
 					MqttProxy.instance().publish(event.keys[0], event.values[0])
 					MqttProxy.instance().publish(event.keys[0], event.values[0])

 				end
			end
		end
	end

	def getQuery(query)
		authorizeOAuth2IfRequired()
		api_client_obj = OAuth2::Client.new(@client_id, @client_secret, {:site => 'https://www.googleapis.com'})
		api_access_token_obj = OAuth2::AccessToken.new(api_client_obj, @accessToken.token)
		result = api_access_token_obj.get(query)
	end



	def authorizeOAuth2IfRequired()
		#puts "Checking Google Calendar Oauth2 authentication"

		if (@accessToken == nil || @accessToken.expired?) then

			#Request new access token with refresh token if request token exists
			unless (@refreshToken == "") then
				refreshTokens()
			else # If no access token and no refresh token exists, we have to request authentication again
				puts "Client is not authorized yet. Autorizing for Google Calendar with OAuth2"

				redirect_uri = 'http://localhost/oauth2callback'
				auth_client_obj = OAuth2::Client.new(@client_id, @client_secret, {:site => 'https://accounts.google.com', :authorize_url => "/o/oauth2/auth", :token_url => "/o/oauth2/token"})

				puts "1) Paste this URL into your browser where you are logged in to the relevant Google account:"
				puts auth_client_obj.auth_code.authorize_url(:scope => @scope, :access_type => "offline", :redirect_uri => redirect_uri, :approval_prompt => 'force')

				puts "2) Accept the authorization request from Google in your browser:"
				puts "3) Google will redirect you to localhost, but just copy the code parameter out of the URL they redirect you to, paste it here and hit enter:\n"

				code = gets.chomp.strip
				@accessToken = auth_client_obj.auth_code.get_token(code, { :redirect_uri => redirect_uri, :token_method => :post })
				puts "4) Set the config parameter googlecalendar:refreshToken to #{@accessToken.refresh_token}"
			end

			unless (@accessToken.refresh_token.nil?) then
				@refreshToken = @accessToken.refresh_token
			end

		else 
			# puts "Client is already authorized"
		end
	end

	def refreshTokens()
		#puts "Refreshing Google Calendar OAuth2 token using refreshToken #{@refreshToken}"
		accessTokenStr = ""
		if (@accessToken != nil && @accessToken.token != nil) then 
			accessTokenStr = @accessToken.token
		end

		refresh_client_obj = OAuth2::Client.new(@client_id, @client_secret, {:site => 'https://accounts.google.com', :authorize_url => '/o/oauth2/auth', :token_url => '/o/oauth2/token'})
		refresh_access_token_obj = OAuth2::AccessToken.from_hash(refresh_client_obj, {:access_token => accessTokenStr, :refresh_token => @refreshToken, :token_type => "Bearer"})
		
		newAccessToken = refresh_access_token_obj.refresh!
		@accessToken = newAccessToken

		# The new AccessToken object might not have a refresh token set when no refresh token was returned from the server
		# In this case we keep using the old one. Otherwise we update the used refresh token with the new one
		if (@accessToken.refresh_token != nil && @accessToken.refresh_token != "") then 
			@refreshToken = @accessToken.refresh_token
		end
	end


end

# Start the whole thing
EventMachine.run {
	Calendar.instance().run()
	MqttProxy.instance().run()
	Signal.trap("INT") {  EventMachine.stop }
}
