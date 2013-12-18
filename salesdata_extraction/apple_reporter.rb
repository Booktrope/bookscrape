require 'nokogiri'
require 'parse-ruby-client'

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
		row_hash[:units_sold] = row.children[4].text
		row_hash[:country] = row.children[7].text
		row_hash[:apple_id] = row.children[8].text
		results.push(row_hash)
	end
	return results
})


def get_book_hash()
	book_hash = Hash.new

	#getting the number of books in parse
	book_count = Parse::Query.new("Book").tap do |q|
   	q.exists("appleId")
   	q.limit = 0
   	q.count = 1
	end.get	 

	#requesting all books at once
	#TODO: parse is limited to 1000 rows per query. Need to update this to loop requests 
	#using skip to get everything.
	book_list = Parse::Query.new("Book").tap do |q|
		q.exists("appleId")
		q.limit = book_count["count"]
	end.get

	book_list.each do | book |
		book_hash[book["appleId"]] = book
	end
	return book_hash
end

def save_sales_data_to_parse(results)
	book_hash = get_book_hash()
	results.each do | result |
		apple_sales_data = Parse::Object.new("AppleSalesData")
		apple_sales_data["book"] = book_hash[result[:apple_id].to_i]
		apple_sales_data["appleId"] = result[:apple_id].to_i
		apple_sales_data["dailySales"] = result[:units_sold].to_i
		apple_sales_data["country"] = result[:country]
		#TODO: get the date out of the page.
		apple_sales_data["crawlDate"] = Parse::Date.new((Date.today).strftime("%Y/%m/%d")+" 00:00:00")
		
		apple_sales_data.save
		puts "#{result[:title]}\t#{result[:units_sold]}\t#{result[:country]}\t#{result[:apple_id]}"
	end
end

if !results.nil? && results.count > 0
	#initialize parse
	Parse.init :application_id => BT_CONSTANTS[:parse_application_id],
		        :api_key        => BT_CONSTANTS[:parse_api_key]
	save_sales_data_to_parse(results)
end