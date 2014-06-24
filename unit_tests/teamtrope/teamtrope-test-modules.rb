$Test_root = File.absolute_path(File.dirname(__FILE__))

# linking to custom modules
require File.join($Test_root, "..", "..", "booktrope-modules")

cwd = Pathname(__FILE__).dirname
$:.unshift(cwd.to_s) unless $:.include?(cwd.to_s) || $:.include?(cwd.expand_path.to_s)

require 'lib/test_util'