# encoding: utf-8
require "amazon/ecs"
require "parse-ruby-client"
require "nokogiri"
require "trollop"
require 'json'

$basePath = File.absolute_path(File.dirname(__FILE__))

# linking to custom modules
require File.join($basePath, "..", "..","ruby_modules", "download_simple")
require File.join($basePath, "..", "..","ruby_modules", "constants")

$log_dir    = File.join($basePath, "missing_log")
$config_dir = File.join($basePath, "config")
$cron_dir   = File.join($basePath, "cron_log")


# TODO: jrj - look into using a ruby logging gem.
Dir.mkdir($log_dir) unless File.exists?($log_dir)
Dir.mkdir($cron_dir) unless File.exists?($cron_dir)

opts = Trollop::options do

   banner <<-EOS
Pulls data from Amazon

   Usage:
            ruby bookDropAmazonPickUp.rb [--dontSaveToParse] --asinList
   EOS

   opt :dontSaveToParse, "Turns off parse", :short => 'x'
   opt :asinList, "List of asin's", :type => :string, :short => 'a'
   version "0.1.2 2013 Justin Jeffress"

end

#TODO: jrj - refactor the script to get the list of ASINS to scan from parse instead of the ASIN file.
#TODO: jrj - improve logging - add a date and time stamp of when the error occurred.
#TODO: jrj - improve logging - in the html files saved upon not finding data in the page, add a comment to the html with what is missing.
#TODO: jrj - upon 503 add a wait and try again.

shouldSaveToParse = opts.dontSaveToParse ? false : true;

def harvestAmazonData(asinList, shouldSaveToParse)
	res = Amazon::Ecs.item_lookup(asinList,:response_group => 'ItemAttributes,SalesRank,Images')
	if !res.is_valid_request? or res.has_error?
	   $stderr.puts "there was an requesting the following asins: " + asinList
		$stderr.puts res.error
	end
	
	if !res.items.nil? && res.items.count <= 0
	   puts "error fetching asins: "+asinList
	end
	
	res.items.each do |item|
		asin = item.get('ASIN')
		detailPageUrl = item.get('DetailPageURL')
		salesRank = item.get('SalesRank')
		largeImageUrl = item.get('LargeImage/URL')
		author = item.get('ItemAttributes/Author')
		manufacturer = item.get('ItemAttributes/Manufacturer')
		title = item.get('ItemAttributes/Title')
			
		kindle_price = "0"
		stars = "0"
		customer_reviews = "0"
				
		response = Download_simple.downloadData(detailPageUrl)
		
		if response.code == "200"
		   hasNoAvgReviews = false
		   hasNoReviews = false
			data = Nokogiri.parse(response.body)			
			if data.at_css("tbody#kindle_meta_binding_winner")
				kindle_price = data.at_css("tbody#kindle_meta_binding_winner tr#tmm_"<< asin <<" td.price").text.strip.gsub(/\n.*/, "").tr('$','')
			else
				kindle_prices = data.xpath("//td[@class='productBlockLabel']")
				kindle_prices.each do |item|
					if item.text.strip == "Kindle Price:"
						if item.next.next
							kindle_price = item.next.next.text.strip.tr("$","")
						end
					end
				end
				$stderr.puts "kindle_meta_binding_winner not found data extracted from productBlockLabel #{kindle_price}"
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
				match = /#([0-9,]*)/.match(salesRankTag.text)
				salesRank = match[1].gsub(/,/,"")
			end
			
			if data.at("//span[@class='crAvgStars']/a[last()]")
			   customer_reviews = data.at("//span[@class='crAvgStars']/a[last()]").text.strip.gsub(/ customer review/,"").gsub(/s/,"")
			elsif data.at_css("div.reviews div#revSum div.fl.mt15.clearboth")
			   customer_reviews = data.at("div.reviews div#revSum div.fl.mt15.clearboth").text.strip.gsub(/See all /,"").gsub(/ customer review/,"").gsub(/s/,"")
			else
			   hasNoReviews = true
			end
			
			if hasNoAvgReviews
			   $stderr.puts "crAvgStars not found! no reviews #{asin}"
			end
			if hasNoReviews
			   $stderr.puts "no reviews found! no reviews #{asin}"
			end
		else
			$stderr.puts "Error fetching detailUrlPage = #{response.code}"
		end
		
		time = Time.new
		crawl_date = time.strftime("%Y/%m/%d")
		crawl_time = time.strftime("%H:%M:%S")
		
		if shouldSaveToParse
		   book_object = Parse::Query.new("Book").eq("asin", asin).get.first
			if book_object.nil?
			   book_object = Parse::Object.new("Book")
			   book_object['asin'] = asin
			   book_object['title'] = title
			   book_object['detail_url'] = detailPageUrl
			   book_object['large_image'] = largeImageUrl
			   book_object['author'] = author
			   book_object['publisher'] = manufacturer
			   book_object.save
			end
			
			crawl_object = Parse::Object.new("AmazonStats")
			crawl_object['asin'] = asin
			crawl_object['sales_rank'] = salesRank.to_i
			crawl_object['kindle_price'] = kindle_price.to_f
			crawl_object['num_of_reviews'] = customer_reviews.to_f
			crawl_object['average_stars'] = stars.to_f
			crawl_object['crawl_date'] = crawl_date
			crawl_object['crawl_time'] = crawl_time
			crawl_object['book'] = book_object
			crawl_object.save
		else
		   puts "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" % [asin, kindle_price, title, author, manufacturer, salesRank, customer_reviews, stars, crawl_date, crawl_time, detailPageUrl, largeImageUrl]
		end
		
		if salesRank == "0" || kindle_price == "0" || customer_reviews == "0" || stars == "0"
		   log_file = File.join($log_dir, "#{asin}-#{time.strftime('%Y-%m-%d')}T#{time.strftime('%H%M%S')}Z-#{ crawl_object ? crawl_object.id : "NOT-LOADED"}.html")
		   File.open( log_file, 'w') { |file| file.write(response.body) }
		end
	end
end

#loading the ./config/config.json file and parsing into a json object.
config_json = JSON.parse(File.read(File.join($config_dir, "config.json")))

Amazon::Ecs.options = {
:associate_tag     => config_json[CONST_AWS::LABEL][CONST_AWS::ASSOCIATE_TAG],
:AWS_access_key_id => config_json[CONST_AWS::LABEL][CONST_AWS::ACCESS_KEY_ID],
:AWS_secret_key    => config_json[CONST_AWS::LABEL][CONST_AWS::SECRET_KEY]
}

Parse.init :application_id => config_json[CONST_PARSE::LABEL][CONST_PARSE::APPLICATION_ID],
	        :api_key        => config_json[CONST_PARSE::LABEL][CONST_PARSE::API_KEY]


count = 1
max = 10
isStart = true
asin_args = ""
File.open(opts.asinList) do |file|
	file.each_line do |line|
		if !isStart
			asin_args << ","
		end
		isStart = false
		asin_args << line.strip
		if count % max == 0
			harvestAmazonData(asin_args, shouldSaveToParse)
			asin_args = ""
			isStart = true
		end
		count = count + 1
	end
end

harvestAmazonData(asin_args, shouldSaveToParse) if asin_args.length > 0
