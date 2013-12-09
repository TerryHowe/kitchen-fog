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

require 'logger'
require 'stringio'
require 'rspec'
require 'kitchen'
require_relative '../../spec_helper'

describe Kitchen::Driver::Fog do
  let(:logged_output) { StringIO.new }
  let(:logger) { Logger.new(logged_output) }
  let(:config) { Hash.new }
  let(:state) { Hash.new }

  let(:instance) do
    double(
      :name => 'potatoes', :logger => logger, :to_str => 'instance'
    )
  end

  let(:driver) do
    d = Kitchen::Driver::Fog.new(config)
    d.instance = instance
    d
  end

  describe '#initialize'do
    context 'default options' do
      it 'defaults to no server name' do
        driver[:server_name].should eq(nil)
      end

      it 'defaults to local user\'s SSH public key' do
        driver[:public_key_path].should eq(File.expand_path(
          '~/.ssh/id_dsa.pub'))
      end

      it 'defaults to SSH with root user on port 22' do
        driver[:username].should eq('root')
        driver[:port].should eq('22')
      end

      it 'defaults to use ipv4' do
        driver[:use_ipv6].should eq(false)
      end

      it 'defaults to no network name' do
        driver[:network_name].should eq(nil)
      end

      it 'defaults to no upload_public_ssh_key' do
        driver[:upload_public_ssh_key].should eq(false)
      end
    end

    context 'overridden options' do
      let(:config) do
        {
          :authentication => {
            :openstack_tenant => 'that_one',
            :openstack_region => 'atlantis',
            :openstack_service_name => 'the_service',
          },
          :server_create => {
            :image_ref => '22',
            :flavor_ref => '33',
          },
          :public_key_path => '/tmp',
          :username => 'admin',
          :port => '2222',
          :server_name => 'puppy',
          :ssh_key => '/path/to/id_rsa'
        }
      end

      it 'uses all the overridden options' do
        drv = driver
        config.each do |k, v|
          drv[k].should eq(v)
        end
      end

      it 'SSH with user-specified private key' do
        driver[:ssh_key].should eq('/path/to/id_rsa')
      end
    end
  end

  describe '#create' do
    let(:server) do
      double(:id => 'test123', :wait_for => true,
        :public_ip_addresses => %w{1.2.3.4})
    end
    let(:driver) do
      d = Kitchen::Driver::Fog.new(config)
      d.instance = instance
      d.stub(:generate_name).with('potatoes').and_return('a_monkey!')
      d.stub(:create_server).and_return(server)
      d.stub(:wait_for_sshd).with('1.2.3.4').and_return(true)
      d.stub(:get_ip).and_return('1.2.3.4')
      d.stub(:upload_public_ssh_key).and_return(true)
      d
    end

    context 'required options provided' do
      let(:config) do
        {
          :authentication => {
            :openstack_username => 'hello',
            :openstack_api_key => 'world',
            :openstack_auth_url => 'http:',
            :openstack_tenant => 'www'
          },
          :server_create => {
            :flavorRef => 101,
            :imageRef => 222
          }
        }
      end

      it 'generates a server name in the absence of one' do
        driver.create(state)
        driver[:server_name].should eq('a_monkey!')
      end

      it 'gets a proper hostname (IP)' do
        driver.create(state)
        state[:hostname].should eq('1.2.3.4')
      end

      it 'does not disable SSL validation' do
        driver.should_not_receive(:disable_ssl_validation)
        driver.create(state)
      end
    end

    context 'SSL validation disabled' do
      let(:config) { { :disable_ssl_validation => true } }

      it 'disables SSL cert validation' do
        driver.should_receive(:disable_ssl_validation)
        driver.create(state)
      end
    end
  end

  describe '#destroy' do
    let(:server_id) { '12345' }
    let(:hostname) { 'example.com' }
    let(:state) { { :server_id => server_id, :hostname => hostname } }
    let(:server) { double(:nil? => false, :destroy => true) }
    let(:servers) { double(:get => server) }
    let(:compute) { double(:servers => servers) }

    let(:driver) do
      d = Kitchen::Driver::Fog.new(config)
      d.instance = instance
      d.stub(:compute).and_return(compute)
      d
    end

    context 'a live server that needs to be destroyed' do
      it 'destroys the server' do
        state.should_receive(:delete).with(:server_id)
        state.should_receive(:delete).with(:hostname)
        driver.destroy(state)
      end

      it 'does not disable SSL cert validation' do
        driver.should_not_receive(:disable_ssl_validation)
        driver.destroy(state)
      end
    end

    context 'no server ID present' do
      let(:state) { Hash.new }

      it 'does nothing' do
        driver.stub(:compute)
        driver.should_not_receive(:compute)
        state.should_not_receive(:delete)
        driver.destroy(state)
      end
    end

    context 'a server that was already destroyed' do
      let(:servers) do
        s = double('servers')
        s.stub(:get).with('12345').and_return(nil)
        s
      end
      let(:compute) { double(:servers => servers) }
      let(:driver) do
        d = Kitchen::Driver::Fog.new(config)
        d.instance = instance
        d.stub(:compute).and_return(compute)
        d
      end

      it 'does not try to destroy the server again' do
        allow_message_expectations_on_nil
        driver.destroy(state)
      end
    end

    context 'SSL validation disabled' do
      let(:config) { { :disable_ssl_validation => true } }

      it 'disables SSL cert validation' do
        driver.should_receive(:disable_ssl_validation)
        driver.destroy(state)
      end
    end
  end

  describe '#compute' do
    let(:config) do
      {
        :authentication => {
          :openstack_username => 'monkey',
          :openstack_api_key => 'potato',
          :openstack_auth_url => 'http:',
          :openstack_tenant => 'link',
          :openstack_region => 'ord',
          :openstack_service_name => 'the_service'
        }
      }
    end

    context 'all requirements provided' do
      it 'creates a new compute connection' do
        Fog::Compute.stub(:new) { |arg| arg }
        res = config.merge({ :provider => 'fog' })
        driver.send(:compute).should eq(res[:authentication])
      end
    end

    context 'only an API key provided' do
      let(:config) { { :authentication => { :openstack_api_key => '1234' } } }

      it 'raises an error' do
        expect { driver.send(:compute) }.to raise_error(ArgumentError)
      end
    end

    context 'only a username provided' do
      let(:config) do
        { :authentication => { :openstack_username => 'monkey' } }
      end

      it 'raises an error' do
        expect { driver.send(:compute) }.to raise_error(ArgumentError)
      end
    end
  end

  describe '#create_server' do
    let(:config) do
      {
        :server_name => 'hello',
        :image_ref => 'there',
        :flavor_ref => 'captain',
        :public_key_path => 'tarpals'
      }
    end
    let(:server) do
      double(:id => 'test222', :wait_for => true,
        :public_ip_addresses => %w{1.2.3.4})
    end
    let(:servers) do
      s = double('servers')
      s.stub(:create).and_return(server)
      s
    end
    let(:compute) { double(:servers => servers) }
    let(:driver) do
      d = Kitchen::Driver::Fog.new(config)
      d.instance = instance
      d.stub(:compute).and_return(compute)
      d
    end

    context 'a default config' do
      before(:each) do
        @expected = config.merge(:name => config[:server_name])
        @expected.delete_if do |k, v|
          k == :server_name
        end
      end

      it 'creates the server using a compute connection' do
        state = {}
        driver.send(:create_server, state).should eq(server)
        state.should eq({ :server_id => 'test222' })
      end
    end

    context 'a provided public key path' do
      let(:config) do
        {
          :server_name => 'hello',
          :image_ref => 'there',
          :flavor_ref => 'captain',
          :public_key_path => 'tarpals'
        }
      end
      before(:each) do
        @expected = config.merge(:name => config[:server_name])
        @expected.delete_if do |k, v|
          k == :server_name
        end
      end

      it 'passes that public key path to Fog' do
        state = {}
        driver.send(:create_server, state).should eq(server)
        state.should eq({ :server_id => 'test222' })
      end
    end

    context 'a provided key name' do
      let(:config) do
        {
          :server_name => 'hello',
          :image_ref => 'there',
          :flavor_ref => 'captain',
          :public_key_path => 'montgomery',
          :key_name => 'tarpals'
        }
      end

      before(:each) do
        @expected = config.merge(:name => config[:server_name])
        @expected.delete_if do |k, v|
          k == :server_name
        end
      end

      it 'passes that key name to Fog' do
        state = {}
        driver.send(:create_server, state).should eq(server)
        state.should eq({ :server_id => 'test222' })
      end
    end
  end

  describe '#generate_name' do
    before(:each) do
      Etc.stub(:getlogin).and_return('user')
      Socket.stub(:gethostname).and_return('host')
    end

    it 'generates a name' do
      driver.send(:generate_name, 'monkey').should match(
        /^monkey-user-host-/)
    end

    context 'local node with a long hostname' do
      before(:each) do
        Socket.unstub(:gethostname)
        Socket.stub(:gethostname).and_return('ab.c' * 20)
      end

      it 'limits the generated name to 64-characters' do
        driver.send(:generate_name, 'long').length.should eq(64)
      end
    end
  end

  describe '#get_ip' do
    let(:addresses) { nil }
    let(:public_ip_addresses) { nil }
    let(:private_ip_addresses) { nil }
    let(:parsed_ips) { [[], []] }
    let(:driver) do
      d = Kitchen::Driver::Fog.new(config)
      d.instance = instance
      d.stub(:parse_ips).and_return(parsed_ips)
      d
    end
    let(:server) do
      double(:addresses => addresses,
        :public_ip_addresses => public_ip_addresses,
        :private_ip_addresses => private_ip_addresses)
    end

    context 'both public and private IPs' do
      let(:public_ip_addresses) { %w{1::1 1.2.3.4} }
      let(:private_ip_addresses) { %w{5.5.5.5} }
      let(:parsed_ips) { [%w{1.2.3.4}, %w{5.5.5.5}] }

      it 'returns a public IPv4 address' do
        driver.send(:get_ip, server).should eq('1.2.3.4')
      end
    end

    context 'only public IPs' do
      let(:public_ip_addresses) { %w{4.3.2.1 2::1} }
      let(:parsed_ips) { [%w{4.3.2.1}, []] }

      it 'returns a public IPv4 address' do
        driver.send(:get_ip, server).should eq('4.3.2.1')
      end
    end

    context 'only private IPs' do
      let(:private_ip_addresses) { %w{3::1 5.5.5.5} }
      let(:parsed_ips) { [[], %w{5.5.5.5}] }

      it 'returns a private IPv4 address' do
        driver.send(:get_ip, server).should eq('5.5.5.5')
      end
    end

    context 'IPs in user-defined network group' do
      let(:config) { { :network_name => 'mynetwork' } }
      let(:addresses) do
        {
          'mynetwork' => [
            { 'addr' => '7.7.7.7' },
            { 'addr' => '4::1' }
          ]
        }
      end

      it 'returns a IPv4 address in user-defined network group' do
        driver.send(:get_ip, server).should eq('7.7.7.7')
      end
    end

    context 'an Fog deployment without the floating IP extension' do
      let(:server) do
        s = double('server')
        s.stub(:addresses).and_return(addresses)
        s.stub(:public_ip_addresses).and_raise(
          Fog::Compute::OpenStack::NotFound)
        s.stub(:private_ip_addresses).and_raise(
          Fog::Compute::OpenStack::NotFound)
        s
      end

      context 'both public and private IPs in the addresses hash' do
        let(:addresses) do
          {
            'public' => [{ 'addr' => '6.6.6.6' }, { 'addr' => '7.7.7.7' }],
            'private' => [{ 'addr' => '8.8.8.8' }, { 'addr' => '9.9.9.9' }]
          }
        end
        let(:parsed_ips) { [%w{6.6.6.6 7.7.7.7}, %w{8.8.8.8 9.9.9.9}] }

        it 'selects the first public IP' do
          driver.send(:get_ip, server).should eq('6.6.6.6')
        end
      end

      context 'only public IPs in the address hash' do
        let(:addresses) do
          { 'public' => [{ 'addr' => '6.6.6.6' }, { 'addr' => '7.7.7.7' }] }
        end
        let(:parsed_ips) { [%w{6.6.6.6 7.7.7.7}, []] }

        it 'selects the first public IP' do
          driver.send(:get_ip, server).should eq('6.6.6.6')
        end
      end

      context 'only private IPs in the address hash' do
        let(:addresses) do
          { 'private' => [{ 'addr' => '8.8.8.8' }, { 'addr' => '9.9.9.9' }] }
        end
        let(:parsed_ips) { [[], %w{8.8.8.8 9.9.9.9}] }

        it 'selects the first private IP' do
          driver.send(:get_ip, server).should eq('8.8.8.8')
        end
      end
    end

    context 'no IP addresses whatsoever' do
      it 'raises an exception' do
        expect { driver.send(:get_ip, server) }.to raise_error
      end
    end
  end

  describe '#parse_ips' do
    let(:pub_v4) { %w{1.1.1.1 2.2.2.2} }
    let(:pub_v6) { %w{1::1 2::2} }
    let(:priv_v4) { %w{3.3.3.3 4.4.4.4} }
    let(:priv_v6) { %w{3::3 4::4} }
    let(:pub) { pub_v4 + pub_v6 }
    let(:priv) { priv_v4 + priv_v6 }

    context 'both public and private IPs' do
      context 'IPv4 (default)' do
        it 'returns only the v4 IPs' do
          driver.send(:parse_ips, pub, priv).should eq([pub_v4, priv_v4])
        end
      end

      context 'IPv6' do
        let(:config) { { :use_ipv6 => true } }

        it 'returns only the v6 IPs' do
          driver.send(:parse_ips, pub, priv).should eq([pub_v6, priv_v6])
        end
      end
    end

    context 'only public IPs' do
      let(:priv) { nil }

      context 'IPv4 (default)' do
        it 'returns only the v4 IPs' do
          driver.send(:parse_ips, pub, priv).should eq([pub_v4, []])
        end
      end

      context 'IPv6' do
        let(:config) { { :use_ipv6 => true } }

        it 'returns only the v6 IPs' do
          driver.send(:parse_ips, pub, priv).should eq([pub_v6, []])
        end
      end
    end

    context 'only private IPs' do
      let(:pub) { nil }

      context 'IPv4 (default)' do
        it 'returns only the v4 IPs' do
          driver.send(:parse_ips, pub, priv).should eq([[], priv_v4])
        end
      end

      context 'IPv6' do
        let(:config) { { :use_ipv6 => true } }

        it 'returns only the v6 IPs' do
          driver.send(:parse_ips, pub, priv).should eq([[], priv_v6])
        end
      end
    end

    context 'no IPs whatsoever' do
      let(:pub) { nil }
      let(:priv) { nil }

      context 'IPv4 (default)' do
        it 'returns empty lists' do
          driver.send(:parse_ips, pub, priv).should eq([[], []])
        end
      end

      context 'IPv6' do
        let(:config) { { :use_ipv6 => true } }

        it 'returns empty lists' do
          driver.send(:parse_ips, nil, nil).should eq([[], []])
        end
      end
    end
  end

  describe '#upload_public_ssh_key' do
    let(:server) { double(:password => 'aloha') }
    let(:state) { { :hostname => 'host' } }
    let(:read) { double(:read => 'a_key') }
    let(:ssh) do
      s = double('ssh')
      s.stub(:run) { |args| args }
      s
    end

    it 'opens an SSH session to the server' do
      Fog::SSH.stub(:new).with('host', 'root',
        { :password => 'aloha' }).and_return(ssh)
      driver.stub(:open).with(File.expand_path(
        '~/.ssh/id_dsa.pub')).and_return(read)
      read.stub(:read).and_return('a_key')
      res = driver.send(:upload_public_ssh_key, state, config, server)
      expected = [
        'mkdir .ssh',
        'echo "a_key" >> ~/.ssh/authorized_keys',
        'passwd -l root'
      ]
      res.should eq(expected)
    end
  end

  describe '#disable_ssl_validation' do
    it 'turns off Excon SSL cert validation' do
      driver.send(:disable_ssl_validation).should eq(false)
    end
  end
end

# vim: ai et ts=2 sts=2 sw=2 ft=ruby
