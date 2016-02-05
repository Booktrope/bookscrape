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
   version "1.0.0 2014 Justin Jeffress"

end

$debug_mode = ($opts.debug) ? true : false;
$debug_parse_query = ($debug_mode && $opts.parseQuery) ? true : false;

$should_run_headless = ($opts.headless) ?  true : false

$BT_CONSTANTS = Booktrope::Constants.instance

Booktrope::ParseHelper.init_production

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
      changeling["status"] = Booktrope::PRICE_CHANGE::ATTEMPTED
      changeling.save_perserve(["book","salesChannel"])

      edit_page_url = changeling["book"]["kdpUrl"]
      if edit_page_url.nil? || edit_page_url == ""
        edit_page_url = lookup_book_edit_page_url(change_hash, changeling["book"]["asin"])
      end

      if edit_page_url.nil? || edit_page_url == ""
        log.error "edit page url not found!"
        next
      end

      log.info "going to page #{edit_page_url}"
      Watir_harness.browser.goto(edit_page_url)
      sleep 3.0

      Watir_harness.browser.div(:xpath, "//div[@id='title-setup-step2']/div/div").wait_until_present

      if !Watir_harness.browser.div(:id, "title-setup-top-warning-alert").present?

        Watir_harness.browser.div(:xpath, "//div[@id='title-setup-step2']/div/div").click

        us_price = Watir_harness.browser.text_field(:id, "pricing-grid-US-price-input")
        us_price.clear
        us_price.send_keys changeling["price"]

        Watir_harness.browser.tr(:class, "pricing-grid-loading-cell").wait_while_present

        if changeling["price"] < 2.99 || changeling["price"] > 9.99
          #make sure 35% Royalty
          thirty_five_percent_royalty = Watir_harness.browser.radio(:xpath, "(//input[@name='royaltyPlan-radio'])[1]")
          if !thirty_five_percent_royalty.set?
            thirty_five_percent_royalty.set
          end
        else
          #make sure 70% Royalty
          seventy_percent_royalty = Watir_harness.browser.radio(:xpath, "(//input[@name='royaltyPlan-radio'])[2]")
          if  !seventy_percent_royalty.set?
            seventy_percent_royalty.set
          end
        end

        Watir_harness.browser.checkbox(:id, "title-setup-agreement").set

        # DON'T CLICK!! if you don't want to change the price.
        Watir_harness.browser.button(:css, "span#title-setup-step2-submit input.a-button-input").click

        sleep(35.0)
        Watir_harness.browser.button(:class, "a-button-input").wait_until_present
        changeling["status"] = Booktrope::PRICE_CHANGE::UNCONFIRMED
        changeling.save_perserve(["book","salesChannel"])
        Watir_harness.browser.button(:class, "a-button-input").click

      else
        log.error "Already Set"
      end
    end
  })
end

def lookup_book_edit_page_url(change_hash, current_asin)

  # setting the books per page to 50
  if Watir_harness.browser.span(:id, "bookshelftable-records-per-page-dropdown").span(:class, "a-dropdown-prompt").present?
    Watir_harness.browser.span(:id, "bookshelftable-records-per-page-dropdown").span(:class, "a-dropdown-prompt").click
    if Watir_harness.browser.link(:id, "dropdown1_2").present?
      Watir_harness.browser.link(:id, "dropdown1_2").click
      sleep(10.0)
    end
  end

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
          if change_hash[asin]["book"]["kdpUrl"] == "" || change_hash[asin]["book"]["kdpUrl"].nil?
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
      else # handling the new bookshelf html TODO: refactor this to be more elegant (once they make the html changes final the if above can be deleted.)
        book_id = book.id
        if book.span(:id, "zme-indie-bookshelf-digital-metadata-asin-#{book_id}").present?
          asin = book.span(:id, "zme-indie-bookshelf-digital-metadata-asin-#{book_id}").text.gsub(/ASIN: /, "")

          if change_hash.has_key? asin
            hash_count = hash_count + 1
            edit_page_url = "https://kdp.amazon.com/title-setup/#{book_id}"
            puts "#{asin}\t#{edit_page_url}"

            if change_hash[asin]["book"]["kdpUrl"] == "" || change_hash[asin]["book"]["kdpUrl"].nil?
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

def change_prices_for_apple(change_hash)
  class_name = "Price_Changer::iTunesConnect_Changer"
  results = Watir_harness.run($should_run_headless, class_name, lambda { | log |

    url = $BT_CONSTANTS[:itunes_connect_url]

    Watir_harness.browser.goto url

    Watir_harness.browser.iframe(:id, 'authFrame').text_field(:id, "appleId").wait_until_present

    Watir_harness.browser.iframe(:id, 'authFrame').text_field(:id, "appleId").set $BT_CONSTANTS[:itunes_connect_username]
    Watir_harness.browser.iframe(:id, 'authFrame').text_field(:id, "pwd").set $BT_CONSTANTS[:itunes_connect_password]

    Watir_harness.browser.iframe(:id, 'authFrame').button(:id, "sign-in").wait_until_present
    Watir_harness.browser.iframe(:id, 'authFrame').button(:id, "sign-in").click

    Watir_harness.browser.div(:id, "pageWrapper").wait_until_present
    Watir_harness.browser.div(:id, "pageWrapper").div(:class, "homepageWrapper").ul(:id, "main-nav").span(:text, "My Books").wait_until_present
    Watir_harness.browser.div(:id, "pageWrapper").div(:class, "homepageWrapper").ul(:id, "main-nav").span(:text, "My Books").click

    click_my_books_menu = lambda {
      Watir_harness.browser.link(:class, "menuopener").wait_until_present
      Watir_harness.browser.link(:class, "menuopener").click
      Watir_harness.browser.div(:id, "site-nav-wrapper").span(:text, "My Books").click
    }
    click_my_books_menu.call

    change_hash.each do | key, changeling |
      changeling["status"] = Booktrope::PRICE_CHANGE::ATTEMPTED
      changeling.save_perserve(["book","salesChannel"])

      search_lambda = lambda {
        Watir_harness.browser.td(:id, "search-param-value-appleId").wait_until_present
        Watir_harness.browser.td(:id, "search-param-value-appleId").text_field.set(changeling["book"]["appleId"])
        log.info "Searching for: #{changeling["book"]["appleId"]}"
        Watir_harness.browser.div(:id, "titleSearch").td(:class, "searchfield").button.click
      }

      search_lambda.call
      log.info 'foo'
      if Watir_harness.browser.image(:src, "https://itc.mzstatic.com/itc/images/icon_alert.jpg").present?
        log.info 'present'
        click_my_books_menu.call
        log.info 'clicked my books'
        search_lambda.call
      end

      Watir_harness.browser.div(:class, "resultList").link.click
      sleep(5.0)

      if !Watir_harness.browser.div(:id, "message-on-store-status-#{changeling["book"]["appleId"]}-publication").present?
        changeling["status"] = Booktrope::PRICE_CHANGE::NOT_ON_STORE
        changeling.save_perserve(["book","salesChannel"])
        next
      end

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
        #Watir_harness.browser.span(:class, "wrapper-right-button").text_field.click

        Watir_harness.browser.input(:id, "customBlueActionButton").click
        Watir_harness.browser.button(:id, "customBlueActionButton").wait_until_present
        Watir_harness.browser.button(:id, "customBlueActionButton").click

        changeling["status"] = Booktrope::PRICE_CHANGE::UNCONFIRMED
        changeling.save_perserve(["book","salesChannel"])
      else
        territory_hash = {"United States" => :usd, "Canada" => :cad, "United Kingdom" => :gbp, "Australia" => :aud}
        territory_hash.each do | country, currency |
          update_by_territory country, currency, changeling["price"], log
          #might need to add a #wait_until_present
        end
        changeling["status"] = Booktrope::PRICE_CHANGE::UNCONFIRMED
        changeling.save_perserve(["book","salesChannel"])
      end

      click_my_books_menu.call
    end
  })
end

def update_by_territory(country, currency, price, log)
  territories = Watir_harness.browser.div(:class, "resultList").table(:class => "main", :class => "content-status", :class => "vpp").trs
  territories.each do | territory |
    if country == territory.tds[0].text
      log.info country
      territory.tds[0].click
      sleep 5.0
      Watir_harness.browser.text_field(:id, "srpSubmit").wait_until_present
      Watir_harness.browser.text_field(:id, "srpSubmit").clear
      price = price.in(:usd).in(currency).to_s(:plain) if currency != :usd
      Watir_harness.browser.text_field(:id, "srpSubmit").set(price)

      log.info "set price to #{price}"
      #Watir_harness.browser.table(:xpath, "//div[@id='editPanel']/div/table").when_present.click
      Watir_harness.browser.text_field(:id, "srpSubmit").fire_event "onchange"
      log.info "fire event: onchange"

      size = Watir_harness.browser.select_list(:id, "pricingPopup").options.size
      log.info "number of options: #{size}"

      Watir_harness.browser.select_list(:id, "pricingPopup").options[size-1].select
      log.info "selected the last item"

      #Watir_harness.browser.select_list(:id, "pricingPopup").fire_event "onSuccess"
      Watir_harness.browser.span(:id, "TierUpdateContainer").click

      #setting the start date today via the javascript button
      Watir_harness.browser.text_field(:id, "startdate").when_present.fire_event "onfocus"
      Watir_harness.browser.button(:class, "ui-datepicker-nonebtn").wait_until_present
      Watir_harness.browser.button(:class, "ui-datepicker-nonebtn").click
      log.info "set the start date"

      #setting the end date to none via the javascript button
      Watir_harness.browser.text_field(:id, "enddate").when_present.fire_event "onfocus"
      Watir_harness.browser.button(:class, "ui-datepicker-nonebtn").wait_until_present
      Watir_harness.browser.button(:class, "ui-datepicker-nonebtn").click
      log.info "set the end date"

      Watir_harness.browser.img(:id, "lightboxSaveButtonEnabled").click
      sleep 5.0

      if Watir_harness.browser.div(:class => "lcAjaxLightboxMessages", :class => "error").present?
        size = Watir_harness.browser.select_list(:id, "pricingPopup").options.size
        log.info "number of options: #{size}"

        Watir_harness.browser.select_list(:id, "pricingPopup").options[size-1].select
        log.info "selected the last item"
        Watir_harness.browser.img(:id, "lightboxSaveButtonEnabled").click
        sleep 15.0
      end

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
  top = "The following books have had their prices changed for #{Date.today} PST<br />\n<br />\n"
  email_parameters = {
    :to      => (!$opts.emailOverride.nil?) ? $opts.emailOverride : 'justin.jeffress@booktrope.com, andy@booktrope.com, annelle.willard@booktrope.com, heather.ludviksson@booktrope.com, Katherine Sears <ksears@booktrope.com>, Kenneth Shear <ken@booktrope.com>',
    :from    => '"Price Changer" <justin.jeffress@booktrope.com>',
    :subject => ($opts.debug) ? 'Price Changes (DEBUG changes not actually made)' : 'Price Changes',
    :html    => top + body
  }
  #puts body
  mailgun.messages.send_email(email_parameters)
end

def get_change_hash_for(channel)

  change_date = Time.now.utc.to_s #add_days(Time.now.utc, 1).to_s
  puts change_date
  changelings = Parse::Query.new("PriceChangeQueue").tap do |q|
    q.less_eq("changeDate", Parse::Date.new(change_date))
    q.less_eq("status", Booktrope::PRICE_CHANGE::ATTEMPTED)
    q.order_by ="changeDate"
    q.in_query("salesChannel", Parse::Query.new("SalesChannel").tap do | inner_query |
      inner_query.eq("name", channel)
    end)
    q.include = "book,salesChannel"
  end.get

  change_hash = Hash.new

  changelings.each do | changeling |

    next if channel == Booktrope::PRICE_CHANGE::AMAZON_CHANNEL && ((changeling["isPriceIncrease"] || changeling["isEnd"]) && !is_complete_on_other_channels(changeling["book"], changeling["changeDate"]))
    next if changeling["book"][changeling["salesChannel"]["controlField"]].nil?
    puts "#{changeling["changeDate"].value}\t#{changeling["book"][changeling["salesChannel"]["controlField"]]}\t#{changeling["status"]}\t#{changeling["book"]["title"]}\t#{changeling["book"]["author"]}\t#{changeling["price"]}\t#{changeling["isEnd"]}"
    control_number = changeling["book"][changeling["salesChannel"]["controlField"]]

    puts "#{changeling.parse_object_id}\t#{changeling["changeDate"].value}\t#{DateTime.parse(change_date)}"

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
    when Booktrope::PRICE_CHANGE::AMAZON_CHANNEL
      puts "Amazon"
      change_prices_for_amazon(change_hash)
    when Booktrope::PRICE_CHANGE::APPLE_CHANNEL
      puts "Apple"
      change_prices_for_apple(change_hash)
   end
end

def is_complete_on_other_channels(book, date)

  result = false
  changinglings_on_other_channels = Parse::Query.new("PrefunkQueue").tap do | q |
    q.eq("book", book)
    q.eq("changeDate", date)
    q.not_eq("channelName", Booktrope::PRICE_CHANGE::AMAZON_CHANNEL)
    q.greater_eq("status", Booktrope::PRICE_CHANGE::CONFIRMED)
    q.count = 1
    q.limit = 0
  end.get

  changinglings_on_other_channels["count"]

  # there is only one other channel apple so we a count of 1
  result = true if changinglings_on_other_channels["count"] == 1

  return result
end

def display_books_in_change_hash(change_hash)
  puts "The following book(s) will be changed:"
  change_hash.each do | key, value |
    puts "#{key}\t#{value["book"]["title"]}"
  end
end

def convert_status_to_code(change_hash)
  change_hash.each do | key, value |
    case value["status"]
    when Booktrope::PRICE_CHANGE::SCHEDULED
      value["status_text"] = Booktrope::PRICE_CHANGE::SCHEDULED_TEXT
    when Booktrope::PRICE_CHANGE::ATTEMPTED
      value["status_text"] = Booktrope::PRICE_CHANGE::ATTEMPTED_TEXT
    when Booktrope::PRICE_CHANGE::UNCONFIRMED
      value["status_text"] = Booktrope::PRICE_CHANGE::UNCONFIRMED_TEXT
    when Booktrope::PRICE_CHANGE::CONFIRMED
      value["status_text"] = Booktrope::PRICE_CHANGE::CONFIRMED_TEXT
    when Booktrope::PRICE_CHANGE::NOT_ON_STORE
      value["status_text"] = Booktrope::PRICE_CHANGE::NOT_ON_STORE_TEXT
    when Booktrope::PRICE_CHANGE::META_ERROR
      value["status_text"] = Booktrope::PRICE_CHANGE::META_ERROR_TEXT
    end
  end
end

body = ""

[Booktrope::PRICE_CHANGE::AMAZON_CHANNEL, Booktrope::PRICE_CHANGE::APPLE_CHANNEL, ].each do | channel |
#[Booktrope::PRICE_CHANGE::APPLE_CHANNEL].each do | channel |
#[Booktrope::PRICE_CHANGE::AMAZON_CHANNEL].each do | channel |
  change_hash = get_change_hash_for channel
  display_books_in_change_hash(change_hash) if $debug_mode
  if change_hash.keys.size > 0 && !$debug_parse_query
    change_prices_for channel, change_hash
    convert_status_to_code change_hash
    body = body +"<h1>#{channel}</h1><br/>\n"+ Booktrope::MailHelper.alternating_table_body_for_hash_of_parse_objects(change_hash, :col_data => [ "asin" => {:object => "", :field => "asin"}, "Title" => {:object => "book", :field => "title"}, "Author" => {:object => "book", :field => "author"}, "Price" => {:object => "", :field => "price"}, "Status" => {:object => "", :field =>"status_text" }, "Status Code" => {:object => "", :field => "status"}])
  end
end

sendEmail(body) if !$opts.suppressMail && body.length > 0
