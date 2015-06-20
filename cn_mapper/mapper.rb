require 'trollop'
require 'json'
require 'time'
require 'mailgun'

# linking to custom modules
$basePath   = File.absolute_path(File.dirname(__FILE__))
require File.join($basePath, '..', 'booktrope-modules')


$opts = Trollop::options do

  banner <<-EOS
Maps sales data with null book pointers to their book via control numbers.

  Usage:
            ruby mapper.rb [--dontSaveToParse] [--parseDev]
  EOS

  opt :parseDev, "Sets parse environment to dev", :short => 'd'
  opt :dontSaveToParse, "Turns off parse", :short => 'x'
  opt :suppressMail, "Suppresses the compeletion email", :short=> 's'
  opt :dontSaveToRJMetrics, "Turns off RJMetrics", :short => 'r'
  opt :testRJMetrics, "Use RJMetrics test", :short => 't'
  version "1.0.1 2014 Justin Jeffress"
end


$log = Bt_logging.create_logging('cn_mapper::Mapper')

KEYS = ["parse_book_id", "crawlDate", "country"]

$BT_CONSTANTS = Booktrope::Constants.instance

$opts.parseDev ?  Booktrope::ParseHelper.init_development : Booktrope::ParseHelper.init_production
$is_test_rj = ($opts.testRJMetrics) ? true : false

def send_report_email(body)

  report = "cn_mapper"
  top = "We were unable to map daily sales data to a book for the following sales records #{Date.today} PST <br /><br />\n"
  top += "Please add the control numbers below to the corresponding project in teamtrope.<br /><br />"
  subject = 'Unable to Map Sales Data to Book'
  Booktrope::MailHelper.send_report_email(report, subject, top + body, [])
end


def load_book_hash(book_list, keys, control_number_name)


  keys = [ keys ] unless keys.is_a? Array
  book_hash = Hash.new
  book_list.each do | book |

    keys.each do | key |

      if !book[key].nil? && book[key] != 0
        control_number = (control_number_name == "asin") ? book[key] : (  book[key].gsub(/-/, '').to_i)
        #puts "duplicate: #{key}\t#{control_number}\t#{book["title"]} " if book_hash.has_key? control_number

        book_hash[control_number] = book
      end
    end

  end
  return book_hash
end

def convert_ISBN10_to_ISBN13(isbn10)
  prefix = "978"
  result = prefix + isbn10[0, isbn10.size-1]
  bound = 10

  factor = 1
  check_digit = 0
  result.size.times do | digit |
    check_digit = check_digit + (result[digit].to_i() * factor)
    factor = (factor == 1) ? 3 : 1
  end
  check_digit = check_digit % bound

  if check_digit > 0
    check_digit = bound - check_digit
  end
  result = result + check_digit.to_s
  return result
end

def map_sales_data_to_book(book_hash, sales_data_cn, table_name, url, shouldToI = false, rj_options)

  $log.info "Performing query on #{table_name}"

  rjClient = Booktrope::RJHelper.new rj_options[:table], KEYS, $is_test_rj unless $opts.dontSaveToRJMetrics

  ls_query = Parse::Query.new(table_name).tap do | q |
    q.limit = 1000
    q.eq("book", nil)
  end.get

  not_found = Array.new
  already_inserted = Hash.new

  batch = Parse::Batch.new
  batch.max_requests = 50


  ls_query.each do | ls_stat |
    isbn = ls_stat[sales_data_cn]
    isbn_10 = ""
    if table_name.eql? "CreateSpaceSalesData"
      isbn_10 = ls_stat[sales_data_cn]
      isbn = convert_ISBN10_to_ISBN13(isbn_10)
      #puts "#{ls_stat[sales_data_cn]} #{isbn}"
    end

    isbn = isbn.to_i if shouldToI

    if isbn != 0 && book_hash.has_key?(isbn)
      book = book_hash[isbn]

      $log.info "found"
      ls_stat["book"] = book

      batch.update_object_run_when_full! ls_stat unless $opts.dontSaveToParse

      hash = Hash.new
      hash["parse_book_id"] = ls_stat["book"].parse_object_id
      hash["crawlDate"] = ls_stat["crawlDate"].value

      rj_options[:push_data].each do | key |
        hash[key] = ls_stat[key]
      end

      rjClient.add_object! hash unless $opts.dontSaveToRJMetrics

    else
      $log.info "Not found: #{isbn} class: #{isbn.class}"

      if !already_inserted.has_key? isbn
        not_found.push({:cn => isbn ,
         :url => url.gsub(/\{0\}/, (isbn_10 != "") ? isbn_10.to_s : isbn.to_s),
         :object_id => ls_stat.parse_object_id})
        already_inserted[isbn] = true
      else
        $log.info "Already inserted this item. #{isbn}"
      end
    end
  end

  batch.run! unless batch.requests.length < 1 || $opts.dontSaveToParse
  rjClient.pushData unless rjClient.data.count < 1 || $opts.dontSaveToRJMetrics

  return not_found
end


def map_no_book_sales_to_book_per_channel(sales_channels_to_map)

  book_list = Booktrope::ParseHelper.get_books

  body = ""
  sales_channels_to_map.each do | channel |
    book_hash = load_book_hash(book_list, channel[:book_control_number], channel[:sales_control_number])

    book_hash.count

    not_found = map_sales_data_to_book(book_hash, channel[:sales_control_number], channel[:sales_table_name], channel[:url], (channel[:should_to_i]) ? true : false, channel[:rj_options])
    cn_text = channel[:control_number_title]

    body += "<h2>#{channel[:title]}</h2>\n<br />\n"
    body += Booktrope::MailHelper.alternating_table_body(not_found, "Parse Object ID" => :object_id, cn_text => :cn, "URL" => :url)
  end
  send_report_email body if body.length > 0
end

sales_channels_to_map = [
{:title => "Amazon", :control_number_title => "ASIN", :book_control_number => "asin", :sales_table_name => "AmazonSalesData", :sales_control_number => "asin", :rj_options => {:table => Booktrope::RJHelper::AMAZON_SALES_TABLE,:push_data =>["dailySales", "netSales", "dailyKdpUnlimited", "netKdpUnlimited", "country", "forceFree"]}, :url => "<a href=\"http://amzn.com/{0}\">Amazon Store<a/>"},
{:title => "Apple",  :control_number_title => "Apple ID", :book_control_number => "appleId", :sales_table_name => "AppleSalesData", :sales_control_number => "appleId", :rj_options => {:table => Booktrope::RJHelper::APPLE_SALES_TABLE,:push_data =>["dailySales", "appleId", "country"]}, :url => "<a href=\"https://itunes.apple.com/book/id{0}\">iBooks Store</a>"},
{:title => "Createspace", :control_number_title => "ISBN", :book_control_number => ["createspaceIsbn", "hardbackIsbn"], :sales_table_name => "CreateSpaceSalesData", :sales_control_number => "asin", :rj_options => {:table => Booktrope::RJHelper::CREATESPACE_SALES_TABLE,:push_data =>["country", "dailySales"]}, :url => "<a href=\"http://amzn.com/{0}\">Amazon Store</a>"},
{:title => "Google Play", :control_number_title => "ISBN", :book_control_number => "epubIsbnItunes", :sales_table_name => "GooglePlaySalesData", :sales_control_number => "epubIsbn", :rj_options => {:table => Booktrope::RJHelper::GOOGLE_PLAY_SALES_TABLE,:push_data =>["title", "epubIsbn", "dailySales", "country"]}, :url => "NA", :should_to_i => true} ,
{:title => "Lightning Source", :control_number_title => "ISBN", :book_control_number => ["lightningSource","hardbackIsbn"], :sales_table_name => "LightningSalesData", :sales_control_number => "isbn", :rj_options => {:table => Booktrope::RJHelper::LSI_SALES_TABLE,:push_data =>["netSales", "country"]}, :url => "NA"},
{:title => "Nook", :control_number_title => "BNID", :book_control_number => "bnid", :sales_table_name => "NookSalesData", :sales_control_number => "nookId", :rj_options => {:table => Booktrope::RJHelper::NOOK_SALES_TABLE ,:push_data => ["dailySales", "netSales", "dailyKdpUnlimited", "netKdpUnlimited", "country", "forceFree"]}, :url => "<a href=\"http://www.barnesandnoble.com/s/{0}?keyword={0}&store=nookstore\">Nook Store</a>"},
]

map_no_book_sales_to_book_per_channel sales_channels_to_map

