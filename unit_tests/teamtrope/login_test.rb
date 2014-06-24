require_relative "teamtrope-test-modules"
require 'test/unit'
require 'time'

Teamtrope_URL = "https://www.teamtrope.com"
DEV_teamtrope_URL = "http://tt.dev/wp-login.php?redirect_to=/"

class TestTeamtropeWorkFlow < Test::Unit::TestCase

   def test_login
      teamtrope_test = TeamtropeTest::TestHarness.new #[:firefox, :safari]
      teamtrope_test.run false, "login_test", lambda {
      	browser = teamtrope_test.watir_browser
         
         login teamtrope_test.watir_browser
         teamtrope_test.watir_browser.li(:id, "wp-admin-bar-new-content").link(:text, "New").wait_until_present
         assert_equal(true, teamtrope_test.watir_browser.li(:id, "wp-admin-bar-new-content").link(:text, "New").present?, "No admin bar")
         teamtrope_test.watir_browser.li(:id, "wp-admin-bar-new-content").link(:text, "New").hover
         sleep 3.0
         
         teamtrope_test.watir_browser.li(:id, "wp-admin-bar-new-projects").link.click
         teamtrope_test.watir_browser.text_field(:id, "title").set "Test Project #{Time.now}"
         teamtrope_test.watir_browser.text_field(:id, "acf-field-book_pcr_step").set "New Manuscript"
         teamtrope_test.watir_browser.select_list(:id, "acf-field-book_author").select 'Justin Jeffress'
         teamtrope_test.watir_browser.select_list(:id, "acf-field-book_genre").select 'Science Fiction'
         teamtrope_test.watir_browser.link(:id, "link-status").click
         teamtrope_test.watir_browser.p(:id, "tagcloud-status").wait_until_present
         teamtrope_test.watir_browser.link(:text, "Manuscript Development").click
         sleep 2.0
         
         assert_equal(true, teamtrope_test.watir_browser.p(:id, "tagcloud-status").link(:text, "Manuscript Development").present?, "tag not present")
         teamtrope_test.watir_browser.text_field(:id, "acf-field-book_pcr_step_cover_design").set "Submit PFS"
         teamtrope_test.watir_browser.text_field(:id, "acf-field-book_pcr_step_mkt_info").set "Upload Cover Concept"
         teamtrope_test.watir_browser.button(:id, "publish").click
         teamtrope_test.watir_browser.li(:id, "wp-admin-bar-view").link.click
         
         #insert test logic here
         browser.label(:text, "Project Interest").click
         browser.text_field(:id, "input_38_1_3").set "Justin"
         browser.text_field(:id, "input_38_1_6").set "Jeffress"
         browser.select_list(:id, "input_38_5").select "Book Manager"
         browser.textarea(:id, "input_38_6").set "I am the one who wrote the price changer."
         browser.button(:id, "gform_submit_button_38").click
         
         sleep 3
         
         assert_equal(true, browser.div(:id, "gform_confirmation_message_38").present?, "Project Interest: Confirmation message did not display.")
         
         browser.div(:id, "gform_confirmation_message_38").link(:text, "Refresh project page to continue.").wait_until_present
         assert_equal(true,browser.div(:id, "gform_confirmation_message_38").link(:text, "Refresh project page to continue.").present?, "Error submitting form.")
         
         submit_accept_team_member(browser, "Justin Jeffress", "Book Manager")
         assert_equal(false, browser.uls(:class, "needs").last.li(:class, "green").present?, "Accept Member Failed")         

         submit_accept_team_member(browser, "Justin Jeffress", "Project Manager")
         assert_equal(false, browser.uls(:class, "needs").last.li(:class, "yellow").present?, "Accept Member Failed")

         submit_accept_team_member(browser, "Justin Jeffress", "Cover Designer")
         assert_equal(false, browser.uls(:class, "needs").last.li(:class, "blue").present?, "Accept Member Failed")

         submit_accept_team_member(browser, "Justin Jeffress", "Proofreader")
         submit_accept_team_member(browser, "Justin Jeffress", "Editor")
         assert_equal(false, browser.uls(:class, "needs").last.li(:class, "red").present?, "Accept Member Failed")
         
         browser.label(:text, "Revenue Split").click
         
         browser.text_field(:id, "input_39_24").set "Justin Jeffress"
         browser.text_field(:id, "input_39_29").set "justin.jeffress@booktrope.com"
         
         browser.text_field(:id, "input_39_25").set "Justin Jeffress"
         browser.text_field(:id, "input_39_30").set "justin.jeffress@booktrope.com"
         
         browser.text_field(:id, "input_39_35").set "Justin Jeffress"
         browser.text_field(:id, "input_39_36").set "justin.jeffress@booktrope.com"
         
         browser.text_field(:id, "input_39_26").set "Justin Jeffress"
         browser.text_field(:id, "input_39_31").set "justin.jeffress@booktrope.com"
         
         browser.text_field(:id, "input_39_27").set "Justin Jeffress"
         browser.text_field(:id, "input_39_32").set "justin.jeffress@booktrope.com"
                  
         browser.text_field(:id, "input_39_28").set "Justin Jeffress"         
         browser.text_field(:id, "input_39_33").set "justin.jeffress@booktrope.com"
         
         browser.radio(:id, "choice_23_0").click
         browser.button(:id, "gform_submit_button_39").click
         
         browser.div(:id, "gform_confirmation_message_39").link(:text, "Refresh project page to continue.").wait_until_present
         assert_equal(true,browser.div(:id, "gform_confirmation_message_39").link(:text, "Refresh project page to continue.").present?, "Error submitting form.")
         browser.div(:id, "gform_confirmation_message_39").link(:text, "Refresh project page to continue.").click
         
         browser.label(:text, "Edit Complete Date").click
         
         browser.select_list(:id, "input_51_11_1").select "7"
         browser.select_list(:id, "input_51_11_2").select "7"
         browser.select_list(:id, "input_51_11_3").select "2014"
         
         browser.button(:id, "gform_submit_button_51").click
         browser.div(:id, "gform_confirmation_message_51").link(:text, "Refresh project page to continue.").wait_until_present
         assert_equal(true,browser.div(:id, "gform_confirmation_message_51").link(:text, "Refresh project page to continue.").present?, "Error submitting form.")
         
         browser.div(:id, "gform_confirmation_message_51").link(:text, "Refresh project page to continue.").click

         sleep 10.0
         
         #teamtrope_test.watir_browser.li(:id , "wp-admin-bar-edit").link.click
         #teamtrope_test.watir_browser.div(:id , "delete-action").link.click  
      }
   end
   
   def submit_accept_team_member(browser, username, job)
   
      browser.label(:text, "Accept Team Member").click
      browser.select_list(:id, "input_62_13").select username
      browser.select_list(:id, "input_62_5").select job
      browser.text_field(:id, "input_62_11").set "06/07/2020" if job == "Editor"      
      browser.button(:id, "gform_submit_button_62").click
      
      browser.div(:id, "gform_confirmation_message_62").link(:text, "Refresh project page to continue.").wait_until_present
      assert_equal(true,browser.div(:id, "gform_confirmation_message_62").link(:text, "Refresh project page to continue.").present?, "Error submitting form.")
      browser.div(:id, "gform_confirmation_message_62").link(:text, "Refresh project page to continue.").click   
   end
   
   def login(browser)
      browser.goto DEV_teamtrope_URL
      browser.text_field(:id, "user_login").set "justin"
      browser.text_field(:id, "user_pass").set "1b0oktr0pe2"
      browser.button(:id, "wp-submit").click
      assert_equal(true, browser.div(:id, "site-logo").link.present?, "failed to login correctly")
   end
end