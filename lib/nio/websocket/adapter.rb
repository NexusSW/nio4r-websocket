module NIO
  module WebSocket
    class Adapter
      def initialize(io, options)
        @inner = io
        @options = options
        @buffer = ''
      end
      attr_reader :inner, :options
      attr_accessor :monitor

      def write(data)
        @buffer << data
        monitor.add_interest :w
        pump_buffer
      end

      def pump_buffer
        @mutex ||= Mutex.new
        @mutex.synchronize do
          written = 0
          begin
            written = inner.write_nonblock @buffer unless @buffer.empty?
            @buffer.slice!(0, written) if written > 0
          rescue IO::WaitWritable
            return written
          ensure
            monitor.interests = @buffer.empty? ? :r : :rw
          end
          written
        end
      end
    end
  end
end
