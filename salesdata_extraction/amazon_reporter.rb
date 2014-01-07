require 'nokogiri'
require 'trollop'
require 'parse-ruby-client'

basePath = File.absolute_path(File.dirname(__FILE__))
# linking to custom modules
require File.join(basePath, "..", "ruby_modules", "constants")
require File.join(basePath, "..", "ruby_modules", "selenium_harness")

$opts = Trollop::options do

   banner <<-EOS
Extracts book sales data from Amazon KDP

   Usage:
            ruby amazon_reporter.rb [--dontSaveToParse] [--headless]
   EOS

   opt :dontSaveToParse, "Turns off parse", :short => 'x'
   opt :headless, "Runs headless", :short => 'h'
   version "1.0.0 2014 Justin Jeffress"

end

should_run_headless = ($opts.headless) ?  true : false

class_name = "Salesdata_Extraction::Amazon_reporter"
results = Selenium_harness.run(should_run_headless, class_name, lambda { | log |
	BT_CONSTANTS = BTConstants.get_constants
	url = BT_CONSTANTS[:amazon_kdp_url]
	
	Selenium_harness.get(url)
	
	sign_button = Selenium_harness.find_element(:id, "dtp_signin")
	sign_button.click
	
	username_input = Selenium_harness.find_element(:id, "ap_email")
	username_input.send_keys BT_CONSTANTS[:amazon_kdp_username]
	
	password_input = Selenium_harness.find_element(:id, "ap_password")
	password_input.send_keys BT_CONSTANTS[:amazon_kdp_password]
	
	login_button = Selenium_harness.find_element(:id, "signInSubmit-input")
	login_button.click
	
	report_link = Selenium_harness.find_element(:link_text, "Reports")
	report_link.click
	
	month_to_date_sales_link = Selenium_harness.find_element(:id, "mtdLink")
	month_to_date_sales_link.click
	
	sleep(5.0)
	
	country = "US"
	
	results = Array.new
	
	print_lambda = lambda { | extraction_array |
		report_page = Nokogiri.parse(Selenium_harness.page_source)
		promo_table_rows = report_page.css("table#promotionTransactionsReports tbody tr")
		promo_table_rows.each do | row |
			break if row.children.size < 9
			extraction_data = Hash.new
			extraction_data[:title]      = row.children[1].text
			extraction_data[:asin]       = row.children[2].text
			extraction_data[:net_sales]  = row.children[5].text
			extraction_data[:force_free] = row.children[8].text
			extraction_data[:country]    = country
			extraction_array.push(extraction_data)
		end
		return extraction_array
	}
	
	results.concat(print_lambda.call(Array.new))

	report_select = Selenium_harness.find_element(:id, "marketplaceSelect")
	report_options = report_select.find_elements(:tag_name, "option")
	report_options.each do | option |
		next if option.attribute("value") == "US"
		extraction_data = Hash.new
		country = option.attribute("value")
		
		option.click
		sleep(5.0)
		
		results.concat(print_lambda.call(Array.new))
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
		book_hash[book["asin"]] = book
	end
	
	return book_hash
end

def save_sales_data_to_parse(results)

	book_hash = get_book_hash

	results.each do | result |
		
		net_sales = result[:net_sales].to_i
		daily_sales = net_sales
		
		#setting the crawl date
		crawl_date = Parse::Date.new((Date.today).strftime("%Y/%m/%d")+" "+Time.now().strftime("%H:%M:%S"))
	
		#checking to see if we have a record from the previous day only if it's not the first of the month.
		if Date.today.day != 1
			old_sales_data = Parse::Query.new("AmazonSalesData").tap do |q|
				q.greater_than("crawlDate", Parse::Date.new(((Date.today-1).strftime("%Y/%m/01")+" "+"00:00:00")))
				q.eq("asin", result[:asin])
				q.eq("country", result[:country])
				q.order_by = "crawlDate"
				q.order = :descending
				q.limit = 1
			end.get.first
		end
	
		#amazon tracks month to date sales, so we need to subtract yesterday's net from today's
		if !old_sales_data.nil?
			daily_sales = net_sales - old_sales_data["netSales"].to_i
			puts "daily sales: #{daily_sales}"
		end
	
		#getting the book object to link the amazon_sales_data to.
		book = book_hash[result[:asin]]
		
		#if we lack a book then it's not in parse so we add it. Next time the amazon book pick up tool runs
		#the rest of the data will be filled out.
		if book.nil?
			book = Parse::Object.new("Book")
			book["asin"] = result[:asin]
			book.save if !$opts.dontSaveToParse
		end
	
		amazon_sales_data = Parse::Object.new("AmazonSalesData")
		amazon_sales_data["book"] = book
		amazon_sales_data["asin"] = result[:asin]
		amazon_sales_data["netSales"] = net_sales
		amazon_sales_data["forceFree"] = result[:force_free].to_i
		amazon_sales_data["country"] = result[:country]
		amazon_sales_data["crawlDate"] = crawl_date
		amazon_sales_data["dailySales"] = daily_sales
		
		amazon_sales_data.save if !$opts.dontSaveToParse
		
	end
end

if !results.nil? && results.count > 0
	#initialize parse
	Parse.init :application_id => BT_CONSTANTS[:parse_application_id],
		        :api_key        => BT_CONSTANTS[:parse_api_key]
	save_sales_data_to_parse(results)
end