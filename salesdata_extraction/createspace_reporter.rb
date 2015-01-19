require 'nokogiri'
require 'trollop'
require 'mailgun'


$basePath = File.absolute_path(File.dirname(__FILE__))
require File.join($basePath, '..', 'booktrope-modules')

$opts = Trollop::options do

  banner <<-EOS
Extracts book sales data from createspace

   Usage:
            ruby createspace_reporter.rb [--dontSaveToParse] [--headless]
   EOS
   
  opt :testRJMetrics, "Use RJMetrics test", :short => 't'
  opt :dontSaveToParse, "Turns off parse", :short => 'x'
  opt :headless, "Runs headless", :short => 'h'
  version "2.0.0 2014 Justin Jeffress"
end

$amazon_channels = {"Amazon" => "US", "Amazon Europe - GBP" => "GB", "Amazon Europe - EUR" => "EU" }
should_run_headless = ($opts.headless) ?  true : false
is_test_rj = ($opts.testRJMetrics) ? true : false

$BT_CONSTANTS = Booktrope::Constants.instance

#initialize parse
Booktrope::ParseHelper.init_production

$batch = Parse::Batch.new
$batch.max_requests = 50

$rjClient = Booktrope::RJHelper.new Booktrope::RJHelper::CREATESPACE_SALES_TABLE, ["parse_book_id", "crawlDate", "country"], is_test_rj if !$opts.dontSaveToRJMetrics

class_name = "Salesdata_Extraction::Createspace_reporter"
results = Watir_harness.run(should_run_headless, class_name, lambda { | log |

	results = Array.new
	
	url = $BT_CONSTANTS[:createspace_url]
	
	browser = Watir_harness.browser
	
	browser.goto(url)
	
	browser.text_field(:id, "loginField").wait_until_present
	browser.text_field(:id, "loginField").set $BT_CONSTANTS[:createspace_username]
	
	browser.text_field(:id, "passwordField").set $BT_CONSTANTS[:createspace_password]
	browser.button(:id, "login_button").click
	
	browser.link(:text, "View Detailed Royalty Report").wait_until_present
	browser.link(:text, "View Detailed Royalty Report").click

	browser.link(:text, "Royalty By Channel").wait_until_present
	browser.link(:text, "Royalty By Channel").click
	
	browser.select(:id, "member_reports_dateoptions").wait_until_present
	

	
	browser.select(:id, "member_reports_dateoptions").options.each do | option |
		option.select if option.value == "TODAY"
	end
	
	log.info "sleeping..."
	sleep 15.0
	log.info "done"
	
	browser.div(:id, "AdvancedExpander").click
	
	browser.checkbox(:id, "member_reports_eancolumn").set
	browser.checkbox(:id, "member_reports_asincolumn").set
	browser.button(:id, "searchFormSection_save").click

	browser.div(:id, "resultTable").table.tbody.wait_until_present
	browser.div(:id, "resultTable").table.tbody.trs.each do | row |
		row_data = Hash.new
		row_data[:title] = row.tds[0].text.strip
		row_data[:channel] = $amazon_channels[row.tds[1].text.strip]
		row_data[:isbn] = row.tds[2].text.strip
		row_data[:asin] = row.tds[3].text.strip
		row_data[:units_sold] = row.tds[4].text.strip
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
		#crawl_date = Parse::Date.new((Date.today).strftime("%Y/%m/%d")+" "+Time.now().strftime("%H:%M:%S"))
		crawl_date = Parse::Date.new((Date.today).strftime("%Y/%m/17")+" "+Time.now().strftime("23:35:00"))
	
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
		$batch.create_object_run_when_full! cs_sales_data if !$opts.dontSaveToParse		
		pushdata_to_rj(cs_sales_data, ["country", "dailySales"]) if !$opts.dontSaveToRJMetrics
	end	
end

def pushdata_to_rj(cs_sales_data, fields)
	return if !cs_sales_data.has_key?("book") || cs_sales_data["book"].nil?
	
	hash = Hash.new
	hash["parse_book_id"] = cs_sales_data["book"].parse_object_id
	hash["crawlDate"]     = cs_sales_data["crawlDate"].value

	fields.each do | key |
		hash[key] = cs_sales_data[key]
	end
	$rjClient.add_object! hash 
end

def send_report_email(results)

	report = "createspace_report"
	subject = 'Createspace Sales Numbers'
	top = "Createspace Sales Numbers for #{Date.today} PST<br />\n<br />\n"
	Booktrope::MailHelper.send_report_email(report, subject, top, results.sort_by{ |k| k[:units_sold] }.reverse, "isbn" => :isbn, "Title" => :title, "Country" => :channel, "Daily Sales" => :units_sold, :total => [:units_sold])

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