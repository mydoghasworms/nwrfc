module NWRFC
  
  class NWError < Exception

    attr_reader :code, :group, :message, :class, :type, :number

    # Instantiate Error object with a handle to an FFI::MemoryPointer
    # to an NWRFCLib::RFCError object. The error object is analyzed so that
    # when the caller intercepts it with Rescue, all the error details are
    # available
    def initialize(error)
      @code =    NWRFCLib::RFC_RC[error[:code]]
      @group =   NWRFCLib::RFC_ERROR_GROUP[error[:group]]
      @message = error[:message].get_str
      @type =    error[:abapMsgType].get_str
      @number =  error[:abapMsgNumber].get_str
    end

    def inspect
      "#{@message} (code #{@code}, group #{@group}, type #{@type}, number #{@number})"
    end

  end

end