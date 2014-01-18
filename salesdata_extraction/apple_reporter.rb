require 'nokogiri'
require 'trollop'
require 'parse-ruby-client'
require 'time'
require 'mailgun'

basePath = File.absolute_path(File.dirname(__FILE__))
# linking to custom modules
require File.join(basePath, "..", "ruby_modules", "constants")
require File.join(basePath, "..", "ruby_modules", "selenium_harness")
require File.join(basePath, "..", "ruby_modules", "mail_helper")

$opts = Trollop::options do

   banner <<-EOS
Extracts book sales data from iTunes Connect

   Usage:
            ruby apple_reporter.rb [--dontSaveToParse] [--headless]
   EOS

   opt :dontSaveToParse, "Turns off parse", :short => 'x'
   opt :headless, "Runs headless", :short => 'h'
   version "1.0.0 2014 Justin Jeffress"

end

should_run_headless = ($opts.headless) ?  true : false
class_name = "Salesdata_Extraction::Apple_reporter"

def get_sales_from_table(the_sales_table, sales_date)
	results = Array.new
	the_sales_table.each do | row |
		row_hash = Hash.new
		row_hash[:title] = row.children[0].text
		row_hash[:units_sold] = row.children[4].text
		row_hash[:country] = row.children[7].text
		row_hash[:apple_id] = row.children[8].text
		row_hash[:crawl_date] = sales_date
		results.push(row_hash)
	end
	return results
end

$BT_CONSTANTS = BTConstants.get_constants
results = Selenium_harness.run(should_run_headless,class_name, lambda { | log |
	results = Array.new

	url = $BT_CONSTANTS[:itunes_connect_url]
	
	Selenium_harness.get(url)	
	
	username_input = Selenium_harness.find_element(:id, "accountname")
	username_input.send_keys $BT_CONSTANTS[:itunes_connect_username]
	
	password_input = Selenium_harness.find_element(:id, "accountpassword")
	password_input.send_keys $BT_CONSTANTS[:itunes_connect_password]
	
	login_button = Selenium_harness.find_element(:xpath, "(//input[@name='1.Continue'])[2]")
	login_button.click
	
	sales_and_trends_link = Selenium_harness.find_element(:link_text, "Sales and Trends")
	sales_and_trends_link.click
	
	wait = Selenium::WebDriver::Wait.new(:timeout => 5)
	
	wait.until { Selenium_harness.find_element(:id, "chart_canvas_kit").displayed? }
	wait.until { Selenium_harness.find_element(:link_text, "Sales") }
	
	sales_link = Selenium_harness.find_element(:link_text, "Sales")
	sales_link.click

	sleep(5.0)
	#wait.until { Selenium_harness.find_element(:xpath, "//table[@id='theForm:salesTable']/tbody/tr") }

	
	the_page_data = Nokogiri.parse(Selenium_harness.page_source)	
	the_sales_table = the_page_data.css("//table[@id='theForm:salesTable']/tbody/tr")
	
	#getting the current date
	date = the_page_data.css("div#chosenDate")
	
	date_parts = date.text.strip.split
	sales_date = "#{date_parts[2]}/#{Date::ABBR_MONTHNAMES.index(date_parts[0]).to_s.rjust(2,'0')}/#{date_parts[1].gsub(/,/,"").rjust(2,'0')} 00:00:00"
   results.concat get_sales_from_table(the_sales_table, sales_date)
   
	#removed code that clicks the previous date Git Hash: d7b22336ed69a8caa957b023348d360a9aee9c0e
	
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
		apple_sales_data["crawlDate"] = Parse::Date.new(result[:crawl_date])
		
		puts "#{result[:title]}\t#{result[:units_sold]}\t#{result[:country]}\t#{result[:apple_id]}\t#{result[:crawl_date]}" if $opts.dontSaveToParse
		
		if !$opts.dontSaveToParse
			begin	
				apple_sales_data.save
			rescue Exception => e
				puts e.message
			end
			sleep(5.0)
		end
	end
end

def send_report_email(results)

	top = "Apple Sales Numbers for #{results[0][:crawl_date]} PST <br /><br />\n"
	mailgun = Mailgun(:api_key => $BT_CONSTANTS[:mailgun_api_key], :domain => $BT_CONSTANTS[:mailgun_domain])
	email_parameters = {
		:to      => 'justin.jeffress@booktrope.com, andy@booktrope.com, heather.ludviksson@booktrope.com',
		:from    =>	'"Booktrope Daily Crawler 1.0" <justin.jeffress@booktrope.com>',
		:subject => 'Apple Sales Numbers',
		:html    => top + Mail_helper.alternating_table_body(results, "Apple ID" => :apple_id, "Title" => :title, "Country" => :country, "Daily Sales" => :units_sold)
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