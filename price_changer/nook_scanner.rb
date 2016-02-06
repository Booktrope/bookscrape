basePath = File.absolute_path(File.dirname(__FILE__))
require File.join(basePath, '..', 'booktrope-modules')

$BT_CONSTANTS = Booktrope::Constants.instance
Booktrope::ParseHelper.init_production


options = [Booktrope::Constraint.new(:exists, "bnid", true),
        Booktrope::Constraint.new(:exists, "nookUrl", false)]


not_mapped_books = Booktrope::ParseHelper.get_books_with_constraints(options)

mapped_hash = Hash.new
not_mapped_hash = Hash.new


mapped_options = [Booktrope::Constraint.new(:exists, "bnid", true),
          Booktrope::Constraint.new(:exists, "nookUrl", true)]

mapped_books = Booktrope::ParseHelper.get_books_with_constraints(mapped_options)

mapped_books.each_with_index do | mapped_book, index |
  mapped_hash[mapped_book["nookUrl"]] = 1
end

not_mapped_books.each_with_index do | not_mapped_book, index |
  not_mapped_hash[not_mapped_book["bnid"]] = not_mapped_book
end


class_name = "Price_Changer::NookScanner"
results = Watir_harness.run($should_run_headless, class_name, lambda { | log |
  url = $BT_CONSTANTS[:nookpress_url]

  nook_url_list = Array.new

  #requesting the page
  Watir_harness.browser.goto url

  #finding and clicking the login button
  Watir_harness.browser.link(:id, "clickclick").click

  #entering credentials
  Watir_harness.browser.text_field(:id, "email").set($BT_CONSTANTS[:nookpress_username])
  Watir_harness.browser.text_field(:id, "password").set($BT_CONSTANTS[:nookpress_password])

  #clicking on the login button
  Watir_harness.browser.button(:id, "login_button").click
  done = false
  while(!done)
    Watir_harness.browser.table(:class, "project-list").wait_until_present

    #navigating all of the index pages and collecting the url for each edit book url.
    nook_project_list = Watir_harness.browser.links(:css, "table.project-list tbody tr td.title a")
    nook_project_list.each do | nook_book |
      if !mapped_hash.has_key? nook_book.href
        nook_url_list.push nook_book.href
        log.info "added #{nook_book.href}"
      else
        #log.info "Skipped #{nook_book.href}"
      end
    end

    next_button = Watir_harness.browser.li(:class, "next_page")

    if next_button.class_name.include? "disabled"
      puts "done"
      done = true
    else
      puts "click next"
      next_button.link(:css, "a").click
    end
  end

  nook_url_list.each do | nook_url |
    Watir_harness.browser.goto(nook_url)

    nook_id = Watir_harness.browser.p(:css, "div.row div.project-body.columns p").text.strip.gsub(/B&N Identifier:/,"").gsub(/\s/,"")
    epub_isbn = ""

    Watir_harness.browser.link(:text, "Title & Description").click


    if Watir_harness.browser.radio(:id, "project_publish_settings_has_isbn_false").checked?
      nook_id = "missing: " + nook_id
    else
      epub_isbn = Watir_harness.browser.text_field(:id, "project_publish_settings_isbn").value
    end

    #TODO: track alerts and send an email
    log.info "#{nook_id}\t#{epub_isbn}\t#{nook_url}"

    if not_mapped_hash.has_key? nook_id
      log.info "match #{nook_id}"
      not_mapped_hash[nook_id]["nookUrl"] = nook_url
      not_mapped_hash[nook_id].save
    end
    sleep(5.0)
  end

})
