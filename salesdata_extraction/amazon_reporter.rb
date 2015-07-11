require 'nokogiri'
require 'trollop'

$basePath = File.absolute_path(File.dirname(__FILE__))
require File.join($basePath, '..', 'booktrope-modules')

$opts = Trollop::options do

  banner <<-EOS
Extracts book sales data from Amazon KDP

  Usage:
            ruby amazon_reporter.rb [--dontSaveToParse] [--headless]
  EOS

  opt :parseDev, "Sets parse environment to dev", :short => 'd'
  opt :suppressMail, "Suppresses the compeletion email", :short=> 's'
  opt :dontSaveToRJMetrics, "Turns off RJMetrics", :short => 'r'
  opt :testRJMetrics, "Use RJMetrics test", :short => 't'
  opt :dontSaveToParse, "Turns off parse", :short => 'x'
  opt :headless, "Runs headless", :short => 'h'
  version "2.0.0 2014 Justin Jeffress"
end

should_run_headless = ($opts.headless) ?  true : false
is_test_rj = ($opts.testRJMetrics) ? true : false

$start_date = (Date.today).strftime("%Y/%m/%d")

$BT_CONSTANTS = Booktrope::Constants.instance

$rjClient = Booktrope::RJHelper.new Booktrope::RJHelper::AMAZON_SALES_TABLE, ["parse_book_id", "crawlDate", "country"], is_test_rj if !$opts.dontSaveToRJMetrics

#initialize parse
if $opts.parseDev
  Booktrope::ParseHelper.init_development
else
  Booktrope::ParseHelper.init_production
end

$batch = Parse::Batch.new
$batch.max_requests = 50

$marketplace_hash = {
      "Amazon.com" => "US",
      "Amazon.co.uk" => "UK",
      "Amazon.de" => "DE",
      "Amazon.fr" => "FR",
      "Amazon.es" => "ES",
      "Amazon.it" => "IT",
      "Amazon.nl" => "NL",
      "Amazon.co.jp" => "JP",
      "Amazon.in" => "IN",
      "Amazon.ca" => "CA",
      "Amazon.com.br" => "BR",
      "Amazon.com.mx" => "MX",
      "Amazon.com.au" => "AU"
 }

class_name = "Salesdata_Extraction::Amazon_reporter"
results = Watir_harness.run(should_run_headless, class_name, lambda { | log |

  browser = Watir_harness.browser

  url = $BT_CONSTANTS[:amazon_kdp_url]

  #getting the amazon kdp page
  browser.goto url

  #clicking the login button
  browser.link(:class, "a-button-text").click

  #entering the username and password
  browser.text_field(:id, "ap_email").wait_until_present
  browser.text_field(:id, "ap_email").set $BT_CONSTANTS[:amazon_kdp_username]

  browser.text_field(:id, "ap_password").set $BT_CONSTANTS[:amazon_kdp_password]


  #clicking the login button
  browser.button(:id, "signInSubmit-input").click


  #clicking on the reports button
  browser.link(:text, "Reports").wait_until_present
  browser.link(:text, "Reports").click

  sleep(5.0)

  #clicking on the month to date sales
  browser.link(:id, "mtdLink").wait_until_present
  browser.link(:id, "mtdLink").click

  sleep(15.0)

  browser.table(:id, "promotionTransactionsReports").tbody.wait_until_present

  #The country that appears first is US so we set it to US.
  country = "US"
  log.info country
  results = Array.new

  #declaring our lambda function since we need to run this code both outside and inside the loop.
  #sure we can do it with a loop but closures are fun too.
  print_lambda = lambda { | extraction_array |
    sleep 5.0
    browser.table(:id, "promotionTransactionsReports").tbody.wait_until_present
    browser.table(:id, "promotionTransactionsReports").tbody.trs.each do | row |
      break if row.tds.size < 9
      extraction_data = Hash.new
      extraction_data[:title]         = row.tds[1].text
      extraction_data[:asin]          = row.tds[2].text
      extraction_data[:net_sales]     = row.tds[5].text
      extraction_data[:kdp_unlimited] = row.tds[6].text
      extraction_data[:force_free]    = row.tds[8].text
      extraction_data[:country]       = country
      extraction_array.push(extraction_data)
    end
    return extraction_array
  }

  #extracting the data from the US
  results.concat(print_lambda.call(Array.new))
  sleep(5.0)

  browser.div(:id, "marketplaceSelect_chosen").present?
  browser.div(:id, "marketplaceSelect_chosen").click
  channels = browser.ul(:class, "chosen-results").lis.map(&:text)
  #getting the dropdown for country stores and looping through each country
  channels.each do | channel |
    country = $marketplace_hash[channel]
    next if country.nil? || country == "US"

    log.info country

    log.info browser.ul(:class, "chosen-results").present?

    unless browser.ul(:class, "chosen-results").present?
      log.info browser.div(:id, "marketplaceSelect_chosen").present?
      browser.div(:id, "marketplaceSelect_chosen").click
      browser.ul(:class, "chosen-results").wait_until_present
    end

    browser.ul(:class, "chosen-results").li(:text, channel).click
    browser.body.click
    sleep 5.0
    extraction_data = Hash.new
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

def prepare_or_push_data_to_rjmetrics(amazon_sales_data, fields)
  return if (!amazon_sales_data.has_key?("book") || amazon_sales_data["book"].nil?)

  hash = Hash.new

  hash["parse_book_id"] = amazon_sales_data["book"].parse_object_id
  hash["crawlDate"] = amazon_sales_data["crawlDate"].value

  fields.each do | key |
    hash[key] = amazon_sales_data[key]
  end

  $rjClient.add_object! hash if !$opts.dontSaveToRJMetrics
end

def save_sales_data_to_parse(results)
puts "save_sales_data_to_parse"
  book_hash = get_book_hash

  results.each do | result |

    net_sales = result[:net_sales].to_i
    net_kdp_unlimited = result[:kdp_unlimited].to_i
    daily_sales = net_sales
    daily_kdp_unlimited = net_kdp_unlimited

    #setting the crawl date
    crawl_date = Parse::Date.new((Date.today).strftime("%Y/%m/%d 23:55:00"))
    #crawl_date = Parse::Date.new((Date.today).strftime("%Y/04/14  23:55:00"))

    #checking to see if we have a record from the previous day only if it's not the first of the month.
    #if Date.today.day != 1
      old_sales_data = Parse::Query.new("AmazonSalesData").tap do |q|
        q.greater_than("crawlDate", Parse::Date.new(((Date.today-1).strftime("%Y/%m/01")+" "+"00:00:00")))
        #q.less_than("crawlDate", Parse::Date.new(((Date.today-1).strftime("%Y/%m/23")+" "+"00:00:00")))
        q.eq("asin", result[:asin])
        q.eq("country", result[:country])
        q.order_by = "crawlDate"
        q.order = :descending
        q.limit = 1
      end.get.first
    #end

    #amazon tracks month to date sales, so we need to subtract yesterday's net from today's
    if !old_sales_data.nil?
      daily_sales = net_sales - old_sales_data["netSales"].to_i
      kdp_unlimited = net_kdp_unlimited - old_sales_data["netKdpUnlimited"].to_i
      puts "daily sales: #{daily_sales}"
    end

    result[:daily_sales] = daily_sales
    result[:daily_kdp_unlimited] = kdp_unlimited

    #getting the book object to link the amazon_sales_data to.
    book = book_hash[result[:asin]]

    amazon_sales_data = Parse::Object.new("AmazonSalesData")
    amazon_sales_data["book"] = book
    amazon_sales_data["asin"] = result[:asin]
    amazon_sales_data["netSales"] = net_sales
    amazon_sales_data["netKdpUnlimited"] = net_kdp_unlimited
    amazon_sales_data["forceFree"] = result[:force_free].to_i
    amazon_sales_data["country"] = result[:country]
    amazon_sales_data["crawlDate"] = crawl_date
    amazon_sales_data["dailySales"] = daily_sales
    amazon_sales_data["dailyKdpUnlimited"] = kdp_unlimited

    $batch.create_object_run_when_full!(amazon_sales_data) if !$opts.dontSaveToParse
    prepare_or_push_data_to_rjmetrics(amazon_sales_data, ["dailySales", "netSales", "dailyKdpUnlimited", "netKdpUnlimited", "country", "forceFree"]) if !$opts.dontSaveToRJMetrics && amazon_sales_data["dailySales"] > 0

    sleep 2.0
  end
end

def send_report_email(results)

  report = "amazon_report"
  top = "Amazon Sales Numbers for #{$start_date} PST<br />\n<br />\n"
  subject = 'Amazon Sales Numbers'
  Booktrope::MailHelper.send_report_email(report, subject, top, results.sort_by{ |k| k[:daily_sales] }.reverse, "asin" => :asin, "Title" => :title, "Country" => :country, "Daily Sales" => :daily_sales, "Month To Date" => :net_sales, "Daily KDP Unlimited" => :daily_kdp_unlimited, "Month To Date (KDP Unlimited)" => :kdp_unlimited, "Force Free" => :force_free, :total => [:daily_sales, :net_sales, :daily_kdp_unlimited, :kdp_unlimited, :force_free])

end

if !results.nil? && results.count > 0
  save_sales_data_to_parse(results)

  send_report_email(results) unless $opts.suppressMail
end

if $batch.requests.length > 0
  $batch.run!
  $batch.requests.clear
end

if !$opts.dontSaveToRJMetrics && $rjClient.data.count > 0
  puts $rjClient.pushData
end
