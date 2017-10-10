require 'nio/websocket/adapter'

module NIO
  module WebSocket
    class Adapter
      class Client < Adapter
        def initialize(url, io, options)
          super io, options
          @url = url
        end
        attr_reader :url
      end
    end
  end
end
