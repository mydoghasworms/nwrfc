module NWRFC

  # Implementation of a server to host RFC functions to be called from an ABAP system
  class Server

    TIMEOUT = 0

    # Register a server with the given gateway and program ID
    def initialize(params)
      raise "Rarameters must be a Hash" unless params.instance_of? Hash
      @rparams = NWRFC.make_conn_params(params)
      raise "Could not create valid pointer from parameters" unless @rparams.instance_of? FFI::MemoryPointer
      @error =  NWRFCLib::RFCError.new
      @handle = NWRFCLib.register_server(@rparams, params.size, @error)
      NWRFC.check_error(@error)
    end


    # Start serving an RFC function, given the definition and the block,
    # to which the connection and functions are yielded
    def serve(function, &block)
      # Establish callback handler
      callback = Proc.new do |connection, function_handle, error|
        function_call = FunctionCall.new(function_handle)
        yield(function_call)
      end
      rc = NWRFCLib.install_server_function(nil, function.desc, callback, @error)
      NWRFC.check_error(@error) if rc > 0

      # Server loop
      while (rc==NWRFCLib::RFC_RC[:RFC_OK] || rc==NWRFCLib::RFC_RC[:RFC_RETRY] || rc==NWRFCLib::RFC_RC[:RFC_ABAP_EXCEPTION])
        rc = NWRFCLib.listen_and_dispatch(@handle, TIMEOUT, @error)
      end
    end

    # Disconnect from the server
    def disconnect
      NWRFCLib.close_connection(@handle, @error)
      NWRFC.check_error(@error)
    end

    alias :close :disconnect

  end
  
end