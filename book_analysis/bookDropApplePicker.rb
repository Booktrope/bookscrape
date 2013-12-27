require 'trollop'
require 'json'
require 'parse-ruby-client'

$basePath   = File.absolute_path(File.dirname(__FILE__))
$config_dir = File.join($basePath, "config")

# linking to custom modules
require File.join($basePath, "..", "ruby_modules", "bt_logging")
require File.join($basePath, "..", "ruby_modules", "download_simple")
require File.join($basePath, "..", "ruby_modules", "constants")


log = Bt_logging.create_logging('Book_analysis::Apple')

BT_CONSTANTS = BTConstants.get_constants

#Parse.init :application_id => BT_CONSTANTS[:parse_application_id],
#	        :api_key        => BT_CONSTANTS[:parse_api_key]

Parse.init :application_id => "4JLzurLzmUziWmqqpUXfoPeHUepJl1dcy0hACLRq",
	        :api_key        => "pPWK59OijhjOYpXQNApb1dO8oqGuriJLoKtqmAkO"


books = Parse::Query.new("Book").tap do |q|
   q.limit  = 200
   q.exists("itunes_epub_isbn")
end.get



books.each do |book|
   response = Download_simple.downloadData("#{BT_CONSTANTS[:itunes_lookup_url]}?isbn=#{book['itunes_epub_isbn']}")

   if response.code == "200"
      json = JSON.parse(response.body)

      if json["resultCount"] == 0
         log.warn "No Results: #{book['itunes_epub_isbn']},#{book['asin']},\"#{book['title']}\""
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
   
      #puts "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t\n" % [  id, price, title, author, userRatingCount, averageUserRating, detailUrl, imageUrl100]
      
      puts "%s,\"%s\",%s,%s,%s,%s,%s,%s,%s" % [book['itunes_epub_isbn'], title, author, price, id, userRatingCount, averageUserRating, detailUrl, imageUrl100]
      
	   time = Time.new
      crawl_date = time.strftime("%Y/%m/%d")
	   crawl_time = time.strftime("%H:%M:%S")
      
      if book["appleId"].nil? || book["appleId"] == 0
      	puts "it's nil"
      	book["appleId"] = apple_id.to_i
      	book.save
      end
      
      appleStats = Parse::Object.new("AppleStats")
      appleStats['book'] = book
      appleStats['trackId'] = id.to_i
      appleStats['author'] = author
      appleStats['title'] = title
      appleStats['price'] = price
      appleStats['large_image'] = imageUrl100
      appleStats['detail_url'] = detailUrl
      appleStats['average_stars'] = averageUserRating.to_f
      appleStats['num_of_reviews'] = userRatingCount.to_i
      appleStats['crawl_date'] = crawl_date
      appleStats['crawl_time'] = crawl_time
      
      #appleStats.save
   end
   sleep(1.0);
end
