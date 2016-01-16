# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'crawling/version'

Gem::Specification.new do |spec|
  spec.name          = "crawling"
  spec.version       = Crawling::VERSION
  spec.authors       = ["James Pike"]
  spec.email         = ["github@chilon.net"]

  spec.summary       = %q{Tool to manage personal configuration and environment files.}
  spec.description   = spec.summary
  spec.homepage      = "http://github.com/ohjames/crawling"
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org by setting 'allowed_push_host', or
  # delete this section to allow pushing this gem to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  else
    raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "bin"
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.9"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec"

  spec.add_dependency "moister", "~> 0.2"
  spec.add_dependency "diffy", "~> 3.1.0"
end
