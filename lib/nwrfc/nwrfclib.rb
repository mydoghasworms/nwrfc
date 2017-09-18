# Author:: Martin Ceronio martin.ceronio@infosize.co.za
# Copyright:: Copyright (c) 2012 Martin Ceronio
# License:: MIT and/or Creative Commons Attribution-ShareAlike
# SAP, Netweaver, RFC and other names referred to in this code
# are, or may be registered trademarks and the property of SAP, AG
# No ownership over any of these is asserted by Martin Ceronio

require 'rubygems'
require 'ffi'

RUBY_VERSION_18 = RUBY_VERSION[0..2] == "1.8"
# Check if ICONV compatibility (for Ruby 1.8 and below) is required
STRING_SUPPORTS_ENCODE = ''.respond_to?(:encode) # Ruby 1.9 and onwards

require 'iconv' unless STRING_SUPPORTS_ENCODE

# Provide an alias for FFI::MemoryPointer#read_int to `read_uint` in 1.8
# See http://stackoverflow.com/questions/9035661/ruby-ffi-memorypointer-read-int-present-in-1-9-but-not-1-8
# Probably not good to interpret an unsigned int as an int, but we don't expect to use it for big values
# that could result in sign conversion
# FIXME - This must go! Replace with calls to get_* defined in FFI::MemoryPointer
if RUBY_VERSION_18
  FFI::MemoryPointer.class_eval { alias :read_uint :read_int }
end

# Enhancement to FFI::Pointer to be able to read a double-null terminated string,
# which would be returned e.g. by RfcGetVersion() in the SDK
# See http://stackoverflow.com/questions/9293307/ruby-ffi-ruby-1-8-reading-utf-16le-encoded-strings
module FFI
  class Pointer

    # Enhancement to FFI::Pointer to be able to read a double-null terminated string,
    # which would be returned e.g. by RfcGetVersion() in the SDK
    # See http://stackoverflow.com/questions/9293307/ruby-ffi-ruby-1-8-reading-utf-16le-encoded-strings
    # It should be safe to call this on a Pointer within the context of the NW RFC SDK library,
    # because all strings are supposed to be UTF-16LE encoded and double-null terminated
    def read_string_dn(max=0)
      cont_nullcount = 0
      offset = 0
      until cont_nullcount == 2
        byte = get_bytes(offset, 1)
        cont_nullcount += 1 if byte == "\000"
        cont_nullcount = 0 if byte != "\000"
        offset += 1
      end
      get_bytes(0, offset+1)
    end
  end
end

# Enhancement to the String class to put string values into double-null
# terminated UTF16 little endian encoded strings as required by the NW RFC
# SDK function, which should work on Linux and Windows (and maybe other
# architectures, though the plan is not to support them)
#String.class_eval{define_method(:cU){ Iconv.conv("UTF-16LE", "UTF8", self+"\0") }}

# Availability of String::convert() should indicate otherwise
if STRING_SUPPORTS_ENCODE

  class String

    # Convert string from UTF-8 to double-null terminated UTF-16LE string
    def cU
      (self.to_s + "\0").force_encoding('UTF-8').encode('UTF-16LE')
    end

    # Convert string from UTF-16LE to UTF-8 and trim trailing whitespace
    def uC
      self.force_encoding('UTF-16LE').encode('UTF-8').rstrip
    end

  end

else

  class String

    # Convert string from UTF-8 to doudble-null terminated UTF-16LE string
    def cU
      NWRFCLib::Cutf8_to_utf16le.iconv(self+"\0")
    end

    # Convert string from UTF-16LE to UTF-8 and trim trailing whitespace
    def uC
      NWRFCLib::Cutf16le_to_utf8.iconv(self).rstrip
    end

  end

end

# Enhancement to FFI::StructLayout::CharArray to add a get_str method that changes the
# string value of the character array by enforcing encoding of UTF-16LE (as used in NW RFC SDK)
# and strips off blanks at the end to return a readable String
class FFI::StructLayout::CharArray
  def get_str
    self.to_ptr.read_string(self.size).uC
  end
end

# Enhancement for JRuby to enable the same reading of strings as above, but for JRuby we must make
# the enhancement to FFI::StructLayout::CharArrayProxy
# TODO Perhaps we should make the alternate change (above) the other branch of the following if statement
if RUBY_PLATFORM == 'java'
  class FFI::StructLayout::CharArrayProxy
    def get_str
      self.to_ptr.read_string(self.size).uC
    end
  end
end

# Library wrapper around NW RFC SDK shared library using RUBY-FFI
module NWRFCLib

  unless STRING_SUPPORTS_ENCODE # Ruby 1.8 and below
    Cutf8_to_utf16le = Iconv.new("UTF-16LE", "UTF-8")
    Cutf16le_to_utf8 = Iconv.new("UTF-8", "UTF-16LE")
  end

  extend FFI::Library
  ffi_lib 'sapnwrfc'

  # Multiplier for providing correct byte size for String passed to RFC library
  #@todo Make platform-dependent size based on RUBY_PLATFORM
  B_SIZE = 2

  RFC_RC = enum(
      :RFC_OK,
      :RFC_COMMUNICATION_FAILURE,
      :RFC_LOGON_FAILURE,
      :RFC_ABAP_RUNTIME_FAILURE,
      :RFC_ABAP_MESSAGE,
      :RFC_ABAP_EXCEPTION,
      :RFC_CLOSED,
      :RFC_CANCELED,
      :RFC_TIMEOUT,
      :RFC_MEMORY_INSUFFICIENT,
      :RFC_VERSION_MISMATCH,
      :RFC_INVALID_PROTOCOL,
      :RFC_SERIALIZATION_FAILURE,
      :RFC_INVALID_HANDLE,
      :RFC_RETRY,
      :RFC_EXTERNAL_FAILURE,
      :RFC_EXECUTED,
      :RFC_NOT_FOUND,
      :RFC_NOT_SUPPORTED,
      :RFC_ILLEGAL_STATE,
      :RFC_INVALID_PARAMETER,
      :RFC_CODEPAGE_CONVERSION_FAILURE,
      :RFC_CONVERSION_FAILURE,
      :RFC_BUFFER_TOO_SMALL,
      :RFC_TABLE_MOVE_BOF,
      :RFC_TABLE_MOVE_EOF,
      :RFC_UNKNOWN_ERROR
  )

  RFC_ERROR_GROUP = enum(
      :OK,
      :ABAP_APPLICATION_FAILURE,
      :ABAP_RUNTIME_FAILURE,
      :LOGON_FAILURE,
      :COMMUNICATION_FAILURE,
      :EXTERNAL_RUNTIME_FAILURE,
      :EXTERNAL_APPLICATION_FAILURE
  )

  RFC_DIRECTION = enum(
      :RFC_IMPORT, 1,
      :RFC_EXPORT, 2,
      :RFC_CHANGING, 3,
      :RFC_TABLES, 7
  )

  RFC_TYPE = enum(
      :RFCTYPE_CHAR, 0,
      :RFCTYPE_DATE, 1,
      :RFCTYPE_BCD, 2,
      :RFCTYPE_TIME, 3,
      :RFCTYPE_BYTE, 4,
      :RFCTYPE_TABLE, 5,
      :RFCTYPE_NUM, 6,
      :RFCTYPE_FLOAT, 7,
      :RFCTYPE_INT, 8,
      :RFCTYPE_INT2, 9,
      :RFCTYPE_INT1, 10,
      :RFCTYPE_NULL, 14,
      :RFCTYPE_ABAPOBJECT, 16,
      :RFCTYPE_STRUCTURE, 17,
      :RFCTYPE_DECF16, 23,
      :RFCTYPE_DECF34, 24,
      :RFCTYPE_XMLDATA, 28,
      :RFCTYPE_STRING, 29,
      :RFCTYPE_XSTRING, 30,
      :RFCTYPE_BOX, 31,
      :RFCTYPE_GENERIC_BOX, 32,
      :_RFCTYPE_max_value
  )

  # Connection parameter wrapper (struct RFC_CONNECTION_PARAMETER in sapnwrfc.h)
  class RFCConnParam < FFI::Struct
    layout :name, :pointer,
           :value, :pointer
  end

  # Connection Details (struct RFC_ATTRIBUTES in sapnwrfc.h)
  class RFCConnection < FFI::Struct
    layout :dest, [:char, (64+1)*B_SIZE],
           :host, [:char, (100+1)*B_SIZE],
           :partnerHost, [:char, (100+1)*B_SIZE],
           :sysNumber, [:char, (2+1)*B_SIZE],
           :sysId, [:char, (8+1)*B_SIZE],
           :client, [:char, (3+1)*B_SIZE],
           :user, [:char, (12+1)*B_SIZE],
           :language, [:char, (2+1)*B_SIZE],
           :trace, [:char, (1+1)*B_SIZE],
           :isoLanguage, [:char, (2+1)*B_SIZE],
           :codepage, [:char, (4+1)*B_SIZE],
           :partnerCodepage, [:char, (4+1)*B_SIZE],
           :rfcRole, [:char, (1+1)*B_SIZE],
           :type, [:char, (1+1)*B_SIZE],
           :partnerType, [:char, (1+1)*B_SIZE],
           :rel, [:char, (4+1)*B_SIZE],
           :partnerRel, [:char, (4+1)*B_SIZE],
           :kernelRel, [:char, (4+1)*B_SIZE],
           :cpicConvId, [:char, (8+1)*B_SIZE],
           :progName, [:char, (128+1)*B_SIZE],
           :reserved, [:char, (86+1)*B_SIZE]
  end

  # Error info wrapper (struct RFC_ERROR_INFO in sapnwrfc.h)
  class RFCError < FFI::Struct
    layout :code, :int,
           :group, :int,
           :key, [:char, (128)*B_SIZE],
           :message, [:char, (512)*B_SIZE],
           :abapMsgClass, [:char, (20+1)*B_SIZE],
           :abapMsgType, [:char, (1+1)*B_SIZE],
           :abapMsgNumber, [:char, (3+1)*B_SIZE],
           :abapMsgV1, [:char, (50+1)*B_SIZE],
           :abapMsgV2, [:char, (50+1)*B_SIZE],
           :abapMsgV3, [:char, (50+1)*B_SIZE],
           :abapMsgV4, [:char, (50+1)*B_SIZE]
  end

  # Function Parameter Description (struct RFC_PARAMETER_DESC in sapnwrfc.h)
  class RFCFuncParam < FFI::Struct
    layout :name, [:char, (30+1)*B_SIZE],
           :type, :int, #enum RFCTYPE
           :direction, :int, #enum RFC_DIRECTION
           :nucLength, :uint,
           :ucLength, :uint,
           :decimals, :uint,
           :typeDescHandle, :pointer, #RFC_TYPE_DESC_HANDLE
           :defaultValue, [:char, (30+1)*B_SIZE], #RFC_PARAMETER_DEFVALUE
           :parameterText, [:char, (79+1)*B_SIZE], #RFC_PARAMETER_TEXT
           :optional, :uchar, #RFC_BYTE
           :extendedDescription, :pointer
  end

  class RFCFieldDesc < FFI::Struct
    layout :name, [:char, (30+1)*B_SIZE],
           :type, :int, #enum RFCTYPE
           :nucLength, :uint,
           :nucOffset, :uint,
           :ucLength, :uint,
           :ucOffset, :uint,
           :decimals, :uint,
           :typeDescHandle, :pointer, #RFC_TYPE_DESC_HANDLE
           :extendedDescription, :pointer
  end

  class RFCDataContainer < FFI::Struct
    layout :handle, :pointer
  end

  #  typedef :RFCDataContainer, RFCStructureHandle
  #  typedef :RFCDataContainer, RFCTableHandle

  class RFC_FUNCTION_DESC_HANDLE < FFI::Struct
    layout :handle, :pointer
  end

  class RFC_TYPE_DESC_HANDLE < FFI::Struct
    layout :handle, :pointer
  end

  class DATA_CONTAINER_HANDLE < FFI::Struct
    layout :handle, :pointer
  end

  class RFC_DECF16 < FFI::Union
    layout :bytes, [:uchar, 8],
           :align, :double
  end

  #  class SAP_MAX_ALIGN_T < FFI::Union
  #    layout :align1, :long,
  #      :align2, :double,
  #      :align3, :pointer,
  #      :align4,
  #  end

  #  class RFC_DECF34 < FFI::Union
  #    layout :bytes, [:uchar, 16],
  #      :align, 16
  #  end

  #############################################################################################################
  # ATTACH FUNCTIONS
  # The functions here were obtained by parsing content from the doxygen files from the documentation
  # accompanying the NW RFC SDK, and were tweaked here and there afterward. Most of them are actually not
  # yet used in our NWRFC library, so calling them may not work. For best results, consult sapnwrfc.h from
  # the SDK
  #############################################################################################################
  # Callback for function server (function implementation)
  callback :funcimpl, [:pointer, :pointer, :pointer], :int

  # Function mappings
  [
      [:add_exception, :RfcAddException, [:pointer, :pointer, :pointer], :int],
      [:add_function_desc, :RfcAddFunctionDesc, [:pointer, :pointer, :pointer], :int],
      [:add_parameter, :RfcAddParameter, [:pointer, :pointer, :pointer], :int],
      [:add_type_desc, :RfcAddTypeDesc, [:pointer, :pointer, :pointer], :int],
      [:add_type_field, :RfcAddTypeField, [:pointer, :pointer, :pointer], :int],
      # @method append_new_row(table_handle, error_handle)
      # @returns FFI::Pointer pointer to structure of new row
      # calls RfcAppendNewRow()
      [:append_new_row, :RfcAppendNewRow, [:pointer, :pointer], :pointer],
      # @method append_row(table_handle, structure, error_handle)
      # @returns Integer RC
      # calls RfcAppendRow()
      [:append_row, :RfcAppendRow, [:pointer, :pointer, :pointer], :int],
      [:clone_structure, :RfcCloneStructure, [:pointer, :pointer], :pointer],
      [:clone_table, :RfcCloneTable, [:pointer, :pointer], :pointer],
      [:close_connection, :RfcCloseConnection, [:pointer, :pointer], :int],
      [:confirm_transaction, :RfcConfirmTransaction, [:pointer, :pointer], :int],
      [:create_function, :RfcCreateFunction, [:pointer, :pointer], :pointer],
      [:create_function_desc, :RfcCreateFunctionDesc, [:pointer, :pointer], :pointer],
      [:create_structure, :RfcCreateStructure, [:pointer, :pointer], :pointer],
      [:create_table, :RfcCreateTable, [:pointer, :pointer], :pointer],
      [:create_transaction, :RfcCreateTransaction, [:pointer, :pointer, :pointer, :pointer], :pointer],
      [:create_type_desc, :RfcCreateTypeDesc, [:pointer, :pointer], :pointer],
      [:delete_all_rows, :RfcDeleteAllRows, [:pointer, :pointer], :int],
      [:delete_current_row, :RfcDeleteCurrentRow, [:pointer, :pointer], :int],
      [:describe_function, :RfcDescribeFunction, [:pointer, :pointer], :pointer],
      [:describe_type, :RfcDescribeType, [:pointer, :pointer], :pointer],
      [:destroy_function, :RfcDestroyFunction, [:pointer, :pointer], :int],
      [:destroy_function_desc, :RfcDestroyFunctionDesc, [:pointer, :pointer], :int],
      [:destroy_structure, :RfcDestroyStructure, [:pointer, :pointer], :int],
      [:destroy_table, :RfcDestroyTable, [:pointer, :pointer], :int],
      [:destroy_transaction, :RfcDestroyTransaction, [:pointer, :pointer], :int],
      [:destroy_type_desc, :RfcDestroyTypeDesc, [:pointer, :pointer], :int],
      [:enable_basxml, :RfcEnableBASXML, [:pointer, :pointer], :int],
      [:get_bytes, :RfcGetBytes, [:pointer, :pointer, :pointer, :uint, :pointer], :int],
      [:get_cached_function_desc, :RfcGetCachedFunctionDesc, [:pointer, :pointer, :pointer], :pointer],
      [:get_cached_type_desc, :RfcGetCachedTypeDesc, [:pointer, :pointer, :pointer], :pointer],
      [:get_chars, :RfcGetChars, [:pointer, :pointer, :pointer, :uint, :pointer], :int],
      [:get_connection_attributes, :RfcGetConnectionAttributes, [:pointer, :pointer, :pointer], :int],
      [:get_current_row, :RfcGetCurrentRow, [:pointer, :pointer], :pointer],
      [:get_date, :RfcGetDate, [:pointer, :pointer, :pointer, :pointer], :int],
      [:get_dec_f16, :RfcGetDecF16, [:pointer, :pointer, :pointer, :pointer], :int],
      [:get_dec_f34, :RfcGetDecF34, [:pointer, :pointer, :pointer, :pointer], :int],
      [:get_direction_as_string, :RfcGetDirectionAsString, [:pointer], :pointer],
      [:get_exception_count, :RfcGetExceptionCount, [:pointer, :pointer, :pointer], :int],
      [:get_exception_desc_by_index, :RfcGetExceptionDescByIndex, [:pointer, :uint, :pointer, :pointer], :int],
      [:get_exception_desc_by_name, :RfcGetExceptionDescByName, [:pointer, :pointer, :pointer, :pointer], :int],
      [:get_field_count, :RfcGetFieldCount, [:pointer, :pointer, :pointer], :int],
      [:get_field_desc_by_index, :RfcGetFieldDescByIndex, [:pointer, :uint, :pointer, :pointer], :int],
      [:get_field_desc_by_name, :RfcGetFieldDescByName, [:pointer, :pointer, :pointer, :pointer], :int],
      [:get_float, :RfcGetFloat, [:pointer, :pointer, :pointer, :pointer], :int],
      [:get_function_desc, :RfcGetFunctionDesc, [:pointer, :pointer, :pointer], :pointer],
      [:get_function_name, :RfcGetFunctionName, [:pointer, :pointer, :pointer], :int],
      [:get_int, :RfcGetInt, [:pointer, :pointer, :pointer, :pointer], :int],
      [:get_int1, :RfcGetInt1, [:pointer, :pointer, :pointer, :pointer], :int],
      [:get_int2, :RfcGetInt2, [:pointer, :pointer, :pointer, :pointer], :int],
      [:get_num, :RfcGetNum, [:pointer, :pointer, :pointer, :uint, :pointer], :int],
      [:get_parameter_count, :RfcGetParameterCount, [:pointer, :pointer, :pointer], :int],
      [:get_parameter_desc_by_index, :RfcGetParameterDescByIndex, [:pointer, :uint, :pointer, :pointer], :int],
      [:get_parameter_desc_by_name, :RfcGetParameterDescByName, [:pointer, :pointer, :pointer, :pointer], :int],
      [:get_partner_snc_key, :RfcGetPartnerSNCKey, [:pointer, :pointer, :pointer, :pointer], :int],
      [:get_partner_snc_name, :RfcGetPartnerSNCName, [:pointer, :pointer, :uint, :pointer], :int],
      [:get_partner_sso_ticket, :RfcGetPartnerSSOTicket, [:pointer, :pointer, :pointer, :pointer], :int],
      [:get_rc_as_string, :RfcGetRcAsString, [:pointer], :pointer],
      [:get_row_count, :RfcGetRowCount, [:pointer, :pointer, :pointer], :int],
      [:get_string, :RfcGetString, [:pointer, :pointer, :pointer, :uint, :pointer, :pointer], :int],
      [:get_string_length, :RfcGetStringLength, [:pointer, :pointer, :pointer, :pointer], :int],
      [:get_structure, :RfcGetStructure, [:pointer, :pointer, :pointer, :pointer], :int],
      [:get_table, :RfcGetTable, [:pointer, :pointer, :pointer, :pointer], :int],
      [:get_time, :RfcGetTime, [:pointer, :pointer, :pointer, :pointer], :int],
      [:get_transaction_id, :RfcGetTransactionID, [:pointer, :pointer, :pointer], :int],
      [:get_type_as_string, :RfcGetTypeAsString, [:pointer], :pointer],
      [:get_type_desc, :RfcGetTypeDesc, [:pointer, :pointer, :pointer], :pointer],
      [:get_type_length, :RfcGetTypeLength, [:pointer, :pointer, :pointer, :pointer], :int],
      [:get_type_name, :RfcGetTypeName, [:pointer, :pointer, :pointer], :int],
      [:get_version, :RfcGetVersion, [:pointer, :pointer, :pointer], :pointer],
      [:get_x_string, :RfcGetXString, [:pointer, :pointer, :pointer, :uint, :pointer, :pointer], :int],
      [:init, :RfcInit, [:pointer], :int],
      [:insert_new_row, :RfcInsertNewRow, [:pointer, :pointer], :pointer],
      [:insert_row, :RfcInsertRow, [:pointer, :pointer, :pointer], :int],
      [:install_generic_server_function, :RfcInstallGenericServerFunction, [:pointer, :pointer, :pointer], :int],
      [:install_server_function, :RfcInstallServerFunction, [:pointer, :pointer, :funcimpl, :pointer], :int],
      [:install_transaction_handlers, :RfcInstallTransactionHandlers, [:pointer, :pointer, :pointer, :pointer, :pointer, :pointer], :int],
      [:invoke, :RfcInvoke, [:pointer, :pointer, :pointer], :int],
      [:invoke_in_transaction, :RfcInvokeInTransaction, [:pointer, :pointer, :pointer], :int],
      [:is_basxml_supported, :RfcIsBASXMLSupported, [:pointer, :pointer, :pointer], :int],
      #[:is_connection_handle_valid, :RfcIsConnectionHandleValid, [:pointer, :pointer, :pointer], :int],
      [:is_parameter_active, :RfcIsParameterActive, [:pointer, :pointer, :pointer, :pointer], :int],
      [:listen_and_dispatch, :RfcListenAndDispatch, [:pointer, :int, :pointer], :int],
      [:move_to, :RfcMoveTo, [:pointer, :uint, :pointer], :int],
      [:move_to_first_row, :RfcMoveToFirstRow, [:pointer, :pointer], :int],
      [:move_to_last_row, :RfcMoveToLastRow, [:pointer, :pointer], :int],
      [:move_to_next_row, :RfcMoveToNextRow, [:pointer, :pointer], :int],
      [:move_to_previous_row, :RfcMoveToPreviousRow, [:pointer, :pointer], :int],
      [:open_connection, :RfcOpenConnection, [:pointer, :uint, :pointer], :pointer],
      [:ping, :RfcPing, [:pointer, :pointer], :int],
      [:register_server, :RfcRegisterServer, [:pointer, :uint, :pointer], :pointer],
      [:reload_ini_file, :RfcReloadIniFile, [:pointer], :int],
      #    [:remove_function_desc, :RfcRemoveFunctionDesc, [:pointer, :pointer, :pointer], :int],
      #    [:remove_type_desc, :RfcRemoveTypeDesc, [:pointer, :pointer, :pointer], :int],
      [:reset_server_context, :RfcResetServerContext, [:pointer, :pointer], :int],
      [:sapuc_to_utf8, :RfcSAPUCToUTF8, [:pointer, :uint, :pointer, :pointer, :pointer, :pointer], :int],
      [:set_bytes, :RfcSetBytes, [:pointer, :pointer, :pointer, :uint, :pointer], :int],
      [:set_chars, :RfcSetChars, [:pointer, :pointer, :pointer, :uint, :pointer], :int],
      [:set_date, :RfcSetDate, [:pointer, :pointer, :pointer, :pointer], :int],
      #[:set_dec_f16, :RfcSetDecF16, [:pointer, :pointer, :pointer, :pointer], :int],
      [:set_dec_f16, :RfcSetDecF16, [:pointer, :pointer, RFC_DECF16.by_value, :pointer], :int],
      [:set_dec_f34, :RfcSetDecF34, [:pointer, :pointer, :pointer, :pointer], :int],
      [:set_float, :RfcSetFloat, [:pointer, :pointer, :double, :pointer], :int],
      [:set_ini_path, :RfcSetIniPath, [:pointer, :pointer], :int],
      [:set_int, :RfcSetInt, [:pointer, :pointer, :long, :pointer], :int],
      [:set_int1, :RfcSetInt1, [:pointer, :pointer, :uint8, :pointer], :int],
      [:set_int2, :RfcSetInt2, [:pointer, :pointer, :short, :pointer], :int],
      [:set_num, :RfcSetNum, [:pointer, :pointer, :pointer, :uint, :pointer], :int],
      [:set_parameter_active, :RfcSetParameterActive, [:pointer, :pointer, :int, :pointer], :int],
      [:set_string, :RfcSetString, [:pointer, :pointer, :pointer, :uint, :pointer], :int],
      [:set_structure, :RfcSetStructure, [:pointer, :pointer, :pointer, :pointer], :int],
      [:set_table, :RfcSetTable, [:pointer, :pointer, :pointer, :pointer], :int],
      [:set_time, :RfcSetTime, [:pointer, :pointer, :pointer, :pointer], :int],
      #[:set_trace_dir, :RfcSetTraceDir, [:pointer, :pointer], :int],
      #[:set_trace_encoding, :RfcSetTraceEncoding, [:pointer, :pointer], :int],
      #[:set_trace_level, :RfcSetTraceLevel, [:pointer, :pointer, :uint, :pointer], :int],
      [:set_type_length, :RfcSetTypeLength, [:pointer, :uint, :uint, :pointer], :int],
      [:set_x_string, :RfcSetXString, [:pointer, :pointer, :pointer, :uint, :pointer], :int],
      [:snc_key_to_name, :RfcSNCKeyToName, [:pointer, :pointer, :uint, :pointer, :uint, :pointer], :int],
      [:snc_name_to_key, :RfcSNCNameToKey, [:pointer, :pointer, :pointer, :pointer, :pointer], :int],
      [:start_server, :RfcStartServer, [:int, :pointer, :pointer, :uint, :pointer], :pointer],
      [:submit_transaction, :RfcSubmitTransaction, [:pointer, :pointer], :int],
      [:utf8_to_sapuc, :RfcUTF8ToSAPUC, [:pointer, :uint, :pointer, :pointer, :pointer, :pointer], :int]
  ].each { |funcsig|
    attach_function(funcsig[0], funcsig[1], funcsig[2], funcsig[3], :blocking => true)
  }

  # Take Hash of connection parameters and returns FFI pointer to an array
  # for passing to connection
  # ---
  # TODO - Ideally, this method should live in nwrfc.rb
  def NWRFCLib.make_conn_params(params) #https://github.com/ffi/ffi/wiki/Structs
    par = FFI::MemoryPointer.new(RFCConnParam, params.length)
    pars = params.length.times.collect do |i|
      RFCConnParam.new(par + i * RFCConnParam.size)
    end
    #TODO Optimize this method
    tpar = params.to_a
    params.length.times do |n|
      #      str = (tpar[n][0].to_s + "\0").encode("UTF-16LE")
      pars[n][:name] = FFI::MemoryPointer.from_string(tpar[n][0].to_s.cU)
      #      str = (tpar[n][1].to_s + "\0").encode("UTF-16LE")
      #      str = str.encode("UTF-16LE")
      pars[n][:value] = FFI::MemoryPointer.from_string(tpar[n][1].to_s.cU)
    end
    par
  end

end
