module Booktrope
	module MailHelper
	
		require 'mailgun'

		def MailHelper.send_report_email(report, subject, top, results, columns = {})

			$BT_CONSTANTS = Booktrope::Constants.instance

			sales_report = Parse::Query.new("SalesReport").tap do | q |
				q.eq("name", report)
				q.include = "report_subscriber"
			end.get

			email_to_field = ""
				sales_report.each_with_index do | sr, index |
				email_to_field << ", " if index != 0
				email_to_field << "#{sr["report_subscriber"]["name"]} <#{sr["report_subscriber"]["email"]}>"
			end

			mailgun = Mailgun(:api_key => $BT_CONSTANTS[:mailgun_api_key], :domain => $BT_CONSTANTS[:mailgun_domain])
			email_parameters = {
				:to      => email_to_field,
				:from    =>	'"Booktrope Daily Crawler 2.0" <justin.jeffress@booktrope.com>',
				:subject => subject,
				:html    => top + MailHelper.alternating_table_body(results.sort_by{|k| k[:daily_sales]}.reverse, columns)
			}

			mailgun.messages.send_email(email_parameters)
		end
		
		def MailHelper.alternating_table_body_for_hash_of_parse_objects(change_hash, options = {})
			options[:col_data] = [] if !options.has_key? :col_data
			body = "<table width=\"99%\" border=\"0\" cellpadding=\"1\" cellspacing=\"0\" bgcolor=\"#EAEAEA\">\n"
		  body = body + "   <tr>\n"
			body = body + "      <td>\n"
			body = body + "         <table width=\"100%\" border=\"0\" cellpadding=\"3\" cellspacing=\"0\" bgcolor=\"#FFFFFF\">\n"
			body = body + "            <tr>\n"
			body = body + "               <th align=\"left\">#</th>\n"
			options[:col_data].each do | key |
				key.each do | header, foo |
					body = body + "               <th align=\"left\">#{header}</th>\n"
				end
			end
			body = body + "            </tr>\n"
			row_color = "#EAF2FA"

			i = 0
			change_hash.each do | change_key, change_value |
				body = body + "            <tr bgcolor=\"#{row_color}\">\n"
				body = body + "               <td><font style=\"font-family: sans-serif; font-size:12px;\">#{i+1}</font></td>\n"
				options[:col_data].each do | hash_key |
					hash_key.each do | col_key, col_value |
						result = ""
						if(col_value[:object] != "")
							result = change_value[col_value[:object]][col_value[:field]]
						else
							result = change_value[col_value[:field]]
						end
						body = body + "               <td><font style=\"font-family: sans-serif; font-size:12px;\">#{result}</font></td>\n"
					end
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

		def MailHelper.alternating_table_body(results, options = {})
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
				body = body + "               <td width=\"#{100/options.count+1}%\"><font style=\"font-family: sans-serif; font-size:12px;\">#{i+1}</font></td>\n"
				index = 0
				options.each do | key, value |
					next if key == :total
					body = body + "               <td width=\"#{100/options.count+1}%\"><font style=\"font-family: sans-serif; font-size:12px;\">#{result[value]}</font></td>\n"
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

			if totals.length > 0
				body = body + "            <tr bgcolor=\"#{row_color}\">\n"
				body = body + "               <td width=\"#{100/options.count+1}%\"><font style=\"font-family: sans-serif; font-size:12px;\"><strong>Total:</strong></font></td>\n"
				row_map.each do | row |
					total = (!row.nil?) ? row : "&nbsp;"
					body = body + "               <td width=\"#{100/options.count+1}%\"><font style=\"font-family: sans-serif; font-size:12px;\">#{total}</font></td>\n"			
				end
				body = body + "            </tr>\n"
			end
		
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
end