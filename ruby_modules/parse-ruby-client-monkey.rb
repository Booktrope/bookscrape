require 'parse-ruby-client'

module Parse
	class Batch
		attr_accessor :max_requests

		def add_request_run_when_full(request)
			if @requests.length >= @max_requests
				self.run!
				@requests.clear
			end
			@requests << request
		end

		def create_object_run_when_full!(object)
			method = "POST"
			path = Parse::Protocol.class_uri(object.class_name)
			body = object.safe_hash
			add_request_run_when_full({
				"method" => method,
				"path" => path,
				"body" => body
			})
		end		

		def update_object_run_when_full!(object)
			method = "PUT"
			path = Parse::Protocol.class_uri(object.class_name, object.id)
			body = object.safe_hash
			add_request_run_when_full({
				"method" => method,
				"path" => path,
				"body" => body
			})
		end
		
		def delete_object_run_when_full!(object)
			add_request_run_when_full({
				"method" => "DELETE",
				"path" => Parse::Protocol.class_uri(object.class_name, object.id)
			})
		end
		
		def marshal_dump
			[requests, client]
		end
		
		def marshal_load(array)
			@requests, client = array
		end
		
	end
	
	class Date
		def marshal_load(array)
			
		end
	end
	
	class Client
		def marshal_dump
			[host, application_id, api_key, master_key, session_token, max_retries]
		end
		
		def marshal_load(array)
			host, application_id, api_key, master_key, session_token, max_retries = array
		end
	end
end