module NIO
  module WebSocket
    class ClientAdapter
      def initialize(url, io, options)
        @url = url
        @inner = io
        @options = options
      end
      attr_reader :url, :inner, :options
      def write(data)
        inner.write(data)
      end
    end
  end
end
