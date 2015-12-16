require 'base64'

def err(*messages)
  print "\e[31m" + messages.join("\n") + "\n\e[0m"
end

def warn(*messages)
  print "\e[33m" + messages.join("\n") + "\n\e[0m"
end

if ARGV[0] == "destroy"
  warn 'Attached storages will be deleted.',
       'If do not want to lose the data, detach storage.'
end

unless defined? USERNAME then
  USERNAME = ENV['USER'] || ENV['USERNAME']

  if USERNAME.nil? then
    err 'The user name is not detected.',
         'Check your USER or USERNAME environment variable.'
    exit
  end
end

unless defined? DOT_SSH_DIR then
  paths = []

  if ENV.has_key?('HOME') then
    paths.push ENV['HOME']
  end

  if ENV.has_key?('HOMEDRIVE') and ENV.has_key?('HOMEPATH') then
    paths.push ENV['HOMEDRIVE'] + ENV['HOMEPATH']
  end

  if ENV.has_key?('USERPROFILE') then
    paths.push ENV['USERPROFILE']
  end

  paths.map! do |path|
    File.expand_path(File.join(path, '.ssh'))
  end

  DOT_SSH_DIR = paths.find { |path| File.exists? path }

  if DOT_SSH_DIR.nil? then
    warn '.ssh directory not found.', paths.map { |path| "  " + path }
  end
end

unless defined? TIMEZONE then
  TIMEZONE = ''
end

unless defined? USERSETUP then
  USERSETUP = ''
end

class VagrantDev
  def self.setup(options)
    self::Envrionment.setup(options)
  end

  def self.vm_define(config, &block)
    Dir.glob('*/vmdefine.rb') do |path|
      vmname = File.dirname(path)
      config.vm.define vmname, autostart: false do |config|
        config.vm.provider :virtualbox do |vb|
          vb.shared_folder DOT_SSH_DIR
        end
        block.call(config, vmname)
        self::Envrionment.new(config, vmname).load(path)
      end
    end
  end
end

class VagrantDev::Envrionment
  @@vagrantfile_path = Dir.pwd
  @@provisions_path = '.provisions'

  attr_accessor :config
  attr_accessor :vmname

  def self.setup(options)
    @@provisions_path ||= options[:provisions]
  end

  def initialize(config, vmname)
    @config = config
    @vmname = vmname
  end

  def load(vmdefine_path)
    instance_eval File.read(vmdefine_path)
  end

  def provision(code)
    initialize_path = File.join(File.dirname(__FILE__), 'initialize')
    provisions_path = File.join(@@vagrantfile_path, @@provisions_path)

    vm_initialize_path = vm_internal_path(initialize_path)
    vm_provisions_path = vm_internal_path(provisions_path)

    <<-CODE
      set -e
      eval "$(#{vm_initialize_path} #{vmname} #{vm_provisions_path})"
      provision_start
      provide root locale $(resource locale.gen)
      provide root timezone #{TIMEZONE}
      provide root shared-folder install
      provide root create-user #{USERNAME}
      provide root mountsf .ssh /home/#{USERNAME}/.ssh --user-only #{USERNAME}
      #{code}
      provide #{USERNAME} user-setup #{encode(USERSETUP)}
      provide root shared-folder start
      provision_complete
    CODE
  end

  def encode(data)
    Base64.strict_encode64(data)
  end

  def vm_internal_path(path)
    base = @@vagrantfile_path
    rel = Pathname(path).relative_path_from(Pathname(base))
    '/vagrant/' + rel.to_s
  end
end

module VagrantPlugins::ProviderVirtualBox
  class Config < Vagrant.plugin("2", :config)
    def attach_storage(filename, params)
      basedir = params.delete(:basedir)
      filename = File.join(basedir, filename)
      size = params.delete(:size)

      unless File.exist? filename
        options = ['--filename', filename, '--size', size]
        self.customize ['createhd', *options]
      end

      params[:medium] = filename
      keys = params.keys.map { |key| '--' + key.to_s }
      options = keys.zip(params.values).flatten
      self.customize ['storageattach', :id, *options]
    end

    def shared_folder(hostpath, name = File.basename(hostpath))
      return unless hostpath

      self.customize ['sharedfolder', 'add', :id,
        '--name', name,
        '--hostpath', hostpath
      ]
    end
  end
end
