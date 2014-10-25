basePath = File.absolute_path(File.dirname(__FILE__))
# linking to custom modules
require File.join(basePath, '..', 'booktrope-modules')
require 'trollop'
require 'mechanize'

$opts = Trollop::options do
   banner <<-EOS
Extracts various meta data from GooglePlay.

   Usage:
            ruby google_play.rb [--dontSaveToParse] --testRJMetrics --dontSaveToParse --dontSaveToRJMetrics
   EOS
   
   opt :testRJMetrics, "Use RJMetrics test sandbox. This option will save to the sandbox.", :short => 't'
   opt :dontSaveToParse, "Prevents the collected data from being saved to parse.", :short => 'x'
   opt :dontSaveToRJMetrics, "Turns of RJMetrics entirely. Data wont be saved to either the sandbox or live.", :short => 'r'
   
   version "1.0.0 2014 Justin Jeffress"
end

PLAY_BASE = "https://play.google.com"
SEARCH_BASE = "https://play.google.com/store/search?c=books&q="

$BT_CONSTANTS = Booktrope::Constants.instance

$log = Bt_logging.create_logging('Book_analysis::GooglePlay')

Booktrope::ParseHelper.init :application_id => $BT_CONSTANTS[:parse_application_id],
							       :api_key        => $BT_CONSTANTS[:parse_api_key]
							       
is_test_rj = ($opts.testRJMetrics) ? true : false
$rjClient = Booktrope::RJHelper.new Booktrope::RJHelper::GOOGLE_PLAY_STATS_TABLE, ["parse_book_id", "crawlDate"], is_test_rj if !$opts.dontSaveToRJMetrics

$batch = Parse::Batch.new
$batch.max_requests = 50

def crawl_google_play

	unconfirmed_hash = Hash.new
	
	options = [Booktrope::Constraint.new(:eq, "channelName", Booktrope::PRICE_CHANGE::GOOGLE_CHANNEL),
		Booktrope::Constraint.new(:eq, "status", Booktrope::PRICE_CHANGE::UNCONFIRMED),
		Booktrope::Constraint.new(:include, "", "book,salesChannel")
	]
	change_queue = Booktrope::ParseHelper.get_price_change_queue(options)
	
	change_queue.each do | item |
		if !unconfirmed_hash.has_key? item["book"]
			unconfirmed_hash[item["book"]] = item
		else
			unconfirmed_hash[item["book"]] = item if unconfirmed_hash[item["book"]]["changeDate"].value > item["changeDate"].value
		end
	end
	
	book_list = Booktrope::ParseHelper.get_books(:exists => ["epubIsbnItunes"])

	agent = Mechanize.new

	book_list.each do | book |
		search_url = SEARCH_BASE + book["epubIsbnItunes"]
		#puts search_url
		
		detail_url = book["detailUrlGooglePlay"]
	
		if detail_url.nil? || detail_url == ""
			done = false
		
			attempts = 0
			max_attempts = 3
		
			while !done
				done = true
				attempts = attempts + 1
				begin
					page = agent.get(search_url)
				rescue Mechanize::ResponseCodeError
					$log.info "retrying #{search_url}"
					sleep(5.0)
					if !(attempts >= max_attempts)
						done = false
					end
				end
			end
		
			next if attempts >= max_attempts
		
			doc = Nokogiri::HTML(page.body)
		
			if !doc.css("div.empty-search").one?
				if doc.css("div.cover a.card-click-target").one?
					relative_book_url = doc.css("div.cover a.card-click-target").attribute("href").text.strip
					detail_url = "#{PLAY_BASE}#{relative_book_url}"
					book["detailUrlGooglePlay"] = detail_url
					$batch.update_object_run_when_full!(book) if !$opts.dontSaveToParse
				end
			end
		end
	
		next if detail_url.nil? || detail_url == ""
		$log.info "fetching: #{detail_url}"
	
		html = agent.get(detail_url).body
		dom = Nokogiri::HTML(html)
	
		average_reviews = 0.0
		total_reviews = 0
		price = 0.0
		cover_image_url = ""
			
		if dom.css("div.score-container div.score").one?
			average_reviews = dom.css("div.score-container div.score").text.strip
		end
			
		if dom.css("div.reviews-stats span.reviews-num").one?
			total_reviews = dom.css("div.reviews-stats span.reviews-num").text.strip
		end
			
		if dom.css("div.details-actions button.price.buy span.full-price").one?
			price = dom.xpath("//div[@id='body-content']/div/div[2]/div[2]/div[4]/span/button/span[3]").text.strip.gsub(/\$/,"").gsub(/ Buy/, "")
		elsif dom.css("div.details-actions button.price.buy").one?
			price = dom.css("div.details-actions button.price.buy").text.strip.gsub(/\$/,"").gsub(/ Buy/, "")
		end
			
		if dom.css("div.cover-container img.cover-image").one?
			cover_image_url = dom.css("div.cover-container img.cover-image").attribute("src").value
		end
	
		if book["imageUrlGooglePlay"].nil? || book["imageUrlGooglePlay"] != cover_image_url
			book["imageUrlGooglePlay"] = cover_image_url
			$batch.update_object_run_when_full!(book) if !$opts.dontSaveToParse
		end
		
		puts "#{average_reviews}\t#{total_reviews}\t#{price}\t#{cover_image_url}\t#{book['epubIsbnItunes']}\t#{detail_url}"
	
		google_play_stats = Parse::Object.new("GooglePlayStats")
		google_play_stats["book"] = book
		google_play_stats["price"] = price.to_f
		google_play_stats["numOfReviews"] = total_reviews.to_i
		google_play_stats["averageReviews"] = average_reviews.to_f
		google_play_stats["crawlDate"] = Parse::Date.new(Time.now.utc.strftime("%Y/%m/%d %H:%M:%S"))
	
		$batch.create_object_run_when_full!(google_play_stats) if !$opts.dontSaveToParse
		pushdata_to_rj(google_play_stats, ["price", "numOfReviews", "averageReviews"]) if !$opts.dontSaveToRJMetrics
		
		if unconfirmed_hash.has_key? book
			$log.info "found a book with a price change. #{book["title"]} epubISBN: #{book['epubIsbnItunes']} #{unconfirmed_hash[book].id} #{price} #{unconfirmed_hash[book]["price"]}"
			if unconfirmed_hash[book]["price"] == price.to_f
				$log.info "CONFIRMED: Expected: #{unconfirmed_hash[book]["price"]} Actual: #{price}"
				unconfirmed_hash[book]["status"] = Booktrope::PRICE_CHANGE::CONFIRMED
				#unconfirmed_hash[book]["status_text"] = Booktrope::PRICE_CHANGE::CONFIRMED_TEXT
				unconfirmed_hash[book].save
			end
		end
		
		sleep 0.5
	end
end

def pushdata_to_rj(google_play_stats, fields)
	return if !google_play_stats.has_key? "book" || !google_play_stats["book"].nil?

	hash = Hash.new
	hash["parse_book_id"] = google_play_stats["book"].parse_object_id
	hash["crawlDate"] = google_play_stats["crawlDate"].value

	fields.each do | key |
		hash[key] = google_play_stats[key]
	end
	$rjClient.add_object! hash if !$opts.dontSaveToRJMetrics
end

crawl_google_play

if $batch.requests.length > 0
	$batch.run!
	$batch.requests.clear
end

if !$opts.dontSaveToRJMetrics && $rjClient.data.count > 0 
	puts $rjClient.pushData
end