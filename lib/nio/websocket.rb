require 'nio/websocket/version'
require 'websocket/driver'
require 'nio'
require 'socket'
require 'uri'
require 'openssl'
require 'logger'
require 'nio/websocket/adapter/client'
require 'nio/websocket/adapter/server'

module NIO
  module WebSocket
    # API
    #
    # create and return a websocket client that communicates either over the given IO object (upgrades the connection),
    # or we'll create a new connection to url if io is not supplied
    # url is required, regardless, for wrapped WebSocket::Driver HTTP Header generation
    def self.connect(url, options = {}, io = nil)
      io ||= open_socket(url, options)
      adapter = NIO::WebSocket::Adapter::Client.new(url, io, options)
      yield(adapter.driver, adapter)
      logger.info "Client #{io} connected to #{url}"
      adapter.driver
    end

    def self.listen(options = {}, server = nil)
      server ||= create_server(options)
      connect_monitor = selector.register(server, :r)
      connect_monitor.value = proc do
        accept_socket server, options do |io| # this next block won't run until ssl (if enabled) has started
          adapter = NIO::WebSocket::Adapter::Server.new(io, options)
          yield(adapter.driver, adapter)
          logger.info "Host accepted client connection #{io} on port #{options[:port]}"
        end
      end
      ensure_reactor
      logger.info 'Host listening for new connections on port ' + options[:port].to_s
      server
    end

    SERVER_ADAPTER = NIO::WebSocket::Adapter::Server
    CLIENT_ADAPTER = NIO::WebSocket::Adapter::Client

    def self.logger
      @logger ||= Logger.new(STDERR, level: :error)
    end

    def self.logger=(logger)
      @logger = logger
    end
    #
    # End API

    def self.selector
      @selector ||= NIO::Selector.new
    end

    # return an open socket given the url and options
    def self.open_socket(url, options)
      uri = URI(url)
      options[:ssl] = %w(https wss).include? uri.scheme unless options.key? :ssl
      port = uri.port || (options[:ssl] ? 443 : 80) # redundant?  test uri.port if port is unspecified but because ws: & wss: aren't default protocols we'll maybe still need this(?)
      logger.debug "Opening Connection to #{uri.hostname} on port #{port}"
      io = TCPSocket.new uri.hostname, port
      return io unless options[:ssl]
      logger.debug "Upgrading Connection #{io} to ssl"
      io = upgrade_to_ssl(io, options).connect
      logger.info "Connection #{io} upgraded to ssl"
      io
    end

    # supply a block to run after protocol negotiation
    def self.accept_socket(server, options)
      waiting = accept_nonblock server
      if [:r, :w].include? waiting
        logger.warn 'Expected to receive new connection, but the server is not quite ready'
        return
      end
      logger.debug "Receiving new connection #{waiting} on port #{options[:port]}"
      if options[:ssl]
        logger.debug "Upgrading Connection #{waiting} to ssl"
        io = upgrade_to_ssl(waiting, options)
        try_accept_nonblock io do
          logger.info "Connection #{io} upgraded to ssl"
          yield io
        end
      else
        yield waiting
      end
    end

    def self.try_accept_nonblock(io)
      waiting = accept_nonblock io
      if [:r, :w].include? waiting
        monitor = selector.register(io, :rw)
        monitor.value = proc do
          waiting = accept_nonblock io # just because nio says it's not e.g. 'writable' doesn't mean we don't have something to read & vice versa & but what about spin cases?
          if [:r, :w].include? waiting
            monitor.interests = :rw
          else
            monitor.close
            yield waiting
          end
        end
      else
        yield waiting
      end
    end

    def self.accept_nonblock(io)
      return io.accept_nonblock
    rescue IO::WaitReadable
      return :r
    rescue IO::WaitWritable
      return :w
    end

    # return a TCPServer object listening on the given port with the specified options
    def self.create_server(options)
      options[:address] ? TCPServer.new(options[:address], options[:port]) : TCPServer.new(options[:port])
    end

    # noop unless ssl options are specified
    def self.upgrade_to_ssl(io, options)
      return io unless options[:ssl]
      ctx = OpenSSL::SSL::SSLContext.new
      (options[:ssl_context] || {}).each do |k, v|
        ctx.send "#{k}=", v if ctx.respond_to? k
      end
      OpenSSL::SSL::SSLSocket.new(io, ctx)
    end

    def self.ensure_reactor
      last_reactor_error_time = Time.now - 1
      last_reactor_error_count = 0
      @reactor ||= Thread.start do
        begin
          Thread.current.abort_on_exception = true
          loop do
            break if selector
            sleep 0.1
          end
          loop do
            selector.select do |monitor|
              begin
                monitor.value.call # force proc usage - no other pattern support
              rescue => e
                logger.error "Error occured in callback on socket #{monitor.io}.  No longer handling this connection."
                logger.error e.message
                e.backtrace.drop(1).map { |s| logger.error "\t#{s}" }
                monitor.close # protect global loop from being crashed by a misbehaving driver, or a sloppy disconnect
              end
            end
          end
        rescue => e
          logger.fatal 'Error occured in reactor subsystem.  Trying again.'
          logger.fatal e.message
          e.backtrace.drop(1).map { |s| logger.fatal "\t#{s}" }
          last_reactor_error_count = 0 if last_reactor_error_time + 1 <= Time.now
          last_reactor_error_time = Time.now
          last_reactor_error_count += 1
          sleep 0.1
          retry if last_reactor_error_count <= 5
          raise
        end
      end
    end

    def self.reset
      logger.info 'Resetting reactor subsystem'
      @selector = nil
      return unless @reactor
      @reactor.exit
      @reactor = nil
    end
  end
end
