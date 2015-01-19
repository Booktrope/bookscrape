require 'rjmetrics_client'
require 'pp'

basePath = File.absolute_path(File.dirname(__FILE__))
require File.join(basePath, '..', 'booktrope-modules')

BT_CONSTANTS = Booktrope::Constants.instance

Booktrope::ParseHelper.init_production

$rjClient = Booktrope::RJHelper.new "booktrope_parse", ["teamtropeId", "parseId"], true

def syncParseBooks(skip)

	book_list = Parse::Query.new("Book").tap do | q |
		q.count = 1
		q.limit = 100
		q.skip = skip
	end.get
	
	data = Array.new
	book_list["results"].each do | book |
	
		next if book["teamtropeId"].nil?
	
		book_hash = Hash.new
		book_hash["asin"]    = book["asin"]
		book_hash["appleId"] = book["appleId"]

		book_hash["title"] = book["title"]
		book_hash["author"] = book["author"]
		book_hash["publisher"] = book["publisher"]
		
		book_hash["bnid"] = book["bnid"]
		book_hash["epubIsbnItunes"] = book["epubIsbnItunes"]
		book_hash["epubIsbn"] = book["epubIsbn"]
		book_hash["hardbackIsbn"] = book["hardbackIsbn"]
		book_hash["paperbackIsbn"] = book["paperbackIsbn"]
		
		book_hash["createspaceIsbn"] = book["createspaceIsbn"]
		book_hash["lightningsourceIsbn"] = book["lightningsourceIsbn"]
		book_hash["teamtropeId"] = book["teamtropeId"]
		book_hash["metaCometId"] = book["metaCometId"]
		book_hash["parseId"] = book.parse_object_id
		
		book_hash["kdpUrl"] = book["kdpUrl"]
		book_hash["largeImageAmazon"] = book["large_image"]
		book_hash["detailUrlAmazon"] = book["detail_url"]
		book_hash["largeImageApple"] = book["largeImageApple"]
		book_hash["detailUrlApple"] = book["detailUrlApple"]
		book_hash["nookUrl"] = book["nookUrl"]
		book_hash["largeImageNook"] = book["largeImageNook"]
		book_hash["detailUrlNook"] = book["detailUrlNook"]
		
		book_hash["publicationDateAmazon"] = book["publicationDateAmazon"]
		book_hash["createdAt"] = book["createdAt"]
		book_hash["updatedAt"] = book["updatedAt"]

		$rjClient.add_object! book_hash
	end
	syncParseBooks(skip + 100) if book_list["results"].count == 100
end

skip = 0
syncParseBooks skip

$rjClient.pushData if $rjClient.data.count > 0