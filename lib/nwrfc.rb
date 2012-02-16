# Author:: Martin Ceronio martin.ceronio@infosize.co.za
# Copyright:: Copyright (c) 2012 Martin Ceronio
# License:: MIT and/or Creative Commons Attribution-ShareAlike
# SAP, Netweaver, RFC and other names referred to in this code
# are, or may be registered trademarks and the property of SAP, AG
# No ownership over any of these is asserted by Martin Ceronio

require File.dirname(__FILE__)+'/nwrfc/nwrfclib'

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

  # Represents a remote-enabled function module for RFC, can be instantiated either by the caller
  # or by calling Connection#get_function. This only represents the description of the function;
  # to call a function, an instance of a function call must be obtained with #get_function_call
  class Function
    attr_reader :desc, :connection, :function_name

    # Get a function module instance; can also be obtained by calling Connection#get_function
    def initialize(connection, function_name)
      @function_name = function_name
      @error =  NWRFCLib::RFCError.new
      @desc = NWRFCLib.get_function_desc(connection.handle, function_name.cU, @error.to_ptr)
      @connection = connection
      NWRFC.check_error(@error)
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

  # Representation of a data container (function, structure or table)
  class DataContainer
    attr_reader :handle, :desc

    def initialize(handle)
      @error = NWRFCLib::RFCError.new
      @handle = handle
      @desc = NWRFCLib.describe_type(@handle, @error)
      @member_metadata = {} #Cache of metadata for members
      NWRFC.check_error(@error)
    end

    # Return the member specified by string or symbol
    def [](element)
      member = element.to_s.upcase
      metadata = member_metadata(element)
      case metadata[:type]
      when :RFCTYPE_CHAR
        # TODO: Try use :string parameter in get_chars
        return read_chars(metadata)
      when :RFCTYPE_DATE
        return Date.parse(read_chars(metadata))
        #return Date.new(date[0..3].to_i, date[4..5].to_i, date[6..7].to_i)
      when :RFCTYPE_BCD
        size = metadata[:ucLength]
        cb = FFI::MemoryPointer.new :char, size * 2
        rc = NWRFCLib.get_chars(@handle, metadata[:name].cU, cb, size * 2, @error.to_ptr)
        NWRFC.check_error(@error) if rc > 0
        cb.read_string(size).uC
      when :RFCTYPE_TIME
        # TODO: See whether we can optimize this
        timec = read_chars(metadata)
        return Time.parse("#{timec[0..1]}:#{timec[2..3]}:#{timec[4..5]}")
      when :RFCTYPE_BYTE
        return read_chars(metadata)
      when :RFCTYPE_TABLE
        new_handle = NWRFCLib::RFCDataContainer.new
        rc = NWRFCLib.get_table(@handle, member.cU, new_handle.to_ptr, @error.to_ptr)
        NWRFC.check_error(@error) if rc > 0
        # CAVEAT: Other calls using the handle require "handle" field
        # of the RFC_DATA_CONTAINER struct for some reason.
        new_handle = new_handle[:handle]
        value = Table.new(new_handle)
      when :RFCTYPE_NUM
        return read_chars(metadata).to_i
      when :RFCTYPE_FLOAT
        double = FFI::MemoryPointer.new :double
        rc = NWRFCLib.get_float(@handle, member.cU, double, @error)
        NWRFC.check_error(@error) if rc > 0
        return double.get_double(0)
      when :RFCTYPE_INT
        int = FFI::MemoryPointer.new :int
        rc = NWRFCLib.get_int(@handle, member.cU, int, @error)
        NWRFC.check_error(@error) if rc > 0
        return int.get_int(0)
      when :RFCTYPE_INT2
        short = FFI::MemoryPointer.new :short
        rc = NWRFCLib.get_int2(@handle, member.cU, short, @error)
        NWRFC.check_error(@error) if rc > 0
        return short.get_short(0)
      when :RFCTYPE_INT1
        int1 = FFI::MemoryPointer.new :uint8
        rc = NWRFCLib.get_int1(@handle, member.cU, int1, @error)
        NWRFC.check_error(@error) if rc > 0
        return int1.get_uint8(0)
      when :RFCTYPE_NULL
        raise "Unsupported type RFCTYPE_NULL" #You should never run into this
      when :RFCTYPE_STRUCTURE
        new_handle = NWRFCLib::RFCDataContainer.new
        rc = NWRFCLib.get_structure(@handle, member.cU, new_handle.to_ptr, @error.to_ptr)
        NWRFC.check_error(@error) if rc > 0
        new_handle = new_handle[:handle]
        value = Structure.new(new_handle)
      when :RFCTYPE_DECF16
        return read_chars(metadata).to_f
      when :RFCTYPE_DECF34
        return read_chars(metadata).to_f
      when :RFCTYPE_XMLDATA
        raise "Unsupported type RFCTYPE_XMLDATA (no longer used)" #You should never run into this
      when :RFCTYPE_STRING
        return read_string(metadata)
      when :RFCTYPE_XSTRING
      else
        raise "Illegal member type #{metadata[:type]}"
      end
      NWRFC.check_error(@error)
      value
    end

    def []=(element, value)
      member = element.to_s.upcase
      metadata = member_metadata(element)
      case metadata[:type]
      when :RFCTYPE_CHAR
        NWRFCLib.set_chars(@handle, member.cU, value.cU, value.length, @error.to_ptr)
      when :RFCTYPE_DATE
        value = value_to_date(value)
        NWRFCLib.set_date(@handle, member.cU, value.cU, @error.to_ptr)
      when :RFCTYPE_BCD
      when :RFCTYPE_TIME
        value = value_to_time(value)
        NWRFCLib.set_time(@handle, member.cU, value.cU, @error.to_ptr)
      when :RFCTYPE_BYTE
      when :RFCTYPE_TABLE
      when :RFCTYPE_NUM
      when :RFCTYPE_FLOAT
        NWRFCLib.set_float(@handle, member.cU, value.to_f, @error.to_ptr)
        #NWRFCLib.set_chars(@handle, member.cU, value.to_s.cU, value.to_s.length, @error.to_ptr)
      when :RFCTYPE_INT
        NWRFCLib.set_int(@handle, member.cU, value.to_i, @error.to_ptr)
      when :RFCTYPE_INT2
        NWRFCLib.set_int2(@handle, member.cU, value.to_i, @error.to_ptr)
      when :RFCTYPE_INT1
        NWRFCLib.set_int1(@handle, member.cU, value.to_i, @error.to_ptr)
      when :RFCTYPE_NULL
        raise "Unsupported type RFCTYPE_NULL" #You should never run into this
      when :RFCTYPE_STRUCTURE
      when :RFCTYPE_DECF16
      when :RFCTYPE_DECF34
      when :RFCTYPE_XMLDATA
      when :RFCTYPE_STRING
      when :RFCTYPE_XSTRING
      else
        raise "Illegal member type #{@members[:type]}"
      end
      NWRFC.check_error(@error)
    end

    def value_to_time(value)
      return value.strftime(NW_TIME_FORMAT) if value.respond_to? :strftime
      value.to_s
    end

    def value_to_date(value)
      return value.strftime(NW_DATE_FORMAT) if value.respond_to? :strftime
      # Force the resulting string into 8 characters otherwise
      value = value.to_s
      value << ' ' until value.size == 8 if value.size < 8
      value = value[0..7] if value.size > 8
      value
    end

    def value_to_time(value)
      return value.strftime(NW_TIME_FORMAT) if value.respond_to? :strftime
      # Force the resulting string into 6 characters otherwise
      value = value.to_s
      value << ' ' until value.size == 6 if value.size < 6
      value = value[0..6] if value.size > 6
      value
    end

    # Get the metadata of a member (function, structure or table)
    def member_metadata(member_name)
      member = member_name.to_s.upcase
      if self.class == NWRFC::FunctionCall
        fpar = NWRFCLib::RFCFuncParam.new
        rc = NWRFCLib.get_parameter_desc_by_name(@desc, member.cU, fpar.to_ptr, @error.to_ptr)
        NWRFC.check_error(@error) if rc > 0
        member_to_hash(fpar)
      elsif self.class == NWRFC::Table || self.class == NWRFC::Structure
        fd = NWRFCLib::RFCFieldDesc.new
        rc = NWRFCLib.get_field_desc_by_name(@desc, member.cU, fd.to_ptr, @error.to_ptr)
        NWRFC.check_error(@error) if rc > 0 
        member_to_hash(fd)
      end
    end

    private
    # Returns the subset of metadata values common to both a function parameter
    # and a type field
    def member_to_hash(member)
      {
        :name => member[:name].get_str,
        :type => NWRFCLib::RFCTYPE[member[:type]],
        :nucLength => member[:nucLength],
        :ucLength => member[:ucLength],
        :decimals => member[:decimals],
        :typeDescHandle => member[:typeDescHandle]
      }
    end

    def read_chars(metadata)
      size = metadata[:ucLength]
      cb = FFI::MemoryPointer.new :char, size
      rc = NWRFCLib.get_chars(@handle, metadata[:name].cU, cb, metadata[:nucLength], @error.to_ptr)
      NWRFC.check_error(@error) if rc > 0
      cb.read_string(size).uC
    end

    def read_string(metadata)
      #size = metadata[:ucLength]
      size = FFI::MemoryPointer.new(:uint)
      rc = NWRFCLib.get_string_length(@handle, metadata[:name].cU, size, @error)
      NWRFC.check_error(@error) if rc > 0
      buf_len = size.read_uint + 1
      sbuf = FFI::MemoryPointer.new :char, buf_len * NWRFCLib::B_SIZE
      rc = NWRFCLib.get_string(@handle, metadata[:name].cU, sbuf, buf_len, size, @error)
      NWRFC.check_error(@error) if rc > 0
      sbuf.read_string(sbuf.size).uC
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