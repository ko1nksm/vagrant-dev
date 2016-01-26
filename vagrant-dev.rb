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

unless defined? SETUP then
  SETUP = ""
end

def BOOTSTRAP(vmname="")
  [
    'echo "========================================"',
    'echo "Provision start"',
    "eval \"$(~vagrant/provisioner/bootstrap #{vmname})\"",
  ].join("\n")
end

def COMPLETE()
  [
    'echo "Provision complete"',
    'echo "========================================"',
  ].join("\n")
end

def READ(file)
  File.read(file)
end

class VagrantDev
  attr_accessor :config

  def initialize(config)
    @config = config
  end

  def self.install(config)
    provisioner = File.join(File.dirname(__FILE__), 'provisioner')
    config.vm.provision "file", source: provisioner, destination: "./"
    config.vm.provision "shell", inline: "chmod +x ~vagrant/provisioner/*"
    yield VagrantDev.new(config)
  end

  def enumerate_vms(vagrantfile_dir)
    Dir.glob(File.join(vagrantfile_dir, '*', 'vm.rb')) do |path|
      vmname = File.basename(File.dirname(path))
      config.vm.define vmname, autostart: false do |config|
        yield vmname, config, Proc.new {
          VagrantDev::Envrionment.new(config, vmname).load(path)
        }
      end
    end
  end
end

class VagrantDev::Envrionment
  attr_accessor :config
  attr_accessor :vmname

  def initialize(config, vmname)
    @config = config
    @vmname = vmname
  end

  def load(vmdefine_path)
    instance_eval File.read(vmdefine_path)
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

      name = params.values_at(:storagectl, :port, :device).join('-')
      key = "vagrant-dev/attach_storage/" + name
      self.customize ['setextradata', :id, key, '1']
    end

    def shared_folder(hostpath, name = File.basename(hostpath))
      return unless hostpath

      self.customize ['sharedfolder', 'add', :id,
        '--name', name,
        '--hostpath', hostpath
      ]
    end

    def description(text)
      self.customize ['modifyvm', :id, '--description', text]
    end
  end
end
