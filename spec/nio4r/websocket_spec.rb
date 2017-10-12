require 'spec_helper'
require 'timeout'

shared_examples 'Core Tests' do
  subject(:client) { WireUp.client }
  subject(:host) { WireUp.host }
  it 'Accepts new connections' do
    expect(client).not_to be_nil
  end
  context 'Client Driver' do
    it 'completes the handshake' do
      complete = false
      client.ping('wait for it') do
        complete = true
      end
      Timeout.timeout(10) do
        loop do
          break if complete && host
          sleep 0.1
        end
      end
      expect(complete).to be true
      expect(host).not_to be nil
    end
    it 'receives a message from the host' do
      expect(host.text('host test msg')).not_to eq false
      sleep 1
      expect(client.last_message).to eq('host test msg')
    end
    it 'knows how to play ping/pong' do
      ponged = nil
      pinged = client.ping('test text') do
        ponged = true
      end
      expect(pinged).not_to eq false
      sleep 1
      expect(ponged).to eq true
    end
  end
  context 'Host Driver' do
    it 'receives a message from the client' do
      expect(client.text('client test msg')).not_to eq false
      sleep 1
      expect(host.last_message).to eq('client test msg')
    end
    it 'knows how to play ping/pong' do
      ponged = nil
      pinged = host.ping('test text') do
        ponged = true
      end
      expect(pinged).not_to eq false
      sleep 1
      expect(ponged).to eq true
    end
  end
  after :context do
    NIO::WebSocket.reset
  end
end

class ::WebSocket::Driver
  def test_onmessage(msg)
    @last_message = msg
  end
  attr_reader :last_message
end

module WireUp
  def self.connection(test_driver)
    test_driver.on :message do |msg|
      test_driver.test_onmessage msg.data
    end
    test_driver
  end

  def self.add_host(host_driver)
    @host = connection(host_driver)
    host
  end

  def self.host
    @host
  end

  def self.add_client(client_driver)
    @client = connection(client_driver)
    client
  end

  def self.client
    @client
  end
end

NIO::WebSocket.logger.level = :debug
describe NIO::WebSocket do
  context 'ws://localhost:8080' do
    before :context do
      NIO::WebSocket.listen port: 8080 do |host|
        WireUp.add_host host
      end
      NIO::WebSocket.connect 'ws://localhost:8080' do |client|
        WireUp.add_client client
      end
    end
    include_examples 'Core Tests'
  end
  # context 'wss://localhost:8443' do
  #   before :context do
  #     retry_count = 3
  #     begin
  #       key = OpenSSL::PKey::RSA.new 2048
  #     rescue OpenSSL::PKey::RSAError
  #       retry_count -= 1
  #       retry if retry_count > 0
  #       raise
  #     end

  #     name = OpenSSL::X509::Name.parse 'CN=nobody/DC=testing'

  #     cert = OpenSSL::X509::Certificate.new
  #     cert.version = 2
  #     cert.serial = 0
  #     cert.not_before = Time.now
  #     cert.not_after = Time.now + 3600
  #     cert.public_key = key.public_key
  #     cert.subject = name

  #     cert.issuer = name
  #     cert.sign key, OpenSSL::Digest::SHA1.new

  #     NIO::WebSocket.listen port: 8443, ssl_context: { key: key, cert: cert } do |driver|
  #       @host = WireUp.connection driver
  #     end
  #     NIO::WebSocket.connect 'wss://localhost:8443', ssl_context: { verify_mode: OpenSSL::SSL::VERIFY_NONE } do |driver|
  #       @client = WireUp.connection driver
  #     end
  #   end
  #   include_examples 'Core Tests'
  # end
end
