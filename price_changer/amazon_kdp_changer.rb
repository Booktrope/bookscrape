require 'nokogiri'
require 'trollop'
require 'parse-ruby-client'
require 'mailgun'

basePath = File.absolute_path(File.dirname(__FILE__))
# linking to custom modules
require File.join(basePath, "..", "ruby_modules", "constants")
require File.join(basePath, "..", "ruby_modules", "selenium_harness")
require File.join(basePath, "..", "ruby_modules", "mail_helper")

$opts = Trollop::options do

   banner <<-EOS
Changes prices of books on KDP Select.

   Usage:
            ruby amazon_kdp_changer.rb [--dontSaveToParse] [--headless]
   EOS

   opt :dontSaveToParse, "Turns off parse", :short => 'x'
   opt :headless, "Runs headless", :short => 'h'
   version "1.0.0 2014 Justin Jeffress"

end

$should_run_headless = ($opts.headless) ?  true : false

#Parse.init :application_id => $BT_CONSTANTS[:parse_application_id],
#	        :api_key        => $BT_CONSTANTS[:parse_api_key]

Parse.init :application_id => "RIaidI3C8TOI7h6e3HwEItxYGs9RLXxhO0xdkdM6",
	        :api_key        => "EQVJvWgCKVp4zCc695szDDwyU5lWcO3ssEJzspxd"

$BT_CONSTANTS = BTConstants.get_constants

def change_prices(change_hash)
	class_name = "Price_Changer::Amazon_KDP_Changer"
	results = Selenium_harness.run($should_run_headless, class_name, lambda { | log |

		url = $BT_CONSTANTS[:amazon_kdp_url]
	
		#getting the amazon kdp page
		Selenium_harness.get(url)
	
		#clicking the login button
		sign_button = Selenium_harness.find_element(:css, "a.a-button-text")
		sign_button.click
	
		#entering the username and password
		username_input = Selenium_harness.find_element(:id, "ap_email")
		username_input.send_keys $BT_CONSTANTS[:amazon_kdp_username]
	
		password_input = Selenium_harness.find_element(:id, "ap_password")
		password_input.send_keys $BT_CONSTANTS[:amazon_kdp_password]
	
		#clicking the login button
		login_button = Selenium_harness.find_element(:id, "signInSubmit-input")
		login_button.click
	
		wait = Selenium::WebDriver::Wait.new(:timeout => 5)
	
		done = false
		i = 0
		while(!done)
			puts "Page: #{i+1}"
			books = Selenium_harness.find_elements(:xpath, "//tr[@class='mt-row']")
			books.each do | book |
				asin_elements = book.find_elements(:css, "div.asinText")
				if asin_elements.count > 0
					asin = asin_elements[0].text.strip.gsub(/\(ASIN: /, "").gsub(/\)$/, "")
					puts asin
					if change_hash.has_key? asin
						puts "match!!!"
						
						anchor = book.find_element(:css, "div.kdpTitleField.kdpTitleLabel a.a-link-normal.mt-link-content")
						anchor.click
						
						step2_link = Selenium_harness.find_element(:id, "title-setup-step2")
						step2_link.click
						
						
						change_hash.delete asin
						break if change_hash.size <= 0
					end
				end
			end
			break if change_hash.size <= 0
			next_button = Selenium_harness.find_elements(:xpath, "//a[contains(@href, '#next')]")
			if next_button.count > 0
				next_button[0].click
				sleep(5.0)
				wait.until { Selenium_harness.find_element(:xpath, "//tr[@class='mt-row']").displayed? }				
			else
				done = true 
			end
			i = i + 1
		end
	})
end

changelings = Parse::Query.new("PriceChangeQueue").tap do |q|
	q.less_eq("changeDate", Parse::Date.new(((Date.today+1).strftime("%Y/%m/%d")+" "+"00:00:00")))
	q.eq("status", 0)
	q.include = "book"
end.get

change_hash = Hash.new

changelings.each do | changeling |
	puts "#{changeling["asin"]}\t#{changeling["book"]["title"]}\t#{changeling["book"]["author"]}\t#{changeling["price"]}"
	change_hash[changeling["asin"]] = changeling
end

change_prices(change_hash)