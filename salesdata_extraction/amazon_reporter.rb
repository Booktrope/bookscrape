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
Extracts book sales data from Amazon KDP

   Usage:
            ruby amazon_reporter.rb [--dontSaveToParse] [--headless]
   EOS

   opt :dontSaveToParse, "Turns off parse", :short => 'x'
   opt :headless, "Runs headless", :short => 'h'
   version "1.0.0 2014 Justin Jeffress"

end

should_run_headless = ($opts.headless) ?  true : false

$BT_CONSTANTS = BTConstants.get_constants

class_name = "Salesdata_Extraction::Amazon_reporter"
results = Selenium_harness.run(should_run_headless, class_name, lambda { | log |
	
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
	
	#clicking on the reports button
	report_link = Selenium_harness.find_element(:link_text, "Reports")
	report_link.click
	
	sleep(5.0)
	
	#clicking on the month to date sales
	month_to_date_sales_link = Selenium_harness.find_element(:id, "mtdLink")
	month_to_date_sales_link.click
	
	wait = Selenium::WebDriver::Wait.new(:timeout => 15)
	wait.until { Selenium_harness.find_element(:css, "table#promotionTransactionsReports tbody tr").displayed? }
	
	#The country that appears first is US so we set it to US.
	country = "US"
	
	results = Array.new
	
	#declaring our lambda function since we need to run this code both outside and inside the loop.
	#sure we can do it with a loop but closures are fun too.
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
	
	#extracting the data from the US
	results.concat(print_lambda.call(Array.new))

	sleep(5.0)

	#getting the dropdown for country stores and looping through each country
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
	
		result[:daily_sales] = daily_sales
	
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


def send_report_email(results)
	top = "Amazon Sales Numbers for #{Date.today} PST<br />\n<br />\n"
	mailgun = Mailgun(:api_key => $BT_CONSTANTS[:mailgun_api_key], :domain => $BT_CONSTANTS[:mailgun_domain])
	email_parameters = {
		:to      => 'justin.jeffress@booktrope.com, andy@booktrope.com, heather.ludviksson@booktrope.com, Katherine Sears <ksears@booktrope.com>, Kenneth Shear <ken@booktrope.com>',
		:from    =>	'"Booktrope Daily Crawler 1.1" <justin.jeffress@booktrope.com>',
		:subject => 'Amazon Sales Numbers',
		:html    => top + Mail_helper.alternating_table_body(results.sort_by{|k| k[:daily_sales]}.reverse, "asin" => :asin, "Title" => :title, "Country" => :country, "Daily Sales" => :daily_sales, "Month To Date" => :net_sales, "Force Free" => :force_free, :total => [:daily_sales, :net_sales, :force_free])
	}

	mailgun.messages.send_email(email_parameters)
end

if !results.nil? && results.count > 0
	#initialize parse
	Parse.init :application_id => $BT_CONSTANTS[:parse_application_id],
		        :api_key        => $BT_CONSTANTS[:parse_api_key]
	save_sales_data_to_parse(results)
	send_report_email(results)
end