require 'mailgun'

$basePath   = File.absolute_path(File.dirname(__FILE__))

# linking to custom modules
require File.join($basePath, '..', 'booktrope-modules')

$BT_CONSTANTS = Booktrope::Constants.instance

Booktrope::ParseHelper.init_production

def send_report_email(results)

  report = "not_found_report"
  top = "The following books were not found for sale on the iTunes Store on #{Date.today} PST<br />\n<br />\n"
  subject = 'Apple Analytics - Books Not Found'
  Booktrope::MailHelper.send_report_email(report, subject, top, results.sort_by{|k| k[:title] }, "Title" => :title, "Reason" => :reason, "asin" => :asin, "epub iTunes" => :epubIsbnItunes, "Apple ID" => :appleId)

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
log.info book["objectId"]
next if book["book"].nil?
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
