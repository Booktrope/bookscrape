local_root = File.absolute_path(File.dirname(__FILE__))
# linking to custom modules
require File.join(local_root, "..", "..", "..", "booktrope-modules")

module TeamtropeTest
   class TestHarness
   
      attr_accessor :browsers
      attr_accessor :watir_browser
   
      def initialize(browsers = [:firefox])
   	   @browsers = browsers
   	   @watir_browser = nil
      end
   
      def run(is_headless, className, code)
         browsers.each do | browser |
	         set_up browser
	      
	         code.call
	      
	         tear_down
         end
      end
   
      private
      def set_up(browser)
         @watir_browser = Watir::Browser.new browser
      end
   
      def tear_down
   	   @watir_browser.quit
      end
   end
end