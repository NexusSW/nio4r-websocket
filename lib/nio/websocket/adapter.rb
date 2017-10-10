module NIO
  module WebSocket
    class Adapter
      def initialize(io, options, selector)
        @selector = selector
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
