$Booktrope_root = File.absolute_path(File.dirname(__FILE__))

# linking to custom modules
require File.join($Booktrope_root, "ruby_modules", "bt_logging")
require File.join($Booktrope_root, "ruby_modules", "bt-constants")
require File.join($Booktrope_root, "ruby_modules", "download_simple")
require File.join($Booktrope_root, "ruby_modules", "headless_harness")
require File.join($Booktrope_root, "ruby_modules", "mail_helper")
require File.join($Booktrope_root, "ruby_modules", "selenium_harness")
require File.join($Booktrope_root, "ruby_modules", "rj-helper")
require File.join($Booktrope_root, "ruby_modules", "parse-ruby-client-monkey")
require File.join($Booktrope_root, "ruby_modules", "watir_harness")