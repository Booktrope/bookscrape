require 'headless'

module Headless_harness

	@headless = nil
	
	def self.setup
		#puts "HEADLESS_HARNESS::SETUP"
		@headless = Headless.new
		@headless.start
	end
	
	def self.run(className, code, headless_lambda)
		self.setup
		#puts "HEADLESS_HARNESS::RUN invoking lambda"
		results = headless_lambda.call(className, code)
		self.teardown
		return results
	end
	
	def self.teardown
		#puts "HEADLESS_HARNESS::TEARDOWN"	
		@headless.destroy
	end

end