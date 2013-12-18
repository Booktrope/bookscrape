require 'nokogiri'
require 'parse-ruby-client'
require 'pp'

basePath = File.absolute_path(File.dirname(__FILE__))
# linking to custom modules
require File.join(basePath, "..", "ruby_modules", "constants")
require File.join(basePath, "..", "ruby_modules", "selenium_harness")

class_name = "Salesdata_Extraction::Nookpress_reporter"
results = Selenium_harness.run(class_name, lambda { | log |

	results = Array.new

	BT_CONSTANTS = BTConstants.get_constants
	url = BT_CONSTANTS[:nookpress_url]
	
	Selenium_harness.get(url)
	
	upper_login_button = Selenium_harness.find_element(:id, "clickclick")
	upper_login_button.click
	
	username_input = Selenium_harness.find_element(:id, "email")
	username_input.send_keys BT_CONSTANTS[:nookpress_username]
	
	password_input = Selenium_harness.find_element(:id, "password")
	password_input.send_keys BT_CONSTANTS[:nookpress_password]
	
	login_button = Selenium_harness.find_element(:id, "login_button")
	login_button.click
	
	sleep(5.0)
	
	sales_link = Selenium_harness.find_element(:link_text, "Sales")
	sales_link.click
	
	sleep(1.0)
	
	recent_sales = Selenium_harness.find_element(:link_text, "Recent Sales")
	recent_sales.click
	
	sleep(5.0)
	
	the_page_data = Nokogiri.parse(Selenium_harness.page_source)
	the_sales_table = the_page_data.css("//table[@id='sales-report']/tbody/tr")
	
	the_sales_table.each do | row |
		row_hash = Hash.new
		row_hash[:date]       = row.children[0].text.strip
		row_hash[:bn_id]      = row.children[4].text.strip
		row_hash[:isbn]       = row.children[6].text.strip
		row_hash[:title]      = row.children[8].text.strip
		row_hash[:country]    = row.children[12].text
		row_hash[:units_sold] = row.children[18].text
		results.push row_hash
	end
	return results
})

#TODO: save the data to parse
pp results