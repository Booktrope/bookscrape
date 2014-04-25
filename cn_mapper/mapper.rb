require 'trollop'
require 'json'
require 'time'
require 'mailgun'
require 'pp'

# linking to custom modules
$basePath   = File.absolute_path(File.dirname(__FILE__))
require File.join($basePath, '..', 'booktrope-modules')

log = Bt_logging.create_logging('cn_mapper::Mapper')

$BT_CONSTANTS = BTConstants.get_constants

Parse.init :application_id => $BT_CONSTANTS[:parse_application_id],
	        :api_key        => $BT_CONSTANTS[:parse_api_key]

def send_report_email(body)
	top = "We were unable to map daily sales data to a book for the following sales records #{Date.today} PST <br /><br />\n"
	top += "Please add the control numbers below to the corresponding project in teamtrope.<br /><br />"
	mailgun = Mailgun(:api_key => $BT_CONSTANTS[:mailgun_api_key], :domain => $BT_CONSTANTS[:mailgun_domain])
	email_parameters = {
		:to      => 'justin.jeffress@booktrope.com, andy@booktrope.com', #, heather.ludviksson@booktrope.com, Katherine Sears <ksears@booktrope.com>, Kenneth Shear <ken@booktrope.com>',
		:from    =>	'"Booktrope Mapper" <justin.jeffress@booktrope.com>',
		:subject => 'Unable to Map Sales Data to Book',
		:html    => top + body
	}
	mailgun.messages.send_email(email_parameters)
end


def load_book_hash(book_list, key)
	book_hash = Hash.new
	book_list.each do | book |
		if !book[key].nil? && book[key] != 0
			book_hash[book[key]] = book
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

def map_sales_data_to_book(book_hash, sales_data_cn, table_name, url)

	ls_query = Parse::Query.new(table_name).tap do | q |
		q.limit = 1000
		q.eq("book", nil)
	end.get

	not_found = Array.new


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

		if isbn != 0 && book_hash.has_key?(isbn)
			book = book_hash[isbn]
			
			#puts "found"
			ls_stat["book"] = book
						
			batch.update_object_run_when_full! ls_stat
		else
			not_found.push({:cn => isbn , :url => url.gsub(/\{0\}/, (isbn_10 != "") ? isbn_10.to_s : isbn.to_s)})
		end
	end

	if batch.requests.length > 0
		batch.run!
		#pp batch.requests
	end
	return not_found
end

def map_no_book_sales_to_book_per_channel(sales_channels_to_map)
	book_list = Parse::Query.new("Book").tap do | q |
		q.limit = 1000
	end.get

	body = ""
	sales_channels_to_map.each do | channel |
		book_hash = load_book_hash(book_list, channel[:book_control_number])
		not_found = map_sales_data_to_book(book_hash, channel[:sales_control_number], channel[:sales_table_name], channel[:url])
		
		body += "<h2>#{channel[:title]}</h2>\n<br />\n"
		body += Mail_helper.alternating_table_body(not_found, "ISBN" => :cn, "URL" => :url)
	end
	send_report_email body if body.length > 0
end

sales_channels_to_map = [
{:title => "Amazon", :book_control_number => "asin", :sales_table_name => "AmazonSalesData", :sales_control_number => "asin", :url => "<a href=\"http://amzn.com/{0}\">Amazon Store<a/>"},
{:title => "Apple", :book_control_number => "appleId", :sales_table_name => "AppleSalesData", :sales_control_number => "appleId", :url => "<a href=\"https://itunes.apple.com/book/id{0}\">iBooks Store</a>"},
{:title => "Createspace", :book_control_number => "createspaceIsbn", :sales_table_name => "CreateSpaceSalesData", :sales_control_number => "asin", :url => "<a href=\"http://amzn.com/{0}\">Amazon Store</a>"},
{:title => "Lightning Source", :book_control_number => "lightningSource", :sales_table_name => "LightningSalesData", :sales_control_number => "isbn", :url => "NA"},
{:title => "Nook", :book_control_number => "bnid", :sales_table_name => "NookSalesData", :sales_control_number => "nookId", :url => "<a href=\"http://www.barnesandnoble.com/s/{0}?keyword={0}&store=nookstore\">Nook Store</a>"},
]

map_no_book_sales_to_book_per_channel sales_channels_to_map