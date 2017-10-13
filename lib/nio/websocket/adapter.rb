module NIO
  module WebSocket
    class Adapter
      def initialize(io, driver, options)
        @inner = io
        @options = options
        @driver = driver
        @buffer = ''
        @mutex = Mutex.new

        driver.on :close do |ev|
          WebSocket.logger.info "Driver initiated #{inner} close (code #{ev.code}): #{ev.reason}"
          close :driver
        end
        driver.on :error do |ev|
          WebSocket.logger.info "Driver reports error on #{inner}: #{ev.message}"
          close :driver
        end
      end
      attr_reader :inner, :options, :driver, :monitor

      def close(from = nil)
        driver.close unless from == :driver
        @driver = nil # circular reference
        monitor.close
        WebSocket.selector.wakeup
        inner.close
        WebSocket.logger.info "#{inner} closed"
      end

      def add_to_reactor
        @monitor = WebSocket.selector.register(inner, :rw)
        monitor.value = proc do
          data = inner.read_nonblock(16384) if monitor.readable?
          WebSocket.logger.debug { "Incoming data on #{inner}:\n#{data}" } if data && WebSocket.log_traffic?
          driver.parse data if data
          pump_buffer if monitor.writable?
        end
        WebSocket.ensure_reactor
      end

      def write(data)
        @mutex.synchronize do
          @buffer << data
        end
        return unless monitor
        monitor.interests = :rw
        WebSocket.selector.wakeup
        pump_buffer
      end

      def pump_buffer
        @mutex.synchronize do
          written = 0
          begin
            written = inner.write_nonblock @buffer unless @buffer.empty?
            WebSocket.logger.debug { "Pumped #{written} bytes of data from buffer to #{inner}:\n#{@buffer}" } unless @buffer.empty? || !WebSocket.log_traffic?
            @buffer.slice!(0, written) if written > 0
            WebSocket.logger.debug { "The buffer is now:\n#{@buffer}" } unless @buffer.empty? || !WebSocket.log_traffic?
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
