# Author:: Martin Ceronio martin.ceronio@infosize.co.za
# Copyright:: Copyright (c) 2012 Martin Ceronio
# License:: MIT and/or Creative Commons Attribution-ShareAlike

require 'test/unit'
require 'rubygems'
require File.dirname(__FILE__)+'/../lib/nwrfc'
require 'yaml'

include NWRFC

require 'ruby-debug'

$login_params = YAML.load_file(File.dirname(__FILE__) + "/login_params.yaml")["system3"]

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
end

