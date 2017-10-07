require 'nio/websocket/version'
require 'websocket/driver'
require 'nio/websocket/client_adapter'
require 'nio/websocket/server_adapter'
require 'nio'
require 'socket'
require 'uri'
require 'openssl'

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
      driver = WebSocket::Driver.client(io, options[:websocket_options])
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
          io = SERVER_ADAPTER.new(io, options)
          driver = WebSocket::Driver.server(io, options[:websocket_options])
          yield driver, io if block_given?
          driver.on :connect do
            driver.start if WebSocket::Driver.websocket? driver.env
          end
          add_to_reactor io.inner, driver
        end
      end
      ensure_reactor
      server
    end

    SERVER_ADAPTER = NIO::WebSocket::ServerAdapter
    CLIENT_ADAPTER = NIO::WebSocket::ClientAdapter
    #
    # End API

    # return an open socket given the url and options
    def self.open_socket(url, options)
      uri = URI(url)
      options[:ssl] ||= %w(https wss).include? uri.scheme
      port = uri.port
      port ||= options[:ssl] ? 443 : 80
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
        @selector.register(io, waiting).value = proc do |monitor|
          waiting = accept_nonblock io
          if waiting == io
            @selector.deregister io
            yield io
          else
            monitor.interests = waiting
          end
        end
      end
      io
    end

    def self.accept_nonblock(io)
      waiting = io.accept_nonblock exception: false
      return io unless [:wait_readable, :wait_writable].include?(waiting)
      case waiting
      when :wait_readable then :r
      when :wait_writable then :w
      end
    end

    # return a TCPServer object listening on the given port with the specified options
    def self.create_server(options)
      options[:address] ? TCPServer(options[:address], options[:port]) : TCPServer.new(options[:port])
    end

    # noop unless ssl options are specified
    def self.upgrade_to_ssl(io, options)
      return io unless options[:ssl]
      OpenSSL::SSL::SSLSocket.new(io)
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
          loop do
            break if @selector
            sleep 0.1
          end
          loop do
            @selector.select { |monitor| monitor.value.call } # put an inner rescue in here so we can distinguish user & nio errors
          end
        rescue
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
