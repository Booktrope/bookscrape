require "open-uri"
require "net/http"

# A simple module for downloading a file at a given URL.
# Written By: Justin Jeffress
# Version 1.1

require File.join(File.absolute_path(File.dirname(__FILE__)), "bt_logging")

module Download_simple
	@log = Bt_logging.create_logging('Ruby_module::Download_simple')
	
	def self.downloadData(url, openTimeOut = 30, readTimeOut = 30)
		uri = URI.parse(url)
		http = Net::HTTP.new(uri.host, uri.port)
		http.open_timeout = openTimeOut
		http.read_timeout = readTimeOut
		useragent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/46.0.2490.86 Safari/537.36"

		request = Net::HTTP::Get.new(uri.request_uri)
		request.initialize_http_header(
					{
						'Accept-Language' => 'en-US,en;q=0.8',
						'Cache-Control' => 'max-age=0',
						'User-Agent' => useragent
					}
				)

		@log.info "connecting to: " + url
      
		begin
		   response = http.request(request)
		rescue
         @log.error "operation timed out when attempting to access " + url
			return nil
		end

		if response.code == "301" || response.code == "302"
			if response['location'] != nil
				redirectLink = response['location']
				$stderr.puts "redirecting to: " + redirectLink + "\n"
				if !redirectLink.start_with?("http://") 
					redirectLink = "http://" + uri.host + redirectLink
				end
				@log.info "redirecting to: " + redirectLink + "\n"
				response = Net::HTTP.get_response(URI.parse(redirectLink))
			end
		end
		return response;
	end
end