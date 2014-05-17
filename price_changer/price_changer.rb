require 'trollop'
require 'mailgun'
require 'time'
require 'exchange'
require 'pp'

basePath = File.absolute_path(File.dirname(__FILE__))
require File.join(basePath, '..', 'booktrope-modules')

$opts = Trollop::options do

   banner <<-EOS
Changes prices of books across our various channels.

   Usage:
            ruby price_changer.rb [--debug [--parseQuery]] [--emailOverride email_address] [--suppressMail] [--headless]
   EOS

   opt :debug, "Turns on debugging mode", :short => 'd'
   opt :parseQuery, "Debugs the initial query for parse. (Stops after query and doesn't open the browser.)", :short => 'q'
   opt :suppressMail, "Suppresses the compeletion email", :short=> 's'
   opt :emailOverride, "Overrides the recipients of the email", :type => :string, :short => 'o'
   opt :headless, "Runs headless", :short => 'h'
   version "0.0.9 2014 Justin Jeffress"

end

$debug_mode = ($opts.debug) ? true : false;
$debug_parse_query = ($debug_mode && $opts.parseQuery) ? true : false;

$should_run_headless = ($opts.headless) ?  true : false

$BT_CONSTANTS = BTConstants.get_constants

Parse.init :application_id => $BT_CONSTANTS[:parse_application_id],
	        :api_key        => $BT_CONSTANTS[:parse_api_key]

def change_prices_for_amazon(change_hash)
	class_name = "Price_Changer::Amazon_KDP_Changer"
	results = Watir_harness.run($should_run_headless, class_name, lambda { | log |
		url = $BT_CONSTANTS[:amazon_kdp_url]
		
		Watir_harness.browser.goto url
		
		#logging in
		Watir_harness.browser.a(:class, "a-button-text").click
		Watir_harness.browser.text_field(:id, "ap_email").set($BT_CONSTANTS[:amazon_kdp_username])
		Watir_harness.browser.text_field(:id, "ap_password").set($BT_CONSTANTS[:amazon_kdp_password])
		Watir_harness.browser.button(:id, "signInSubmit-input").click
		
		#changing prices
		change_hash.each do | key, changeling |
			changeling["status"] = PRICE_CHANGE::ATTEMPTED
			changeling.save
			
			edit_page_url = changeling["book"]["kdpUrl"]
			if edit_page_url.nil? || edit_page_url == ""
				edit_page_url = lookup_book_edit_page_url(change_hash, changeling["book"]["asin"])
			end
			
			if edit_page_url.nil? || edit_page_url == ""
				log.error "edit page url not found!"
				next
			end
			
			Watir_harness.browser.goto(edit_page_url)
			Watir_harness.browser.div(:xpath, "//div[@id='title-setup-step2']/div/div").wait_until_present
			
			if !Watir_harness.browser.div(:id, "title-setup-top-warning-alert").present?
			
				Watir_harness.browser.div(:xpath, "//div[@id='title-setup-step2']/div/div").click
				
				us_price = Watir_harness.browser.text_field(:id, "pricing-grid-US-price-input")
				us_price.clear
				us_price.send_keys changeling["price"]
				
				sleep(10.0)
				
				if changeling["price"] < 2.99 || changeling["price"] > 9.99
					#make sure 35% Royalty
					thirty_five_percent_royalty = Watir_harness.browser.radio(:xpath, "(//input[@name='royaltyPlan'])[1]")
					if !thirty_five_percent_royalty.set?
						thirty_five_percent_royalty.set
					end
				else
					#make sure 70% Royalty
					seventy_percent_royalty = Watir_harness.browser.radio(:xpath, "(//input[@name='royaltyPlan'])[2]")
					if	!seventy_percent_royalty.set?
						seventy_percent_royalty.set
					end
				end
				
				Watir_harness.browser.checkbox(:id, "title-setup-agreement").set
				
				# DON'T CLICK!!
				Watir_harness.browser.button(:css, "span#title-setup-step2-submit input.a-button-input").click
				
				sleep(35.0)
				Watir_harness.browser.button(:class, "a-button-input").wait_until_present
				changeling["status"] = PRICE_CHANGE::UNCONFIRMED
				changeling.save
				Watir_harness.browser.button(:class, "a-button-input").click
				
			else
				log.error "Already Set"
			end
		end
	})
end

def lookup_book_edit_page_url(change_hash, current_asin)

	result = ""
	done = false
	i = 0
	hash_count = 0
	while(!done)
		puts "Page: #{i+1}"
		books = Watir_harness.browser.trs(:class, "mt-row")
		books.each do | book |
			
			if book.div(:class, "asinText").present? 
				asin = book.div(:class, "asinText").text.strip.gsub(/\(ASIN: /, "").gsub(/\)$/, "")
				
				if change_hash.has_key? asin
					hash_count = hash_count + 1					
					edit_page_url = book.link(:class => "a-link-normal", :class => "mt-link-content").href
					
					puts "#{asin}\t#{edit_page_url}"
					if change_hash[asin]["book"]["kdpUrl"] == "" || change_hash[asin]["book"]["kdpUrl"]
						change_hash[asin]["book"]["kdpUrl"] = edit_page_url
						puts "saving kdpUrl #{edit_page_url} for asin #{asin}"
						change_hash[asin]["book"].save
						sleep(1.0)
					end
					result = edit_page_url if asin == current_asin
					if hash_count == change_hash.length
						done = true
						break
					end
				end
				
			end
		end
		#break if change_hash.size <= 0
		if Watir_harness.browser.link(:xpath, "//a[contains(@href, '#next')]").present? 
			Watir_harness.browser.link(:xpath, "//a[contains(@href, '#next')]").click
			Watir_harness.browser.div(:class, "mt-loading-overlay").wait_while_present
			Watir_harness.browser.tr(:class, "mt-row").wait_until_present
		else
			done = true 
		end
		i = i + 1
	end
	return result
end

def change_prices_for_nook(change_hash)

	class_name = "Price_Changer::Nookpress_Changer"
	results = Watir_harness.run($should_run_headless, class_name, lambda { | log |
		url = $BT_CONSTANTS[:nookpress_url]
	
		#requesting the page
		Watir_harness.browser.goto url
	
		#finding and clicking the login button
		Watir_harness.browser.link(:id, "clickclick").click
	
		#entering credentials
		Watir_harness.browser.text_field(:id, "email").set($BT_CONSTANTS[:nookpress_username])
		Watir_harness.browser.text_field(:id, "password").set($BT_CONSTANTS[:nookpress_password])
	
		#clicking on the login button
		Watir_harness.browser.button(:id, "login_button").click

		change_hash.each do | key, changeling |
			changeling["status"] = PRICE_CHANGE::ATTEMPTED
			changeling.save
			
			edit_page_url = changeling["book"]["nookUrl"]
			
			if edit_page_url.nil? || edit_page_url == ""
				edit_page_url = nook_lookup_book_edit_page_url(change_hash, changeling["book"]["bnid"])
			end
			
			if edit_page_url.nil? || edit_page_url == ""
				log.error "edit page url not found"
				next
			end
			
			Watir_harness.browser.goto edit_page_url
			
			Watir_harness.browser.link(:text, "Rights & Pricing").click
			
			if Watir_harness.browser.div(:class => "alert-box", :class => "error").present?
				#browser.div(:class => "alert-box", :class => "error").text == "You have missing or invalid fields in your NOOK Book details. You must fix the appropriate fields before posting changes to the store."
				log.error "can't edit book due to missing or invalid fields."
				next 
			end
			Watir_harness.browser.text_field(:id, "prices_USD").clear
			Watir_harness.browser.text_field(:id, "prices_USD").send_keys changeling["price"]
			
			Watir_harness.browser.button(:id, "submit_publish_settings_button").wait_until_present			
			Watir_harness.browser.button(:id, "submit_publish_settings_button").click
			
			Watir_harness.browser.div(:class => "alert-box", :class => "warning", :class => "squeeze").wait_until_present
			Watir_harness.browser.div(:class => "alert-box", :class => "warning", :class => "squeeze").text.end_with? "Changes can take up to 24 hours to appear on the site."
			
			changeling["status"] = PRICE_CHANGE::UNCONFIRMED
			changeling.save
			sleep(1.0)
		end
	})
end

def nook_lookup_book_edit_page_url(change_hash, current_id)
	done = false
	result = ""
	nook_url_list = Array.new
	
	#loop until we've reached the last index page of books. 
	while(!done)
		Watir_harness.browser.table(:class, "project-list").wait_until_present
		
		#navigating all of the index pages and collecting the url for each edit book url.
		nook_project_list = Watir_harness.browser.links(:css, "table.project-list tbody tr td.title a")
			nook_project_list.each do | nook_book |
			nook_url_list.push nook_book.href
			puts nook_book.href
		end
			
		next_button = Watir_harness.browser.li(:class, "next_page")
		
		if next_button.class_name.include? "disabled"
			done = true
		else
			next_button.link(:css, "a").click
		end
	end
	
	#looking up the bnid and epub isbn for the book.
	nook_url_list.each do | nook_url |
		Watir_harness.browser.goto(nook_url)
		
		nook_id = Watir_harness.browser.p(:css, "div.row div.project-body.columns p").text.strip.gsub(/B&N Identifier:/,"").gsub(/\s/,"")
		epub_isbn = ""
		
		Watir_harness.browser.link(:text, "Title & Description").click
		if Watir_harness.browser.radio(:id, "project_publish_settings_has_isbn_false").checked?
			nook_id = "missing: " + nook_id
		else
			epub_isbn = Watir_harness.browser.text_field(:id, "project_publish_settings_isbn").value
		end
		
		#TODO: track alerts and send an email 
		puts "#{nook_id}\t#{epub_isbn}\t#{nook_url}"
		
		if change_hash.has_key? nook_id
			puts "match #{nook_id}"
			change_hash[nook_id]["book"]["nookUrl"] = nook_url
			change_hash[nook_id]["book"].save
			result = nook_url if nook_id == current_id
		end
		sleep(5.0)
	end
	return result
end

def change_prices_for_apple(change_hash)
	class_name = "Price_Changer::iTunesConnect_Changer"
	results = Watir_harness.run($should_run_headless, class_name, lambda { | log |
	
		url = $BT_CONSTANTS[:itunes_connect_url]
		
		Watir_harness.browser.goto url
		
		Watir_harness.browser.text_field(:id, "accountname").set($BT_CONSTANTS[:itunes_connect_username])
		Watir_harness.browser.text_field(:id, "accountpassword").set($BT_CONSTANTS[:itunes_connect_password])
		Watir_harness.browser.button(:class, "sign-in").click

		Watir_harness.browser.link(:text, "Manage Your Books").click
		
		change_hash.each do | key, changeling |
			changeling["status"] = PRICE_CHANGE::ATTEMPTED
			changeling.save
			
			apple_id_input = Watir_harness.browser.td(:id, "search-param-value-appleId").text_field.set(changeling["book"]["appleId"])

			log.info "Searching for: #{changeling["book"]["appleId"]}"			
			Watir_harness.browser.div(:id, "titleSearch").td(:class, "searchfield").button.click
			Watir_harness.browser.div(:class, "resultList").link.click
			sleep(5.0)
			
			#Opening up the rights and pricing page
			Watir_harness.browser.link(:text, "Rights and Pricing").click
			
			
			if !changeling["isPriceIncrease"]
				#Clicking on the Edit Existing Territories button and setting the base currency to US Dollars
				Watir_harness.browser.span(:id, "lcBoxWrapperHeaderUpdateContainer").span(:class, "wrapper-topright-button").link.click
				Watir_harness.browser.td(:id, "baseCurr").select_list.option(:text => "USD - US Dollar").select
				sleep(10.0)
			
				#setting our new price
				Watir_harness.browser.span(:id, "InputContainer").span(:class, "price-field").text_field.set changeling["price"]
				log.info "setting the price at $#{changeling["price"]}"
			
				#setting the start date today via the javascript button
				Watir_harness.browser.text_field(:id, "startdate").when_present.click
				Watir_harness.browser.button(:class, "ui-datepicker-nonebtn").wait_until_present
				Watir_harness.browser.button(:class, "ui-datepicker-nonebtn").click
			
				#setting the end date to none via the javascript button
				Watir_harness.browser.text_field(:id, "enddate").when_present.click
				Watir_harness.browser.button(:class, "ui-datepicker-nonebtn").wait_until_present			
				Watir_harness.browser.button(:class, "ui-datepicker-nonebtn").click
			
				#setting it for all territories.
				Watir_harness.browser.link(:text, "Select All").click
				#clicking the continue button
				Watir_harness.browser.span(:class, "wrapper-right-button").text_field.click
			
				sleep(5.0)
			
				Watir_harness.browser.span(:class, "wrapper-right-button").text_field.click
				Watir_harness.browser.button(:class, "doneActionButton").wait_until_present
				Watir_harness.browser.button(:class, "doneActionButton").click
			
				changeling["status"] = PRICE_CHANGE::UNCONFIRMED
				changeling.save
			else
				territory_hash = {"United States" => :usd, "Canada" => :cad, "United Kingdom" => :gbp, "Australia" => :aud}
				territory_hash.each do | country, currency |
					update_by_territory country, currency, changeling["price"], log
					#might need to add a #wait_until_present
				end
				changeling["status"] = PRICE_CHANGE::UNCONFIRMED
				changeling.save
			end
		end
	})
end

def update_by_territory(country, currency, price, log)
	territories = Watir_harness.browser.div(:class, "resultList").table(:class => "main", :class => "content-status", :class => "vpp").trs
	territories.each do | territory |
		if country == territory.tds[0].text
			territory.tds[0].click
						
			Watir_harness.browser.text_field(:xpath, "//div[@id='editPanel']/div/table/tbody/tr[2]/td[2]/input").wait_until_present
			Watir_harness.browser.text_field(:xpath, "//div[@id='editPanel']/div/table/tbody/tr[2]/td[2]/input").clear
			price = price.in(:usd).in(currency).to_s(:plain) if currency != :usd
			Watir_harness.browser.text_field(:xpath, "//div[@id='editPanel']/div/table/tbody/tr[2]/td[2]/input").set(price)
			
			log.info "set price to #{price}"
			Watir_harness.browser.table(:xpath, "//div[@id='editPanel']/div/table").click
			log.info "clicked on table"
					
			size = Watir_harness.browser.select_list(:id, "pricingPopup").options.size
			log.info "number of options: #{size}"
			
			Watir_harness.browser.select_list(:id, "pricingPopup").options[size-1].select
			log.info "select the last item"
			Watir_harness.browser.table(:xpath, "//div[@id='editPanel']/div/table").click
						
			#setting the start date today via the javascript button
			Watir_harness.browser.text_field(:id, "startdate").when_present.click
			Watir_harness.browser.button(:class, "ui-datepicker-nonebtn").wait_until_present
			Watir_harness.browser.button(:class, "ui-datepicker-nonebtn").click
			log.info "set the start date"
			
			#setting the end date to none via the javascript button
			Watir_harness.browser.text_field(:id, "enddate").when_present.click
			Watir_harness.browser.button(:class, "ui-datepicker-nonebtn").wait_until_present			
			Watir_harness.browser.button(:class, "ui-datepicker-nonebtn").click
			log.info "set the end date"
						
			Watir_harness.browser.button(:xpath, "//div[@id='editPanel']/div[3]/input[2]").click
			log.info "hit the save button"
			break
		end
	end
end

def add_days(time, n_days)
  t2 = time + (n_days * 24 * 60 * 60)
  utc_delta = time.utc_offset - t2.utc_offset
  (utc_delta == 0) ? t2 : t2 + utc_delta
end

def sendEmail(body)
	mailgun = Mailgun(:api_key => $BT_CONSTANTS[:mailgun_api_key], :domain => $BT_CONSTANTS[:mailgun_domain])
	top = "Prices Changed for #{Date.today} PST<br />\n<br />\n"
	email_parameters = {
		:to      => (!$opts.emailOverride.nil?) ? $opts.emailOverride : 'justin.jeffress@booktrope.com, andy@booktrope.com, kelsey@booktrope.com', #, heather.ludviksson@booktrope.com, Katherine Sears <ksears@booktrope.com>, Kenneth Shear <ken@booktrope.com>',
		:from    =>	'"Price Changer" <justin.jeffress@booktrope.com>',
		:subject => ($debug_parse_query) ? 'Price Changes (DEBUG changes not actually made)' : 'Price Changes',
		:html    => top + body
	}
	mailgun.messages.send_email(email_parameters)
end

def get_change_hash_for(channel)

	change_date = add_days(Time.now.utc, 1).to_s
	puts change_date
	changelings = Parse::Query.new("PriceChangeQueue").tap do |q|
		q.less_eq("changeDate", Parse::Date.new(change_date))
		q.less_eq("status", PRICE_CHANGE::ATTEMPTED)
		q.order_by ="changeDate"
		q.in_query("salesChannel", Parse::Query.new("SalesChannel").tap do | inner_query |
			inner_query.eq("name", channel)
		end)
		q.include = "book,salesChannel"
	end.get

	change_hash = Hash.new

	changelings.each do | changeling |
	
		next if channel == PRICE_CHANGE::AMAZON_CHANNEL && ((changeling["isPriceIncrease"] || changeling["isEnd"]) && !is_complete_on_other_channels(changeling["book"], changeling["changeDate"]))
		next if changeling["book"][changeling["salesChannel"]["controlField"]].nil?
		puts "#{changeling["changeDate"].value}\t#{changeling["book"][changeling["salesChannel"]["controlField"]]}\t#{changeling["status"]}\t#{changeling["book"]["title"]}\t#{changeling["book"]["author"]}\t#{changeling["price"]}\t#{changeling["isEnd"]}"
		control_number = changeling["book"][changeling["salesChannel"]["controlField"]]
	
		puts "#{changeling["changeDate"].value}\t#{DateTime.parse(change_date)}"
		
		if changeling["isEnd"] && (changeling["changeDate"].value <= DateTime.parse(Time.now.utc.to_s))
			change_hash[control_number] = (!change_hash.has_key? control_number || changeling["changeDate"].value < change_hash[control_number]["changeDate"].value) ? changeling : change_hash[control_number]
		elsif !changeling["isEnd"] && changeling["changeDate"].value <= DateTime.parse(change_date)
			#If for some reason there are multiple change requests within our span, we want the most recent change.
			#For example if we run a one day promo, we may get both items from the queue, so we only want to do 
			#one of price changes.
			#TODO: 2.0 feature prevent a new price change from being inserted within an existing price change span.
			change_hash[control_number] = (!change_hash.has_key? control_number || changeling["changeDate"].value < change_hash[control_number]["changeDate"].value) ? changeling : change_hash[control_number]
		end
	end
	return change_hash
end

def change_prices_for(channel, change_hash)
	 case channel
	 	when PRICE_CHANGE::AMAZON_CHANNEL
	 		puts "Amazon"
	 		change_prices_for_amazon(change_hash)
	 	when PRICE_CHANGE::APPLE_CHANNEL
	 		puts "Apple"
	 		change_prices_for_apple(change_hash)
	 	when PRICE_CHANGE::NOOK_CHANNEL
	 		puts "Nook"
	 		change_prices_for_nook(change_hash)
	 end
end

def is_complete_on_other_channels(book, date)
	result = false
	changinglings_on_other_channels = Parse::Query.new("PriceChangeQueue").tap do | q |
		q.eq("book", book)
		q.eq("changeDate", date)
		q.not_eq("channelName", AMAZON_CHANNEL)
		q.eq("status", PRICE_CHANGE::CONFIRMED)
		q.count = 1
		q.limit = 0
	end.get
	
	#TODO: if more channels are added we should really execute another query to get how many 
	#channels there are besides amazon.
	result = true if changinglings_on_other_channels["count"] == 2
	
	return result
end

def display_books_in_change_hash(change_hash)
	puts "The following book(s) will be changed:"
	change_hash.each do | key, value |
		puts "#{key}\t#{value["book"]["title"]}"
	end
end

body = ""

[PRICE_CHANGE::AMAZON_CHANNEL, PRICE_CHANGE::APPLE_CHANNEL, PRICE_CHANGE::NOOK_CHANNEL].each do | channel |
#[PRICE_CHANGE::AMAZON_CHANNEL].each do | channel |
#[PRICE_CHANGE::APPLE_CHANNEL, PRICE_CHANGE::NOOK_CHANNEL].each do | channel |
	change_hash = get_change_hash_for channel
	display_books_in_change_hash(change_hash) if $debug_mode
	if change_hash.keys.size > 0 && !$debug_parse_query
		change_prices_for channel, change_hash
		body = body +"<h1>#{channel}</h1><br/>\n"+ Mail_helper.alternating_table_body_for_hash_of_parse_objects(change_hash, :col_data => [ "asin" => {:object => "", :field => "asin"}, "Title" => {:object => "book", :field => "title"}, "Author" => {:object => "book", :field => "author"}, "Price" => {:object => "", :field => "price"}, "Status" => {:object => "", :field => "status"}])
	end
end

sendEmail(body) if !$opts.suppressMail && body.length > 0