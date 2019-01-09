require "nio/websocket/raw_adapter"

module NIO
  module WebSocket
    class Adapter
      class Proxy
        def initialize(srv, client, options)
          @srv_adapter = ProxyAdapter.new srv, options do |data|
            client_adapter.write data
          end
          @client_adapter = ProxyAdapter.new client, options do |data|
            srv_adapter.write data
          end
          WebSocket.logger.debug "Initiating proxy connection between #{srv} and #{client}"
        end
        attr_reader :srv_adapter, :client_adapter

        def add_to_reactor
          srv_adapter.add_to_reactor
          client_adapter.add_to_reactor
        end
      end

      class ProxyAdapter < RawAdapter
        def initialize(io, options, &block)
          super io, options
          @read_event = block
        end

        def read
          super do |data|
            @read_event.call data
          end
        end
      end
    end
  end
end
