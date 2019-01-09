Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/trusty64"
  config.vm.provider "virtualbox" do |vb|
    vb.memory = "512"
  end
  config.vm.provision "chef_apply" do |chef|
    chef.recipe = <<-RECIPE
      apt_update 'update' do
        action :nothing
      end
      apt_repository 'ruby-ng' do
        uri 'ppa:brightbox/ruby-ng'
        distribution node['lsb']['codename']
        only_if { node['lsb']['codename'] == 'trusty' }
        notifies :update, 'apt_update[update]', :immediately
      end
      package %w(git)
      package %w(ruby2.1 ruby2.1-dev) do # raise/lower this if our minimum version ever changes - only affects local testing
        only_if { node['lsb']['codename'] == 'trusty' }
      end
      gem_package 'bundler'
      execute 'bundle install' do
        cwd '/vagrant'
      end
    RECIPE
  end
end
