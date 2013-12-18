# Global constans for Ruby scripts, classes, modules, etc.
# Written By: Justin Jeffress
# Version 1.0
require 'json'

#The amazon ecs keys (used for referring to the key values in a config.json file)
class CONST_AWS
	LABEL = "amazon-ecs"
	ASSOCIATE_TAG = "associate_tag"
	ACCESS_KEY_ID = "access_key_id"
	SECRET_KEY = "secret_key"
end

class CONST_KDP
	LABEL = "amazon-kdp"
	URL = "url"
	USERNAME = "username"
	PASSWORD = "password"
end

#The parse.com keys (used for referring to the key values in a config.json file)
class CONST_PARSE
	LABEL = "parse"
	APPLICATION_ID = "application_id"
	API_KEY = "api_key"
end

class CONST_ITUNES_CONNECT
	LABEL = "itunes"
	URL = "url"
	USERNAME = "username"
	PASSWORD = "password"
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
		
		return hash
	end     
end