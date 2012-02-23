require File.dirname(__FILE__)+'/../lib/nwrfc'
require 'yaml'

include NWRFC

$login_params = YAML.load_file(File.dirname(__FILE__) + "/login_params.yaml")["system1"]

# Create a new function
function = Function.new("MY_STRING")
# Create an inbound parameter of type string for the function
parameter = Parameter.new(:name => "RFC_STRING", :type => :RFCTYPE_STRING, :direction=> :RFC_IMPORT)
function.add_parameter(parameter)
# Set up server
server = Server.new({:gwhost => $login_params["ashost"], :program_id => "RUBYNWRFC"})
trap("SIGINT") { server.disconnect }
# Run server
server.serve(function) { |func|
  puts func[:RFC_STRING]
}