require 'nio/websocket/adapter'

module NIO
  module WebSocket
    class Adapter
      class Client < Adapter
        def initialize(url, io, options, selector)
          super io, options, selector
          @url = url
        end
        attr_reader :url
      end
    end
  end
end
