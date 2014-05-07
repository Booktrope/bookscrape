$basePath = File.absolute_path(File.dirname(__FILE__))

# linking to custom modules
require File.join($basePath, "ruby_modules", "bt_logging")
require File.join($basePath, "ruby_modules", "constants")
require File.join($basePath, "ruby_modules", "download_simple")
require File.join($basePath, "ruby_modules", "headless_harness")
require File.join($basePath, "ruby_modules", "mail_helper")
require File.join($basePath, "ruby_modules", "selenium_harness")
require File.join($basePath, "ruby_modules", "parse-ruby-client-monkey")
require File.join($basePath, "ruby_modules", "watir_harness")
