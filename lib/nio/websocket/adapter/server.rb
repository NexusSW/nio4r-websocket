require 'nio/websocket/adapter'

module NIO
  module WebSocket
    class Adapter
      class Server < Adapter
        def initialize(io, options, selector)
          super
        end
      end
    end
  end
end
