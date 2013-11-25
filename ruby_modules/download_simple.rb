require "open-uri"
require "net/http"

# A simple module for downloading a file at a given URL.
# Written By: Justin Jeffress
# Version 1.1

module Download_simple


Logging.color_scheme( 'bright',
:levels => {
	:info  => :green,
	:warn  => :yellow,
	:error => :red,
	:fatal => [:white, :on_red]
   },
	:date => :blue,
	:logger => :cyan,
	:message => :magenta
)

Logging.appenders.stderr(
	'stderr',
	:layout => Logging.layouts.pattern(
	:pattern => '[%d] %-5l %c: %m\n',
	:color_scheme => 'bright'
   )
)

@log = Logging.logger['Ruby_module::Download_simple']
@log.add_appenders Logging.appenders.stderr
@log.level = :debug


   def self.downloadData(url, openTimeOut = 30, readTimeOut = 30)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = openTimeOut
      http.read_timeout = readTimeOut
      useragent = "Mozilla/5.0 (Windows NT 6.1; rv:6.0) Gecko/20110814 Firefox/6.0"

      request = Net::HTTP::Get.new(uri.request_uri)
      request.initialize_http_header({'User-Agent' => useragent})

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