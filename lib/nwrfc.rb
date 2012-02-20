# Author:: Martin Ceronio martin.ceronio@infosize.co.za
# Copyright:: Copyright (c) 2012 Martin Ceronio
# License:: MIT and/or Creative Commons Attribution-ShareAlike
# SAP, Netweaver, RFC and other names referred to in this code
# are, or may be registered trademarks and the property of SAP, AG
# No ownership over any of these is asserted by Martin Ceronio

require File.dirname(__FILE__)+'/nwrfc/nwrfclib'
require File.dirname(__FILE__)+'/nwrfc/datacontainer'

require 'date'
require 'time'

# This library provides a way to call the functions of the SAP Netweaver RFC
# SDK, i.e. opening a connection to an ABAP system, calling functions etc., as
# well as running an RFC service
#---
# *TODO*: Create an error class that wraps the SAP error struct, so it can
# be raised and the caller can get all the information from there
#+++

module NWRFC

  NW_TIME_FORMAT = "%H%M%S"
  NW_DATE_FORMAT = "%Y%m%d"

  def inspect
    self.to_s
  end

  def NWRFC.get_version
    # See custom method FFI::Pointer#read_string_dn in nwrfclib.rb
    # http://stackoverflow.com/questions/9293307/ruby-ffi-ruby-1-8-reading-utf-16le-encoded-strings
    major = FFI::MemoryPointer.new(:uint)
    minor = FFI::MemoryPointer.new(:uint)
    patch = FFI::MemoryPointer.new(:uint)
    version = NWRFCLib.get_version(major, minor, patch)
    [version.read_string_dn.uC, major.read_uint, minor.read_uint, patch.read_uint]
  end

  def NWRFC.check_error(error_handle)
    raise "Error code #{error_handle[:code]} group #{error_handle[:group]} message #{error_handle[:message].get_str}" \
      if error_handle[:code] > 0
  end

  # Represents a connection to a SAP system that can be used to invoke
  # remote-enabled functions
  class Connection
    attr_reader :handle

    # Opens a connection to the SAP system with the given connection parameters
    # (described in the NW RFC SDK document), passed in the form of a Hash, e.g.
    #   Connection.new { 'ashost' :=> 'ajax.domain.com', ... }
    def initialize(conn_params)
      conn_params.untaint #For params loaded from file, e.g.
      raise "Connection parameters must be a Hash" unless conn_params.instance_of? Hash
      #NWRFCLib.init
      @cparams = NWRFCLib.make_conn_params(conn_params)
      raise "Could not create valid pointer from parameters" unless @cparams.instance_of? FFI::MemoryPointer
      #@errp = FFI::MemoryPointer.new(NWRFCLib::RFCError)
      @error =  NWRFCLib::RFCError.new #@errp
      @handle = NWRFCLib.open_connection(@cparams, conn_params.length, @error.to_ptr)
      NWRFC.check_error(@error)
      self
    end

    # Call the NW RFC SDK's RfcCloseConnection() function with the current
    # connection; this (should - *TODO* - check) invalidate the connection handle
    # and cause an error on any subsequent use of this connection
    def disconnect
      NWRFCLib.close_connection(@handle, @error.to_ptr)
      NWRFC.check_error(@error)
    end
    
    def get_function(function_name)
      Function.new(self, function_name)
    end

    # Return details about the current connection and the system
    def connection_info
      return @get_connection_attributes if @get_connection_attributes
      conn_info = NWRFCLib::RFCConnection.new
      rc = NWRFCLib.get_connection_attributes(@handle, conn_info.to_ptr, @error)
      NWRFC.check_error(@error) if rc > 0
      @get_connection_attributes = conn_info.members.inject({}) {|hash, member|
        hash[member] = conn_info[member].get_str #get_str, own definition in nwrfclib.rb, FFI::StructLayout::CharArray#get_str
        hash
      }
    end  

  end

  def NWRFC.abap_bool(value)
    return true if value == 'X'
    return false if value == ' '
    nil
  end

  def NWRFC.bool_abap(value)
    return 'X' if value == true
    return ' ' if value == false
    nil
  end

  # Represents a function parameter
  class Parameter

    attr_accessor :handle

    # Create a parameter by setting parameter attributes
    def initialize(*args)
      attr = args[0]
      @handle                 = NWRFCLib::RFCFuncParam.new
      @handle[:name]          = attr[:name].cU if attr[:name]
      @handle[:direction]     = NWRFCLib::RFC_DIRECTION[attr[:direction]] if attr[:direction]
      @handle[:type]          = NWRFCLib::RFC_TYPE[attr[:type]] if attr[:type]
      @handle[:ucLength]      = attr[:length] * 2 if attr[:length]
      @handle[:nucLength]     = attr[:length] if attr[:length]
      @handle[:decimals]      = attr[:decimals] if attr[:decimals]
      # TODO: Add support for type description
      #@handle[:typeDescHandle]
      @handle[:defaultValue]  = attr[:defaultValue].cU if attr[:defaultValue]
      @handle[:parameterText] = attr[:parameterText].cU if attr[:parameterText]
      @handle[:optional]      = abap_bool(attr[:optional]) if attr[:optional]
    end
  end

  class Type
    
  end

  # Represents a remote-enabled function module for RFC, can be instantiated either by the caller
  # or by calling Connection#get_function. This only represents the description of the function;
  # to call a function, an instance of a function call must be obtained with #get_function_call
  class Function
    attr_reader :desc, :connection, :function_name

    # Get a function module instance; can also be obtained by calling Connection#get_function
    # Takes either: (connection, function_name) or (function_name)
    # When passed only `function_name`, creates a new function description locally, instead of
    # fetching it form the server pointed to by connection
    def initialize(*args)#(connection, function_name)
      raise("Must initialize function with 1 or 2 arguments") if args.size != 1 && args.size != 2
      @error =  NWRFCLib::RFCError.new
      if args.size == 2
        @function_name = args[1] #function_name
        @desc = NWRFCLib.get_function_desc(args[0].handle, args[1].cU, @error.to_ptr)
        NWRFC.check_error(@error)
        @connection = args[0]
      else
        @function_name = args[0] #function_name
        @desc = NWRFCLib::create_function_desc(args[0].cU, @error)
        NWRFC.check_error(@error)
        @connection = nil
      end
    end

    def add_parameter(parameter)
      rc = NWRFCLib.add_parameter(@desc, parameter.handle, @error)
      NWRFC.check_error(@error) if rc > 0
    end

    # Create and return a callable instance of this function module
    def get_function_call
      FunctionCall.new(self)
    end

    # Get the number of parameters this function has
    def parameter_count
      pcount = FFI::MemoryPointer.new(:uint)
      rc = NWRFCLib.get_parameter_count(@desc, pcount, @error)
      NWRFC.check_error(@error) if rc > 0
      pcount.read_uint
    end

  end

  class FunctionCall < DataContainer
    attr_reader :handle, :desc, :connection, :function

    def initialize(function)
      @error = NWRFCLib::RFCError.new
      @function = function
      @connection = function.connection
      @handle = NWRFCLib.create_function(@function.desc, @error.to_ptr)
      @desc = function.desc
      NWRFC.check_error(@error)
    end

    def invoke
      rc = NWRFCLib.invoke(@connection.handle, @handle, @error.to_ptr)
      NWRFC.check_error(@error) if rc > 0
    end
  end


  class Table < DataContainer

    include Enumerable

    def each(&block)
      rc = NWRFCLib.move_to_first_row(@handle, @error)
      NWRFC.check_error(@error) if rc > 0
      size.times do |row|
        struct_handle = NWRFCLib.get_current_row(@handle, @error)
        NWRFC.check_error(@error)
        # CAVEAT: Other calls using the handle require "handle" field
        # of the RFC_DATA_CONTAINER struct
        yield Structure.new(struct_handle)
      end
    end

    def size
      rows = FFI::MemoryPointer.new(:uint)
      rc = NWRFCLib.get_row_count(@handle, rows, @error)
      rows.read_uint
    end

    # Delete all rows from (empty) the table
    def clear
      rc = delete_all_rows(@handle, @error)
      NWRFC.check_error(@error) if rc > 0
    end

    # Retrieve the row at the given index
    def [](index)
      rc = NWRFCLib.move_to(@handle, index, @error)
      NWRFC.check_error(@error) if rc > 0
      struct_handle = NWRFCLib.get_current_row(@handle, @error)
      NWRFC.check_error(@error)
      Structure.new(struct_handle)
    end

  end #class Table

  # Represents a structure. An instance is obtained internally by passing the
  # handle of a structure. A user can obtain an instance by invoking sub-field
  # access of a structure or a function
  class Structure < DataContainer

    # Return a list (array) of symbols representing the names of the fields
    # of this structure
    #---
    # TODO: This is not working!
    def fields
      fc = FFI::MemoryPointer.new(:uint)
      rc = NWRFCLib.get_field_count(@handle, fc, @error)
      NWRFC.check_error(@error) if rc > 0
      fc = fc.read_uint
      fd = NWRFCLib::RFCFieldDesc.new
      fields = []
      debugger
      fc.times do |index|
        rc = NWRFCLib.get_field_desc_by_index(@handle, index, fd.to_ptr, @error.to_ptr)
        NWRFC.check_error(@error) if rc > 0
        fields << fd[:name].get_str.to_sym
      end
    end
    
  end # class Structure

end #module NWRFC