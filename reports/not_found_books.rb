require 'parse-ruby-client'
require 'mailgun'

$basePath   = File.absolute_path(File.dirname(__FILE__))
$config_dir = File.join($basePath, "config")

# linking to custom modules
require File.join($basePath, "..", "ruby_modules", "bt_logging")
require File.join($basePath, "..", "ruby_modules", "constants")
require File.join($basePath, "..", "ruby_modules", "mail_helper")

$BT_CONSTANTS = Booktrope::Constants.instance

Parse.init :application_id => $BT_CONSTANTS[:parse_application_id],
	        :api_key        => $BT_CONSTANTS[:parse_api_key]

def send_report_email(results)
	top = "The following books were not found for sale on the iTunes Store on #{Date.today} PST<br />\n<br />\n"
	mailgun = Mailgun(:api_key => $BT_CONSTANTS[:mailgun_api_key], :domain => $BT_CONSTANTS[:mailgun_domain])
	email_parameters = {
		:to      => 'justin.jeffress@booktrope.com, andy@booktrope.com', #, heather.ludviksson@booktrope.com, Katherine Sears <ksears@booktrope.com>, Kenneth Shear <ken@booktrope.com>',
		:from    =>	'"Booktrope iBooks Reporter 1.0" <justin.jeffress@booktrope.com>',
		:subject => 'Apple Analytics - Books Not Found',
		:html    => top + Mail_helper.alternating_table_body(results.sort_by{|k| k[:title] }, "Title" => :title, "Reason" => :reason, "asin" => :asin, "epub iTunes" => :epubIsbnItunes, "Apple ID" => :appleId)
	}

	mailgun.messages.send_email(email_parameters)
end

def clear_not_found_table(not_found)

	batch_max = 50
	loop_number = 0
	batch = Parse::Batch.new
	not_found.each do | book |
	
		if loop_number > 0 && loop_number % batch_max == 0
			batch.run!
			batch = Parse::Batch.new
		end
	
		batch.delete_object book
		loop_number = loop_number + 1
	end
	batch.run!
end

log = Bt_logging.create_logging('Reporter::Not_found')

apple_channel_query = Parse::Query.new("SalesChannel").tap do | q |
	q.eq("name", "Apple")
end

not_found = Parse::Query.new("NotFoundBooks").tap do | q |
	q.limit = 1000
	q.include = "book,salesChannel"
	q.in_query "salesChannel", apple_channel_query
end.get

mail_report_data = Array.new
not_found.each do | book |
	book_meta_hash = Hash.new
	book_meta_hash[:title] = book["book"]["title"]
	book_meta_hash[:asin] = book["book"]["asin"]
	book_meta_hash[:epubIsbnItunes] = book["book"]["epubIsbnItunes"]
	book_meta_hash[:appleId] = book["book"]["appleId"]
	book_meta_hash[:reason] = (book["reasonCode"] == -1) ? "SKIPPED: NO CONTROL NUMBERS" : "NOT FOUND"
	mail_report_data.push book_meta_hash
end

send_report_email mail_report_data
clear_not_found_table not_found