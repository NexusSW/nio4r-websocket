module NIO
  module WebSocket
    class Adapter
      def initialize(io, options)
        @inner = io
        @options = options
        @buffer = ''
      end
      attr_reader :inner, :options
      def write(data)
        @buffer << data
        written = 0
        begin
          written = inner.write_nonblock @buffer
          @buffer.slice!(0, written) if written > 0
          ensure_monitor unless @buffer.empty?
        rescue IO::WaitWritable
          pp 'setting up write waiting'
          ensure_monitor
        end
      end

      private

      def ensure_monitor
        @monitor ||= WebSocket.add_write_to_reactor inner do
          written = 0
          begin
            written = inner.write_nonblock @buffer unless @buffer.empty?
            @buffer.slice!(0, written) if written > 0
            pp 'stopping write monitor'
            @monitor.interests = :none if @buffer.empty?
          rescue IO::WaitWritable
            pp 'write blocked'
            @monitor.interests = :w
          end
        end
        @monitor.interests = :w
      end
    end
  end
end
