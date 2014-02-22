require 'trollop'
require 'json'
require 'time'
require 'parse-ruby-client'

$basePath   = File.absolute_path(File.dirname(__FILE__))
$config_dir = File.join($basePath, "config")

# linking to custom modules
require File.join($basePath, "..", "ruby_modules", "bt_logging")
require File.join($basePath, "..", "ruby_modules", "download_simple")
require File.join($basePath, "..", "ruby_modules", "constants")


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

BT_CONSTANTS = BTConstants.get_constants

Parse.init :application_id => BT_CONSTANTS[:parse_application_id],
	        :api_key        => BT_CONSTANTS[:parse_api_key]


books = Parse::Query.new("Book").tap do |q|
	#TODO:: create a helper function that loads the books in one shot.
   q.limit  = 1000
end.get



books.each do | book |

	lookup = "id=#{book["appleId"]}"
	if book["appleId"].nil? || book["appleId"] == 0
		if book["epubIsbnItunes"].nil? || book["epubIsbnItunes"] == 0
			log.warn "Skipped: insufficient control numbers: #{book["title"]}"
			next 
		else
			lookup = "isbn=#{book["epubIsbnItunes"]}"
		end
	end
	
   response = Download_simple.downloadData("#{BT_CONSTANTS[:itunes_lookup_url]}?#{lookup}")

   if response.code == "200"
      json = JSON.parse(response.body)

      if json["resultCount"] == 0
         log.warn "No Results: #{lookup},#{book['appleId']},#{book['asin']},\"#{book['title']}\""
         next
      end

      results = json["results"]
   
      id, author, apple_id, title, price, detailUrl, averageUserRating, userRatingCount, imageUrl100 = ""
   
      results.each do |result|
      	id = result["trackId"]
      	apple_id = result["trackId"]
         author = result["artistName"]
         title = result["trackName"]
         price = result["price"]
         detailUrl = result["trackViewUrl"]
         averageUserRating = result["averageUserRating"]
         userRatingCount =  result["userRatingCount"]
         imageUrl100 = result["artworkUrl100"]
      end
      
      puts "%s,\"%s\",%s,%s,%s,%s,%s,%s,%s" % [book['appleId'], title, author, price, id, userRatingCount, averageUserRating, detailUrl, imageUrl100] if $opts.dontSaveToParse
      
      crawl_date = Parse::Date.new(Time.now.utc.strftime("%Y/%m/%d %H:%M:%S"))
      
      book_is_dirty = false
      #updating our book with its appleId, if we found the book via epubIsbnItunes
      if book["appleId"].nil? || book["appleId"] == 0
      	book["appleId"] = apple_id.to_i
      	book_is_dirty = true
      end
      
      if book["detailUrlApple"]  != detailUrl
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
      sleep(1.0)
   end
   sleep(1.0);
end
