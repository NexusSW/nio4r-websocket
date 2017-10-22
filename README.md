# NIO::WebSocket [![Build Status](https://travis-ci.org/NexusSW/nio4r-websocket.svg?branch=master)](https://travis-ci.org/NexusSW/nio4r-websocket) [![Dependency Status](https://gemnasium.com/badges/github.com/NexusSW/nio4r-websocket.svg)](https://gemnasium.com/github.com/NexusSW/nio4r-websocket)

[![Maintainability](https://api.codeclimate.com/v1/badges/cce01221d575804b09f5/maintainability)](https://codeclimate.com/github/NexusSW/nio4r-websocket/maintainability) [![Test Coverage](https://api.codeclimate.com/v1/badges/cce01221d575804b09f5/test_coverage)](https://codeclimate.com/github/NexusSW/nio4r-websocket/test_coverage) [![Gem Version](https://badge.fury.io/rb/nio4r-websocket.svg)](https://badge.fury.io/rb/nio4r-websocket)

This gem ties websocket-driver, a transport agnostic WebSockets library, together with a nio4r driven socket implementation.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'nio4r-websocket'
```

And then execute:

    bundle

Or install it yourself as:

    gem install nio4r-websocket

## Usage

[YARD Documentation](http://www.rubydoc.info/gems/nio4r-websocket/)

The only usage patterns introduced by this module are in how to instantiate 'websocket-driver' objects.  Please refer to their documentation at <https://github.com/faye/websocket-driver-ruby#driver-api> on how to use them.

Additionally, the WebSocket driver object will emit an `:io_error` event.  In the case that the underlying IO object gets disconnected, or otherwise closed without completing the `WebSocket::Driver#close` mechanism, you will be notified via subscribing to `:io_error` like:

```ruby
driver.on :io_error do
  # some cleanup logic
  # `driver.on :close` may or may not be called - likely not
end
```

### Examples

`require 'nio/websocket'`

Client:

```ruby
NIO::WebSocket.connect 'wss://example.com/' do |driver|
  driver.on :message do |event|
    puts event.data
  end
  ... other wireup code (refer to 'websocket-driver' documentation)
end
```

Server:

```ruby
NIO::WebSocket.listen port:443, ssl_context: { key: openssl_pkey_rsa_obj, cert: x509_cert_obj } do |driver|
  driver.on :message do |event|
    puts event.data
  end
  ... other wireup code (refer to 'websocket-driver' documentation)
end
```

> Note: The above server block (`listen`) is executed on a per-connection basis

### Options

`NIO::WebSocket.listen` accepts `port:` and `address:` options.  Port is required, but address is optional for if you care to bind to a specific IP address on your host.

Both `listen` and `NIO::WebSocket.connect` accept `websocket_options:` which is passed to the corresponding 'websocket-driver' calls.  Additionally, `ssl_context:` is available if you care to enable and customize your SSL experience.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at <https://github.com/NexusSW/nio4r-websocket>.  Ensure that you sign off on all of your commits.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
