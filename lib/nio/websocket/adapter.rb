module NIO
  module WebSocket
    class Adapter
      def initialize(io, options)
        @inner = io
        @options = options
        @buffer = ''
        @mutex = Mutex.new
      end
      attr_reader :inner, :options
      attr_accessor :monitor

      def write(data)
        @mutex.synchronize do
          @buffer << data
        end
        monitor.interests = :rw
        monitor.selector.wakeup
        pump_buffer
      end

      def pump_buffer
        @mutex.synchronize do
          written = 0
          begin
            written = inner.write_nonblock @buffer unless @buffer.empty?
            WebSocket.logger.debug { "Pumped #{written} bytes of data from buffer on #{inner}:\n#{@buffer}" } unless @buffer.empty?
            @buffer.slice!(0, written) if written > 0
            WebSocket.logger.debug "The buffer is now:\n#{@buffer}" unless @buffer.empty?
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
