require "nio/websocket/adapter"

module NIO
  module WebSocket
    class Adapter
      class Proxy < Adapter
        def initialize(url, io, options)
          @url = url
          driver = ::WebSocket::Driver.client(self, options[:websocket_options] || {})
          super io, driver, options
          WebSocket.logger.debug "Initiating handshake on #{io}"
          driver.start
        end
        attr_reader :url
      end
    end
  end
end
