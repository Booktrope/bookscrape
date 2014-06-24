require 'nokogiri'
require 'trollop'
require 'mailgun'

$basePath = File.absolute_path(File.dirname(__FILE__))
require File.join($basePath, '..', 'booktrope-modules')

$opts = Trollop::options do

   banner <<-EOS
Extracts book sales data from Lightning Source

   Usage:
            ruby lightning_reporter.rb [--dontSaveToParse] [--headless]
   EOS

	opt :testRJMetrics, "Use RJMetrics test", :short => 't'
   opt :dontSaveToParse, "Turns off parse", :short => 'x'
   opt :headless, "Runs headless", :short => 'h'
   version "2.0.0 2014 Justin Jeffress"

end

should_run_headless = ($opts.headless) ?  true : false
is_test_rj = ($opts.testRJMetrics) ? true : false


$BT_CONSTANTS = Booktrope::Constants.instance

#initialize parse
Parse.init :application_id => $BT_CONSTANTS[:parse_application_id],
	        :api_key        => $BT_CONSTANTS[:parse_api_key]
	        
$batch = Parse::Batch.new
$batch.max_requests = 50	        

$rjClient = Booktrope::RJHelper.new Booktrope::RJHelper::LSI_SALES_TABLE, ["parse_book_id", "crawlDate", "country"], is_test_rj

class_name = "Salesdata_Extraction::Lightning_reporter"
results = Selenium_harness.run(should_run_headless, class_name, lambda { | log |
	results = Array.new
	url = $BT_CONSTANTS[:lightning_source_url]
	
	#getting the amazon kdp page
	Selenium_harness.get(url)
	
	login_button = Selenium_harness.find_element(:id, "loginbutton")
	login_button.click
	
	sleep(5.0)
	
	driver = Selenium_harness.driver
	
	driver.switch_to().frame("loginFrame")
	
	username_input = Selenium_harness.find_element(:id, "login_txtLogin")
	username_input.send_keys $BT_CONSTANTS[:lightning_source_username]
	
	password_input = Selenium_harness.find_element(:id, "login_txtPassword")
	password_input.send_keys $BT_CONSTANTS[:lightning_source_password]
	
	signin_button = Selenium_harness.find_element(:id, "login_btnSubmit")
	signin_button.click
	
	wait = Selenium::WebDriver::Wait.new(:timeout => 15)
	wait.until { Selenium_harness.find_element(:link, "Publisher Compensation Report").displayed? }	

	report_link = Selenium_harness.find_element(:link, "Publisher Compensation Report")
	
	report_link.click
	
	reports = [	{:operating_unit => "_ctl0__ctl0_BodyContents_MainContent_optOrgID_0", :currency => "_ctl0__ctl0_BodyContents_MainContent_optCurrency_4", :country => "US"},
					{:operating_unit => "_ctl0__ctl0_BodyContents_MainContent_optOrgID_1", :currency => "_ctl0__ctl0_BodyContents_MainContent_optCurrency_1", :country => "GB"},
					{:operating_unit => "_ctl0__ctl0_BodyContents_MainContent_optOrgID_2", :currency => "_ctl0__ctl0_BodyContents_MainContent_optCurrency_0", :country => "AU"}]
	
	reports.each do | options |
		start_date_field = Selenium_harness.find_element(:id, "_ctl0__ctl0_BodyContents_MainContent_PeriodEntry_txtDate1")
		end_date_field   = Selenium_harness.find_element(:id, "_ctl0__ctl0_BodyContents_MainContent_PeriodEntry_txtDate2")
	
		start_date_field.send_keys (Date.today-1).strftime("%m/%d/%Y")
		end_date_field.send_keys (Date.today-1).strftime("%m/%d/%Y")

		Selenium_harness.find_element(:id, options[:operating_unit]).click
		Selenium_harness.find_element(:id, options[:currency]).click
		Selenium_harness.find_element(:id, "_ctl0__ctl0_BodyContents_MainContent_optCompensationType_0").click
	
		submit_button = Selenium_harness.find_element(:id, "_ctl0__ctl0_BodyContents_MainContent_btnSubmit")
		submit_button.click
	
		the_page_data = Nokogiri.parse(Selenium_harness.page_source)	
		the_sales_table = the_page_data.css("table.lsiTable tr")

		the_sales_table.each do | row |
			next if row.children[0].text == "ISBN" || row.children[0].text.gsub(/(\xC2\xA0)+$/,"") == ""
			break if row.children[0].text.strip == "Your search criteria produced no results."
		
			row_hash = Hash.new
			row_hash[:isbn]              = row.children[0].text.strip
			row_hash[:title]             = row.children[2].text.strip
			row_hash[:author]            = row.children[4].text.strip
			row_hash[:quantity_sold]     = row.children[12].text.strip.to_i
			row_hash[:quantity_returned] = row.children[14].text.strip.to_i
			row_hash[:net_quantity]      = row.children[16].text.strip.to_i
			row_hash[:country]           = options[:country]
			row_hash[:crawl_date]        = (Date.today-1).strftime("%Y/%m/%d")+" "+"00:00:00"
			results.push row_hash
		end
	
		back_to_report = Selenium_harness.find_element(:id, "_ctl0__ctl0_BodyContents_MainContent_BackToSearchButton")
		back_to_report.click if options[:operating_unit] != reports[-1][:operating_unit] # don't click the 'New Report' if the current report is the last one.
	end	
	
	return results
})

def get_book_hash()
	book_hash = Hash.new

	#getting the number of books in parse
	book_count = Parse::Query.new("Book").tap do |q|
   	q.exists("isbn")
   	q.limit = 0
   	q.count = 1
	end.get	 

	#requesting all books at once
	#TODO: parse is limited to 1000 rows per query. Need to update this to loop requests 
	#using skip to get everything.
	book_list = Parse::Query.new("Book").tap do |q|
		q.exists("isbn")
		q.limit = book_count["count"]
	end.get

	book_list.each do | book |
		book_hash[book["isbn"]] = book
	end
	return book_hash
end

def save_sales_data_to_parse(results)
	book_hash = get_book_hash()
	results.each do | result |
		lightning_data = Parse::Object.new("LightningSalesData")
		lightning_data["book"] = book_hash[result[:isbn].to_i]
		lightning_data["isbn"] = result[:isbn].to_i
		lightning_data["netSales"] = result[:net_quantity].to_i
		lightning_data["country"] = result[:country]
		lightning_data["crawlDate"] = Parse::Date.new(result[:crawl_date])
		
		puts "#{result[:isbn]}\t#{result[:title]}\t#{result[:country]}\t#{result[:net_quantity]}\t#{result[:crawl_date]}"	if $opts.dontSaveToParse
		
		$batch.create_object_run_when_full! lightning_data if !$opts.dontSaveToParse
		pushdata_to_rj(lightning_data, ["netSales", "country"])
	end
end

def pushdata_to_rj(lightning_data, fields)
	return if !lightning_data.has_key?("book") || lightning_data["book"].nil?

	hash = Hash.new
	hash["parse_book_id"] = lightning_data["book"].parse_object_id
	hash["crawlDate"]     = lightning_data["crawlDate"].value

	fields.each do | key |
		hash[key] = lightning_data[key]
	end
	$rjClient.add_object! hash 
end

def send_report_email(results)
	top = "Lightning Source Sales Numbers for #{results[0][:crawl_date]} PST<br /><br />\n"
	mailgun = Mailgun(:api_key => $BT_CONSTANTS[:mailgun_api_key], :domain => $BT_CONSTANTS[:mailgun_domain])
	email_parameters = {
		:to      => 'justin.jeffress@booktrope.com, andy@booktrope.com, heather.ludviksson@booktrope.com, Katherine Sears <ksears@booktrope.com>, Kenneth Shear <ken@booktrope.com>',
		:from    =>	'"Booktrope Daily Crawler 2.0" <justin.jeffress@booktrope.com>',
		:subject => 'Lightning Source Sales Numbers',
		:html    => top + Mail_helper.alternating_table_body(results.sort_by{|k| k[:net_quantity] }.reverse, "ISBN" => :isbn, "Title" => :title, "Country" => :country,  "Daily Sales" => :quantity_sold, "Returned" => :quantity_returned, "Net Sales" => :net_quantity, :total => [:quantity_sold, :quantity_returned, :net_quantity])
	}
	mailgun.messages.send_email(email_parameters)
end

if !results.nil? && results.count > 0
	save_sales_data_to_parse(results)
	send_report_email(results)
end

if $batch.requests.length > 0 && !$opts.dontSaveToParse
	puts $batch.run!
	$batch.requests.clear
end

if $rjClient.data.count > 0 #&& !$opts.dontSaveToRJMetrics
	puts $rjClient.pushData
end