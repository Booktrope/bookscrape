require 'nokogiri'
require 'parse-ruby-client'
require 'pp'

basePath = File.absolute_path(File.dirname(__FILE__))
# linking to custom modules
require File.join(basePath, "..", "ruby_modules", "constants")
require File.join(basePath, "..", "ruby_modules", "selenium_harness")

class_name = "Salesdata_Extraction::Createspace_reporter"
results = Selenium_harness.run(class_name, lambda { | log |

	results = Array.new
	BT_CONSTANTS = BTConstants.get_constants
	url = BT_CONSTANTS[:createspace_url]
	
	Selenium_harness.get(url)
	
	username_input = Selenium_harness.find_element(:id, "loginField")
	username_input.send_keys BT_CONSTANTS[:createspace_username]
	
	password_input = Selenium_harness.find_element(:id, "passwordField")
	password_input.send_keys BT_CONSTANTS[:createspace_password]
	
	login_button = Selenium_harness.find_element(:id, "login_button")
	login_button.click
	
	report_link = Selenium_harness.find_element(:link_text, "View Detailed Royalty Report")
	report_link.click
	
	royalty_by_channel = Selenium_harness.find_element(:link_text, "Royalty By Channel")
	royalty_by_channel.click
	
	#sleep(5.0)
	wait = Selenium::WebDriver::Wait.new(:timeout => 10)
	
	#wait.until { Selenium_harness.find_element(:id, "searchFormSection_edit") }
	#run_new_report_button = Selenium_harness.find_element(:id, "searchFormSection_edit")
	#pp run_new_report_button
	#puts run_new_report_button.attribute("value")
	#run_new_report_button.click
	
	wait.until { Selenium_harness.find_element(:id, "member_reports_dateoptions") }
	
	report_select = Selenium_harness.find_element(:id, "member_reports_dateoptions")
	report_options = report_select.find_elements(:tag_name, "option")	
	
	report_options.each do | option |
		option.click if option.attribute("value") == "TODAY"
	end
	
	advanced_expander = Selenium_harness.find_element(:id, "AdvancedExpander")
	advanced_expander.click
	
	show_isbn = Selenium_harness.find_element(:id, "member_reports_eancolumn")
	show_isbn.click
	
	show_asin = Selenium_harness.find_element(:id, "member_reports_asincolumn")
	show_asin.click
	
	run_report_button = Selenium_harness.find_element(:id, "searchFormSection_save")
	run_report_button.click
	
	wait.until { Selenium_harness.find_element(:css, "div#resultTable table tbody tr") }
	
	the_page_data = Nokogiri.parse(Selenium_harness.page_source)

	the_sales_table = the_page_data.css("div#resultTable table tbody tr")
	the_sales_table.each do | row |
		row_data = Hash.new
		row_data[:title] = row.children[0].text.strip
		row_data[:channel] = row.children[2].text.strip
		row_data[:isbn] = row.children[4].text.strip
		row_data[:asin] = row.children[6].text.strip
		row_data[:units_sold] = row.children[8].text.strip
		results.push row_data
	end
	
	return results
	
})
results.each do | result |
	puts "#{result[:title]}\t#{result[:channel]}\t#{result[:isbn]}\t#{result[:asin]}\t#{result[:units_sold]}\t"
end