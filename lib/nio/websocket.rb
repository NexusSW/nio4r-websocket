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
      @selector ||= NIO::Selector.new
      io = CLIENT_ADAPTER.new(url, io, options, @selector)
      driver = ::WebSocket::Driver.client(io, options[:websocket_options] || {})
      yield driver, io if block_given?
      driver.start
      add_to_reactor io.inner, driver
      driver
    end

    def self.listen(options = {}, server = nil)
      server ||= create_server(options)
      @selector ||= NIO::Selector.new
      @selector.register(server, :r).value = proc do
        accept_socket server, options do |io| # this next block won't run until ssl (if enabled) has started
          io = SERVER_ADAPTER.new(io, options, @selector)
          driver = ::WebSocket::Driver.server(io, options[:websocket_options] || {})
          yield driver, io if block_given?
          driver.on :connect do
            driver.start if ::WebSocket::Driver.websocket? driver.env
          end
          add_to_reactor io.inner, driver
        end
      end
      ensure_reactor
      server
    end

    SERVER_ADAPTER = NIO::WebSocket::Adapter::Server
    CLIENT_ADAPTER = NIO::WebSocket::Adapter::Client
    #
    # End API

    # return an open socket given the url and options
    def self.open_socket(url, options)
      uri = URI(url)
      options[:ssl] = %w(https wss).include? uri.scheme unless options.key? :ssl
      port = uri.port || (options[:ssl] ? 443 : 80) # redundant?  test uri.port if port is unspecified but because ws: & wss: aren't default protocols we'll maybe still need this(?)
      io = TCPSocket.new uri.hostname, port
      return io unless options[:ssl]
      upgrade_to_ssl(io, options).connect
    end

    # return an open socket from the server given options
    # ssl negotiation may not be immediately completed if enabled
    # supply a block to run after negotiation
    def self.accept_socket(server, options)
      io = server.accept
      unless options[:ssl]
        yield io
        return io
      end
      io = upgrade_to_ssl(io, options)
      waiting = accept_nonblock io
      if waiting == io
        yield io
      else
        monitor = @selector.register(io, waiting)
        monitor.value = proc do
          waiting = accept_nonblock io
          if waiting == io
            monitor.close
            yield io
          else
            monitor.interests = waiting
          end
        end
      end
      io
    end

    def self.accept_nonblock(io)
      return io if io.accept_nonblock
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
      @selector ||= NIO::Selector.new
      @selector.register(io, :r).value = proc do
        driver.parse io.read_nonblock(16384)
      end
      ensure_reactor
    end

    def self.ensure_reactor
      @reactor ||= Thread.start do
        begin
          Thread.abort_on_exception = true
          loop do
            break if @selector
            sleep 0.1
          end
          loop do
            @selector.select do |monitor|
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
