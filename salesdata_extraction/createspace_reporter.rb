require 'nokogiri'
require 'trollop'
require 'parse-ruby-client'
require 'mail'

basePath = File.absolute_path(File.dirname(__FILE__))
# linking to custom modules
require File.join(basePath, "..", "ruby_modules", "constants")
require File.join(basePath, "..", "ruby_modules", "selenium_harness")
require File.join(basePath, "..", "ruby_modules", "mail_helper")

$opts = Trollop::options do

   banner <<-EOS
Extracts book sales data from createspace

   Usage:
            ruby createspace_reporter.rb [--dontSaveToParse] [--headless]
   EOS

   opt :dontSaveToParse, "Turns off parse", :short => 'x'
   opt :headless, "Runs headless", :short => 'h'
   version "1.0.0 2014 Justin Jeffress"

end

$amazon_channels = {"Amazon" => "US", "Amazon Europe - GBP" => "GB", "Amazon Europe - EUR" => "EU" }
should_run_headless = ($opts.headless) ?  true : false

class_name = "Salesdata_Extraction::Createspace_reporter"
results = Selenium_harness.run(should_run_headless, class_name, lambda { | log |

	results = Array.new
	BT_CONSTANTS = BTConstants.get_constants
	url = BT_CONSTANTS[:createspace_url]
	
	Selenium_harness.get(url)
	
	username_input = Selenium_harness.find_element(:id, "loginField")
	username_input.send_keys BT_CONSTANTS[:createspace_username]
	
	password_input = Selenium_harness.find_element(:id, "passwordField")
	password_input.send_keys BT_CONSTANTS[:createspace_password]
	
	login_button = Selenium_harness.find_element(:id, "login_button")
	login_button.click
	
	report_link = Selenium_harness.find_element(:link_text, "View Detailed Royalty Report")
	report_link.click
	
	royalty_by_channel = Selenium_harness.find_element(:link_text, "Royalty By Channel")
	royalty_by_channel.click
	
	#sleep(5.0)
	wait = Selenium::WebDriver::Wait.new(:timeout => 10)
	
	#wait.until { Selenium_harness.find_element(:id, "searchFormSection_edit") }
	#run_new_report_button = Selenium_harness.find_element(:id, "searchFormSection_edit")
	#puts run_new_report_button.attribute("value")
	#run_new_report_button.click
	
	wait.until { Selenium_harness.find_element(:id, "member_reports_dateoptions").displayed? }
	
	report_select = Selenium_harness.find_element(:id, "member_reports_dateoptions")
	report_options = report_select.find_elements(:tag_name, "option")	
	
	report_options.each do | option |
		option.click if option.attribute("value") == "TODAY"
	end
	
	advanced_expander = Selenium_harness.find_element(:id, "AdvancedExpander")
	advanced_expander.click
	
	show_isbn = Selenium_harness.find_element(:id, "member_reports_eancolumn")
	show_isbn.click
	
	show_asin = Selenium_harness.find_element(:id, "member_reports_asincolumn")
	show_asin.click
	
	run_report_button = Selenium_harness.find_element(:id, "searchFormSection_save")
	run_report_button.click
	
	wait.until { Selenium_harness.find_element(:css, "div#resultTable table tbody tr").displayed? }
	
	the_page_data = Nokogiri.parse(Selenium_harness.page_source)

	the_sales_table = the_page_data.css("div#resultTable table tbody tr")
	the_sales_table.each do | row |
		row_data = Hash.new
		row_data[:title] = row.children[0].text.strip
		row_data[:channel] = $amazon_channels[row.children[2].text.strip]
		row_data[:isbn] = row.children[4].text.strip
		row_data[:asin] = row.children[6].text.strip
		row_data[:units_sold] = row.children[8].text.strip
		results.push row_data
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
		daily_sales = result[:units_sold].to_i
			
		#setting the crawl date
		crawl_date = Parse::Date.new((Date.today).strftime("%Y/%m/%d")+" "+Time.now().strftime("%H:%M:%S"))
	
		#getting the book object to link the amazon_sales_data to.
		book = book_hash[result[:asin]]
		
		#TODO: createspace asins are for paperback boosks. looks like we need a way to link the paperback to
		#the ebook version of the book. Add a form to WP.
		#if we lack a book then it's not in parse so we add it. Next time the amazon book pick up tool runs
		#the rest of the data will be filled out.
		#if book.nil?
		#	book = Parse::Object.new("Book")
		#	book["asin"] = result[:asin]
		#	book.save
		#end
	
		cs_sales_data = Parse::Object.new("CreateSpaceSalesData")
		cs_sales_data["book"] = nil
		cs_sales_data["asin"] = result[:asin]
		cs_sales_data["country"] = result[:channel]
		cs_sales_data["crawlDate"] = crawl_date
		cs_sales_data["dailySales"] = daily_sales
		cs_sales_data.save if !$opts.dontSaveToParse
	end	
end

def send_report_email(results)
	mail = Mail.new do 
		to 'justin.jeffress@booktrope.com, andy@booktrope.com, heather.ludviksson@booktrope.com'
		from '"Booktrope Daily Crawler 1.0" <justin.jeffress@booktrope.com>'
		subject 'Createspace Sales Numbers'
	
		html_part do 
			content_type 'text/html; charset=UTF-8'
			top = "Createspace Sales Numbers for #{Date.today} PST<br />\n<br />\n"
			body top + Mail_helper.alternating_table_body(results.sort_by{ |k| k[:units_sold] }.reverse, "isbn" => :isbn, "Title" => :title, "Country" => :channel, "Daily Sales" => :units_sold)
		end
	end
	mail.deliver	
end

if !results.nil? && results.count > 0
	#initialize parse
	Parse.init :application_id => BT_CONSTANTS[:parse_application_id],
		        :api_key        => BT_CONSTANTS[:parse_api_key]
	save_sales_data_to_parse(results)
	send_report_email(results)
end