Vagrant.configure(2) do |config|
  config.vm.box = "dummy"
  # config.vm.box = "ubuntu/trusty64"
  config.vm.network :forwarded_port, guest: 8080, host: 4567
  config.vm.provision :shell, path: "bootstrap.sh"

  config.vm.provider :aws do |aws, override|
    aws.access_key_id = "YOUR KEY"
    aws.secret_access_key = "YOUR SECRET KEY"
    aws.session_token = "SESSION TOKEN"
    aws.keypair_name = "odk-dev"

    aws.ami = "ami-7747d01e"

    aws.elastic_ip = "52.4.26.168"
    aws.security_groups = ["sg-a85ab4ce"]

    override.ssh.username = "ubuntu"
    override.ssh.private_key_path = "PATH TO YOUR PRIVATE KEY"
  end
end
