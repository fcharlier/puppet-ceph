# -*- mode: ruby -*-
# vi: set ft=ruby :

def parse_vagrant_config(
  config_file=File.expand_path(File.join(File.dirname(__FILE__), 'config.yaml'))
)
  require 'yaml'
  config = {
    'operatingsystem' => 'debian',
  }
  if File.exists?(config_file)
    overrides = YAML.load_file(config_file)
    config.merge!(overrides)
  end
  config
end

Vagrant::Config.run do |config|
  v_config = parse_vagrant_config

  if v_config['operatingsystem'] == 'debian'
    config.vm.box = "wheezy64"
    config.vm.box_url = "https://labs.enovance.com/pub/wheezy64.box"
  elsif v_config['operatingsystem'] == 'ubuntu'
    config.vm.box = "precise64"
    config.vm.box_url = "https://labs.enovance.com/pub/precise64.box"
  end

  local_shell_provisionner = File.expand_path("~/.vagrant.d/local.sh")
  if File.exists?(local_shell_provisionner)
    config.vm.provision :shell, :path => local_shell_provisionner
  end

  (0..2).each do |i|
    config.vm.define "mon#{i}" do |mon|
      mon.vm.host_name = "ceph-mon#{i}.test"
      mon.vm.network :hostonly, "192.168.251.1#{i}", { :nic_type => 'virtio' }
      mon.vm.network :hostonly, "192.168.252.1#{i}", { :nic_type => 'virtio' }
      mon.vm.provision :shell, :path => "examples/mon.sh"
    end
  end

  (0..2).each do |i|
    config.vm.define "osd#{i}" do |osd|
      osd.vm.host_name = "ceph-osd#{i}.test"
      osd.vm.network :hostonly, "192.168.251.10#{i}", { :nic_type => 'virtio' }
      osd.vm.network :hostonly, "192.168.252.10#{i}", { :nic_type => 'virtio' }
      osd.vm.provision :shell, :path => "examples/osd.sh"
      (0..1).each do |d|
        osd.vm.customize [ "createhd", "--filename", "disk-#{i}-#{d}", "--size", "5000" ]
        osd.vm.customize [ "storageattach", :id, "--storagectl", "SATA Controller", "--port", 3+d, "--device", 0, "--type", "hdd", "--medium", "disk-#{i}-#{d}.vdi" ]
      end
    end
  end

  (0..1).each do |i|
    config.vm.define "mds#{i}" do |mds|
      mds.vm.host_name = "ceph-mds#{i}.test"
      mds.vm.network :hostonly, "192.168.251.15#{i}", { :nic_type => 'virtio' }
      mds.vm.provision :shell, :path => "examples/mds.sh"
    end
  end
end
