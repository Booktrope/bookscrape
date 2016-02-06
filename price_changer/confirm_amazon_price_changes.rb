# encoding: utf-8
require "nokogiri"
require 'open-uri'
require "trollop"
require 'json'
require 'time'
require 'pp'

basePath = File.absolute_path(File.dirname(__FILE__))
require File.join(basePath, '..', 'booktrope-modules')

Booktrope::ParseHelper.init_production

changelings = Parse::Query.new("PriceChangeQueue").tap do |q|
  q.limit = 1000
  q.eq("status", 50)
  q.eq("channelName", "Amazon")
end.get

# also consider the prefunk queue.
changelings.concat(
  Parse::Query.new("PrefunkQueue").tap do | q |
    q.limit = 1000
    q.eq("status", Booktrope::PRICE_CHANGE::UNCONFIRMED)
    q.eq("channelName", "Amazon")
  end.get
)

changelings.each do | changeling |
  next if changeling['asin'].nil? or changeling['asin'] == ""
  puts changeling["asin"]
  book_url = "http://amzn.com/#{changeling['asin']}"

  kindle_price = nil
  asin = changeling['asin']

  begin
    temp_html_file = open(book_url)
  rescue
    next
  end

  data = Nokogiri::HTML(temp_html_file)

  if data.at_css("tbody#kindle_meta_binding_winner")
    if !data.at_css("tbody#kindle_meta_binding_winner tr#tmm_"<< asin <<" td.price").nil?
      kindle_price = data.at_css("tbody#kindle_meta_binding_winner tr#tmm_"<< asin <<" td.price").text.strip.gsub(/\n.*/, "").tr('$','')
    end
  elsif temp_price_matches = data.at_css("tr.kindle-price").text.strip.gsub(/\n/, "").match(/Kindle Price:.*?([0-9]+\.[0-9]+)/)
    kindle_price = temp_price_matches.captures.first
  else
    kindle_prices = data.xpath("//td[@class='productBlockLabel']")
    kindle_prices.each do |item|
      if item.text.strip == "Kindle Price:"
        if item.next.next
          kindle_price = item.next.next.text.strip.tr("$","")
        end
      end
    end
  end

  unless kindle_price.nil?
    if kindle_price.to_f == changeling['price']
      changeling['status'] = Booktrope::PRICE_CHANGE::CONFIRMED
      changeling.save
      sleep 1.0
    end
  end

end
