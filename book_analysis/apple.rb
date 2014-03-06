require 'trollop'
require 'json'
require 'time'
require 'parse-ruby-client'
require 'mailgun'

$basePath   = File.absolute_path(File.dirname(__FILE__))
$config_dir = File.join($basePath, "config")

BOOK_ANALYSIS_LOOKUP_STATUS_SKIPPED = -1
BOOK_ANALYSIS_LOOKUP_STATUS_DEFAULT = 0
BOOK_ANALYSIS_LOOKUP_STATUS_FOUND = 1

# linking to custom modules
require File.join($basePath, "..", "ruby_modules", "bt_logging")
require File.join($basePath, "..", "ruby_modules", "download_simple")
require File.join($basePath, "..", "ruby_modules", "constants")
require File.join($basePath, "..", "ruby_modules", "mail_helper")

$opts = Trollop::options do

   banner <<-EOS
Extracts various meta data from iBooks using the iTunes search api.

   Usage:
            ruby apple.rb [--dontSaveToParse]
   EOS

   opt :dontSaveToParse, "Turns off parse", :short => 'x'
   
   version "1.0.0 2014 Justin Jeffress"

end


log = Bt_logging.create_logging('Book_analysis::Apple')

$BT_CONSTANTS = BTConstants.get_constants

Parse.init :application_id => $BT_CONSTANTS[:parse_application_id],
	        :api_key        => $BT_CONSTANTS[:parse_api_key]


def book_contains_control_number(book, control_number)
	result = false
	if !book.nil? && !control_number.nil? && !book[control_number].nil? && book[control_number] != 0
		result = true
	end
	return result
end


books = Parse::Query.new("Book").tap do |q|
	#TODO:: create a helper function that loads the books in one shot.
   q.limit  = 1000
end.get

book_hash = Hash.new

books.each do | book |
	control_number = "appleId"
	if !book_contains_control_number book, control_number
		control_number = "epubIsbnItunes"
		if !book_contains_control_number book, control_number
			control_number = "objectId"
		end
	end
	book_hash[book[control_number]] = {:book => book, :control_number => control_number, :status => BOOK_ANALYSIS_LOOKUP_STATUS_DEFAULT}
end

isbn_str = ""
id_str = ""
count = 0
max = 20
request_urls = Array.new
book_hash.each do | key, book_container |

	if book_container[:control_number] == "objectId"
		log.warn "Skipped: insufficient control numbers: #{book_container[:book]["title"]}"
		book_container[:status] = BOOK_ANALYSIS_LOOKUP_STATUS_SKIPPED
		next
	end
	
	book = book_container[:book]
	control_number = book[book_container[:control_number]]	
	lookup = "#{(book_container[:control_number] == "appleId")? "id": "isbn" }=#{control_number}"
	
	case book_container[:control_number]
	when "appleId" 
		id_str <<  "#{id_str.length > 0 ?",":""}#{control_number}"
		count = count + 1
	when "epubIsbnItunes"
		isbn_str << "#{isbn_str.length > 0 ?",":""}#{control_number}"
		count = count + 1
	else
		puts "NONE"
	end

	if count % max == 0
		request_url = "#{$BT_CONSTANTS[:itunes_lookup_url]}?id=#{id_str}&isbn=#{isbn_str}"
		request_urls.push request_url		
		id_str = ""
		isbn_str = ""
	end
end

request_url = "#{$BT_CONSTANTS[:itunes_lookup_url]}?id=#{id_str}&isbn=#{isbn_str}"
request_urls.push request_url
id_str = ""
isbn_str = ""

request_urls.each do | request_url |
	response = Download_simple.downloadData(request_url)
	if response.code == "200"
	
      json = JSON.parse(response.body)

      if json["resultCount"] == 0
         log.warn "No Results: #{request_url}"
         next
      end
      
      results = json["results"]
   
      id, author, apple_id, title, price, detailUrl, averageUserRating, userRatingCount, imageUrl100 = ""
   
      results.each do |result|
      	apple_id = result["trackId"]
         author = result["artistName"]
         title = result["trackName"]
         price = result["price"]
         detailUrl = result["trackViewUrl"]
         averageUserRating = result["averageUserRating"]
         userRatingCount =  result["userRatingCount"]
         imageUrl100 = result["artworkUrl100"]
         
         puts "\"%s\",%s,%s,%s,%s,%s,%s,%s" % [title, author, price, apple_id, userRatingCount, averageUserRating, detailUrl, imageUrl100] if $opts.dontSaveToParse
         
         if book_hash.has_key? apple_id.to_i
         	book = book_hash[apple_id][:book]
	         book_hash[apple_id][:status] = BOOK_ANALYSIS_LOOKUP_STATUS_FOUND
	         
	   		crawl_date = Parse::Date.new(Time.now.utc.strftime("%Y/%m/%d %H:%M:%S"))
				book_is_dirty = false
	         #updating our book with its appleId, if we found the book via epubIsbnItunes
	         
	         if book["detailUrlApple"] != detailUrl
	         	book["detailUrlApple"] = detailUrl
	         	book_is_dirty = true
	         end
	         
	         if book["largeImageApple"] != imageUrl100
	         	book["largeImageApple"] = imageUrl100
	         	book_is_dirty = true
	         end
	         
	         if book_is_dirty && !$opts.dontSaveToParse
	         	book.save
	         	sleep(1.0)
	         end
	         
	         appleStats = Parse::Object.new("AppleStats")
	         appleStats['book'] = book
	         appleStats['appleId'] = apple_id.to_i
	         appleStats['price'] = price
	         appleStats['averageStars'] = averageUserRating.to_f
	         appleStats['numOfReviews'] = userRatingCount.to_i
	         appleStats['crawlDate'] = crawl_date
	         appleStats.save if !$opts.dontSaveToParse
	         sleep(1.0) if !$opts.dontSaveToParse
         else
         end         
      end
	else
		log.error "Error Code #{response.code}: #{response.body}"
	end
	sleep(2.5)
end

apple_channel_query = Parse::Query.new("SalesChannel").tap do | q |
	q.eq("name", "Apple")
end

not_found = Parse::Query.new("NotFoundBooks").tap do | q |
	q.limit = 1000
	q.include = "book,salesChannel"
	q.in_query "salesChannel", apple_channel_query
end.get

not_found_hash = Hash.new
not_found.each do | book |
	not_found_hash[book["book"]["objectId"]] = book
end

apple_channel = Parse::Query.new("SalesChannel").tap do | q |
	q.eq("name", "Apple")
end.get.first

book_hash.sort_by{|k| k[1][:book]["title"]}.each do | key, book_meta |
	if book_meta[:status] != BOOK_ANALYSIS_LOOKUP_STATUS_FOUND
		if !not_found_hash.has_key? book_meta[:book]["objectId"]
			#puts "#{book_meta[:book]["title"]}\t#{book_meta[:book]["epubIsbnItunes"]}\t#{book_meta[:book]["appleId"]}\t#{book_meta[:book]["asin"]}"
			not_found_book = Parse::Object.new("NotFoundBooks")
			not_found_book["book"] = book_meta[:book]
			not_found_book["salesChannel"] = apple_channel
			not_found_book["reasonCode"] = book_meta[:status]
			not_found_book.save
			sleep 0.5
		end		
	end
end