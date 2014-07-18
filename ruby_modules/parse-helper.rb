basePath = File.absolute_path(File.dirname(__FILE__))
require File.join(basePath, "parse-ruby-client-monkey")
module Booktrope
	class ParseHelper
		def ParseHelper.init(data = {})
			Parse.init(data)
		end
		
		def ParseHelper.get_books(data = {})
			
			skip_by = 1000
			skip = 0
			done = false			
			books = Array.new
			
			data[:exists] = [] if data[:exists].nil?

			while !done
				response = Parse::Query.new("Book").tap do | q |
					
					data[:exists].each do | field |
						q.exists(field)
					end
					q.count = 1
					q.limit = skip_by
					q.skip = skip	
				end.get
				books.concat response["results"]
				skip += skip_by
				done = true if skip >= response["count"]
			end
			
			return books
		end
		
	end
end