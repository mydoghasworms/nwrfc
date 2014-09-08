module NWRFC

  # Representation of a data container (function, structure or table)
  # Implements common functions for data containers, such as setting and getting values, tables, structures and
  # takes care of type conversion and calling correct SDK functions to set or get values
  #
  # == Type Conversions
  # To ensure that data is passed correctly to the NW RFC SDK functions, certain conversions are applied to values
  # passed, depending on the type of the field. ABAP supports a number of elementary types, which are listed in the
  #
  # DECFLOAT16 and DECFLOAT34 types are not yet supported.
  #
  # === Inbound
  # For character and string
  class DataContainer
    attr_reader :handle, :desc

    def initialize(handle)
      @error = NWRFCLib::RFCError.new
      @handle = handle
      @desc = NWRFCLib.describe_type(@handle, @error)
      @member_metadata = {} #Cache of metadata for members
      NWRFC.check_error(@error)
    end

    #--
    # VALUE RETRIEVAL
    #++

    # Get value from a data container (structure, function instance or table)
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
          size = metadata[:nucLength] + (metadata[:decimals] || 0)
          size += 10 # Temporary fix for issue https://github.com/mydoghasworms/nwrfc/issues/7
          buf = FFI::MemoryPointer.new(:uchar, size*2)
          rc = NWRFCLib.get_chars(@handle, metadata[:name].cU, buf, size, @error.to_ptr)
          NWRFC.check_error(@error) if rc > 0
          return buf.get_bytes(0, size*2).uC.to_f
        #size = metadata[:ucLength]
        #cb = FFI::MemoryPointer.new :char, size * 2
        #rc = NWRFCLib.get_chars(@handle, metadata[:name].cU, cb, size * 2, @error.to_ptr)
        #NWRFC.check_error(@error) if rc > 0
        #cb.read_string(size).uC

        when :RFCTYPE_TIME
          # TODO: See whether we can optimize this
          timec = read_chars(metadata)
          return Time.parse("#{timec[0..1]}:#{timec[2..3]}:#{timec[4..5]}")

        when :RFCTYPE_BYTE
          size = metadata[:ucLength]
          buf = FFI::MemoryPointer.new(:uchar, size)
          rc = NWRFCLib.get_bytes(@handle, metadata[:name].cU, buf, size, @error.to_ptr)
          NWRFC.check_error(@error) if rc > 0
          return buf.get_bytes(0, size)

        when :RFCTYPE_TABLE
          # TODO Cache instances of table members and return those where available
          new_handle = NWRFCLib::RFCDataContainer.new
          rc = NWRFCLib.get_table(@handle, member.cU, new_handle.to_ptr, @error.to_ptr)
          NWRFC.check_error(@error) if rc > 0
          # CAVEAT: Other calls using the handle require "handle" field
          # of the RFC_DATA_CONTAINER struct for some reason.
          new_handle = new_handle[:handle]
          return Table.new(new_handle)

        when :RFCTYPE_NUM
          return read_chars(metadata)

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
          # TODO Cache instances of structure members and return those where available
          new_handle = NWRFCLib::RFCDataContainer.new
          rc = NWRFCLib.get_structure(@handle, member.cU, new_handle.to_ptr, @error.to_ptr)
          NWRFC.check_error(@error) if rc > 0
          new_handle = new_handle[:handle]
          return Structure.new(new_handle)

        when :RFCTYPE_DECF16
          double = FFI::MemoryPointer.new :double
          rc = NWRFCLib.get_dec_f16(@handle, member.cU, double, @error)
          NWRFC.check_error(@error) if rc > 0
          return double.get_double(0)

        when :RFCTYPE_DECF34
          double = FFI::MemoryPointer.new :double, 2
          rc = NWRFCLib.get_dec_f34(@handle, member.cU, double, @error)
          NWRFC.check_error(@error) if rc > 0
          return double.get_double(0)

        when :RFCTYPE_XMLDATA
          raise "Unsupported type RFCTYPE_XMLDATA (no longer used)" #You should never run into this

        when :RFCTYPE_STRING
          return read_string(metadata)

        when :RFCTYPE_XSTRING
          size = FFI::MemoryPointer.new(:uint)
          rc = NWRFCLib.get_string_length(@handle, metadata[:name].cU, size, @error)
          NWRFC.check_error(@error) if rc > 0
          buf_len = size.read_uint
          sbuf = FFI::MemoryPointer.new :uchar, buf_len
          rc = NWRFCLib.get_x_string(@handle, metadata[:name].cU, sbuf, buf_len, size, @error)
          NWRFC.check_error(@error) if rc > 0
          return sbuf.read_string(sbuf.size)

        else
          raise "Illegal member type #{metadata[:type]}"
      end

    end

    #--
    # VALUE STORAGE
    #++

    # Set value on a data container (structure, function instance or table)
    def []=(element, value)
      member = element.to_s.upcase
      metadata = member_metadata(element)
      case metadata[:type]

        when :RFCTYPE_CHAR
          value = value.to_s
          NWRFCLib.set_chars(@handle, member.cU, value.cU, value.length, @error.to_ptr)

        when :RFCTYPE_DATE
          value = value_to_date(value)
          NWRFCLib.set_date(@handle, member.cU, value.cU, @error.to_ptr)

        when :RFCTYPE_BCD
          stval = value.to_s.cU
          m = FFI::MemoryPointer.from_string stval
          NWRFCLib.set_string(@handle, member.cU, m, value.to_s.size, @error)

        when :RFCTYPE_TIME
          value = value_to_time(value)
          NWRFCLib.set_time(@handle, member.cU, value.cU, @error.to_ptr)

        when :RFCTYPE_BYTE
          m = FFI::MemoryPointer.from_string value.to_s
          NWRFCLib.set_bytes(@handle, member.cU, m, value.to_s.size, @error.to_ptr)

        when :RFCTYPE_TABLE
          raise "Value must be of type table" unless value.class == NWRFC::Table
          NWRFCLib.set_table(@handle, member.cU, value.handle, @error)

        when :RFCTYPE_NUM
          value = value.to_s
          NWRFCLib.set_num(@handle, member.cU, value.cU, value.length, @error.to_ptr)

        when :RFCTYPE_FLOAT
          NWRFCLib.set_float(@handle, member.cU, value.to_f, @error.to_ptr)

        when :RFCTYPE_INT
          NWRFCLib.set_int(@handle, member.cU, value.to_i, @error.to_ptr)

        when :RFCTYPE_INT2
          NWRFCLib.set_int2(@handle, member.cU, value.to_i, @error.to_ptr)

        when :RFCTYPE_INT1
          NWRFCLib.set_int1(@handle, member.cU, value.to_i, @error.to_ptr)

        when :RFCTYPE_NULL
          raise "Unsupported type RFCTYPE_NULL" #You should never run into this

        when :RFCTYPE_STRUCTURE
          raise "Value must be of type table" unless value.class == NWRFC::Structure
          NWRFCLib.set_structure(@handle, member.cU, value.handle, @error)

        when :RFCTYPE_DECF16
          raise "#{@members[:type]}: decfloat16 not supported yet"
          double = NWRFCLib::RFC_DECF16.new #FFI::MemoryPointer.new :double
          double[:align] = value.to_f
                                            #double.put_double(0, value.to_f)
                                            #double = FFI::Pointer.new 4
          NWRFCLib.set_dec_f16(@handle, member.cU, double.pointer, @error)

        when :RFCTYPE_DECF34
          raise "#{@members[:type]}: decfloat34 not supported yet"
          #        double = FFI::MemoryPointer.new :double, 2
          #        double.put_double(0, value.to_f)
          double = NWRFCLib::RFC_DECF34.new #FFI::MemoryPointer.new :double
          double[:align] = value.to_f
          NWRFCLib.set_dec_f34(@handle, member.cU, double, @error)

        when :RFCTYPE_XMLDATA
          raise "Unsupported type RFCTYPE_XMLDATA (no longer used)" #You should never run into this

        when :RFCTYPE_STRING
          stval = value.cU
          m = FFI::MemoryPointer.from_string stval
          NWRFCLib.set_string(@handle, member.cU, m, value.size, @error)

        when :RFCTYPE_XSTRING
          m = FFI::MemoryPointer.new value.size
          m.put_bytes 0, value
          NWRFCLib.set_x_string(@handle, member.cU, m, value.size, @error)

        else
          raise "Illegal member type #{@members[:type]}"
      end
      NWRFC.check_error(@error)
    end

    # Return value as a SAP-formatted date ("YYYYMMDD"). Force value to fit into 8 chars by
    # truncating or padding with spaces
    def value_to_date(value)
      return value.strftime(NW_DATE_FORMAT) if value.respond_to? :strftime
      # Force the resulting string into 8 characters otherwise
      value = value.to_s
      value << ' ' until value.size == 8 if value.size < 8
      value = value[0..7] if value.size > 8
      value
    end

    # Return value as a SAP-formatted time ("HHMMSS"). Force value to fit into 6 chars by
    # truncating or padding with spaces
    def value_to_time(value)
      return value.strftime(NW_TIME_FORMAT) if value.respond_to? :strftime
      # Force the resulting string into 6 characters otherwise
      value = value.to_s
      value << ' ' until value.size == 6 if value.size < 6
      value = value[0..6] if value.size > 6
      value
    end

    # Return a list (array) of symbols representing the names of the fields (or parameters, in the case of a function)
    # of this data container
    def fields
      fc = FFI::MemoryPointer.new(:uint)
      rc = NWRFCLib.get_field_count(@desc, fc, @error)
      NWRFC.check_error(@error) if rc > 0
      fc = fc.read_uint
      fd = NWRFCLib::RFCFieldDesc.new
      # Make a list of field names
      fc.times.inject([]) {|array, index|
        rc = NWRFCLib.get_field_desc_by_index(@desc, index, fd.to_ptr, @error.to_ptr)
        NWRFC.check_error(@error) if rc > 0
        #@todo WARNING! our get_str method did not handle getting the name of the RESPTEXT parameter in STFC_DEEP_TABLE correctly
        # As a workaround, we use our read_string_dn method; do we need to use this elsewhere?
        #array << fd[:name].get_str.to_sym #<-The code with good intentions
        array << fd[:name].to_ptr.read_string_dn.uC.to_sym #<- Workaround; the way of the future?
      }
    end

    # Get the metadata of a member (function, structure or table)
    def member_metadata(member_name)
      # TODO: Cache metadata definitions; will it be quicker than making a hash of metadata for a given member each time?
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
          :type => NWRFCLib::RFC_TYPE[member[:type]],
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

end