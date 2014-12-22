#
# Cookbook Name:: sssd_ldap
# Recipe:: default
#
# Copyright 2013-2014, Limelight Networks, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

package 'sssd' do
  action :install
end

package 'libsss_sudo' do
  action :install
  only_if { node['sssd_ldap']['ldap_sudo'] }
end

# Only run on RHEL
if platform_family?('rhel')

  # authconfig allows cli based intelligent manipulation of the pam.d files
  package 'authconfig' do
    action :install
  end

  # https://bugzilla.redhat.com/show_bug.cgi?id=975082
  ruby_block 'nsswitch sudoers' do
    block do
      edit = Chef::Util::FileEdit.new '/etc/nsswitch.conf'
      edit.insert_line_if_no_match(/^sudoers:/, 'sudoers: files')

      if node['sssd_ldap']['ldap_sudo']
        # Add sss to the line if it's not there.
        edit.search_file_replace(/^sudoers:([ \t]*(?!sss\b)\w+)*[ \t]*$/, '\0 sss')
      else
        # Remove sss from the line if it is there.
        edit.search_file_replace(/^(sudoers:.*)\bsss[ \t]*/, '\1')
      end

      edit.write_file
    end

    action :nothing
  end

  # Have authconfig enable SSSD in the pam files
  execute 'authconfig' do
    command "authconfig #{node['sssd_ldap']['authconfig_params']}"
    notifies :run, 'ruby_block[nsswitch sudoers]', :immediately
    action :nothing
  end
end

# sssd automatically modifies the PAM files with pam-auth-update and /etc/nsswitch.conf, so all that's left is to configure /etc/sssd/sssd.conf
template '/etc/sssd/sssd.conf' do
  source 'sssd.conf.erb'
  owner 'root'
  group 'root'
  mode '0600'

  if platform_family?('rhel')
    # this needs to run immediately so it doesn't happen after sssd
    # service block below, or sssd won't start when recipe completes
    notifies :run, 'execute[authconfig]', :immediately
  end

  notifies :restart, 'service[sssd]'
end

service 'sssd' do
  supports :status => true, :restart => true, :reload => true
  action [:enable, :start]
  provider Chef::Provider::Service::Upstart if node['platform'] == 'ubuntu' && node['platform_version'].to_f >= 13.04
end

# nscd caching will break sssd and is not necessary
service 'nscd' do
  supports :status => true, :restart => true, :reload => true
  action [:disable, :stop]
  provider Chef::Provider::Service::Upstart if node['platform'] == 'ubuntu' && node['platform_version'].to_f >= 13.04
end
