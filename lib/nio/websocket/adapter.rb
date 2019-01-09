require 'nio/websocket/raw_adapter'

module NIO
  module WebSocket
    class Adapter < RawAdapter
      def initialize(io, driver, options)
        @driver = driver

        driver.on :close do |ev|
          WebSocket.logger.info "Driver initiated #{inner} close (code #{ev.code}): #{ev.reason}"
          close :driver
        end
        driver.on :error do |ev|
          WebSocket.logger.error "Driver reports error on #{inner}: #{ev.message}"
          close :driver
        end

        super io, options
      end
      attr_reader :driver

      def teardown
        @driver = nil # circular reference
        super
      end

      def close(from = nil)
        driver.close if from.nil? && !closing
        super()
      end

      def add_to_reactor
        super do
          driver.force_state :closed
          driver.emit :io_error
        end
      end

      def read
        super do |data|
          driver.parse data
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
