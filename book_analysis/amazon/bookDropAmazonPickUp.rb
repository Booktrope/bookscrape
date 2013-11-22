# encoding: utf-8
require "amazon/ecs"
require "parse-ruby-client"
require "nokogiri"
require "trollop"
require 'json'
require 'logging'
require 'time'


basePath = File.absolute_path(File.dirname(__FILE__))
# linking to custom modules
require File.join(basePath, "..", "..","ruby_modules", "download_simple")
require File.join(basePath, "..", "..","ruby_modules", "constants")

#TODO: jrj - refactor the script to get the list of ASINS to scan from parse instead of the ASIN file. Doing so will cut down on requests made to parse.

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

Logging.color_scheme( 'bright',
:levels => {
	:info  => :green,
	:warn  => :yellow,
	:error => :red,
	:fatal => [:white, :on_red]
   },
	:date => :blue,
	:logger => :cyan,
	:message => :magenta
)

Logging.appenders.stdout(
	'stdout',
	:layout => Logging.layouts.pattern(
	:pattern => '[%d] %-5l %c: %m\n',
	:color_scheme => 'bright'
   )
)

$log = Logging.logger['Book_analysis::Amazon']
$log.add_appenders Logging.appenders.stderr
$log.level = :debug

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
			
		kindle_price = "0"
		stars = "0"
		customer_reviews = "0"
		
		done = false
		count = 0
		while(!done)
			sleep(1.0)
			response = Download_simple.downloadData(detailPageUrl)
			done = true if !response.nil? && response.code == "200"
			if ++count > 4 then done = true end
		end
		
		if !response.nil? && response.code == "200"
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
		   book_object = bookHash[asin]
			if book_object['title'] != title then book_object['title'] = title; flag |= 1 end
			if book_object['detail_url'] != detailPageUrl then book_object['detail_url'] = detailPageUrl; flag |= 2 end
			if book_object['large_image'] != largeImageUrl then book_object['large_image'] = largeImageUrl; flag |= 4 end
			if book_object['author'] != author then book_object['author'] = author; flag |= 8 end
			if book_object['publisher'] = manufacturer then book_object['publisher'] = manufacturer; flag |= 16 end
			book_object.save if flag & 31 # anding our max value (of 5 bits) if greater than 0 we know we had a change 
			#TODO: add a log of what we changed by anding by, 1,2,4,8,16 to see if we get a value > 0, if so then the corresponding field changed. 
			
			crawl_object = Parse::Object.new("AmazonStats")
			crawl_object['asin'] = asin
			crawl_object['sales_rank'] = salesRank.to_i
			crawl_object['kindle_price'] = kindle_price.to_f
			crawl_object['num_of_reviews'] = customer_reviews.to_f
			crawl_object['average_stars'] = stars.to_f
			crawl_object['crawl_date'] = crawl_date

			crawl_object['book'] = book_object
			crawl_object.save
		else
		   puts "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" % [asin, kindle_price, title, author, manufacturer, salesRank, customer_reviews, stars, crawl_date.to_h()["iso"], detailPageUrl, largeImageUrl]
		end
		
		if salesRank == "0" || kindle_price == "0" || customer_reviews == "0" || stars == "0"
		   log_file = File.join($log_dir, "#{asin}-#{time.strftime('%Y-%m-%d')}T#{time.strftime('%H%M%S')}Z-#{ crawl_object ? crawl_object.id : "NOT-LOADED"}.html")
		   textHtml = "<!-- salesRank: #{salesRank} kindle_price: #{kindle_price} customer_reviews: #{customer_reviews} stars: #{stars} -->\n" + response.body
		   File.open( log_file, 'w') { |file| file.write(textHtml) }
		end
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


#loading the ./config/config.json file and parsing into a json object.
config_json = JSON.parse(File.read(File.join($config_dir, "config.json")))

Amazon::Ecs.options = {
:associate_tag     => config_json[CONST_AWS::LABEL][CONST_AWS::ASSOCIATE_TAG],
:AWS_access_key_id => config_json[CONST_AWS::LABEL][CONST_AWS::ACCESS_KEY_ID],
:AWS_secret_key    => config_json[CONST_AWS::LABEL][CONST_AWS::SECRET_KEY]
}

Parse.init :application_id => config_json[CONST_PARSE::LABEL][CONST_PARSE::APPLICATION_ID],
	        :api_key        => config_json[CONST_PARSE::LABEL][CONST_PARSE::API_KEY]
	        
	        
book_count = Parse::Query.new("Book").tap do |q|
   q.limit = 0
   q.count = 1
end.get	  

if book_count["count"] > 0
	GROUPING = 10
	skip = 0
	done = false
	while !done
		
		book_list = Parse::Query.new("Book").tap do |q|
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
		puts asin_args
		harvestAmazonData(asin_args, bookHash, shouldSaveToParse) if asin_args.length > 0
		done = true if skip >= book_count["count"]
	end
end