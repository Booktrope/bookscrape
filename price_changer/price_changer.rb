require 'trollop'
require 'mailgun'
require 'time'
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

#Parse.init :application_id => $BT_CONSTANTS[:parse_application_id],
#	        :api_key        => $BT_CONSTANTS[:parse_api_key]

Parse.init :application_id => "RIaidI3C8TOI7h6e3HwEItxYGs9RLXxhO0xdkdM6",
	        :api_key        => "EQVJvWgCKVp4zCc695szDDwyU5lWcO3ssEJzspxd"

def amazon_change_prices(change_hash)
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
			changeling["status"] = 25
			changeling.save
			
			edit_page_url = changeling["book"]["kdpUrl"]
			if edit_page_url.nil? || edit_page_url == ""
				edit_page_url = lookup_book_edit_page_url(change_hash, changeling["book"]["asin"])
			end
			next if edit_page_url.nil? || edit_page_url == "" #TODO log an error here
			
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
				#Watir_harness.browser.button(:css, "span#title-setup-step2-submit input.a-button-input").click
				
				sleep(15.0)
				#Watir_harness.button(:class, "a-button-input").wait_until_present
				changeling["status"] = 50
				changeling.save
				#back_to_shelf = Watir_harness.button(:class, "a-button-input").click
				
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
			
			if book.div(:class, "asinText").present? > 0
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
		if browser.link(:xpath, "//a[contains(@href, '#next')]").present? > 0
			browser.link(:xpath, "//a[contains(@href, '#next')]").click
			Watir_harness.browser.tr(:class, "mt-row").wait_until_present
		else
			done = true 
		end
		i = i + 1
	end
	return result
end

def nook_change_prices(change_hash)

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

		#nook_lookup_book_edit_page_url change_hash

	})
end

def nook_lookup_book_edit_page_url(change_hash)
	done = false
		
	nook_url_list = Array.new
	while(!done)		

		Watir_harness.browser.table(:class, "project-list").wait_until_present 

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
		puts "#{nook_id}\t#{epub_isbn}\t#{nook_url}"
		sleep(5.0)
	end
end

def apple_change_prices(change_hash)
	class_name = "Price_Changer::iTunesConnect_Changer"
	results = Watir_harness.run($should_run_headless, class_name, lambda { | log |
	
		url = $BT_CONSTANTS[:itunes_connect_url]
		
		Watir_harness.browser.goto url
		
		Watir_harness.browser.text_field(:id, "accountname").set($BT_CONSTANTS[:itunes_connect_username])
		Watir_harness.browser.text_field(:id, "accountpassword").set($BT_CONSTANTS[:itunes_connect_password])
		Watir_harness.browser.button(:class, "sign-in").click

		
		Watir_harness.browser.link(:text, "Manage Your Books").click
		
		change_hash.each do | key, changeling |
			apple_id_input = Watir_harness.browser.td(:id, "search-param-value-appleId").text_field.set(changeling["book"]["appleId"])

			log.info "Searching for: #{changeling["book"]["appleId"]}"			
			Watir_harness.browser.div(:id, "titleSearch").td(:class, "searchfield").button.click
			Watir_harness.browser.div(:class, "resultList").link.click
			sleep(5.0)
			
			#Opening up the rights and pricing page
			Watir_harness.browser.link(:text, "Rights and Pricing").click
			
			#Clicking on the Edit Existing Territories button and setting the base currency to US Dollars
			Watir_harness.browser.span(:id, "lcBoxWrapperHeaderUpdateContainer").span(:class, "wrapper-topright-button").link.click
			Watir_harness.browser.td(:id, "baseCurr").select_list.option(:text => "USD - US Dollar").select
			sleep(10.0)
			
			#setting our new price
			Watir_harness.browser.span(:id, "InputContainer").span(:class, "price-field").text_field.set changeling["price"]
			log.info "setting the price at $#{changeling["price"]}"
			
			#setting the start date today via the javascript button
			Watir_harness.browser.text_field(:id, "startdate").when_present.click
			Watir_harness.browser.button(:class, "ui-datepicker-nonebtn").click
			
			#setting the end date to none via the javascript button
			Watir_harness.browser.text_field(:id, "enddate").when_present.click
			Watir_harness.browser.button(:class, "ui-datepicker-nonebtn").click
			
			#setting it for all territories.
			Watir_harness.browser.link(:text, "Select All").click
			#clicking the continue button
			Watir_harness.browser.span(:class, "wrapper-right-button").text_field.click
			
			sleep(5.0)
			#saving it
			#Watir_harness.browser.span(:class, "wrapper-right-button").text_field.click
		end
	})
end

def add_days(time, n_days)
  t2 = time + (n_days * 24 * 60 * 60)
  utc_delta = time.utc_offset - t2.utc_offset
  (utc_delta == 0) ? t2 : t2 + utc_delta
end

def sendEmail(change_hash)
	mailgun = Mailgun(:api_key => $BT_CONSTANTS[:mailgun_api_key], :domain => $BT_CONSTANTS[:mailgun_domain])
	top = "Prices Changed for #{Date.today} PST<br />\n<br />\n"
	email_parameters = {
		:to      => (!$opts.emailOverride.nil?) ? $opts.emailOverride : 'justin.jeffress@booktrope.com, andy@booktrope.com, heather.ludviksson@booktrope.com, Katherine Sears <ksears@booktrope.com>, Kenneth Shear <ken@booktrope.com>',
		:from    =>	'"Price Changer" <justin.jeffress@booktrope.com>',
		:subject => ($debug_parse_query) ? 'Price Changes (DEBUG changes not actually made)' : 'Price Changes',
		:html    => top + Mail_helper.alternating_table_body_for_hash_of_parse_objects(change_hash, :col_data => [ "asin" => {:object => "", :field => "asin"}, "Title" => {:object => "book", :field => "title"}, "Author" => {:object => "book", :field => "author"}, "Price" => {:object => "", :field => "price"}])
	}
	mailgun.messages.send_email(email_parameters)
end

changelings = Parse::Query.new("PriceChangeQueue").tap do |q|

   change_date = add_days(Time.now.utc, 1).to_s
   puts change_date
   change_date = Parse::Date.new(change_date)
	q.less_eq("changeDate", change_date)
	q.less_eq("status", 25)
	q.order_by ="changeDate"
	q.in_query("salesChannel", Parse::Query.new("SalesChannel").tap do | inner_query |
		inner_query.eq("name", "Apple")
	end)
	q.include = "book,salesChannel"
end.get

change_hash = Hash.new

changelings.each do | changeling |
	next if changeling["book"][changeling["salesChannel"]["controlField"]].nil?
	puts "#{changeling["changeDate"].value}\t#{changeling["book"][changeling["salesChannel"]["controlField"]]}\t#{changeling["status"]}\t#{changeling["book"]["title"]}\t#{changeling["book"]["author"]}\t#{changeling["price"]}"
	change_hash[changeling["book"][changeling["salesChannel"]["controlField"]]] = changeling
end

#nook_change_prices(change_hash) if change_hash.keys.size > 0 && !$debug_parse_query
#amazon_change_prices(change_hash) if change_hash.keys.size > 0 && !$debug_parse_query
#apple_change_prices(change_hash) if change_hash.keys.size > 0 && !$debug_parse_query
#sendEmail(change_hash) if !$opts.suppressMail && change_hash.length > 0

