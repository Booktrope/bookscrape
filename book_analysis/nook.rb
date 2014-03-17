require 'trollop'
require 'yaml'
require 'pp'

$basePath = File.absolute_path(File.dirname(__FILE__))
require File.join($basePath, '..', 'booktrope-modules')

$opts = Trollop::options do

   banner <<-EOS
Extracts book sales data from Nook

   Usage:
            ruby nook.rb [--dontSaveToParse] [--headless]
   EOS

   opt :dontSaveToParse, "Turns off parse", :short => 'x'
   opt :headless, "Runs headless", :short => 'h'
   version "1.0.0 2014 Justin Jeffress"

end

$BT_CONSTANTS = BTConstants.get_constants

Parse.init :application_id => $BT_CONSTANTS[:parse_application_id],
	        :api_key        => $BT_CONSTANTS[:parse_api_key]

def save_stats(book, bnid, book_price, sales_rank, average_rating, review_count)
	nook_stats = Parse::Object.new("NookStats")
	nook_stats["bnid"] = bnid
	nook_stats["book"] = book
	nook_stats["price"] = book_price.to_f
	nook_stats["salesRank"] = sales_rank.gsub(/,/,"").to_i
	nook_stats["averageRating"] = average_rating.to_i
	nook_stats["reviewCount"] = review_count.to_i
	nook_stats["crawlDate"] = Parse::Date.new(Time.now.utc.strftime("%Y/%m/%d %H:%M:%S"))
	
	$batch.create_object_run_when_full!(nook_stats)
	
	return true
end

def update_book(book, product_image_url)
	should_update_book = false
	if book["imageUrlNook"].nil? || book["imageUrlNook"] == ""
		book["imageUrlNook"] = product_image_url
		should_update_book = true
	end
	
	if book["detailPageUrlNook"].nil? || book["detailPageUrlNook"] == ""
		book["detailPageUrlNook"] = Selenium_harness.current_url
		should_update_book = true
	end
	
	if should_update_book == true
		$batch.update_object_run_when_full!(book)
	end
	return should_update_book
end

def crawl_nook(book_list)

	skipped = 0
	count = 0
	class_name = "Book_analysis::Nook"
	should_run_headless = ($opts.headless) ?  true : false
	results = Selenium_harness.run(should_run_headless, class_name, lambda { | log |
index = 0
begin

		Selenium_harness.get($BT_CONSTANTS[:nook_url])
		book_list.each_with_index do | book, index |
			if book["bnid"] == 0
				skipped = skipped + 1
				next
			end
			
			stats_saved = false
			book_saved = false
			bnid = book["bnid"]
		
			log.info "looking up: #{bnid}"
		
			#if we don't have the nook url we need to look up via the bnid.
			if book["detailPageUrlNook"].nil? || book["detailPageUrlNook"] == ""
		
				#clicking on the nook store link.
				nook_book_link = Selenium_harness.find_element(:link, "NOOK Books")
				nook_book_link.click
				sleep 2.5
			
				#typing the bnid into the search input box.
				search_bar = Selenium_harness.find_element(:id, "search-input")
				search_bar.clear
				search_bar.send_keys bnid 
			
				#clicking on the search button.
				search_button = Selenium_harness.find_element(:id, "quick-search-button")
				search_button.click
			
				#if there are no results skip it.
				if Selenium_harness.current_url.include? "noresults"
					skipped = skipped + 1
					next
				end
			else
				Selenium_harness.get book["detailPageUrlNook"]
			end
		
			#looking up the price.
			wait = Selenium::WebDriver::Wait.new(:timeout => 60)
			wait.until { Selenium_harness.find_element(:css, ".price,.hilight").displayed? }
	
			price = Selenium_harness.find_element(:css, ".price,.hilight")
			book_price = price.text.gsub(/\$/, "")
		
			#getting the sales rank out of the product details section
			product_details = Selenium_harness.find_elements(:css, "div.product-details ul li")
	
			sales_rank = "0"
			product_details.each do | detail |
				if detail.text.start_with? "Sales rank:"
					sales_rank = detail.text.gsub(/Sales rank: /, "")
				end
			end
	
			#getting the average rating. 
			#We use find_elements so selenium wont crash if the book hasn't been rated.
			average_rating_wrapper = Selenium_harness.find_elements(:css, "div.averageRating span")
			average_rating = 0
			if average_rating_wrapper.length > 0
				average_rating = average_rating_wrapper.first.text.strip
			end
	
			#getting the number of reviews. 
			#We use find_elements so selenium wont crash if the book hasn't been rated.
			num_of_reviews = 0
			num_of_reviews_wrapper = Selenium_harness.find_elements(:css, "span.total a span")
			if num_of_reviews_wrapper.length > 0
				review_count = num_of_reviews_wrapper.first.text.strip
			end
		
			#getting the product image url.
			product_image = Selenium_harness.find_element(:css, "img.product-image")
			product_image_url = product_image.attribute("src")
	
			puts "#{book_price}\t#{sales_rank}\t#{average_rating}\t#{review_count}\t#{product_image_url}" if $opts.dontSaveToParse

			stats_saved = save_stats(book, bnid, book_price, sales_rank, average_rating, review_count) if !$opts.dontSaveToParse
			book_saved = update_book(book, product_image_url)
			
			count = count + 1
	
			sleep 5.0
			
			if count > 5 
				raise "break"
			end
		end
	
		if $batch.requests.length > 0
			$batch.run!
		end
	
		log.info "skipped: #{skipped} crawled: #{count}"
		
rescue Exception => e
	remaining_books = book_list.slice(index, book_list.size - index)
	puts remaining_books.to_yaml
	
	payload = Hash.new
	payload["book_list"] = remaining_books
	payload["batch"] = $batch
	
	File.open('/Users/Justin/Desktop/test.yml', 'w') { | f | f.write payload }
	
	raise e
end
	})
end

$batch = Parse::Batch.new
$batch.max_requests = 50
	        
book_list = Parse::Query.new("Book").tap do | q |
	q.exists("bnid")
	q.limit = 1000
end.get
begin
	crawl_nook book_list
rescue Exception => e
	puts e.message
end