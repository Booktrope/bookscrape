require 'trollop'
require 'mailgun'

$basePath = File.absolute_path(File.dirname(__FILE__))
require File.join($basePath, '..', 'booktrope-modules')

$opts = Trollop::options do

   banner <<-EOS
Extracts book sales data from Lightning Source

   Usage:
            ruby lightning_reporter.rb [--dontSaveToParse] [--testRJMetrics] [--headless]
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
Booktrope::ParseHelper.init_production
	        
$batch = Parse::Batch.new
$batch.max_requests = 50	        

$rjClient = Booktrope::RJHelper.new Booktrope::RJHelper::LSI_SALES_TABLE, ["parse_book_id", "crawlDate", "country"], is_test_rj

class_name = "Salesdata_Extraction::Lightning_reporter"
results = Watir_harness.run(should_run_headless, class_name, lambda { | log | 

	results = Array.new
	url = $BT_CONSTANTS[:lightning_source_url]
	
	browser = Watir_harness.browser
	
	browser.goto url
	
	browser.link(:id, "loginbutton").wait_until_present
	browser.link(:id, "loginbutton").click
	
	browser.iframe(:id, "loginFrame").text_field(:id, "login_txtLogin").set $BT_CONSTANTS[:lightning_source_username]
	browser.iframe(:id, "loginFrame").text_field(:id, "login_txtPassword").set $BT_CONSTANTS[:lightning_source_password]
	
	browser.iframe(:id, "loginFrame").button(:id, "login_btnSubmit").click
	
	browser.link(:text, "Publisher Compensation Report").wait_until_present
	browser.link(:text, "Publisher Compensation Report").click
	
	reports = [	{:operating_unit => "_ctl0__ctl0_BodyContents_MainContent_optOrgID_0", :currency => "_ctl0__ctl0_BodyContents_MainContent_optCurrency_4", :country => "US"},
					{:operating_unit => "_ctl0__ctl0_BodyContents_MainContent_optOrgID_1", :currency => "_ctl0__ctl0_BodyContents_MainContent_optCurrency_1", :country => "GB"},
					{:operating_unit => "_ctl0__ctl0_BodyContents_MainContent_optOrgID_2", :currency => "_ctl0__ctl0_BodyContents_MainContent_optCurrency_0", :country => "AU"}]
	compensation_report = "_ctl0__ctl0_BodyContents_MainContent_optCompensationType_0"
	
	reports.each do | options |
		browser.text_field(:id, "_ctl0__ctl0_BodyContents_MainContent_PeriodEntry_txtDate1").set (Date.today-1).strftime("%m/%d/%Y")
		browser.text_field(:id, "_ctl0__ctl0_BodyContents_MainContent_PeriodEntry_txtDate2").set (Date.today-1).strftime("%m/%d/%Y")
		
		browser.checkbox(:id, options[:operating_unit]).click
		browser.checkbox(:id, options[:currency]).click
		browser.checkbox(:id, compensation_report).click
		browser.button(:id, "_ctl0__ctl0_BodyContents_MainContent_btnSubmit").click
		
		browser.table(:class, "lsiTable").trs(:class, "lsiTable")
		
		browser.table(:class, "lsiTable").trs(:class, "lsiTable").each do | row |
			next if row.tds[0].text.strip == ""
			break if row.tds[0].text.strip == "Your search criteria produced no results."
		
			log.info "#{row.tds[0].text}\t#{row.tds[1].text}\t#{row.tds[2].text}\t#{row.tds[6].text}\t#{row.tds[7].text}\t#{row.tds[8].text}"
			
			row_hash = Hash.new
			row_hash[:isbn]              = row.tds[0].text.strip
			row_hash[:title]             = row.tds[1].text.strip
			row_hash[:author]            = row.tds[2].text.strip
			row_hash[:quantity_sold]     = row.tds[6].text.strip.to_i
			row_hash[:quantity_returned] = row.tds[7].text.strip.to_i
			row_hash[:net_quantity]      = row.tds[8].text.strip.to_i
			row_hash[:country]           = options[:country]
			row_hash[:crawl_date]        = (Date.today-1).strftime("%Y/%m/%d")+" "+"00:00:00"
			results.push row_hash
		end
		
		back_to_report = browser.button(:id, "_ctl0__ctl0_BodyContents_MainContent_BackToSearchButton")
		back_to_report.click if options[:operating_unit] != reports[-1][:operating_unit] # don't click the 'New Report' if the current report is the last one.
	end
	
	return results
})

def get_book_hash
	book_hash = Hash.new
	
	book_list = Booktrope::ParseHelper.get_books(:exists => ["lightningSource"])
	book_list.each do | book |
		book_hash[book["lightningSource"]] = book
	end
	return book_hash
end

def save_sales_data_to_parse(results)
	book_hash = get_book_hash

	results.each do | result |
		lightning_data = Parse::Object.new("LightningSalesData")
		lightning_data["book"] = book_hash[result[:isbn]]
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
		:to      => 'justin.jeffress@booktrope.com, andy@booktrope.com, kelsey@booktrope.com, Katherine Sears <ksears@booktrope.com>, Kenneth Shear <ken@booktrope.com>',
		:from    =>	'"Booktrope Daily Crawler 2.5" <justin.jeffress@booktrope.com>',
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