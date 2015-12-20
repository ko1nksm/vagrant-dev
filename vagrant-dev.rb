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

class VagrantDev
  attr_accessor :config

  def initialize(config)
    @config = config
  end

  def self.configure(config, &block)
    config.vm.provision "fix-no-tty", type: "shell" do |s|
      s.privileged = false
      s.inline = <<-SHELL
        sudo sed -i '/tty/!s/mesg n/tty -s \\&\\& mesg n/' /root/.profile
      SHELL
    end

    provisioner = File.join(File.dirname(__FILE__), 'provisioner')
    config.vm.provision "file", source: provisioner, destination: "./"

    config.vm.provision "prepare provisioner", type: "shell", inline: <<-SHELL
      chmod +x "$(eval echo ~vagrant)/provisioner/"*
      ln -snf "$(eval echo ~vagrant)/provisioner/bootstrap" /bootstrap
    SHELL

    self.new(config).instance_eval(&block)
  end

  def load_vms
    vagrantfile_dir = File.dirname(caller_locations(1,1)[0].absolute_path)
    Dir.glob(File.join(vagrantfile_dir, '*', 'vmdefine.rb')) do |path|
      vmname = File.basename(File.dirname(path))
      config.vm.define vmname, autostart: false do |config|
        yield vmname
        VagrantDev::Envrionment.new(config, vmname).load(path)
      end
    end
  end

  def create_user(username, password: username, keyfile: keyfile, setup: setup)
    keydata = File.read(keyfile)
    setup_script = setup ? SETUP : ""
    config.vm.provision "create user", type: "shell", inline: <<-SHELL
      eval "$(/bootstrap)"
      create-user '#{username}' '#{password}' '#{keydata}' '#{setup_script}'
    SHELL
  end

  def create_partition(device)
    config.vm.provision "create partition", type: "shell", inline: <<-SHELL
      eval "$(/bootstrap)"
      create-partition "#{device}"
    SHELL
  end

  def mount_partition(name, device, path)
    config.vm.provision "mount partition", type: "shell", inline: <<-SHELL
      eval "$(/bootstrap)"
      mount-partition "#{name}" "#{device}" "#{path}"
    SHELL
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
