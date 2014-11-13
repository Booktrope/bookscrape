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
   
   opt :testRJMetrics, "Use RJMetrics test sandbox. This option will save to the sandbox.", :short => 't'
   opt :dontSaveToRJMetrics, "Turns of RJMetrics entirely. Data wont be saved to either the sandbox or live.", :short => 'r'
   opt :dontSaveToParse, "Turns off parse", :short => 'x'
   opt :headless, "Runs headless", :short => 'h'
   opt :marshalFile, "Runs the script based on a marshal file.", :type => :string, :short => 'y'
   opt :groupCount, "The number to group the books into.", :type => :integer, :default => 50, :short => 'g'
   version "1.1.0 2014 Justin Jeffress"

end

$BT_CONSTANTS = Booktrope::Constants.instance

Booktrope::ParseHelper.init_production

is_test_rj = ($opts.testRJMetrics) ? true : false	        
$rjClient = Booktrope::RJHelper.new Booktrope::RJHelper::NOOK_STATS_TABLE, ["parse_book_id", "crawlDate"], is_test_rj if !$opts.dontSaveToRJMetrics
      
def pushdata_to_rj(nook_stats, fields)
	return if !nook_stats.has_key? "book" || !nook_stats["book"].nil?

	hash = Hash.new
	hash["parse_book_id"] = nook_stats["book"].parse_object_id
	hash["crawlDate"] = nook_stats["crawlDate"].value

	fields.each do | key |
		hash[key] = nook_stats[key]
	end
	$rjClient.add_object! hash if !$opts.dontSaveToRJMetrics
end
        
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
	pushdata_to_rj(nook_stats, ["price","salesRank","averageRating","reviewCount"]) if !$opts.dontSaveToRJMetrics
	
	return true
end

def update_book(book, product_image_url)
	should_update_book = false
	if book["imageUrlNook"].nil? || book["imageUrlNook"] == ""
		book["imageUrlNook"] = product_image_url
		should_update_book = true
	end
	
	if book["detailPageUrlNook"].nil? || book["detailPageUrlNook"] == ""
		book["detailPageUrlNook"] = Watir_harness.browser.url
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

def crawl_nook(book_list, unconfirmed_hash)
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
				price =  0
				
				unless !Watir_harness.browser.div(:class => "price", :class =>"hilight").present?
					price = Watir_harness.browser.div(:class => "price", :class =>"hilight")
					book_price = price.text.gsub(/\$/, "")
				end
				#getting the sales rank out of the product details section
				log.info book_price
				sales_rank = "0"
				unless !Watir_harness.browser.div(:class => "product-details").present?
					product_details = Watir_harness.browser.div(:class => "product-details").lis
				
					product_details.each do | detail |
						if detail.text.start_with? "Sales rank:"
							sales_rank = detail.text.gsub(/Sales rank: /, "")
						end
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
				product_image_url = ""
				product_image_url = Watir_harness.browser.img(:class => "product-image").src if Watir_harness.browser.img(:class => "product-image").nil? 
	
				puts "#{book_price}\t#{sales_rank}\t#{average_rating}\t#{review_count}\t#{product_image_url}" if $opts.dontSaveToParse

				if unconfirmed_hash.has_key? book
				pp unconfirmed_hash[book]
				log.info "actual price: #{book_price.to_f} expected price: #{unconfirmed_hash[book]["price"].to_f}"
					if book_price.to_i == unconfirmed_hash[book]["price"].to_i
						unconfirmed_hash[book]["status"] = Booktrope::PRICE_CHANGE::CONFIRMED
						unconfirmed_hash[book].save
					end
				end
				
				stats_saved = save_stats(book, bnid, book_price, sales_rank, average_rating, review_count) if !$opts.dontSaveToParse
				book_saved = update_book(book, product_image_url)

				count = count + 1
				
				sleep 5.0			
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
			$book_group[$current_index] = remaining_books
			
			remaining_groups = $book_group.slice($current_index, $book_group.size - $current_index)
			
			payload = Hash.new
			payload["book_groups"] = remaining_groups
			payload["batch"] = $batch
		
			if $batch.requests.length > 0
				payload["result"] = $batch.run!
				$batch.requests.clear
			end
		
			puts $basePath
			marshal_file = File.join($basePath, "#{Time.now.strftime("%Y-%m-%dT%H-%M-%SZ")}.btm")

			File.open(marshal_file, 'w')  { | f | f.write Marshal.dump(payload) }
			raise e
		end
	})
end

def get_unconfirmed_hash
	unconfirmed_hash = Hash.new
	
	change_queue = get_change_queue
	change_queue.each do | item |
		unconfirmed_hash[item["book"]] = item
	end
	
	return unconfirmed_hash
end

def get_change_queue

	change_queue = Parse::Query.new("PriceChangeQueue").tap do |q|
		q.limit = 1000
		q.eq("status", Booktrope::PRICE_CHANGE::UNCONFIRMED) 
		q.in_query("salesChannel", Parse::Query.new("SalesChannel").tap do | inner_query |
			inner_query.eq("name", Booktrope::PRICE_CHANGE::NOOK_CHANNEL)
		end)
		q.include = "book,salesChannel"
	end.get
	
	return change_queue
end

def get_book_list
	book_list = Array.new
	if Time.now.hour == 5
		book_list = Parse::Query.new("Book").tap do | q |
			q.exists("bnid")
			q.limit = 1000
		end.get
	else
		get_change_queue().each do | changeling |
			book_list.push changeling["book"]
		end
	end
	
	return book_list
end

$batch = Parse::Batch.new
$batch.max_requests = 50

unconfirmed_hash = get_unconfirmed_hash


book_list = Array.new
if $opts.marshalFile.nil?
	book_list = get_book_list
else
	puts $opts.marshalFile
	book_hash = hydrate_from_marshal($opts.marshalFile)
	book_list = book_hash["book_groups"]
end

pp book_list
#raise "crash on purpose"

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
	crawl_nook list, unconfirmed_hash
end

if !$opts.dontSaveToRJMetrics && $rjClient.data.count > 0 
	puts $rjClient.pushData
end