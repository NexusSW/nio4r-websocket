require 'nio/websocket/version'
require 'websocket/driver'
require 'nio/websocket/adapter/client'
require 'nio/websocket/adapter/server'
require 'nio'
require 'socket'
require 'uri'
require 'openssl'
require 'pp'

module NIO
  module WebSocket
    # API
    #
    # create and return a websocket client that communicates either over the given IO object (upgrades the connection),
    # or we'll create a new connection to url if io is not supplied
    # url is required, regardless, for wrapped WebSocket::Driver HTTP Header generation
    def self.connect(url, options = {}, io = nil)
      io ||= open_socket(url, options)
      io = CLIENT_ADAPTER.new(url, io, options)
      driver = ::WebSocket::Driver.client(io, options[:websocket_options] || {})
      yield driver, io if block_given?
      add_to_reactor io, driver
      driver.start
      driver
    end

    def self.listen(options = {}, server = nil)
      server ||= create_server(options)
      connect_monitor = selector.register(server, :r)
      connect_monitor.value = proc do
        accept_socket server, options do |io| # this next block won't run until ssl (if enabled) has started
          io = SERVER_ADAPTER.new(io, options)
          driver = ::WebSocket::Driver.server(io, options[:websocket_options] || {})
          yield driver, io if block_given?
          driver.on :connect do
            pp 'driver connected'
            driver.start if ::WebSocket::Driver.websocket? driver.env
          end
          add_to_reactor io, driver
        end
      end
      ensure_reactor
      server
    end

    SERVER_ADAPTER = NIO::WebSocket::Adapter::Server
    CLIENT_ADAPTER = NIO::WebSocket::Adapter::Client
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
      io = TCPSocket.new uri.hostname, port
      return io unless options[:ssl]
      upgrade_to_ssl(io, options).connect
    end

    # supply a block to run after protocol negotiation
    def self.accept_socket(server, options)
      waiting = accept_nonblock server
      return if [:r, :w].include? waiting
      if options[:ssl]
        io = upgrade_to_ssl(waiting, options)
        try_accept_nonblock io do
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

    def self.add_to_reactor(io, driver)
      monitor = selector.register(io.inner, :rw)
      io.monitor = monitor
      monitor.value = proc do
        driver.parse io.inner.read_nonblock(16384) if monitor.readable?
        io.pump_buffer if monitor.writable?
      end
      ensure_reactor
    end

    def self.ensure_reactor
      @reactor ||= Thread.start do
        begin
          Thread.abort_on_exception = true
          loop do
            break if selector
            sleep 0.1
          end
          loop do
            selector.select do |monitor|
              begin
                monitor.value.call # force proc usage - no other pattern support
              rescue => e
                pp 'driver error', e, e.backtrace
                monitor.close # protect global loop from being crashed by a misbehaving driver, or a sloppy disconnect
              end
            end
          end
        rescue => e
          pp 'reactor error', e, e.backtrace
          sleep 0.1 # TODO: need to add debugging/logging logic here - but don't spin out a whole core in the meantime
          retry
        end
      end
    end

    def self.reset
      @selector = nil
      return unless @reactor
      @reactor.exit
      @reactor = nil
    end
  end
end
