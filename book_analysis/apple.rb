require 'trollop'
require 'json'
require 'time'
require 'mailgun'
require 'pp'

$basePath   = File.absolute_path(File.dirname(__FILE__))
$config_dir = File.join($basePath, "config")

BOOK_ANALYSIS_LOOKUP_STATUS_SKIPPED = -1
BOOK_ANALYSIS_LOOKUP_STATUS_DEFAULT = 0
BOOK_ANALYSIS_LOOKUP_STATUS_FOUND = 1

# linking to custom modules
require File.join($basePath, '..', 'booktrope-modules')

$opts = Trollop::options do

   banner <<-EOS
Extracts various meta data from iBooks using the iTunes search api.

   Usage:
            ruby apple.rb [--dontSaveToParse] --testRJMetrics --dontSaveToParse --dontSaveToRJMetrics
   EOS

   opt :testRJMetrics, "Use RJMetrics test sandbox. This option will save to the sandbox.", :short => 't'
   opt :dontSaveToParse, "Prevents the collected data from being saved to parse.", :short => 'x'
   opt :dontSaveToRJMetrics, "Turns of RJMetrics entirely. Data wont be saved to either the sandbox or live.", :short => 'r'

   version "2.0.0 2014 Justin Jeffress"

end

log = Bt_logging.create_logging('Book_analysis::Apple')

$BT_CONSTANTS = Booktrope::Constants.instance
is_test_rj = ($opts.testRJMetrics) ? true : false
$rjClient = Booktrope::RJHelper.new Booktrope::RJHelper::APPLE_STATS_TABLE, ["parse_book_id", "crawlDate"], is_test_rj if !$opts.dontSaveToRJMetrics

Booktrope::ParseHelper.init_production

$batch = Parse::Batch.new
$batch.max_requests = 50

def book_contains_control_number(book, control_number)
  result = false
  if !book.nil? && !control_number.nil? && !book[control_number].nil? && book[control_number] != "" && /[0-9]{9}/.match(book[control_number])
    result = true
  elsif /[a-zA-Z]+/.match(book[control_number])
    data = { :alert => "Apple Scan detected an error: TeamtropeId: #{book["teamtropeId"]} #{control_number}: #{book[control_number]}"}
    push = Parse::Push.new(data, "PriceChanges")
    push.type = "ios"
    push.save
  end
  return result
end

def pushdata_to_rj(appleStats, fields)
  return if !appleStats.has_key? "book" || !appleStats["book"].nil?

  hash = Hash.new
  hash["parse_book_id"] = appleStats["book"].parse_object_id
  hash["crawlDate"] = appleStats["crawlDate"].value

  fields.each do | key |
    hash[key] = appleStats[key]
  end
  $rjClient.add_object! hash if !$opts.dontSaveToRJMetrics
end

books = Parse::Query.new("Book").tap do |q|
  #TODO:: update to use the helper function that loads the books in one shot.
  q.exists("title")
   q.limit  = 1000
end.get

unconfirmed_hash = Hash.new
change_queue = Parse::Query.new("PriceChangeQueue").tap do |q|
  q.limit = 1000
  q.eq("status", Booktrope::PRICE_CHANGE::UNCONFIRMED)
  q.in_query("salesChannel", Parse::Query.new("SalesChannel").tap do | inner_query |
    inner_query.eq("name", Booktrope::PRICE_CHANGE::APPLE_CHANNEL)
  end)
  q.include = "book,salesChannel"
end.get

# also consider prefunk changes
change_queue.concat(
  Parse::Query.new("PrefunkQueue").tap do | q |
    q.limit = 1000
    q.eq("status", Booktrope::PRICE_CHANGE::UNCONFIRMED)
    q.in_query("salesChannel", Parse::Query.new("SalesChannel").tap do | inner_query |
      inner_query.eq("name", Booktrope::PRICE_CHANGE::APPLE_CHANNEL)
    end)
  end.get
)

change_queue.each do | item |
  if !unconfirmed_hash.has_key? item["book"]
    unconfirmed_hash[item["book"]] = item
  else
    unconfirmed_hash[item["book"]] = item if unconfirmed_hash[item["book"]]["changeDate"].value > item["changeDate"].value
  end
end


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


  book = book_container[:book]
  if book_container[:control_number] == "objectId"
    log.warn "Skipped: insufficient control numbers: #{book_container[:book]["title"]}"
    book_container[:status] = BOOK_ANALYSIS_LOOKUP_STATUS_SKIPPED
    next
  end

  control_number = book[book_container[:control_number]]
  lookup = "#{(book_container[:control_number] == "appleId")? "id": "isbn" }=#{control_number}"

  case book_container[:control_number]
  when "appleId"
    id_str <<  "#{id_str.length > 0 ?",":""}#{control_number.strip}"
    count = count + 1
  when "epubIsbnItunes"
    isbn_str << "#{isbn_str.length > 0 ?",":""}#{control_number.strip}"
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
        apple_id = result["trackId"].to_s
         author = result["artistName"]
         title = result["trackName"]
         price = result["price"]
         detailUrl = result["trackViewUrl"]
         averageUserRating = result["averageUserRating"]
         userRatingCount =  result["userRatingCount"]
         imageUrl100 = result["artworkUrl100"]

         puts "\"%s\",%s,%s,%s,%s,%s,%s,%s" % [title, author, price, apple_id, userRatingCount, averageUserRating, detailUrl, imageUrl100] if $opts.dontSaveToParse

         if book_hash.has_key? apple_id
          book = book_hash[apple_id][:book]
           book_hash[apple_id][:status] = BOOK_ANALYSIS_LOOKUP_STATUS_FOUND

           if unconfirmed_hash.has_key? book
            log.info "found a book with a price change. #{book["title"]} appleId: #{apple_id} #{unconfirmed_hash[book].id} #{price} #{unconfirmed_hash[book]["price"]}"
            #Confirming that price_changer.rb has properly changed the price of the book.
            if unconfirmed_hash[book]["price"] == price
              log.info "CONFIRMED: Expected: #{unconfirmed_hash[book]["price"]} Actual: #{price}"
              unconfirmed_hash[book]["status"] = Booktrope::PRICE_CHANGE::CONFIRMED
              #Don't batch these up since we dont do these often and status is time
              #sensitive so we want to know as soon as it's confirmed.
              unconfirmed_hash[book].save #if !$opts.dontSaveToParse
              sleep(1.0)
            end
           end

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
            !$batch.update_object_run_when_full!(book)
           end

           appleStats = Parse::Object.new("AppleStats")
           appleStats['book'] = book
           appleStats['appleId'] = apple_id.to_i
           appleStats['price'] = price
           appleStats['averageStars'] = averageUserRating.to_f
           appleStats['numOfReviews'] = userRatingCount.to_i
           appleStats['crawlDate'] = crawl_date
           pushdata_to_rj appleStats, ["appleId", "price", "averageStars", "numOfReviews", "crawlDate"] if !$opts.dontSaveToRJMetrics
           $batch.create_object_run_when_full!(appleStats) if !$opts.dontSaveToParse
         else
          #TODO: If we didn't have the apple_id for the book (looked up via epub isbn, we might need to look it up)
         end
      end
  else
    log.error "Error Code #{response.code}: #{response.body}"
  end
  sleep(1.0)
end

not_found = Parse::Query.new("NotFoundBooks").tap do | q |
  q.limit = 1000
  q.include = "book,salesChannel"
  q.in_query( "salesChannel", Parse::Query.new("SalesChannel").tap do | q |
    q.eq("name", "Apple")
  end)
end.get

not_found_hash = Hash.new
not_found.each do | book |
  not_found_hash[book["book"]["objectId"]] = book if !book["book"].nil?
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
      $batch.create_object_run_when_full!(not_found_book) if !$opts.dontSaveToParse
    end
  end
end

if $batch.requests.length > 0
  $batch.requests
  $batch.run!
  $batch.requests.clear
end

if !$opts.dontSaveToRJMetrics && $rjClient.data.count > 0
  puts $rjClient.pushData
end
