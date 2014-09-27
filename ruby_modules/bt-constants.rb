# Global constans for Ruby scripts, classes, modules, etc.
# Written By: Justin Jeffress
# Version 1.0
require 'singleton'
require 'json'
 
module Booktrope

	class PRICE_CHANGE
		SCHEDULED   = 0
		ATTEMPTED   = 25
		UNCONFIRMED = 50
		CONFIRMED   = 99
		NOT_ON_STORE = 404
		SCHEDULED_TEXT   = "Scheduled"
		ATTEMPTED_TEXT   = "Attempted"
		UNCONFIRMED_TEXT = "Unconfirmed"
		CONFIRMED_TEXT   = "Confirmed"
		NOT_ON_STORE_TEXT = "Not Found"
		AMAZON_CHANNEL = "Amazon"
		APPLE_CHANNEL  = "Apple"
		GOOGLE_CHANNEL = "GooglePlay"
		NOOK_CHANNEL   = "Nook"
	end

   class Constants < Hash
   	include Singleton
   	
   	AMAZON_ECS = "amazon-ecs"
   	AMAZON_KDP = "amazon-kdp"
   	ECS_ASSOCIATE_TAG = "associate_tag"
   	ECS_ACCESS_KEY_ID = "access_key_id"
   	ECS_SECRET_KEY = "secret_key"
   	GOOGLE_PLAY = "google-play"
   	PARSE = "parse"
   	PARSE_DEVELOPMENT = "parse-development"
   	PARSE_APP_KEY = "application_id"
   	PARSE_API_KEY = "api_key"
   	ITUNES_CONNECT = "itunes"
   	NOOKPRESS = "nookpress"
   	NOOK_URL = "nook_url"
   	CREATESPACE = "createspace"
   	LIGHTNING_SOURCE = "lightning-source"
   	MAILGUN = "mailgun"
   	API_KEY = "api_key"
   	DOMAIN = "domain"
   	TWILIO = "twilio"
   	ACCOUNT_SID = "account_sid"
   	AUTH_TOKEN = "auth_token"
   	RJMETRICS = "rjmetrics"
   	CLIENT_ID = "client_id"
   	
   	URL = "url"
   	USERNAME = "username"
   	PASSWORD = "password"
   	
   	def initialize
   		load_constants
   	end
   	
   	private
   	def load_constants
	   	basePath = File.absolute_path(File.dirname(__FILE__))
	   	config_json = JSON.parse(File.read(File.join(basePath, "..", "config", "config.json")))
	   	
	   	self[:amazon_ecs_associate_tag] = config_json[AMAZON_ECS][ECS_ASSOCIATE_TAG]
	   	self[:amazon_ecs_access_key_id] = config_json[AMAZON_ECS][ECS_ACCESS_KEY_ID]
	   	self[:amazon_ecs_secret_key]    = config_json[AMAZON_ECS][ECS_SECRET_KEY]
		
	   	self[:amazon_kdp_url]      = config_json[AMAZON_KDP][URL]
	   	self[:amazon_kdp_username] = config_json[AMAZON_KDP][USERNAME]
	   	self[:amazon_kdp_password] = config_json[AMAZON_KDP][PASSWORD]
	   	
	   	self[:google_play_url]      = config_json[GOOGLE_PLAY][URL]
	   	self[:google_play_username] = config_json[GOOGLE_PLAY][USERNAME]
	   	self[:google_play_password] = config_json[GOOGLE_PLAY][PASSWORD]
		
	   	self[:parse_application_id] = config_json[PARSE][PARSE_APP_KEY]
	   	self[:parse_api_key]        = config_json[PARSE][PARSE_API_KEY]
	   	
	   	self[:parse_dev_application_id] = config_json[PARSE_DEVELOPMENT][PARSE_APP_KEY]
	   	self[:parse_dev_api_key]        = config_json[PARSE_DEVELOPMENT][PARSE_API_KEY]
		
	   	self[:itunes_connect_url]      = config_json[ITUNES_CONNECT][URL]
	   	self[:itunes_connect_username] = config_json[ITUNES_CONNECT][USERNAME]
	   	self[:itunes_connect_password] = config_json[ITUNES_CONNECT][PASSWORD]
	   	self[:itunes_lookup_url]       = "http://itunes.apple.com/lookup"
		
	   	self[:nook_url]           = config_json[NOOK_URL]
		
	   	self[:nookpress_url]      = config_json[NOOKPRESS][URL]
	   	self[:nookpress_username] = config_json[NOOKPRESS][USERNAME]
	   	self[:nookpress_password] = config_json[NOOKPRESS][PASSWORD]
		
	   	self[:createspace_url]      = config_json[CREATESPACE][URL]
	   	self[:createspace_username] = config_json[CREATESPACE][USERNAME]
	   	self[:createspace_password] = config_json[CREATESPACE][PASSWORD]

	   	self[:lightning_source_url]      = config_json[LIGHTNING_SOURCE][URL]
	   	self[:lightning_source_username] = config_json[LIGHTNING_SOURCE][USERNAME]
	   	self[:lightning_source_password] = config_json[LIGHTNING_SOURCE][PASSWORD]
		
	   	self[:mailgun_api_key] = config_json[MAILGUN][API_KEY]
	   	self[:mailgun_domain]  = config_json[MAILGUN][DOMAIN]

	   	self[:twilio_account_sid]  = config_json[TWILIO][ACCOUNT_SID]
	   	self[:twilio_auth_token]   = config_json[TWILIO][AUTH_TOKEN]
		
	   	self[:rjmetrics_client_id] = config_json[RJMETRICS][CLIENT_ID]
	   	self[:rjmetrics_api_key]   = config_json[RJMETRICS][API_KEY]
	   	
   	end
   end
end