require 'nio/websocket/adapter'

module NIO
  module WebSocket
    class Adapter
      class Server < Adapter
        def initialize(io, options)
          driver = ::WebSocket::Driver.server(self, options[:websocket_options] || {})
          driver.on :connect do
            if ::WebSocket::Driver.websocket? driver.env
              driver.start
              WebSocket.logger.debug 'driver connected'
            end
          end
          super io, driver, options
        end
      end
    end
  end
end
