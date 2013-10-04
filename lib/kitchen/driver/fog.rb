# -*- encoding: utf-8 -*-
#
# Author:: Jonathan Hartman (<j@p4nt5.com>)
#
# Copyright (C) 2013, Jonathan Hartman
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'benchmark'
require 'fog'
require 'kitchen'
require 'etc'
require 'ipaddr'
require 'socket'

module Kitchen
  module Driver
    # Fog driver for Kitchen.
    #
    # @author Jonathan Hartman <j@p4nt5.com>
    class Fog < Kitchen::Driver::SSHBase
      default_config :name, nil
      default_config :public_key_path, File.expand_path('~/.ssh/id_dsa.pub')
      default_config :username, 'root'
      default_config :port, '22'
      default_config :use_ipv6, false
      default_config :network_name, nil

      def create(state)
        config[:name] ||= generate_name(instance.name)
        config[:disable_ssl_validation] and disable_ssl_validation
        server = create_server
        unless config[:floating_ip_create].nil?
          create_floating_ip(server)
        else
          state[:hostname] = get_ip(server)
        end
        wait_for_sshd(state[:hostname]) ; puts '(ssh ready)'
        unless config[:ssh_key] or config[:key_name]
          do_ssh_setup(state, config, server)
        end
      rescue ::Fog::Errors::Error, Excon::Errors::Error => ex
        raise ActionFailed, ex.message
      end

      def destroy(state)
        return if state[:server_id].nil?

        config[:disable_ssl_validation] and disable_ssl_validation
        server = compute.servers.get(state[:server_id])
        server.destroy unless server.nil?
        info "Fog instance <#{state[:server_id]}> destroyed."
        state.delete(:server_id)
        state.delete(:hostname)
      end

      private

      def compute
        ::Fog::Compute.new(config[:authentication].dup)
      end

      def network
        authentication = config[:authentication].dup
        authentication.delete(:version)
        ::Fog::Network.new(authentication)
      end

      def create_server
        server_def = config[:server_create].dup
        server_def[:name] = config[:name]
        # Can't use the Fog bootstrap and/or setup methods here; they require a
        # public IP address that can't be guaranteed to exist across all
        # OpenStack deployments (e.g. TryStack ARM only has private IPs).
        server = compute.servers.create(server_def)
        state[:server_id] = server.id
        info "Fog instance <#{state[:server_id]}> created."
        server.wait_for { print '.'; ready? } ; puts "\n(server ready)"
        server
      end

      def create_floating_ip(server)
        hsh = config[:floating_ip_create].dup
        floater = network.create_floating_ip(hsh[:floating_network_id], hsh)
        floating_id = floater.body['floatingip']['id']
        state[:hostname] = floater.body['floatingip']['floating_ip_address']
        port = network.ports(:filters => { :device_id => server.id }).first
        network.associate_floating_ip(floating_id, port.id)
      end

      def generate_name(base)
        # Generate what should be a unique server name
        sep = '-'
        pieces = [
          base,
          Etc.getlogin,
          Socket.gethostname,
          Array.new(8) { rand(36).to_s(36) }.join
        ]
        until pieces.join(sep).length <= 64 do
          if pieces[2].length > 24
            pieces[2] = pieces[2][0..-2]
          elsif pieces[1].length > 16
            pieces[1] = pieces[1][0..-2]
          elsif pieces[0].length > 16
            pieces[0] = pieces[0][0..-2]
          end
        end
        pieces.join sep
      end

      def get_ip(server)
        if config[:network_name]
          debug "Using configured network: #{config[:network_name]}"
          return server.addresses[config[:network_name]].first['addr']
        end
        begin
          pub, priv = server.public_ip_addresses, server.private_ip_addresses
        rescue Exception => e
          # See Fog issue: https://github.com/fog/fog/issues/2160
          addrs = server.addresses
          addrs['public'] and pub = addrs['public'].map { |i| i['addr'] }
          addrs['private'] and priv = addrs['private'].map { |i| i['addr'] }
        end
        pub, priv = parse_ips(pub, priv)
        pub.first || priv.first || raise(ActionFailed, 'Could not find an IP')
      end

      def parse_ips(pub, priv)
        pub, priv = Array(pub), Array(priv)
        if config[:use_ipv6]
          [pub, priv].each { |n| n.select! { |i| IPAddr.new(i).ipv6? } }
        else
          [pub, priv].each { |n| n.select! { |i| IPAddr.new(i).ipv4? } }
        end
        return pub, priv
      end

      def do_ssh_setup(state, config, server)
        ssh = ::Fog::SSH.new(state[:hostname], config[:username],
          { :password => server.password })
        pub_key = open(config[:public_key_path]).read
        ssh.run([
          %{mkdir .ssh},
          %{echo "#{pub_key}" >> ~/.ssh/authorized_keys},
          %{passwd -l #{config[:username]}}
        ])
      end

      def disable_ssl_validation
        require 'excon'
        Excon.defaults[:ssl_verify_peer] = false
      end
    end
  end
end

# vim: ai et ts=2 sts=2 sw=2 ft=ruby
