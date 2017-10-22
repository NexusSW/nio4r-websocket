require 'nio/websocket/version'
require 'websocket/driver'
require 'nio'
require 'socket'
require 'uri'
require 'openssl'
require 'logger'
require 'nio/websocket/reactor'
require 'nio/websocket/adapter/client'
require 'nio/websocket/adapter/server'

module NIO
  module WebSocket
    class << self
      # Returns the current logger, or creates one at level ERROR if one has not been assigned
      # @return [Logger] the current logger instance
      def logger
        @logger ||= begin
        logger = Logger.new(STDERR, progname: 'WebSocket', level: Logger::ERROR)
        logger.level = Logger::ERROR
        logger
      end
      end

      attr_writer :logger

      # Should raw traffic be logged through the logger?  Disabled by default for security reasons
      # @param enable [Boolean]
      def log_traffic=(enable)
        @log_traffic = enable
        logger.level = Logger::DEBUG if enable
        enable
      end

      # Should raw traffic be logged through the logger?  Disabled by default for security reasons
      def log_traffic?
        @log_traffic
      end

      # Create and return a websocket client that communicates either over the given IO object (upgrades the connection),
      # or we'll create a new connection to url if io is not supplied
      # @param [String] url ws:// or wss:// location to connect
      # @param [Hash] options
      # @param [IO] io (DI) raw IO object to use in lieu of opening a new connection to url
      # @option options [Hash] :websocket_options Hash to pass to the ::WebSocket::Driver.client
      # @option options [Hash] :ssl_context Hash from which to create the OpenSSL::SSL::SSLContext object
      # @yield [::WebSocket::Driver]
      # @return [::WebSocket::Driver]
      def connect(url, options = {}, io = nil)
        io ||= open_socket(url, options)
        adapter = CLIENT_ADAPTER.new(url, io, options)
        yield(adapter.driver, adapter) if block_given?
        Reactor.queue_task do
          adapter.add_to_reactor
        end
        Reactor.start
        logger.info "Client #{io} connected to #{url}"
        adapter.driver
      end

      # Start handling new connections, passing each through the supplied block
      # @param [Hash] options
      # @param server [TCPServer] (DI) TCPServer-like object to use in lieu of starting a new server
      # @option options [Integer] :port required: Port on which to listen for incoming connections
      # @option options [String] :address optional: Specific Address on which to bind the TCPServer
      # @option options [Hash] :websocket_options Hash to pass to the ::WebSocket::Driver.server
      # @option options [Hash] :ssl_context Hash from which to create the OpenSSL::SSL::SSLContext object
      # @yield [::WebSocket::Driver]
      # @return server, as passed in, or a new TCPServer if no server was specified
      def listen(options = {}, server = nil)
        server ||= create_server(options)
        Reactor.queue_task do
          monitor = Reactor.selector.register(server, :r)
          monitor.value = proc do
            accept_socket server, options do |io| # this next block won't run until ssl (if enabled) has started
              adapter = SERVER_ADAPTER.new(io, options)
              yield(adapter.driver, adapter) if block_given?
              Reactor.queue_task do
                adapter.add_to_reactor
              end
              logger.info "Host accepted client connection #{io} on port #{options[:port]}"
            end
          end
        end
        Reactor.start
        logger.info 'Host listening for new connections on port ' + options[:port].to_s
        server
      end

      SERVER_ADAPTER = NIO::WebSocket::Adapter::Server
      CLIENT_ADAPTER = NIO::WebSocket::Adapter::Client

      # Resets this API to a fresh state
      def reset
        logger.info 'Resetting reactor subsystem'
        Reactor.reset
      end

      # @!endgroup

      private

      # return an open socket given the url and options
      def open_socket(url, options)
        uri = URI(url)
        port = uri.port || (uri.scheme == 'wss' ? 443 : 80) # redundant?  test uri.port if port is unspecified but because ws: & wss: aren't default protocols we'll maybe still need this(?)
        logger.debug "Opening Connection to #{uri.hostname} on port #{port}"
        io = TCPSocket.new uri.hostname, port
        return io unless uri.scheme == 'wss'
        logger.debug "Upgrading Connection #{io} to ssl"
        ssl = upgrade_to_ssl(io, options).connect
        logger.info "Connection #{io} upgraded to #{ssl}"
        ssl
      end

      def create_server(options)
        options[:address] ? TCPServer.new(options[:address], options[:port]) : TCPServer.new(options[:port])
      end

      # supply a block to run after protocol negotiation
      def accept_socket(server, options)
        waiting = accept_nonblock server
        if [:r, :w].include? waiting
          logger.warn 'Expected to receive new connection, but the server is not quite ready'
          return
        end
        logger.debug "Receiving new connection #{waiting} on port #{options[:port]}"
        if options[:ssl_context]
          logger.debug "Upgrading Connection #{waiting} to ssl"
          ssl = upgrade_to_ssl(waiting, options)
          try_accept_nonblock ssl do
            logger.info "Incoming connection #{waiting} upgraded to #{ssl}"
            yield ssl
          end
        else
          yield waiting
        end
      end

      def try_accept_nonblock(io)
        waiting = accept_nonblock io
        if [:r, :w].include? waiting
          # Only happens on server side ssl negotiation
          Reactor.queue_task do
            monitor = Reactor.selector.register(io, :rw)
            monitor.value = proc do
              waiting = accept_nonblock io
              unless [:r, :w].include? waiting
                monitor.close
                yield waiting
              end
            end
          end
        else
          yield waiting
        end
      end

      def accept_nonblock(io)
        return io.accept_nonblock
      rescue IO::WaitReadable
        return :r
      rescue IO::WaitWritable
        return :w
      end

      def upgrade_to_ssl(io, options)
        store = OpenSSL::X509::Store.new
        store.set_default_paths
        ctx = OpenSSL::SSL::SSLContext.new
        { cert_store: store, verify_mode: OpenSSL::SSL::VERIFY_PEER }.merge(options[:ssl_context] || {}).each do |k, v|
          ctx.send "#{k}=", v if ctx.respond_to? k
        end
        OpenSSL::SSL::SSLSocket.new(io, ctx)
      end
    end
  end
end
