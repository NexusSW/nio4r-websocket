require 'spec_helper'
require 'pp'
require 'timeout'

shared_examples 'Core Tests' do
  subject(:client) { @client }
  subject(:host) { @host }
  it 'Accepts new connections' do
    expect(@client).not_to be_nil
  end
  context 'Client Driver' do
    it 'completes the handshake' do
      complete = false
      @client.ping('wait for it') do
        complete = true
      end
      Timeout.timeout(10) do
        loop do
          break if complete && @host
          sleep 0.1
        end
      end
      expect(complete).to be true
      expect(@host).not_to be nil
    end
    it 'receives a message from the host' do
      expect(@host.text('test text')).not_to eq false
      sleep 1
      expect(@client.last_message).to eq('test text')
    end
    it 'knows how to play ping/pong' do
      ponged = nil
      pinged = @client.ping 'test text' do
        ponged = true
      end
      expect(pinged).not_to eq false
      sleep 1
      expect(ponged).to eq true
    end
  end
  context 'Host Driver' do
    it 'receives a message from the client' do
      expect(@client.text('test text')).not_to eq false
      sleep 1
      expect(@host.last_message).to eq('test text')
    end
    it 'knows how to play ping/pong' do
      ponged = nil
      pinged = @host.ping 'test text' do
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
  def onmessage(msg)
    @last_message = msg
  end
  attr_reader :last_message
end

module WireUp
  def self.connection(driver)
    driver.on :message do |msg|
      driver.onmessage msg.data
    end
    driver
  end
end

describe NIO::WebSocket do
  context 'ws://localhost:8080' do
    before :context do
      NIO::WebSocket.listen address: '127.0.0.1', port: 8080 do |driver|
        @host = WireUp.connection driver
      end
      NIO::WebSocket.connect 'ws://127.0.0.1:8080' do |driver|
        @client = WireUp.connection driver
      end
    end
    include_examples 'Core Tests'
  end
  context 'wss://localhost:8443' do
    before :context do
      key = OpenSSL::PKey::RSA.new 2048
      name = OpenSSL::X509::Name.parse 'CN=nobody/DC=testing'

      cert = OpenSSL::X509::Certificate.new
      cert.version = 2
      cert.serial = 0
      cert.not_before = Time.now
      cert.not_after = Time.now + 3600
      cert.public_key = key.public_key
      cert.subject = name

      cert.issuer = name
      cert.sign key, OpenSSL::Digest::SHA1.new

      NIO::WebSocket.listen port: 8443, ssl: true, ssl_context: { key: key, cert: cert } do |driver|
        @host = WireUp.connection driver
      end
      NIO::WebSocket.connect 'wss://localhost:8443', ssl_context: { verify_mode: OpenSSL::SSL::VERIFY_NONE } do |driver|
        @client = WireUp.connection driver
      end
    end
    include_examples 'Core Tests'
  end
end
