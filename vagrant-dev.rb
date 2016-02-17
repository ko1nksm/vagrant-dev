require 'shellwords'

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

unless defined? KEY_FILE then
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
    File.expand_path(File.join path, '.ssh', 'id_rsa.pub')
  end

  KEY_FILE = paths.find { |path| File.exists? path }

  if KEY_FILE.nil? then
    warn 'id_rsa.pub not found.'
  end
end

def BOOTSTRAP(vmname="")
  "eval \"$(~vagrant/helpers/BOOTSTRAP #{vmname})\""
end

def COMPLETE()
  "~vagrant/helpers/COMPLETE"
end

def READ(file)
  Shellwords.escape File.read(file)
end

def DATA(data)
  Shellwords.escape data
end

class VagrantDev
  attr_accessor :config

  def initialize(config)
    @config = config
  end

  def self.configure(config)
    helpers = File.join(File.dirname(__FILE__), 'helpers')
    config.vm.provision "file", source: helpers, destination: "./"
    config.vm.provision "shell", inline: "chmod +x ~vagrant/helpers/*"
    yield VagrantDev.new(config)
  end

  def vms(vagrantfile_dir)
    Dir.glob(File.join(vagrantfile_dir, '*', 'vm.rb')) do |vmpath|
      vmname = File.basename(File.dirname(vmpath))
      config.vm.define vmname, autostart: false do |config|
        vm = VagrantDev::VMDefine.new(config, vmname, vmpath)
        yield vm, config
      end
    end
  end
end

class VagrantDev::VMDefine
  attr_accessor :config
  attr_accessor :name
  attr_accessor :path

  def initialize(config, name, path)
    @config = config
    @name = name
    @path = path
  end

  def load
    instance_eval File.read(@path)
  end
end

module VagrantPlugins::ProviderVirtualBox
  class Config < Vagrant.plugin("2", :config)
    def attach_storage(filename, position, size, options)
      pos = position.split('-')
      basedir = options.delete(:basedir)
      filename = File.join(basedir, filename)

      unless File.exist? filename
        self.customize ['createhd', '--filename', filename, '--size', size]
      end

      options[:storagectl] = pos[0]
      options[:port] = pos[1]
      options[:device] = pos[2]
      options[:medium] = filename
      options[:type] ||= "hdd"
      keys = options.keys.map { |key| '--' + key.to_s }
      params = keys.zip(options.values).flatten
      self.customize ['storageattach', :id, *params]

      key = "vagrant-dev/attach_storage/" + position
      self.customize ['setextradata', :id, key, '1']
    end
  end
end
