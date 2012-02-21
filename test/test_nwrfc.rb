# Author:: Martin Ceronio martin.ceronio@infosize.co.za
# Copyright:: Copyright (c) 2012 Martin Ceronio
# License:: MIT and/or Creative Commons Attribution-ShareAlike

require 'test/unit'
require 'rubygems'
require File.dirname(__FILE__)+'/../lib/nwrfc'
require 'yaml'

include NWRFC

$login_params = YAML.load_file(File.dirname(__FILE__) + "/login_params.yaml")["system1"]

class TestNWRFC < Test::Unit::TestCase
  def test_steps
    connection = Connection.new($login_params)
    assert connection.connection_info
    function = connection.get_function("STFC_STRUCTURE")
    assert function.parameter_count > 0
    connection.disconnect
  end

  # Test setting and getting different types of fields
  # TODO: Test RFCHEX3, other floating point types?
  def test_set_get
    connection = Connection.new($login_params)
    function = connection.get_function("STFC_STRUCTURE")
    function_call = function.get_function_call
    is = function_call[:IMPORTSTRUCT]
    is[:RFCFLOAT] = 10.9154
    assert_equal(10.9154, is[:RFCFLOAT], "RFCFLOAT not equal after assignment: ")
    is[:RFCCHAR1] = 'a'
    assert_equal('a', is[:RFCCHAR1], "RFCCHAR1 not equal after assignment")
    # Test Max INT2
    is[:RFCINT2] = 32767
    assert_equal(32767, is[:RFCINT2], "Positive RFCINT2 not equal after assignment")
    # Test Min INT2
    is[:RFCINT2] = -32767
    assert_equal(-32767, is[:RFCINT2], "Positive RFCINT2 not equal after assignment")
    # Test INT1
    is[:RFCINT1] = 255
    assert_equal(255, is[:RFCINT1], "RFCINT1 not equal after assignment")
    # Test Max INT4
    # Online ABAP help says Max. INT4 value is , but proven to be 2147483647 and min -2147483648
    is[:RFCINT4] = 2147483647
    assert_equal(2147483647, is[:RFCINT4], "Positive RFCINT4 not equal after assignment")
    # Test Min INT2
    is[:RFCINT4] = -2147483648
    assert_equal(-2147483648, is[:RFCINT4], "Negative RFCINT4 not equal after assignment")

    is[:RFCCHAR4] = 'abcd'
    assert_equal('abcd', is[:RFCCHAR4], "RFCCHAR4 not equal after assignment")
    is[:RFCCHAR4] = 'abcdef'
    assert_equal('abcd', is[:RFCCHAR4], "RFCCHAR4 (overlong) not equal after assignment")
    # RFCTIME from string
    t = Time.now
    is[:RFCTIME] = t.strftime("%H%M%S")
    rt = is[:RFCTIME]
    assert_equal(t.strftime("%H%M%S"), rt.strftime("%H%M%S"), "RFCTIME (string) not equal after assignment")
    # RFCTIME from Time object
    is[:RFCTIME] = t
    rt = is[:RFCTIME]
    assert_equal(t.strftime("%H%M%S"), rt.strftime("%H%M%S"), "RFCTIME (Time) not equal after assignment")
    # RFCDATE from string
    is[:RFCDATE] = t.strftime("%Y%m%d")
    rt = is[:RFCDATE]
    assert_equal(t.strftime("%Y%m%d"), rt.strftime("%Y%m%d"), "RFCDATE (string) not equal after assignment")
    # RFCDATE from Time Object
    is[:RFCDATE] = t
    rt = is[:RFCDATE]
    assert_equal(t.strftime("%Y%m%d"), rt.strftime("%Y%m%d"), "RFCDATE (string) not equal after assignment")
    # RFCDATE from Date Object
    t = Date.parse("2012-03-14")
    is[:RFCDATE] = t
    rt = is[:RFCDATE]
    assert_equal(t.strftime("%Y%m%d"), rt.strftime("%Y%m%d"), "RFCDATE (string) not equal after assignment")
    # RFCDATE from DateTime Object
    t = DateTime.now
    is[:RFCDATE] = t
    rt = is[:RFCDATE]
    assert_equal(t.strftime("%Y%m%d"), rt.strftime("%Y%m%d"), "RFCDATE (string) not equal after assignment")

    # Disconnect from system
    connection.disconnect
  end

  # Call function SCP_CHAR_ECHO
  def test_char_echo
    connection = Connection.new($login_params)
    function = connection.get_function("SCP_CHAR_ECHO")
    fc = function.get_function_call
    fc[:IMP] = "Wazzup"
    fc.invoke
    assert fc[:EXP] == fc[:IMP]
    connection.disconnect
  end

  def test_string_echo
    connection = Connection.new($login_params)
    function = connection.get_function("SCP_STRING_ECHO")
    fc = function.get_function_call
    # Test with long string
    fc[:IMP] = (1..1000).to_a.to_s
    fc.invoke
    assert fc[:EXP] == fc[:IMP]
    connection.disconnect
  end

  # Test creating functions without server definition
  def test_new_function
    function = Function.new("MY_FUNCTION")
    parameter = Parameter.new(:name => "MY_PARAM", :type => :RFCTYPE_CHAR, :length => 20, :direction=> :RFC_IMPORT)
    function.add_parameter(parameter)
    assert_equal(1, function.parameter_count)
  end

  # Test setting and getting string
  def test_string
    function = Function.new("MY_STRING")
    parameter = Parameter.new(:name => "RFC_STRING", :type => :RFCTYPE_STRING, :direction=> :RFC_IMPORT)
    function.add_parameter(parameter)
    fc = function.get_function_call
    fc[:RFC_STRING] = "Hello, how are you?"
    assert_equal("Hello, how are you?", fc[:RFC_STRING], "RFC_STRING")
  end

  # Test setting and getting xstring
  def test_xstring
    function = Function.new("MY_XSTRING")
    parameter = Parameter.new(:name => "RFC_XSTRING", :type => :RFCTYPE_XSTRING, :direction=> :RFC_IMPORT)
    function.add_parameter(parameter)
    fc = function.get_function_call
    fc[:RFC_XSTRING] = "Sequence of bytes"
    assert_equal("Sequence of bytes", fc[:RFC_XSTRING], "RFC_XSTRING")
  end

  # Test new types;
  def test_new_float_types
    skip "--- New types decfloat16 and decfloat34 not working yet ---"
    # Set up new function definition with parameters of the type we want to test
    function = Function.new("MY_FUNCTION")
    parameter = Parameter.new(:name => "DECF16", :type => :RFCTYPE_DECF16, :direction=> :RFC_IMPORT)
    function.add_parameter(parameter)
    parameter = Parameter.new(:name => "DECF34", :type => :RFCTYPE_DECF34, :direction=> :RFC_IMPORT)
    function.add_parameter(parameter)
    fc = function.get_function_call
    # Test DECF16
    fc[:DECF16] = 20.723623
    assert_equal(20.723623, fc[:DECF16], "DECF16")
    # Test DECF34
    fc[:DECF34] = 20.723623123
    assert_equal(20.723623123, fc[:DECF34], "DECF34")
  end

  def test_server
    skip "Skip for now"
    require 'ruby-debug'
    # Function to call
    function = Function.new("MY_STRING")
    parameter = Parameter.new(:name => "RFC_STRING", :type => :RFCTYPE_STRING, :direction=> :RFC_IMPORT)
    function.add_parameter(parameter)
    # Set up server
    server = Server.new({:gwhost => $login_params["ashost"], :program_id => "RUBYNWRFC"})
    # Run server
    server.serve(function) {|connection, func|
      debugger
      puts func
    }
  end

  # This test relies on the fact that you do not have a user 'Z_A_Z_AZ'
  # with password 'A@#1&ZA!' on the system you are testing with!
  def test_login_error
    begin
      lparams = $login_params.dup
      lparams["user"] = 'Z_A_Z_AZ'
      lparams["passwd"] = 'A@#1&ZA!'
      Connection.new(lparams)
      raise "Test failed. Do you have a user Z_A_Z_AZ with password A@#1&ZA!?"
    rescue NWError
      assert_equal(:RFC_LOGON_FAILURE, $!.code, "Error code")
      assert_equal(:LOGON_FAILURE, $!.group, "Error group")
      puts $!.inspect # Test the inspect method
    end
  end

end

