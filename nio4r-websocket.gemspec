# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'nio/websocket/version'

Gem::Specification.new do |spec|
  spec.name          = 'nio4r-websocket'
  spec.version       = NIO::WebSocket::VERSION
  spec.authors       = ['Sean Zachariasen']
  spec.email         = ['thewyzard@hotmail.com']

  spec.summary       = 'websocket-driver implementation built over nio4r'
  spec.homepage      = 'https://github.com/nexussw/nio4r-websocket'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split('\x0').reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'nio4r'
  spec.add_dependency 'websocket-driver'

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
end
