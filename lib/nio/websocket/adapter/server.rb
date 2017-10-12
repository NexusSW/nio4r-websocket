require 'nio/websocket/adapter'

module NIO
  module WebSocket
    class Adapter
      class Server < Adapter
        def initialize(io, options)
          driver = ::WebSocket::Driver.server(self, options[:websocket_options] || {})
          super io, driver, options

          driver.on :connect do
            if ::WebSocket::Driver.websocket? driver.env
              driver.start
              WebSocket.logger.debug 'driver connected'
            end
          end
        end
      end
    end
  end
end
