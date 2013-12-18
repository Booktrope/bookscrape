require 'nokogiri'
require 'parse-ruby-client'
require 'pp'

basePath = File.absolute_path(File.dirname(__FILE__))
# linking to custom modules
require File.join(basePath, "..", "ruby_modules", "constants")
require File.join(basePath, "..", "ruby_modules", "selenium_harness")

class_name = "Salesdata_Extraction::Apple_reporter"
results = Selenium_harness.run(class_name, lambda { | log |

	BT_CONSTANTS = BTConstants.get_constants
	url = BT_CONSTANTS[:itunes_connect_url]
	
	Selenium_harness.get(url)	
	
	username_input = Selenium_harness.find_element(:id, "accountname")
	username_input.send_keys BT_CONSTANTS[:itunes_connect_username]
	
	password_input = Selenium_harness.find_element(:id, "accountpassword")
	password_input.send_keys BT_CONSTANTS[:itunes_connect_password]
	
	login_button = Selenium_harness.find_element(:xpath, "(//input[@name='1.Continue'])[2]")
	login_button.click
	
	sales_and_trends_link = Selenium_harness.find_element(:link_text, "Sales and Trends")
	sales_and_trends_link.click
	
	sleep(1.0)
	#wait.until { Selenium_harness.find_element(:link_text, "Sales") }
	
	sales_link = Selenium_harness.find_element(:link_text, "Sales")
	sales_link.click

	sleep(5.0)

	the_page_data = Nokogiri.parse(Selenium_harness.page_source)
	
	the_sales_table = the_page_data.css("//table[@id='theForm:salesTable']/tbody/tr")
	
	results = Array.new
	the_sales_table.each do | row |
		row_hash = Hash.new
		row_hash[:title] = row.children[0].text
		row_hash[:units] = row.children[4].text
		row_hash[:country] = row.children[7].text
		row_hash[:apple_id] = row.children[8].text
		results.push(row_hash)
	end
	return results
})