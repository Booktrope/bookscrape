require 'selenium-webdriver'
require File.join(File.absolute_path(File.dirname(__FILE__)), "bt_logging")

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
		
	def self.setup
		@driver = Selenium::WebDriver.for :firefox
	end
	
	def self.teardown
		@driver.quit
	end
	
	def self.run(className,code)
		result = nil
		self.setup
		#begin
			log = Bt_logging.create_logging(className)
			if code.respond_to? "call"
				log.info "starting"
				results = code.call(log)
				log.info "ending"
			end
		#rescue Exception => e
		# log.error e.message
		#end
		self.teardown
		return results
	end

end