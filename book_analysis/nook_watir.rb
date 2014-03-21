require 'trollop'
require 'time'
require 'pp'

$basePath = File.absolute_path(File.dirname(__FILE__))
require File.join($basePath, '..', 'booktrope-modules')

$opts = Trollop::options do

   banner <<-EOS
Extracts book sales data from Nook

   Usage:
            ruby nook_watir.rb [--dontSaveToParse] [--headless] [--marshalFile file_name]
   EOS

   opt :dontSaveToParse, "Turns off parse", :short => 'x'
   opt :headless, "Runs headless", :short => 'h'
   opt :marshalFile, "Runs the script based on a marshal file.", :type => :string, :short => 'y'
   opt :groupCount, "The number to group the books into.", :type => :integer, :default => 0, :short => 'g'
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

def hydrate_from_marshal(file)
	hash = Hash.new
	hash = Marshal.load(File.read(file))
	return hash
end

def crawl_nook(book_list)
	class_name = "Book_analysis::Nook_watir"
	should_run_headless = ($opts.headless) ?  true : false
	Watir_harness.run(should_run_headless, class_name, lambda { | log | 

		skipped = 0
		count = 0
		step = 0
		stats_saved = false
		book_saved = false
		begin
	
			Watir_harness.browser.goto $BT_CONSTANTS[:nook_url]	
			book_list.each_with_index do | book, index |
				step = index
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
					
					#typing the bnid into the search input box.				
					Watir_harness.browser.text_field(:name => 'keyword').set(bnid)
					#clicking on the search button.
					Watir_harness.browser.button(:class => 'branded').click				
				
					#if there are no results skip it.
					if Watir_harness.browser.url.include? "noresults"
						skipped = skipped + 1
						next
					end
				else
					Watir_harness.browser.goto book["detailPageUrlNook"]
				end
		
				#looking up the price.
				sleep 0.5
				price =  Watir_harness.browser.div(:class => "price", :class =>"hilight")
				book_price = price.text.gsub(/\$/, "")
		
				#getting the sales rank out of the product details section
				product_details = Watir_harness.browser.div(:class => "product-details").lis

				sales_rank = "0"
				product_details.each do | detail |
					if detail.text.start_with? "Sales rank:"
						sales_rank = detail.text.gsub(/Sales rank: /, "")
					end
				end
	
				#getting the average rating. 
				#We use find_elements so selenium wont crash if the book hasn't been rated.
				average_rating = 0

				if Watir_harness.browser.div(:class => "averageRating").span.exists?
					average_rating = Watir_harness.browser.div(:class => "averageRating").span.text.strip
				end
	
				#getting the number of reviews. 
				#We use find_elements so selenium wont crash if the book hasn't been rated.
				review_count = 0
				if Watir_harness.browser.span(:class => "total").a.span.exists?
					review_count = Watir_harness.browser.span(:class => "total").a.span.text.strip
				end
		
				#getting the product image url.
				product_image_url = Watir_harness.browser.img(:class => "product-image").src
	
				puts "#{book_price}\t#{sales_rank}\t#{average_rating}\t#{review_count}\t#{product_image_url}" if $opts.dontSaveToParse

				stats_saved = save_stats(book, bnid, book_price, sales_rank, average_rating, review_count) if !$opts.dontSaveToParse
				book_saved = update_book(book, product_image_url)
			
				count = count + 1
				
				sleep 2.5			
			end
	
			if $batch.requests.length > 0
				$batch.run!
				$batch.requests.clear
			end
	
			log.info "skipped: #{skipped} crawled: #{count}"
		
		rescue Exception => e
			if stats_saved || book_saved
				step = step + 1
			end
		
			remaining_books = book_list.slice(step, book_list.size - step)
				
			payload = Hash.new
			payload["book_list"] = remaining_books
			payload["batch"] = $batch
		
			if $batch.requests.length > 0
				payload["result"] = $batch.run!
			end
		
			puts $basePath
			marshal_file = File.join($basePath, "#{Time.now.strftime("%Y-%m-%dT%H-%M-%SZ")}.btm")

			File.open(marshal_file, 'w')  { | f | f.write Marshal.dump(payload) }
			raise e
		end
	})
end

def run(should_run_headless, class_name, lambda)

	browser = Watir::Browser.new :firefox
	log = Bt_logging.create_logging(class_name)
	lambda.call(log)
	browser.quit
end

$batch = Parse::Batch.new
$batch.max_requests = 50

book_list = Array.new
if $opts.marshalFile.nil?
	book_list = Parse::Query.new("Book").tap do | q |
		q.exists("bnid")
		q.limit = 1000
	end.get
else
	puts $opts.marshalFile
	book_hash = hydrate_from_marshal($opts.marshalFile)
	book_list = book_hash["book_list"]
end

$current_index = 0
$book_group = Array.new
inner_list = Array.new
count = 0
book_list.each do | book |

	inner_list.push book
	count = count + 1
	
	if inner_list.size >= $opts.groupCount
		$book_group.push inner_list
		inner_list = Array.new
		count = 0
	end
end

if inner_list.size > 0
	$book_group.push inner_list
end

$book_group.each_with_index do | list, index |
	$current_index = index
	crawl_nook list
end