# encoding: utf-8

# [TTR-97] Scrape Secret Cravings for Books with 30 or more reviews
#
# This is both the class and the wrapper for an Amazon scrape for the publisher Secret Cravings.  In the future, this
# should be refactored so the wrapper can be stand-alone and we can specify the class for the scrape we want to perform
# and keep the SecretCraving class alone in its' own file.  I've already spent too much time on this particular task
# so I'm leaving additional refactor for later.  Hopefully what I've done so far will save a lot of time needed for the
# next "scrape" we need to do.
#
# @author Brian Ronald <brian.ronald@booktrope.com>

require "trollop"
# require 'json'
require './amazon_book_scrubber.rb'

basePath = File.absolute_path(File.dirname(__FILE__))
# linking to custom modules
require File.join(basePath, '..', 'booktrope-modules')

p = Trollop::Parser.new do
  version "1.0.0 2015 Brian Ronald"
  banner <<-EOS
Pulls data from an Amazon Advanced search and outputs it to a CSV file

   Usage:
            ruby secret_cravings.rb [-f output.csv]
  EOS

  opt :limit, 'Limit results to this value', :type => :integer, :short => 'l'
  opt :filename, 'The filename to output to.', :type => :string, :short => 'f' , :required => true
end
opts = Trollop::with_standard_exception_handling p do
  raise Trollop::HelpNeeded if ARGV.empty? # show help screen
  p.parse ARGV
end

# Secret Cravings specific book
class SecretCravings < AmazonBookScrubber
  AdvancedSearchArguments = {
      'field-publisher' => 'Secret Cravings'
  }

  ColumnDefinition = [
      :asin, :title, :author, :publication_date, :cover_art, :link, :rating, :num_reviews, :kindle_price, :paperback_price
  ]
end

client = Selenium::WebDriver::Remote::Http::Default.new
client.timeout = 180 # seconds – default is 60

browser = Watir::Browser.new :firefox, http_client: client

scraper = SecretCravings.new(browser)

if opts[:limit]
  scraper.max = opts[:limit]
end

scraper.filename = opts[:filename]
scraper.run
browser.quit
