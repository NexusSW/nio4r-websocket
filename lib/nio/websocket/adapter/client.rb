require 'nio/websocket/adapter'

module NIO
  module WebSocket
    class Adapter
      class Client < Adapter
        def initialize(url, io, options)
          @url = url
          driver = ::WebSocket::Driver.client(self, options[:websocket_options] || {})
          super io, driver, options
          driver.start
        end
        attr_reader :url
      end
    end
  end
end
