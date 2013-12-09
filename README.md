[![Build Status](https://travis-ci.org/TerryHowe/kitchen-fog.png?branch=master)](https://travis-ci.org/TerryHowe/kitchen-fog)

# Kitchen::Fog

A Fog Nova driver for Test Kitchen 1.0!

Generalized from [Jonathan Hartman](https://github.com/RoboticCheese)'s awesome work on an [OpenStack driver](https://github.com/RoboticCheese/kitchen-openstack) which is shamelessly copied from [Fletcher Nichol](https://github.com/fnichol)'s
awesome work on an [EC2 driver](https://github.com/opscode/kitchen-ec2).

## Installation

Add this line to your application's Gemfile:

    gem 'kitchen-fog'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install kitchen-fog

## Usage

Provide, at a minimum, the required driver options in your `.kitchen.yml` file.  The authentication and server_create sections are specific to the provider:

    ---
    driver_plugin: fog
    driver_config:
      authentication:
        provider: 'openstack'
        openstack_username: 'username'
        openstack_api_key: 'password'
        openstack_auth_url: 'https://id.example.com:35357/v2.0/tokens'
        openstack_tenant: 'tenant_name'
        openstack_region: 'region-b.geo-1'
      server_create:
        flavor_ref: '103'
        image_ref: '8c096c29-a666-4b82-99c4-c77dc70cfb40'
        key_name: 'bover'
        nics: [ 'net_id': '76abe0b1-581a-4698-b200-a2e890f4eb8d' ]
      floating_ip_create:
        floating_network_id: '7da74520-9d5e-427b-a508-213c84e69616'
      require_chef_omnibus: latest
      public_key_path: /home/terry/.ssh/bover.pub
      username: ubuntu

By default, a unique server name will be generated and the current user's SSH
key will be used, though that behavior can be overridden with additional
options:

    server_name: [A UNIQUE SERVER NAME]
    ssh_key: [PATH TO YOUR PRIVATE SSH KEY]
    upload_public_ssh_key: [TRUE UPLOADS PUBLIC KEY TO SERVER]
    public_key_path: [PATH TO YOUR SSH PUBLIC KEY]
    username: [SSH USER]
    port: [SSH PORT]

If a key\_name is provided it will be used instead of any
public\_key\_path that is specified.

    disable_ssl_validation: true

Only disable SSL cert validation if you absolutely know what you are doing,
but are stuck with a deployment without valid SSL certs.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
