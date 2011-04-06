# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "canonicurl/version"

Gem::Specification.new do |s|
  s.name        = "canonicurl"
  s.version     = Canonicurl::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["David Dai"]
  s.email       = ["david.github@gmail.com"]
  s.homepage    = ""
  s.summary     = %q{A Canonical URL cache using Redis}
  s.description = %q{}

  s.rubyforge_project = "canonicurl"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
  s.add_dependency 'redis', '>= 2.2.0'
  s.add_dependency 'em-http-request', '>= 1.0.0.beta.3'
end
