#!/usr/bin/env gem build
require 'base64'

Gem::Specification.new do |s|
  s.name = "smoke_signals"
  s.version = "0.9.0"
  s.authors = ["Jonathan Tran"]
  s.homepage = "http://github.com/jtran/smoke_signals"
  s.summary = "Lisp-style conditions and restarts for Ruby"
  s.description = "SmokeSignals makes it easy to separate policy of error recovery from implementation of error recovery."
  s.email = Base64.decode64("anRyYW5AYWx1bW5pLmNtdS5lZHU=\n")
  s.license = 'MIT'

  s.files = `git ls-files`.split("\n")
  s.test_files = `git ls-files -- test/*`.split("\n")
  s.require_paths = ["lib"]

  # Ruby version
  s.required_ruby_version = '>= 1.8.7'
end
