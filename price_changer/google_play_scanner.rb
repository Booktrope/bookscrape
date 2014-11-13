basePath = File.absolute_path(File.dirname(__FILE__))
# linking to custom modules
require File.join(basePath, '..', 'booktrope-modules')
require 'watir-scroll'
require 'trollop'


$opts = Trollop::options do

   banner <<-EOS
Adds the googlePlayUrl for editing books to its book record in parse.com

   Usage:
            ruby google_play_scanner.rb [--dontSaveToParse]
   EOS
   
   opt :dontSaveToParse, "Prevents the collected data from being saved to parse.", :short => 'x'
	opt :headless, "Runs headless", :short => 'h'
   
   version "1.0.0 2014 Justin Jeffress"

end

should_run_headless = ($opts.headless) ? true : false

$BT_CONSTANTS = Booktrope::Constants.instance

$log = Bt_logging.create_logging('PriceChanger::GooglePlayScanner')

Booktrope::ParseHelper.init_production

$batch = Parse::Batch.new
$batch.max_requests = 50
		       
book_list = Booktrope::ParseHelper.get_books :exists => ["epubIsbnItunes"]

book_hash = Hash.new

book_list.each do | book |
	unless !book['googlePlayUrl'].nil?
		book_hash[book['epubIsbnItunes']] = book
	end
end
							       
should_run_headless = false
class_name = "PriceChanger::GooglePlayScanner"
Watir_harness.run(should_run_headless, class_name, lambda { | log | 
	browser = Watir_harness.browser
	
	browser.goto $BT_CONSTANTS[:google_play_url]
	
	if browser.link(:text, "Sign in").present?
		browser.link(:text, "Sign in").click
	end
	
	browser.text_field(:id, "Email").set  $BT_CONSTANTS[:google_play_username]
	browser.text_field(:id, "Passwd").set $BT_CONSTANTS[:google_play_password]
	browser.button(:id, "signIn").click
	
	browser.div(:id, "pfe-book-catalog").wait_until_present
	browser.div(:id, "pfe-book-catalog").click
	
	browser.tbody(:id, "pfe-book-catalog-list").wait_until_present
	scroll_height = browser.execute_script("return document.getElementById('pfe-book-catalog-list').getElementsByTagName('tr')[0].scrollHeight")
	size = browser.tbody(:id, "pfe-book-catalog-list").trs.count
	
	done = false
	
	while(!done)
		browser.scroll.to browser.tbody(:id, "pfe-book-catalog-list").trs.last
		sleep 2.0
		if size == browser.tbody(:id, "pfe-book-catalog-list").trs.count
			done = true
		end
		size = browser.tbody(:id, "pfe-book-catalog-list").trs.count
	end
	
	browser.tbody(:id, "pfe-book-catalog-list").trs.each do | row |
		google_play_url = row.tds[1].a.href
		epub_isbn = row.tds[3].text.gsub(/ E$/,"")
		title = row.tds[1].text
		
		if book_hash.has_key? epub_isbn
			$log.info "#{google_play_url}\t#{epub_isbn}\t#{title}"
			book_hash[epub_isbn]["googlePlayUrl"] = google_play_url
			$batch.update_object_run_when_full! book_hash[epub_isbn] if !$opts.dontSaveToParse
		end
		
	end
})

if $batch.requests.length > 0 && !$opts.dontSaveToParse
	$batch.run!
	$batch.requests.clear
end