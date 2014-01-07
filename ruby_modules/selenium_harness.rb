require 'selenium-webdriver'
require File.join(File.absolute_path(File.dirname(__FILE__)), "bt_logging")
require File.join(File.absolute_path(File.dirname(__FILE__)), "headless_harness")

module Selenium_harness
	@driver = nil
	
	def self.driver		
		return @driver
	end
	
	def self.find_element(type, label)
		return @driver.find_element(type, label)
	end
	
	def self.page_source
		return @driver.page_source
	end
	
	def self.get(url)
		@driver.get(url)
	end
		
	def self.setup(headless)
		#puts "SELENIUM_HARNESS::SETUP"
		profile = Selenium::WebDriver::Firefox::Profile.new
		if headless && RbConfig::CONFIG['host_os'].start_with?("darwin")
			Selenium::WebDriver::Firefox::Binary.path = "/opt/local/lib/firefox-x11/firefox-bin"
			profile['general.useragent.override'] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.9; rv:25.0) Gecko/20100101 Firefox/25.0"
		end
		#puts "SELENIUM_HARNESS::SETUP #{Selenium::WebDriver::Firefox::Binary.path}"


		@driver = Selenium::WebDriver.for :firefox, :profile => profile
	end
	
	def self.teardown
		#puts "SELENIUM_HARNESS::TEARDOWN"
		@driver.quit
	end
	
	def self.run(should_run_headless, className, code)
		results = nil
		headless_lambda = lambda { | className, code |
			self.setup should_run_headless
			results = nil
			begin
				log = Bt_logging.create_logging(className)
				if code.respond_to? "call"
					log.info "starting"
					results = code.call(log)
					log.info "ending"
				end
			rescue Exception => e
			 log.error e.message
			end
			self.teardown			
			return results
		}

		if should_run_headless
			results = Headless_harness.run(className, code, headless_lambda)
		else
			results = headless_lambda.call(className, code)
		end	
		return results					
	end
end