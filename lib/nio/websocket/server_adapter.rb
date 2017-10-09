module NIO
  module WebSocket
    class ServerAdapter
      def initialize(io, options)
        @inner = io
        @options = options
      end
      attr_reader :inner, :options
      def write(data)
        inner.write data
      end
    end
  end
end
