Gem::Specification.new do |s|
  s.name        = 'nwrfc'
  s.version     = '0.0.8'
  s.date        = '2015-06-05'
  s.summary     = "SAP Netweaver RFC Library Wrapper"
  s.description = "SAP Netweaver RFC Library Wrapper using Ruby-FFI"
  s.authors     = ["Martin Ceronio"]
  s.email       = 'martin.ceronio@infosize.co.za'
  s.homepage    = 'http://rubygems.org/gems/nwrfc'
  s.has_rdoc    = true
  s.add_dependency('ffi', '>= 1.9.3')
  s.extra_rdoc_files = ['README.rdoc']
  s.files = %w(README.rdoc Rakefile) + Dir.glob("{bin,lib,spec}/**/*")
  s.require_path = "lib"
  s.licenses    = ['MIT']
end
