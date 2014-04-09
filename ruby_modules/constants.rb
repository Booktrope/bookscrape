# Global constans for Ruby scripts, classes, modules, etc.
# Written By: Justin Jeffress
# Version 1.0
require 'json'

#The amazon ecs keys (used for referring to the key values in a config.json file)
class CONST_AWS
	LABEL         = "amazon-ecs"
	ASSOCIATE_TAG = "associate_tag"
	ACCESS_KEY_ID = "access_key_id"
	SECRET_KEY    = "secret_key"
end

class CONST_KDP
	LABEL    = "amazon-kdp"
	URL      = "url"
	USERNAME = "username"
	PASSWORD = "password"
end

class PRICE_CHANGE
	SCHEDULED   = 0
	ATTEMPTED   = 25
	UNCONFIRMED = 50
	CONFIRMED   = 99
	AMAZON_CHANNEL = "Amazon"
	APPLE_CHANNEL  = "Apple"
	NOOK_CHANNEL   = "Nook"
end

#The parse.com keys (used for referring to the key values in a config.json file)
class CONST_PARSE
	LABEL          = "parse"
	APPLICATION_ID = "application_id"
	API_KEY        = "api_key"
end

class CONST_ITUNES_CONNECT
	LABEL    = "itunes"
	URL      = "url"
	USERNAME = "username"
	PASSWORD = "password"
end

class CONST
	NOOKURL = "nook_url"
end

class CONST_NOOKPRESS
	LABEL    = "nookpress"
	URL      = "url"
	USERNAME = "username"
	PASSWORD = "password"
end

class CONST_CREATESPACE
	LABEL    = "createspace"
	URL      = "url"
	USERNAME = "username"
	PASSWORD = "password"
end

class CONST_LIGHTNING_SOURCE
	LABEL    = "lightning-source"
	URL      = "url"
	USERNAME = "username"
	PASSWORD = "password"
end

class CONST_MAILGUN
	LABEL   = "mailgun"
	API_KEY = "api_key"
	DOMAIN  = "domain"
end

class CONST_TWILIO
	LABEL = "twilio"
	ACCOUNT_SID = "account_sid"
	AUTH_TOKEN = "auth_token"
end

module BTConstants
   @basePath = File.absolute_path(File.dirname(__FILE__))
	@constants = nil
	def self.get_constants
		if @constants.nil?
			@constants = self.load_constants
		end
		return @constants
	end

	def self.load_constants
		config_json = JSON.parse(File.read(File.join(@basePath, "..", "config", "config.json")))
		hash = Hash.new
		
		hash[:amazon_ecs_associate_tag] = config_json[CONST_AWS::LABEL][CONST_AWS::ASSOCIATE_TAG]
		hash[:amazon_ecs_access_key_id] = config_json[CONST_AWS::LABEL][CONST_AWS::ACCESS_KEY_ID]
		hash[:amazon_ecs_secret_key]    = config_json[CONST_AWS::LABEL][CONST_AWS::SECRET_KEY]
		
		hash[:amazon_kdp_url]      = config_json[CONST_KDP::LABEL][CONST_KDP::URL]
		hash[:amazon_kdp_username] = config_json[CONST_KDP::LABEL][CONST_KDP::USERNAME]
		hash[:amazon_kdp_password] = config_json[CONST_KDP::LABEL][CONST_KDP::PASSWORD]
		
		hash[:parse_application_id] = config_json[CONST_PARSE::LABEL][CONST_PARSE::APPLICATION_ID]
		hash[:parse_api_key]        = config_json[CONST_PARSE::LABEL][CONST_PARSE::API_KEY]
		
		hash[:itunes_connect_url]      = config_json[CONST_ITUNES_CONNECT::LABEL][CONST_ITUNES_CONNECT::URL]
		hash[:itunes_connect_username] = config_json[CONST_ITUNES_CONNECT::LABEL][CONST_ITUNES_CONNECT::USERNAME]
		hash[:itunes_connect_password] = config_json[CONST_ITUNES_CONNECT::LABEL][CONST_ITUNES_CONNECT::PASSWORD]
		hash[:itunes_lookup_url] = "http://itunes.apple.com/lookup"
		
		hash[:nook_url]           = config_json[CONST::NOOKURL]
		
		hash[:nookpress_url]      = config_json[CONST_NOOKPRESS::LABEL][CONST_NOOKPRESS::URL]
		hash[:nookpress_username] = config_json[CONST_NOOKPRESS::LABEL][CONST_NOOKPRESS::USERNAME]
		hash[:nookpress_password] = config_json[CONST_NOOKPRESS::LABEL][CONST_NOOKPRESS::PASSWORD]
		
		hash[:createspace_url]      = config_json[CONST_CREATESPACE::LABEL][CONST_CREATESPACE::URL]
		hash[:createspace_username] = config_json[CONST_CREATESPACE::LABEL][CONST_CREATESPACE::USERNAME]
		hash[:createspace_password] = config_json[CONST_CREATESPACE::LABEL][CONST_CREATESPACE::PASSWORD]

		hash[:lightning_source_url]      = config_json[CONST_LIGHTNING_SOURCE::LABEL][CONST_LIGHTNING_SOURCE::URL]
		hash[:lightning_source_username] = config_json[CONST_LIGHTNING_SOURCE::LABEL][CONST_LIGHTNING_SOURCE::USERNAME]
		hash[:lightning_source_password] = config_json[CONST_LIGHTNING_SOURCE::LABEL][CONST_LIGHTNING_SOURCE::PASSWORD]
		
		hash[:mailgun_api_key] = config_json[CONST_MAILGUN::LABEL][CONST_MAILGUN::API_KEY]
		hash[:mailgun_domain]  = config_json[CONST_MAILGUN::LABEL][CONST_MAILGUN::DOMAIN]

		hash[:twilio_account_sid]  = config_json[CONST_TWILIO::LABEL][CONST_TWILIO::ACCOUNT_SID]
		hash[:twilio_auth_token]   = config_json[CONST_TWILIO::LABEL][CONST_TWILIO::AUTH_TOKEN]
		
		return hash
	end
end