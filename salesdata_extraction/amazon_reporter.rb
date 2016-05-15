$basePath = File.absolute_path(File.dirname(__FILE__))
require File.join($basePath, '..', 'booktrope-modules')
require 'trollop'
require 'spreadsheet'
require 'csv'
require 'pp'

opts = Trollop::options do

   banner <<-EOS
   Extract Sales Data from the amazon spreadsheet and save them to parse.

   Usage:
      ruby amazon_reporter.rb
   EOS
   opt :production, "By default the script saves to the developer instance of parse."
   opt :start_date, "The start date serves as the lower bound.", type: String, required: true
   opt :end_date, "The end date serves as the upper bound.", type: String
   opt :dont_save, "Don't save to parse if this is provided", short: 'x'
   opt :file, "Path to the excel file to extract the data from.", type: String, required: true
   version "0.0.0 2016 Justin Jeffress"
end

channels = {
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
      "Amazon.com.au" => "AU"  }

if opts.production
  Booktrope::ParseHelper.init_production
else
  Booktrope::ParseHelper.init_development
end

lower_bound = Parse::Date.new "#{opts.start_date} 23:55"

# set upper_bound to lower_bound if no end_date provided via command line
upper_bound = if opts.end_date
  Parse::Date.new "#{opts.end_date} 23:55"
else
  lower_bound
end

puts opts.dont_save

batch = Parse::Batch.new
batch.max_requests = 50

book_hash = {}
book_list = Booktrope::ParseHelper.get_books(exists: ["asin"])
book_list.each do | book |
  book_hash[book["asin"]] = book
end

totals = {}

royality_report_txt = ''

doc = Spreadsheet.open(opts.file)
doc.worksheet(0).rows.each do | row |
  royality_report_txt << row.join("\t").gsub(/"/, "") << "\n"
end

orders_report = ""
doc.worksheet(1).rows.each do | row |
  orders_report << row.join("\t").gsub(/"/, "") << "\n"
end

extracted_data_hash = {}
CSV.parse(royality_report_txt, headers: :first_row, col_sep: "\t").each_with_index do | row, index |
  key = "#{row["Royalty Date"]}_#{row["ASIN"]}_#{channels[row["Marketplace"]]}"
  sales_record_hash = extracted_data_hash[key]
  sales_record_hash ||= { asin: row["ASIN"], crawl_date: row["Royalty Date"], channel: channels[row["Marketplace"]], daily_sales: 0, daily_free_units_promo: 0, force_free: 0 }

  puts "#{row["Royalty Date"]}\t#{row["ASIN"]}\t#{row["Title"]}\t#{row["Marketplace"]}\t#{row["Transaction Type"]}\t#{row["Units Sold"]}"

  case row["Transaction Type"]
  when "Standard"
    sales_record_hash[:daily_sales] += row["Units Sold"].to_i
  when "Free - Promotion"
    sales_record_hash[:daily_free_units_promo] += row["Units Sold"].to_i
  when "Free - Price Match"
    sales_record_hash[:force_free] += row["Units Sold"].to_i
  else
    next
  end

  extracted_data_hash[key] = sales_record_hash

end

CSV.parse(orders_report, headers: :first_row, col_sep: "\t").each_with_index do | row, index |
  key = "#{row["Order Date"]}_#{row["ASIN"]}_#{channels[row["Marketplace"]]}"
  sales_record_hash = extracted_data_hash[key]
  sales_record_hash ||= { asin: row["ASIN"], crawl_date: row["Order Date"], channel: channels[row["Marketplace"]] }

  sales_record_hash[:daily_kdp_unlimited] = row["Kindle Edition Normalized Pages (KENP) Read"].to_i

  extracted_data_hash[key] = sales_record_hash
end


results = []

extracted_data_hash.sort.each do | key, sales_record_hash |

  crawl_date = Parse::Date.new(sales_record_hash[:crawl_date] + " 23:55")
  next if !(lower_bound.value <= crawl_date.value) || !(crawl_date.value <= upper_bound.value)

  new_record = true

  amazon_sales_data = nil
  # amazon_sales_data = Parse::Query.new("AmazonSalesData").tap do |q|
  #   q.eq("crawlDate", crawl_date)
  #   q.eq("asin", sales_record_hash[:asin])
  #   q.eq("country", sales_record_hash[:channel])
  #   q.order_by = "crawlDate"
  #   q.limit = 1
  # end.get.first

  new_record = false unless amazon_sales_data.nil?

  amazon_sales_data ||= Parse::Object.new("AmazonSalesData")

  book = book_hash[sales_record_hash[:asin]]
  amazon_sales_data["book"] = book
  amazon_sales_data["asin"] = sales_record_hash[:asin]

  #amazon_sales_data["netSales"] = net_sales
  #amazon_sales_data["netKdpUnlimited"] = net_kdp_unlimited

  unless totals.has_key? crawl_date.strftime
    totals[crawl_date.strftime] = { date: crawl_date, sales: 0, read: 0 }
  end

  totals[crawl_date.strftime][:sales] += sales_record_hash[:daily_sales] unless sales_record_hash[:daily_sales].nil?
  totals[crawl_date.strftime][:read] += sales_record_hash[:daily_kdp_unlimited] unless sales_record_hash[:daily_kdp_unlimited].nil?

  amazon_sales_data["country"] = sales_record_hash[:channel]
  amazon_sales_data["crawlDate"] = crawl_date
  amazon_sales_data["dailySales"] = sales_record_hash[:daily_sales]
  amazon_sales_data["forceFree"] = sales_record_hash[:force_free]
  amazon_sales_data["dailyKdpUnlimited"] = sales_record_hash[:daily_kdp_unlimited]
  amazon_sales_data["dailyFreeUnitsPromo"] = sales_record_hash[:daily_free_units_promo]

  wrapper_hash = sales_record_hash
  wrapper_hash[:title] = book['title'] unless book.nil?
  results.push(wrapper_hash)

  puts "#{sales_record_hash[:crawl_date]}\t#{sales_record_hash[:asin]}\t#{sales_record_hash[:channel]}\t#{sales_record_hash[:daily_sales]},#{sales_record_hash[:force_free]},#{sales_record_hash[:daily_free_units_promo]},#{sales_record_hash[:daily_kdp_unlimited]}"

  unless opts.dont_save
    if new_record
      batch.create_object_run_when_full! amazon_sales_data
    else
      batch.update_object_run_when_full! amazon_sales_data
    end
  end

  #sleep 0.25
end

totals.each do | key, total |
  puts "#{key}: sold: #{total[:sales]} read: #{total[:read]}"

  ascr = Parse::Query.new("AggregateSalesChannel").tap {| q | q.eq("crawlDate", total[:date]) }.get.first
  new_record = false
  if ascr.nil?
    ascr = Parse::Object.new("AggregateSalesChannel")
    new_record = true
  end

  ascr["crawlDate"] = total[:date] #Parse::Date.new(start_date + " 23:55")
  ascr["amazonSales"] = total[:sales]
  ascr["KENPRead"] = total[:read]

  unless opts.dont_save
    if new_record
      batch.create_object_run_when_full! ascr
    else
      batch.update_object_run_when_full! ascr
    end
  end
  sleep 0.5
end

unless opts.dont_save
  if batch.requests.length > 0
    pp batch.run!
    batch.requests.clear
  end
end
