module NIO
  module WebSocket
    class RawAdapter
      def initialize(io, options)
        @inner = io
        @options = options
        @buffer = ""
        @mutex = Mutex.new
      end
      attr_reader :inner, :options, :monitor, :closing

      def teardown
        monitor.close
        inner.close
      end

      def close
        return false if @closing

        @closing = true
        monitor.interests = :rw
        Reactor.selector.wakeup
        true
      end

      def add_to_reactor
        @monitor = Reactor.selector.register(inner, :rw) # This can block if this is the main thread and the reactor is busy
        monitor.value = proc do
          begin
            read if monitor.readable?
            pump_buffer if monitor.writable?
          rescue Errno::ECONNRESET, EOFError, Errno::ECONNABORTED
            teardown
            WebSocket.logger.info "#{inner} socket closed"
          rescue IO::WaitReadable # rubocop:disable Lint/HandleExceptions
          rescue IO::WaitWritable
            monitor.interests = :rw
          end
          if @closing
            if !monitor.readable? && @buffer.empty?
              teardown
              WebSocket.logger.info "#{inner} closed"
            else
              monitor.interests = :rw unless monitor.closed? # keep the :w interest so that our block runs each time
              # edge case: if monitor was readable this time, and the write buffer is empty, if we emptied the read buffer this time our block wouldn't run again
            end
          end
        end
      end

      def read
        data = inner.read_nonblock(16384)
        if data
          WebSocket.logger.debug { "Incoming data on #{inner}:\n#{data}" } if WebSocket.log_traffic?
          yield data if block_given?
        end
        data
      end

      def write(data)
        @mutex.synchronize do
          @buffer << data
        end
        return unless monitor
        pump_buffer
        Reactor.selector.wakeup unless monitor.interests == :r
      end

      def pump_buffer
        @mutex.synchronize do
          written = 0
          begin
            written = inner.write_nonblock @buffer unless @buffer.empty?
            WebSocket.logger.debug { "Pumped #{written} bytes of data from buffer to #{inner}:\n#{@buffer}" } unless @buffer.empty? || !WebSocket.log_traffic?
            @buffer = @buffer.byteslice(written..-1) if written > 0
            WebSocket.logger.debug { "The buffer is now:\n#{@buffer}" } unless @buffer.empty? || !WebSocket.log_traffic?
          rescue IO::WaitWritable, IO::WaitReadable
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
