module Mail_helper
	def Mail_helper.alternating_table_body(results, options = {})
		options[:total] = [] if !options.has_key? :total
		totals = populate_total_hash options[:total]
		body = "<table width=\"99%\" border=\"0\" cellpadding=\"1\" cellspacing=\"0\" bgcolor=\"#EAEAEA\">\n"
   	body = body + "   <tr>\n"
		body = body + "      <td>\n"
		body = body + "         <table width=\"100%\" border=\"0\" cellpadding=\"3\" cellspacing=\"0\" bgcolor=\"#FFFFFF\">\n"
		body = body + "            <tr>\n"
		body = body + "               <th align=\"left\">#</th>\n"
		options.each do | key, value |
			next if key == :total
			body = body + "               <th align=\"left\">#{key}</th>\n"
		end
		body = body + "            </tr>\n"
		row_color = "#EAF2FA"
		i = 0
		row_map = Array.new(options.count-1) #-1 since :totals does not appear in a separate column, they are mapped to a row.
		results.each do | result |
		
			body = body + "            <tr bgcolor=\"#{row_color}\">\n"
			body = body + "               <td><font style=\"font-family: sans-serif; font-size:12px;\">#{i+1}</font></td>\n"
			index = 0
			options.each do | key, value |
				next if key == :total
				body = body + "               <td><font style=\"font-family: sans-serif; font-size:12px;\">#{result[value]}</font></td>\n"
				if totals.has_key? value
					totals[value] = totals[value] + result[value].to_i
					row_map[index] = totals[value] 
				end
				index = index + 1
			end
			body = body + "            </tr>\n"
			row_color = (i.even?) ? "#FFFFFF" : "#EAF2FA"
			i = i + 1
		end

		body = body + "            <tr bgcolor=\"#{row_color}\">\n"
		body = body + "               <td><font style=\"font-family: sans-serif; font-size:12px;\"><strong>Total:</strong></font></td>\n"
		row_map.each do | row |
			total = (!row.nil?) ? row : "&nbsp;"
			body = body + "               <td><font style=\"font-family: sans-serif; font-size:12px;\">#{total}</font></td>\n"			
		end

		body = body + "            </tr>\n"
		
		body = body + "         </table>\n"
		body = body + "      </td>\n"
		body = body + "   </tr>\n"
		body = body + "</table>\n"
		return body
	end
	
	def self.populate_total_hash(totals)
		results = Hash.new
		totals.each do | total |
			results[total] = 0
		end
		return results
	end
end