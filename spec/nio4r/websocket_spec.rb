require 'spec_helper'
require 'pp'

shared_examples 'Core Tests' do
  it 'Listens for new connections' do
    expect(@host).not_to be_nil
    expect(@client).not_to be_nil
  end
end

describe NIO::WebSocket do
  context 'ws://localhost:8080' do
    before :context do
      NIO::WebSocket.listen address: '127.0.0.1', port: 8080 do |driver|
        @host = driver
      end
      NIO::WebSocket.connect 'ws://localhost:8080' do |driver|
        driver.on :connect do
          driver.ping
        end
        driver.on :pong do |msg|
          pp 'ponged', msg
        end
        @client = driver
      end
    end
    subject(:client) { @client }
    subject(:host) { @host }
    after :context do
      NIO::WebSocket.reset
    end
    include_examples 'Core Tests'
  end
end
