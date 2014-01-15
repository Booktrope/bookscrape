
module Mail_helper
	def Mail_helper.alternating_table_body(results, options = {})
		body = "<table width=\"99%\" border=\"0\" cellpadding=\"1\" cellspacing=\"0\" bgcolor=\"#EAEAEA\">\n"
   	body = body + "   <tr>\n"
		body = body + "      <td>\n"
		body = body + "         <table width=\"100%\" border=\"0\" cellpadding=\"3\" cellspacing=\"0\" bgcolor=\"#FFFFFF\">\n"
		body = body + "            <tr>\n"
		body = body + "               <th align=\"left\">#</th>\n"
		options.keys.each do | key |
			body = body + "               <th align=\"left\">#{key}</th>\n"
		end
		body = body + "            </tr>\n"
		row_color = "#EAF2FA"
		i = 0
		results.each do | result |
			body = body + "            <tr bgcolor=\"#{row_color}\">\n"
			body = body + "               <td><font style=\"font-family: sans-serif; font-size:12px;\">#{i+1}</font></td>\n"
			options.values.each do | value |
					body = body + "               <td><font style=\"font-family: sans-serif; font-size:12px;\">#{result[value]}</font></td>\n"
			end
			body = body + "            </tr>\n"
			
			row_color = (i.even?) ? "#FFFFFF" : "#EAF2FA"
			i = i + 1
		end
		body = body + "         </table>\n"
		body = body + "      </td>\n"
		body = body + "   </tr>\n"
		body = body + "</table>\n"
		return body
	end
end