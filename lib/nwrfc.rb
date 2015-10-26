# Author:: Martin Ceronio martin.ceronio@infosize.co.za
# Copyright:: Copyright (c) 2012 Martin Ceronio
# License:: MIT and/or Creative Commons Attribution-ShareAlike
# SAP, Netweaver, RFC and other names referred to in this code
# are, or may be registered trademarks and the property of SAP, AG
# No ownership over any of these is asserted by Martin Ceronio

require File.dirname(__FILE__)+'/nwrfc/nwrfclib'
require File.dirname(__FILE__)+'/nwrfc/datacontainer'
require File.dirname(__FILE__)+'/nwrfc/server'
require File.dirname(__FILE__)+'/nwrfc/nwerror'

require 'date'
require 'time'

# This library provides a way to call the functions of the SAP Netweaver RFC
# SDK, i.e. opening a connection to an ABAP system, calling functions etc., as
# well as running an RFC service

module NWRFC

  # ABAP Time Format ("HHMMSS")
  NW_TIME_FORMAT = "%H%M%S"
  # ABAP Date Format ("YYYYMMDD")
  NW_DATE_FORMAT = "%Y%m%d"

  def inspect
    self.to_s
  end

  # Return the version of the NW RFC SDK library
  def NWRFC.get_version
    # See custom method FFI::Pointer#read_string_dn in nwrfclib.rb
    # http://stackoverflow.com/questions/9293307/ruby-ffi-ruby-1-8-reading-utf-16le-encoded-strings
    major = FFI::MemoryPointer.new(:uint)
    minor = FFI::MemoryPointer.new(:uint)
    patch = FFI::MemoryPointer.new(:uint)
    version = NWRFCLib.get_version(major, minor, patch)
    [version.read_string_dn.uC, major.read_uint, minor.read_uint, patch.read_uint]
  end

  # Take Hash of connection parameters and returns FFI pointer to an array
  # for setting up a connection
  def NWRFC.make_conn_params(params) #https://github.com/ffi/ffi/wiki/Structs
    par = FFI::MemoryPointer.new(NWRFCLib::RFCConnParam, params.length)
    pars = params.length.times.collect do |i|
      NWRFCLib::RFCConnParam.new(par + i * NWRFCLib::RFCConnParam.size)
    end
    tpar = params.to_a
    params.length.times do |n|
      pars[n][:name] = FFI::MemoryPointer.from_string(tpar[n][0].to_s.cU)
      pars[n][:value] = FFI::MemoryPointer.from_string(tpar[n][1].to_s.cU)
    end
    par
  end

  # Check for an error using error handle (used internally)
  def NWRFC.check_error(error_handle)
    raise NWError, error_handle \
      if error_handle[:code] > 0
    #raise "Error code #{error_handle[:code]} group #{error_handle[:group]} message #{error_handle[:message].get_str}" \
      
  end

  # Represents a client connection to a SAP system that can be used to invoke
  # remote-enabled functions
  class Connection
    attr_reader :handle

    # Opens a connection to the SAP system with the given connection parameters
    # (described in the NW RFC SDK document), passed in the form of a Hash, e.g.
    #   Connection.new { 'ashost' :=> 'ajax.domain.com', ... }
    def initialize(conn_params)
      conn_params.untaint #For params loaded from file, e.g.
      raise "Connection parameters must be a Hash" unless conn_params.instance_of? Hash
      @cparams = NWRFC.make_conn_params(conn_params)
      raise "Could not create valid pointer from parameters" unless @cparams.instance_of? FFI::MemoryPointer
      @error =  NWRFCLib::RFCError.new
      @handle = NWRFCLib.open_connection(@cparams, conn_params.length, @error.to_ptr)
      NWRFC.check_error(@error)
      self
    end

    # Call the NW RFC SDK's RfcCloseConnection() function with the current
    # connection; this *should* invalidate the connection handle
    # and cause an error on any subsequent use of this connection
    #@todo Write test to check that handle is invalidated and causes subsequent calls to fail
    def disconnect
      NWRFCLib.close_connection(@handle, @error.to_ptr)
      NWRFC.check_error(@error)
    end

    # Get the description of a given function module from the system to which we are connected
    # @return [Function] function module description
    def get_function(function_name)
      Function.new(self, function_name)
    end

    # Return details about the current connection and the system
    # @return [Hash] information about the current connection
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

    alias :close :disconnect

    def start_transaction(queue_name = nil)
      @tid = FFI::MemoryPointer.new(:char, 50)
      rc = NWRFCLib.get_transaction_id(@handle, @tid, @error)
      NWRFC.check_error(@error) if rc > 0
      queue_name = FFI::MemoryPointer.from_string(queue_name.to_s.cU) if queue_name
      transaction_handle = NWRFCLib.create_transaction(@handle, @tid, queue_name, @error)
      NWRFC.check_error(@error)
      Transaction.new(transaction_handle)
    end

  end

  class Transaction
    attr_reader :handle

    def initialize(handle)
      @handle = handle
      @error =  NWRFCLib::RFCError.new
    end

    def commit
      rc = NWRFCLib.submit_transaction(@handle, @error)
      NWRFC.check_error(@error) if rc > 0
      rc = NWRFCLib.confirm_transaction(@handle, @error)
      NWRFC.check_error(@error) if rc > 0
      rc = NWRFCLib.destroy_transaction(@handle, @error)
      NWRFC.check_error(@error) if rc > 0
    end

    alias :submit :commit

  end

  # Converts ABAP true/false into Ruby true/false
  # @return True for 'X', False for ' ' or nil otherwise
  def NWRFC.abap_bool(value)
    return true if value == 'X'
    return false if value == ' '
    nil
  end

  # Converts Ruby true/false into ABAP true/false
  # @return 'X' for true,, ' ' for false or nil otherwise
  def NWRFC.bool_abap(value)
    return 'X' if value == true
    return ' ' if value == false
    nil
  end

  # Represents the metadata of a function parameter
  class Parameter

    attr_accessor :handle

    # Create a parameter by setting parameter attributes
    #@todo For certain types, e.g. :RFCTYPE_BCD, a length specification is
    #  required, otherwise a segfault is the result later down the line.
    #  Find and implement all the types where this is required
    def initialize(*args)  

      attr = args[0]
      


      raise "RFCTYPE_BCD requires a length" if attr[:type] == :RFCTYPE_BCD && !(attr[:length])

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
    attr_reader :desc, :function_name
    attr_accessor :connection

    # Get a function module instance; can also be obtained by calling Connection#get_function
    # Takes either: (connection, function_name) or (function_name)
    # When passed only `function_name`, creates a new function description locally, instead of
    # fetching it form the server pointed to by connection
    #@overload new(connection, function_name)
    #   Fetches a function definition from the server pointed to by the connection
    #   @param [Connection] connection Connection to SAP ABAP system
    #   @param [String] function_name Name of the function module on the connected system
    #
    #@overload new(function_name)
    #   Returns a new function descriptor. This is ideally used in the case of establishing a
    #   server function. In this case, the function cannot be used to make a remote function call.
    #   @param [String] function_name Name of the new function module
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

    # Add a parameter to a function module. Ideally to be used in the case where a function definition is built
    # up in the client code, rather than fetching it from the server for a remote call
    # @param [Parameter] Definition of a function module parameter
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

    # Return the description of parameters associated with this Function
    def parameters
      parameter_count.times.inject({}) do |params, index|
        param = NWRFCLib::RFCFuncParam.new
        NWRFCLib.get_parameter_desc_by_index(@desc, index, param.to_ptr, @error.to_ptr)
        params[param[:name].get_str] = {
          :type => NWRFCLib::RFC_TYPE[param[:type]],
          :direction => NWRFCLib::RFC_DIRECTION[param[:direction]],
          :nucLength => param[:nucLength],
          :ucLength => param[:ucLength],
          :decimals => param[:decimals],
          :typeDescHandle => param[:typeDescHandle],
          :defaultValue => param[:defaultValue].get_str,
          :parameterText => param[:parameterText].get_str,
          :optional => param[:optional]
        }
        params
      end
    end

  end

  # Represents a callable instance of a function
  class FunctionCall < DataContainer
    attr_reader :handle, :desc, :connection, :function

    # Call with either Function or Connection and Function Call instance (handle)
    #@overload new(function)
    #   Get a function call instance from the function description
    #   @param [Function] function Function Description
    #@overload new(function_handle)
    #   Used in the case of server functions; instantiate a function call instance from the connection
    #   and function description handles received when function is invoked on our side from a remote
    #   system; in this case, there is no handle to the connection, and we take advantage only of the
    #   data container capabilities
    #   @param [FFI::Pointer] function_handle Pointer to the function handle (RFC_FUNCTION_HANDLE)
    def initialize(*args)
      @error = NWRFCLib::RFCError.new
      if args[0].class == FFI::Pointer
        @handle = args[0]
        @connection = nil
        @function = nil
        # @connection = args[0].connection
        @desc = NWRFCLib.describe_function(@handle, @error)
        #@todo Investigate having a referenced Function object as well in the server case; does it have practical applications?
        #  Doing this would require an extra way of handling the constructor of Function
        # @function = Function.new
      elsif args[0].class == Function
        @function = args[0] #function
        @connection = args[0].connection
        @handle = NWRFCLib.create_function(@function.desc, @error.to_ptr)
        @desc = args[0].desc
      end
      NWRFC.check_error(@error)
    end

    # Execute the function on the connected ABAP system
    #@raise NWRFC::NWError
    def invoke(tx = nil)
      raise "Not a callable function" unless @connection
      if tx
        rc = NWRFCLib.invoke_in_transaction(tx.handle, @handle, @error.to_ptr)
        NWRFC.check_error(@error) if rc > 0
      else
        rc = NWRFCLib.invoke(@connection.handle, @handle, @error.to_ptr)
        #@todo Handle function exceptions by checking for :RFC_ABAP_EXCEPTION (5)
        NWRFC.check_error(@error) if rc > 0
      end
    end

    # Returns whether or not a given parameter is active, i.e. whether it will be sent to the server during the RFC
    # call with  FunctionCall#invoke. This is helpful for functions that set default values on parameters or otherwise
    # check whether parameters are passed in cases where this may have an impact on performance or otherwise
    # @param[String, Symbol] parameter Name of the parameter
    def active?(parameter)
      is_active = FFI::MemoryPointer.new :int
      rc = NWRFCLib.is_parameter_active(@handle, parameter.to_s.cU, is_active, @error)
      NWRFC.check_error(@error) if rc > 0
      is_active.read_int == 1
    end

    # Set a named parameter to active or inactive
    def set_active(parameter, active=true)
      (active ? active_flag = 1 : active_flag = 0)
      rc = NWRFCLib.set_parameter_active(@handle, parameter.to_s.cU, active_flag, @error)
      NWRFC.check_error(@error) if rc > 0
      active
    end

    # Set a named parameter to inactive
    def deactivate(parameter)
      set_active(parameter, false)
    end

  end


  class Table < DataContainer

    include Enumerable

    # Iterate over the rows in a table. Each row is yielded as a structure
    def each(&block) #:yields row
      return [] if size == 0
      rc = NWRFCLib.move_to_first_row(@handle, @error)
      NWRFC.check_error(@error) if rc > 0
      size.times do |row|
        struct_handle = NWRFCLib.get_current_row(@handle, @error)
        NWRFC.check_error(@error)
        NWRFCLib.move_to_next_row(@handle, @error)
        # CAVEAT: Other calls using the handle require "handle" field
        # of the RFC_DATA_CONTAINER struct
        yield Structure.new(struct_handle)
      end
    end

    # Return the number of rows in the table
    def size
      rows = FFI::MemoryPointer.new(:uint)
      rc = NWRFCLib.get_row_count(@handle, rows, @error)
      rows.read_uint
    end

    # Delete all rows from (empty) the table
    def clear
      rc = NWRFCLib.delete_all_rows(@handle, @error)
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

    # Append a row (structure) to the table
    def append(row)
      raise "Must append a structure" unless row.class == NWRFC::Structure
      rc = NWRFCLib.append_row(@handle, row.handle, @error)
      NWRFC.check_error(@error) if rc > 0
    end

    # Add new (empty) row and return the structure handle
    # or yield it to a passed block
    # @return Structure
    def new_row
      s_handle = NWRFCLib.append_new_row(@handle, @error)
      NWRFC.check_error(@error)
      s = Structure.new(s_handle)
      if block_given?
        yield s
      else
        s
      end
    end

  end #class Table

  # Represents a structure. An instance is obtained internally by passing the
  # handle of a structure. A user can obtain an instance by invoking sub-field
  # access of a structure or a function
  class Structure < DataContainer


    
  end # class Structure

end #module NWRFC
