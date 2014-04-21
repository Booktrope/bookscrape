# encoding: utf-8
require "amazon/ecs"
require "parse-ruby-client"
require "nokogiri"
require "trollop"
require 'json'
require 'time'
require 'pp'


basePath = File.absolute_path(File.dirname(__FILE__))
# linking to custom modules
require File.join(basePath, "..","ruby_modules", "bt_logging")
require File.join(basePath, "..","ruby_modules", "constants")
require File.join(basePath, "..","ruby_modules", "download_simple")

opts = Trollop::options do

   banner <<-EOS
Pulls data from Amazon

   Usage:
            ruby bookDropAmazonPickUp.rb [--dontSaveToParse]
   EOS

   opt :dontSaveToParse, "Turns off parse", :short => 'x'
   opt :pathToHtmlFiles, "The path to save the html files that are captured if an extracted value is not found.", :type => :string, :short => 'p'
   version "0.1.3 2013 Justin Jeffress"

end

$log = Bt_logging.create_logging('Book_analysis::Amazon')
$changeQueue = Hash.new

def harvestAmazonData(asinList, bookHash, shouldSaveToParse)
	res = Amazon::Ecs.item_lookup(asinList,:response_group => 'ItemAttributes,SalesRank,Images')
	if !res.is_valid_request? or res.has_error?
	   $log.error "There was an error requesting the following asins: " + asinList
		$log.error res.error
	end
	
	if !res.items.nil? && res.items.count <= 0
	   $log.error "error fetching asins: " + asinList
	end
	
	res.items.each do |item|
		asin = item.get('ASIN')
		detailPageUrl = item.get('DetailPageURL')
		salesRank = item.get('SalesRank')
		largeImageUrl = item.get('LargeImage/URL')
		author = item.get('ItemAttributes/Author')
		manufacturer = item.get('ItemAttributes/Manufacturer')
		title = item.get('ItemAttributes/Title')
		
		book_object = bookHash[asin]
		
		bookHash.delete(asin)
			
		kindle_price = "0"
		stars = "0"
		customer_reviews = "0"
		price_get = false
		
		done = false
		count = 0
		while(!done)
			sleep(2.0)
			response = Download_simple.downloadData(detailPageUrl)
			done = true if !response.nil? && response.code == "200"
			if count > 4 then done = true end
			count = count + 1
		end
		
		if !response.nil? && response.code == "200"
		   hasNoAvgReviews = false
		   hasNoReviews = false
			data = Nokogiri.parse(response.body)			
			if data.at_css("tbody#kindle_meta_binding_winner")
				if !data.at_css("tbody#kindle_meta_binding_winner tr#tmm_"<< asin <<" td.price").nil?
					kindle_price = data.at_css("tbody#kindle_meta_binding_winner tr#tmm_"<< asin <<" td.price").text.strip.gsub(/\n.*/, "").tr('$','')
				end
			else
				kindle_prices = data.xpath("//td[@class='productBlockLabel']")
				kindle_prices.each do |item|
					if item.text.strip == "Kindle Price:"
						if item.next.next
							kindle_price = item.next.next.text.strip.tr("$","")
						end
					end
				end
				$log.warn "#{asin} kindle_meta_binding_winner not found data extracted from productBlockLabel #{kindle_price}"
			end
			
			if data.at_css("span.crAvgStars span span")
			   stars = data.at_css("span.crAvgStars span span").text.strip.gsub(/ out of 5 stars/,"")
			elsif data.at_css("div.reviews div.gry.txtnormal.acrRating")
			   stars = data.at_css("div.gry.txtnormal.acrRating").text.strip.gsub(/ out of 5 stars/,"")
			else
			   hasNoAvgReviews = true
			end
			
			if salesRank == nil
				salesRankTag = data.at_css("li#SalesRank")
				match = /#([0-9,]*)/.match(salesRankTag.text) if !salesRankTag.nil?
				salesRank = match[1].gsub(/,/,"") if !salesRankTag.nil?
			end
			
			if data.at("//span[@class='crAvgStars']/a[last()]")
			   customer_reviews = data.at("//span[@class='crAvgStars']/a[last()]").text.strip.gsub(/ customer review/,"").gsub(/s/,"")
			elsif data.at_css("div.reviews div#revSum div.fl.mt15.clearboth")
			   customer_reviews = data.at("div.reviews div#revSum div.fl.mt15.clearboth").text.strip.gsub(/See all /,"").gsub(/ customer review/,"").gsub(/s/,"")
			else
			   hasNoReviews = true
			end
			
			if hasNoAvgReviews
			   $log.warn "#{asin} crAvgStars not found! no reviews"
			end
			if hasNoReviews
			   $log.warn "#{asin} No reviews found!"
			end
		else
			$log.error "#{asin} Failed to fetch detailUrlPage error code: = #{response.code} url: #{detailPageUrl}"
		end
		
		time = Time.new
		crawl_date = Parse::Date.new(time.strftime("%Y/%m/%d %H:%M:%S"))
		
		if shouldSaveToParse		   
		   #we only update if a field that we pull form amazon is different than what is already stored in parse. (except the asin that just wouldn't make sense)
		   flag = 0
		   
			if !title.nil?         && book_object['title']       != title then book_object['title'] = title; flag |= 1 end
			if !detailPageUrl.nil? && book_object['detail_url']  != detailPageUrl then book_object['detail_url'] = detailPageUrl; flag |= 2 end
			if !largeImageUrl.nil? && book_object['large_image'] != largeImageUrl then book_object['large_image'] = largeImageUrl; flag |= 4 end
			if !author.nil?        && book_object['author']      != author then book_object['author'] = author; flag |= 8 end
			if !manufacturer.nil?  && book_object['publisher']   != manufacturer then book_object['publisher'] = manufacturer; flag |= 16 end

			begin
				book_object.save if flag & 31 # anding our max value (of 5 bits) if greater than 0 we know we had a change 				
			rescue Exception => e
				$log.error pp book_object
				$log.error pp e
			end
			#TODO: add a log of what we changed by anding by, 1,2,4,8,16 to see if we get a value > 0, if so then the corresponding field changed. 
			
			price_get = true if kindle_price != "0"
			
			crawl_object = Parse::Object.new("AmazonStats")
			crawl_object['asin'] = asin
			crawl_object['sales_rank'] = salesRank.to_i
			crawl_object['kindle_price'] = kindle_price.to_f
			crawl_object['num_of_reviews'] = customer_reviews.to_f
			crawl_object['average_stars'] = stars.to_f
			crawl_object['crawl_date'] = crawl_date
			crawl_object['got_price'] = price_get

			crawl_object['book'] = book_object
			begin
				crawl_object.save
			rescue Exception => e
				$log.error pp crawl_object
				$log.error pp e
			end			
		else
		   puts "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" % [asin, kindle_price, title, author, manufacturer, salesRank, customer_reviews, stars, crawl_date.to_h()["iso"], detailPageUrl, largeImageUrl]
		end
		
		if $changeQueue.has_key? asin
			
			if kindle_price.to_f == $changeQueue[asin]["price"]
				$changeQueue[asin]["status"] = 99
				$changeQueue[asin].save
				
				require 'twilio-ruby'
				account_sid = 'AC2980067718d40f28035f4bb858f9be6e'
				auth_token = 'e27948e87e55c31c0f2dee2586cd49c5'
				client = Twilio::REST::Client.new account_sid, auth_token
				client.account.messages.create(:from => '+18183348793',
				:to => '+13102924925',
				:body => "Price Verified #{asin} #{kindle_price.to_f}")
				client = Twilio::REST::Client.new account_sid, auth_token
				client.account.messages.create(:from => '+18183348793',
				:to => '+18183085878',
				:body => "Price Verified #{asin} #{kindle_price.to_f}")
			end
		end
		
		if salesRank == "0" || kindle_price == "0" || customer_reviews == "0" || stars == "0"
		   log_file = File.join($log_dir, "#{asin}-#{time.strftime('%Y-%m-%d')}T#{time.strftime('%H%M%S')}Z-#{ crawl_object ? crawl_object.id : "NOT-LOADED"}.html")
		   textHtml = "<!-- salesRank: #{salesRank} kindle_price: #{kindle_price} customer_reviews: #{customer_reviews} stars: #{stars} -->\n" + response.body
		   File.open( log_file, 'w') { |file| file.write(textHtml) }
		end
	end
	if bookHash.length > 0
	
		is_first = true
		asin_list = ""
		bookHash.each do | key, value |
			asin_list << "," if !is_first
			asin_list << key
			is_first = false
		end
		$log.error "not all books were returned from amazon: #{asin_list}"
	end
	sleep(1.0)
end


$config_dir = File.join(basePath, "config")
workingPath = !opts.pathToHtmlFiles.nil? && opts.pathToHtmlFiles.strip != "" ? opts.pathToHtmlFiles : basePath 

$log_dir    = File.join(workingPath, "missing_log")
$cron_dir   = File.join(workingPath, "cron_log")


Dir.mkdir($log_dir) unless File.exists?($log_dir)
Dir.mkdir($cron_dir) unless File.exists?($cron_dir)

shouldSaveToParse = opts.dontSaveToParse ? false : true;

BT_CONSTANTS = BTConstants.get_constants
Amazon::Ecs.options = {
:associate_tag     => BT_CONSTANTS[:amazon_ecs_associate_tag],
:AWS_access_key_id => BT_CONSTANTS[:amazon_ecs_access_key_id],
:AWS_secret_key    => BT_CONSTANTS[:amazon_ecs_secret_key]
}

Parse.init :application_id => BT_CONSTANTS[:parse_application_id],
	        :api_key        => BT_CONSTANTS[:parse_api_key]

#Parse.init :application_id => "RIaidI3C8TOI7h6e3HwEItxYGs9RLXxhO0xdkdM6",
#	        :api_key        => "EQVJvWgCKVp4zCc695szDDwyU5lWcO3ssEJzspxd"


changelings = Parse::Query.new("PriceChangeQueue").tap do |q|
	q.limit = 1000
	q.eq("status", 50)
	q.in_query("salesChannel", Parse::Query.new("SalesChannel").tap do | inner_query |
		inner_query.eq("name", "Amazon")
	end)	
end.get

changelings.each do | changeling |
	$changeQueue[changeling["asin"]] = changeling
end


book_count = Parse::Query.new("Book").tap do |q|
	q.exists("asin")
   q.limit = 0
   q.count = 1
end.get	  

if book_count["count"] > 0
	GROUPING = 10
	skip = 0
	done = false
	while !done
		
		book_list = Parse::Query.new("Book").tap do |q|
			q.exists("asin")
			q.skip = skip 
			q.limit = 10
		end.get
		skip = skip + GROUPING
		
		bookHash = Hash.new
		isStart = true
		asin_args = ""
		count = 1
		book_list.each do |book|
			bookHash[book["asin"]] = book
		
			if !isStart
				asin_args << ","
			end
			isStart = false
			asin_args << book["asin"]
		end
		harvestAmazonData(asin_args, bookHash, shouldSaveToParse) if asin_args.length > 0
		done = true if skip >= book_count["count"]
	end
end