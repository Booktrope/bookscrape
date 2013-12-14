require 'nokogiri'

basePath = File.absolute_path(File.dirname(__FILE__))
# linking to custom modules
require File.join(basePath, "..", "..", "ruby_modules", "constants")
require File.join(basePath, "..", "..", "ruby_modules", "selenium_harness")

class_name = "Salesdata_Extraction::Amazon_reporter"
results = Selenium_harness.run(class_name, lambda {
	BT_CONSTANTS = BTConstants.get_constants
	url = BT_CONSTANTS[:amazon_kdp_url]
	
	Selenium_harness.get(url)
	
	sign_button = Selenium_harness.find_element(:id, "dtp_signin")
	sign_button.click
	
	username_input = Selenium_harness.find_element(:id, "ap_email")
	username_input.send_keys BT_CONSTANTS[:amazon_kdp_username]
	
	password_input = Selenium_harness.find_element(:id, "ap_password")
	password_input.send_keys BT_CONSTANTS[:amazon_kdp_password]
	
	login_button = Selenium_harness.find_element(:id, "signInSubmit-input")
	login_button.click
	
	report_link = Selenium_harness.find_element(:link_text, "Reports")
	report_link.click
	
	month_to_date_sales_link = Selenium_harness.find_element(:id, "mtdLink")
	month_to_date_sales_link.click
	
	sleep(5.0)
	
	country = "US"
	
	results = Array.new
	
	print_lambda = lambda { | extraction_array |
		report_page = Nokogiri.parse(Selenium_harness.page_source)
		promo_table_rows = report_page.css("table#promotionTransactionsReports tbody tr")
		promo_table_rows.each do | row |
			break if row.children.size < 9
			extraction_data = Hash.new
			extraction_data[:title]      = row.children[1].text
			extraction_data[:asin]       = row.children[2].text
			extraction_data[:net_sales]  = row.children[5].text
			extraction_data[:force_free] = row.children[8].text
			extraction_data[:country]    = country
			extraction_array.push(extraction_data)
		end
		return extraction_array
	}
	
	results.concat(print_lambda.call(Array.new))
			
	report_select = Selenium_harness.find_element(:id, "marketplaceSelect")
	report_options = report_select.find_elements(:tag_name, "option")
	report_options.each do | option |
		next if option.attribute("value") == "US"
		extraction_data = Hash.new
		country = option.attribute("value")
		
		option.click
		sleep(5.0)
		
		results.concat(print_lambda.call(Array.new))
	end
	return results
})
results.each do | result |
puts "#{result[:title]}\t#{result[:asin]}\t#{result[:net_sales]}\t#{result[:force_free]}\t#{result[:country]}"
end