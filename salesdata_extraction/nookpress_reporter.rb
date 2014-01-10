require 'nokogiri'
require 'trollop'
require 'parse-ruby-client'
require 'time'

basePath = File.absolute_path(File.dirname(__FILE__))
# linking to custom modules
require File.join(basePath, "..", "ruby_modules", "constants")
require File.join(basePath, "..", "ruby_modules", "selenium_harness")


$opts = Trollop::options do

   banner <<-EOS
Extracts book sales data from nook press

   Usage:
            ruby nookpress_reporter.rb [--dontSaveToParse] [--headless]
   EOS

   opt :dontSaveToParse, "Turns off parse", :short => 'x'
   opt :headless, "Runs headless", :short => 'h'
   version "1.0.0 2014 Justin Jeffress"

end

should_run_headless = ($opts.headless) ?  true : false

class_name = "Salesdata_Extraction::Nookpress_reporter"
results = Selenium_harness.run(should_run_headless, class_name, lambda { | log |

	results = Array.new

	BT_CONSTANTS = BTConstants.get_constants
	url = BT_CONSTANTS[:nookpress_url]
	
	#requesting the page
	Selenium_harness.get(url)
	
	#finding and clicking the login button
	upper_login_button = Selenium_harness.find_element(:id, "clickclick")
	upper_login_button.click
	
	#entering credentials
	username_input = Selenium_harness.find_element(:id, "email")
	username_input.send_keys BT_CONSTANTS[:nookpress_username]
	
	password_input = Selenium_harness.find_element(:id, "password")
	password_input.send_keys BT_CONSTANTS[:nookpress_password]
	
	#clicking on the login button
	login_button = Selenium_harness.find_element(:id, "login_button")
	login_button.click
	
	wait = Selenium::WebDriver::Wait.new(:timeout => 5)

	#wait for the Sales link to appear and then click on it.
	wait.until { Selenium_harness.find_element(:link_text, "Sales").displayed? }	
	
	sales_link = Selenium_harness.find_element(:link_text, "Sales")
	sales_link.click
	
	#clicking on the monthly sales reports link
	#wait.until { Selenium_harness.find_element(:link_text, "Monthly Sales Reports") }

	#clicking on the Recent Sales link
	wait.until { Selenium_harness.find_element(:link_text, "Recent Sales").displayed? }
	
	recent_sales = Selenium_harness.find_element(:link_text, "Recent Sales")
	recent_sales.click
	
	wait.until { Selenium_harness.find_element(:xpath, "//table[@id='sales-report']/tbody/tr").displayed? }
	
	current_date = Date.parse(Time.now.to_s)
	
	
	the_page_data = Nokogiri.parse(Selenium_harness.page_source)
	the_sales_table = the_page_data.css("//table[@id='sales-report']/tbody/tr")
	
	the_sales_table.each do | row |
	
		#since this script runs before the current day is over, we don't want to grab 
		#today's stats since we could miss sales for that day, so we skip those and pull them tomorrow.
		next if Date.strptime(row.children[0].text.strip, "%m/%d/%Y").day == current_date.day
	
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

def get_book_hash()

	book_hash = Hash.new
	
	#getting the number of books in parse
	book_count = Parse::Query.new("Book").tap do |q|
   	q.limit = 0
   	q.count = 1
	end.get	 

	#requesting all books at once
	#TODO: parse is limited to 1000 rows per query. Need to update this to loop requests 
	#using skip to get everything.
	book_list = Parse::Query.new("Book").tap do |q|
		q.limit = book_count["count"]
	end.get

	#building the book_hash
	book_list.each do | book |
		book_hash[book["isbn"]] = book
	end
	
	return book_hash
end

def save_sales_data_to_parse(results)
	book_hash = get_book_hash

	results.each do | result |
		daily_sales = result[:units_sold].to_i
			
		#setting the crawl date
		date_array = result[:date].split("/")
		crawl_date = Parse::Date.new("#{date_array[2]}/#{date_array[0]}/#{date_array[1]} 00:00:00")
	
		#getting the book object to link the amazon_sales_data to.
		book = book_hash[result[:isbn]]
	
		nook_sales_data = Parse::Object.new("NookSalesData")
		nook_sales_data["book"] = book
		nook_sales_data["isbn"] = result[:isbn].to_i
		nook_sales_data["nookId"] = result[:bn_id].to_i
		nook_sales_data["country"] = result[:country]
		nook_sales_data["crawlDate"] = crawl_date
		nook_sales_data["dailySales"] = daily_sales
		nook_sales_data.save if !$opts.dontSaveToParse
		puts "#{nook_sales_data[:isbn]}\t#{nook_sales_data[:bn_id]}\t#{nook_sales_data[:country]}\t#{nook_sales_data[:date]}\t#{nook_sales_data[:units_sold]}"
		sleep(5.0)
	end	
end

if !results.nil? && results.count > 0
	#initialize parse
	Parse.init :application_id => BT_CONSTANTS[:parse_application_id],
		        :api_key        => BT_CONSTANTS[:parse_api_key]
	save_sales_data_to_parse(results)
end