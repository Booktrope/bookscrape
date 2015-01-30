require 'nokogiri'
require 'trollop'
require 'time'
require 'mailgun'

$basePath = File.absolute_path(File.dirname(__FILE__))
require File.join($basePath, '..', 'booktrope-modules')

$opts = Trollop::options do

   banner <<-EOS
Extracts book sales data from nook press

   Usage:
            ruby nookpress_reporter.rb [--dontSaveToParse] [--headless]
   EOS
   
   opt :parseDev, "Sets parse environment to dev", :short => 'd'
   opt :testRJMetrics, "Use RJMetrics test", :short => 't'
   opt :dontSaveToRJMetrics, "Turns of RJMetrics", :short => 'r'
   opt :dontSaveToParse, "Turns off parse", :short => 'x'
   opt :headless, "Runs headless", :short => 'h'
   version "2.0.0 2014 Justin Jeffress"

end

should_run_headless = ($opts.headless) ?  true : false
is_test_rj = ($opts.testRJMetrics) ? true : false

$BT_CONSTANTS = Booktrope::Constants.instance

#initialize parse
$opts.parseDev ?  Booktrope::ParseHelper.init_development : Booktrope::ParseHelper.init_production

$batch = Parse::Batch.new
$batch.max_requests = 50

$rjClient = Booktrope::RJHelper.new Booktrope::RJHelper::NOOK_SALES_TABLE, ["parse_book_id", "crawlDate", "country"], is_test_rj unless $opts.dontSaveToRJMetrics

class_name = "Salesdata_Extraction::Nookpress_reporter"
results = Watir_harness.run(should_run_headless, class_name, lambda { | log |

	results = Array.new

	url = $BT_CONSTANTS[:nookpress_url]
	
	browser = Watir_harness.browser
	
	#requesting the page
	browser.goto(url)
	
	#finding and clicking the login button
	browser.link(:id, "clickclick").wait_until_present
	browser.link(:id, "clickclick").click
	
	#entering credentials
	browser.text_field(:id, "email").wait_until_present
	browser.text_field(:id, "email").set $BT_CONSTANTS[:nookpress_username]

	browser.text_field(:id, "password").set $BT_CONSTANTS[:nookpress_password]
	
	
	#clicking on the login button
	browser.button(:id, "login_button").click


	#wait for the Sales link to appear and then click on it.
	browser.link(:text, "Sales").wait_until_present
	browser.link(:text, "Sales").click
	

	#clicking on the Recent Sales link	
	browser.link(:text, "Recent Sales").wait_until_present
	browser.link(:text, "Recent Sales").click
	
	browser.table(:id, "sales-report").wait_until_present
	
	current_date = Date.parse(Time.now.to_s)
	
	browser.table(:id, "sales-report").tbody.trs.each do | row |
		#since this script runs before the current day is over, we don't want to grab 
		#today's stats since we could miss sales for that day, so we skip those and pull them tomorrow.
		next if Date.strptime(row.tds[0].text.strip, "%m/%d/%Y").day == current_date.day
	
		row_hash = Hash.new
		row_hash[:date]       = row.tds[0].text.strip
		row_hash[:bn_id]      = row.tds[2].text.strip
		row_hash[:isbn]       = row.tds[3].text.strip
		row_hash[:title]      = row.tds[4].text.strip
		row_hash[:country]    = row.tds[6].text.strip
		row_hash[:units_sold] = row.tds[9].text.strip
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
		
		$batch.create_object_run_when_full! nook_sales_data if !$opts.dontSaveToParse
		pushdata_to_rj(nook_sales_data, ["dailySales", "country"]) if !$opts.dontSaveToRJMetrics
		
		puts "#{result[:isbn]}\t#{result[:bn_id]}\t#{result[:country]}\t#{result[:date]}\t#{result[:units_sold]}" if $opts.dontSaveToParse
	end	
end

def pushdata_to_rj(nook_sales_data, fields)
	return if !nook_sales_data.has_key?("book") || nook_sales_data["book"].nil?

	hash = Hash.new
	hash["parse_book_id"] = nook_sales_data["book"].parse_object_id
	hash["crawlDate"]     = nook_sales_data["crawlDate"].value

	fields.each do | key |
		hash[key] = nook_sales_data[key]
	end
	$rjClient.add_object! hash 
end

def send_report_email(results)

	report = "nook_report"
	subject = 'Nookpress Sales Numbers'
	top = "Nookpress Sales Numbers for #{results[0][:date]}<br />\n<br />\n"
	#Booktrope::MailHelper.send_report_email(report, subject, top, results.sort_by{ |k| k[:units_sold].to_i }, "Nook Id" => :bn_id,"isbn" => :isbn, "Title" => :title, "Country" => :country, "Daily Sales" => :units_sold, :total => [:units_sold])

end

if !results.nil? && results.count > 0
	save_sales_data_to_parse(results)
	send_report_email(results)
end

if $batch.requests.length > 0 && !$opts.dontSaveToParse
	puts $batch.run!
	$batch.requests.clear
end

if !$opts.dontSaveToRJMetrics && $rjClient.data.count > 0
	puts $rjClient.pushData
end