require 'watir-webdriver'
require 'selenium-webdriver'
require 'twilio-ruby'
basePath = File.absolute_path(File.dirname(__FILE__))
require File.join(basePath, '..', 'booktrope-modules')


module Watir_harness
  @browser = nil
  @download_folder = ""

  def self.download_folder
    return @download_folder
  end

  def self.download_folder=(folder)
    @download_folder = folder
  end

  def self.browser
    return @browser
  end

  def self.find_element(type, label)
    return @browser.find_element(type, label)
  end

  def self.find_elements(type, label)
    return @browser.find_elements(type, label)
  end

  def self.page_source
    return @browser.page_source
  end

  def self.get(url)
    @browser.get(url)
  end

  def self.current_url
    return @browser.current_url
  end

  def self.setup(headless)
    #puts "SELENIUM_HARNESS::SETUP"
    profile = Selenium::WebDriver::Firefox::Profile.new
    if headless && RbConfig::CONFIG['host_os'].start_with?("darwin")
       Selenium::WebDriver::Firefox::Binary.path = "/opt/local/lib/firefox-x11/firefox-bin"
      profile['general.useragent.override'] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.9; rv:25.0) Gecko/20100101 Firefox/25.0"
    end

    client = Selenium::WebDriver::Remote::Http::Default.new
    client.timeout = 180 # seconds – default is 60

    #TODO: clean this up
    profile['browser.download.folderList'] = 2
    puts "folder: #{@download_folder}"
    profile['browser.download.dir'] = @download_folder
    profile["browser.download.manager.showWhenStarting"] = false
    profile["browser.helperApps.alwaysAsk.force"]= false
    profile['browser.helperApps.neverAsk.saveToDisk'] = "text/csv, application/a-gzip,application/gzip, application/x-gzip, application/x-gunzip, application/gzipped, application/gzip-compressed, application/x-compressed, application/x-compress, gzip/document, application/octet-stream"
    profile['pdfjs.disabled'] = true

    #puts "SELENIUM_HARNESS::SETUP #{Selenium::Webbrowser::Firefox::Binary.path}"

    @browser = Watir::Browser.new :firefox , profile: profile, http_client: client
    @browser.window.resize_to(1400,900)
  end

  def self.teardown
    #puts "SELENIUM_HARNESS::TEARDOWN"
    @browser.quit
  end

  def self.run(should_run_headless, className, code)
    results = nil
    headless_lambda = lambda { | className, code |
      self.setup should_run_headless
      results = nil
      begin
        log = Bt_logging.create_logging(className)
        if code.respond_to? "call"
          log.info "starting"
          results = code.call(log)
          log.info "ending"
        end
      rescue Exception => e
        log.error e.message
        lines = e.backtrace.map{ |x|
          x.match(/^(.+?):(\d+)(|:in `(.+)')$/);
          [$1,$2,$4]
        }
        lines.each do | line |
          log.error "%s,%s,%s" % [ line[0], line[1], line[2]]
        end

        account_sid = 'AC2980067718d40f28035f4bb858f9be6e'
        auth_token = 'e27948e87e55c31c0f2dee2586cd49c5'
        client = Twilio::REST::Client.new account_sid, auth_token
        client.account.messages.create(:from => '+18183348793',
        :to => '+13102924925',
        :body => "Script Failure #{className}")
        client = Twilio::REST::Client.new account_sid, auth_token
        client.account.messages.create(:from => '+18183348793',
        :to => '+18183085878',
        :body => "Script Failure #{className}")

         raise e
      ensure
        self.teardown
      end

      return results
    }

    if should_run_headless
      results = Headless_harness.run(className, code, headless_lambda)
    else
      results = headless_lambda.call(className, code)
    end
    return results
  end
end
