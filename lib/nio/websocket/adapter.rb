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
          WebSocket.logger.error "Driver reports error on #{inner}: #{ev.message}"
          close :driver
        end
      end
      attr_reader :inner, :options, :driver, :monitor

      def teardown
        @driver = nil # circular reference
        monitor.close
        inner.close
      end

      def close(from = nil)
        return false if @closing

        driver.close if from.nil?
        @closing = true
        monitor.interests = :rw
        WebSocket.selector.wakeup
        true
      end

      def add_to_reactor
        WebSocket.selector.wakeup
        @monitor = WebSocket.selector.register(inner, :rw) # This can block if this is the main thread and the reactor is busy
        monitor.value = proc do
          begin
            read if monitor.readable?
            pump_buffer if monitor.writable?
          rescue Errno::ECONNRESET, EOFError
            driver.force_state :closed
            driver.emit :io_error
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
        WebSocket.ensure_reactor
      end

      def read
        data = inner.read_nonblock(16384)
        if data
          WebSocket.logger.debug { "Incoming data on #{inner}:\n#{data}" } if WebSocket.log_traffic?
          driver.parse data
        end
        data
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
            @buffer = @buffer.byteslice(written..-1) if written > 0
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

class ::WebSocket::Driver
  def force_state(newstate)
    @ready_state = STATES.index newstate
  end
end
