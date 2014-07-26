#encoding:utf-8
require 'trollop'
require 'time'
require 'mailgun'
require 'csv'

$basePath = File.absolute_path(File.dirname(__FILE__))
require File.join($basePath, '..', 'booktrope-modules')

$opts = Trollop::options do

   banner <<-EOS
Extracts book sales data from google play

   Usage:
            ruby googleplay_reporter.rb [--dontSaveToParse] [--headless]
   EOS
   
   opt :testRJMetrics, "Use RJMetrics test", :short => 't'
   opt :dontSaveToParse, "Turns off parse", :short => 'x'
   opt :downloadFolder, "The folder to save the report file from google play into.", :type => :string, :short => 'd'
   opt :archiveFolder, "The archive folder to drop the unzipped file into for posterity", :type => :string, :short => 'a'   
   opt :headless, "Runs headless", :short => 'h'
   version "1.0.0 2014 Justin Jeffress"

end
	
should_run_headless = ($opts.headless) ?  true : false
is_test_rj = ($opts.testRJMetrics) ? true : false

$BT_CONSTANTS = Booktrope::Constants.instance

#initialize parse
Booktrope::ParseHelper.init :application_id => $BT_CONSTANTS[:parse_application_id],
									 :api_key        => $BT_CONSTANTS[:parse_api_key]

$batch = Parse::Batch.new
$batch.max_requests = 50

$rjClient = Booktrope::RJHelper.new Booktrope::RJHelper::NOOK_SALES_TABLE, ["parse_book_id", "crawlDate", "country"], is_test_rj

Watir_harness.download_folder = $opts.downloadFolder
class_name = "Salesdata_Extraction::Googleplay_reporter"

Watir_harness.run(should_run_headless, class_name, lambda { | log |
	
	browser = Watir_harness.browser
	browser.goto $BT_CONSTANTS[:google_play_url]
	
	if browser.link(:text, "Sign in").present?
		browser.link(:text, "Sign in").click
	end

	#login
	browser.text_field(:id, "Email").set  $BT_CONSTANTS[:google_play_username]
	browser.text_field(:id, "Passwd").set $BT_CONSTANTS[:google_play_password]
	browser.button(:id, "signIn").click

	#clicking on the report button
	browser.div(:id, "pfe-analytics-reports").span(:id, "105").click
	
	browser.text_field(:id, "fromdate").wait_until_present
	
	browser.text_field(:id, "fromdate").set (Time.now - (1 * 24 * 60 * 60)).strftime("%Y-%m-%d")
	browser.text_field(:id, "todate").set (Time.now - (1 * 24 * 60 * 60)).strftime("%Y-%m-%d")
	
	#clicking on the dropdown
	browser.div(:class => "VIpgJd-TzA9Ye-eEGnhe", :class => "VIpgJd-Kb3HCc-xl07Ob-LgbsSe", :class => "itQ7ub-FzV1B-Hg84td").click
	
	#clicking on the all button
	browser.div(:class, "VIpgJd-j7LFlb-MPu53c").wait_until_present
	browser.div(:class, "VIpgJd-j7LFlb-MPu53c").click
	sleep 1.0
	
	#click button to save the file
	browser.div(:class => "VIpgJd-TzA9Ye-eEGnhe", :class => "tk3N6e-LgbsSe", :class => "tk3N6e-LgbsSe-n2to0e").click
	
	#wait for file to download
	while !Dir.glob($opts.downloadFolder+"*.part").empty?
		sleep(5.0)
	end
	
})

def process_download_folder()
	puts "processing the download folder: #{$opts.downloadFolder}"
	Dir.foreach($opts.downloadFolder) do | item |
		next if item == '.' or item == '..' or item.start_with?('.')
		csv_file = File.join($opts.downloadFolder, item)
		if (csv_file =~ /GoogleSalesSummaryReport\.csv/)
			csv_to_parse csv_file
			FileUtils.move csv_file, File.join($opts.archiveFolder, "#{File.basename(item, ".csv")}_#{(Time.now - (1 * 24 * 60 * 60)).strftime("%Y_%m_%d")}.csv")
		end		
	end
end

def csv_to_parse(file)
	contents = File.open(file, "r") { |f| f.read }
	contents = contents[2..contents.length-2] #removing the BOM from the UTF-16LE file
	contents.gsub!(/\0/,'') #removing null bytes left over from converting from utf-16 to utf-8
	
	results = Array.new
	
	csv = CSV.parse(contents, :headers => true, :col_sep => "\t")
	csv.each do | row |
		puts "#{row["Title"]}\t#{row["Primary ISBN"]}\t#{row["Country of Sale"]}\t#{row["Net Units Sold"]}"
		
		row_hash = Hash.new
		row_hash[:title]      = row["Title"]
		row_hash[:isbn]       = row["Primary ISBN"]
		row_hash[:country]    = row["Country of Sale"]
		row_hash[:units_sold] = row["Net Units Sold"].to_i
		#row_hash[:crawl_date] = Time.parse("2014/07/08 00:00:00").utc.strftime("%Y-%m-%d %H:%M:%S")
		row_hash[:crawl_date] = (Time.now - (1 * 24 * 60 * 60)).strftime("%Y-%m-%d 00:00:00")
		
		google_sales_data = Parse::Object.new("GooglePlaySalesData")
		google_sales_data["title"]      = row_hash[:title]
		google_sales_data["epubIsbn"]   = row_hash[:isbn]
		google_sales_data["dailySales"] = row_hash[:units_sold]
		google_sales_data["country"]    = row_hash[:country]
		google_sales_data["crawlDate"]  = Parse::Date.new(row_hash[:crawl_date])		
		google_sales_data["book"] = $book_hash[row_hash[:isbn]] if $book_hash.has_key? row_hash[:isbn]

		$batch.create_object_run_when_full! google_sales_data if !$opts.dontSaveToParse
		pushdata_to_rj(google_sales_data, ["title", "epubIsbn", "dailySales", "country"])
		results.push row_hash
	end
	if results.size > 0
		send_report_email results
	end
end

def get_book_hash()
	book_hash = Hash.new	
	book_list = Booktrope::ParseHelper.get_books(:exists => ["epubIsbnItunes"])

	book_list.each do | book |
		book_hash[book["epubIsbnItunes"]] = book
	end
	return book_hash
end


def pushdata_to_rj(google_sales_data, fields)
	return if !google_sales_data.has_key?("book") || google_sales_data["book"].nil?

	hash = Hash.new
	hash["parse_book_id"] = google_sales_data["book"].parse_object_id
	hash["crawlDate"]     = google_sales_data["crawlDate"].value

	fields.each do | key |
		hash[key] = google_sales_data[key]
	end
	$rjClient.add_object! hash 
end

def send_report_email(results)
	top = "Google Play Sales Numbers for #{results[0][:crawl_date]} PST<br />\n<br />\n"
	mailgun = Mailgun(:api_key => $BT_CONSTANTS[:mailgun_api_key], :domain => $BT_CONSTANTS[:mailgun_domain])
	email_parameters = {
		:to      => 'justin.jeffress@booktrope.com, andy@booktrope.com', #, Katherine Sears <ksears@booktrope.com>, Kenneth Shear <ken@booktrope.com>',
		:from    =>	'"Booktrope Daily Crawler 2.0" <justin.jeffress@booktrope.com>',
		:subject => 'Google Play Sales Numbers',
		:html    => top + Mail_helper.alternating_table_body(results.sort_by{ |k| k[:units_sold].to_i }.reverse, "ISBN" => :isbn, "Title" => :title, "Country" => :country, "Daily Sales" => :units_sold, :total => [:units_sold])
	}

	mailgun.messages.send_email(email_parameters)
end

$book_hash = get_book_hash()
process_download_folder

if $batch.requests.length > 0 && !$opts.dontSaveToParse
	puts $batch.run!
	$batch.requests.clear
end

if $rjClient.data.count > 0 #&& !$opts.dontSaveToRJMetrics
	puts $rjClient.pushData
end