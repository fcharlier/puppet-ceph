#!/bin/bash

set -x
set -e

AGENT_OPTIONS="--onetime --verbose --ignorecache --no-daemonize --no-usecacheonfailure --no-splay --show_diff --debug"

# ensure a correct domain name is set from dhclient
grep -q 'supersede domain-name "test";' /etc/dhcp/dhclient.conf ||  {
    echo 'supersede domain-name "test";' >> /etc/dhcp/dhclient.conf
    pkill -9 dhclient
    dhclient eth0
}

# add hosts to /etc/hosts
grep -q "ceph-mon0" /etc/hosts || echo "192.168.251.10	ceph-mon0 ceph-mon0.test" >> /etc/hosts
grep -q "ceph-mon1" /etc/hosts || echo "192.168.251.11	ceph-mon1 ceph-mon1.test" >> /etc/hosts
grep -q "ceph-mon2" /etc/hosts || echo "192.168.251.12	ceph-mon2 ceph-mon2.test" >> /etc/hosts
grep -q "ceph-osd0" /etc/hosts || echo "192.168.251.100	ceph-osd0 ceph-osd0.test" >> /etc/hosts
grep -q "ceph-osd1" /etc/hosts || echo "192.168.251.101	ceph-osd1 ceph-osd1.test" >> /etc/hosts
grep -q "ceph-osd2" /etc/hosts || echo "192.168.251.102	ceph-osd2 ceph-osd2.test" >> /etc/hosts
grep -q "ceph-mds0" /etc/hosts || echo "192.168.251.150	ceph-mds0 ceph-mds0.test" >> /etc/hosts
grep -q "ceph-mds1" /etc/hosts || echo "192.168.251.151	ceph-mds1 ceph-mds1.test" >> /etc/hosts

# Use puppetlabs apt repositories
if [ ! -f /root/puppetlabs-release.deb ]; then
    wget -O /root/puppetlabs-release.deb http://apt.puppetlabs.com/puppetlabs-release-$(lsb_release -cs).deb
fi

export DEBIAN_FRONTEND=noninteractive

dpkg -i /root/puppetlabs-release.deb

# Remove all previous installs of Puppet/Chef

apt-get -y autoremove --purge puppet chef
gem list|awk '{ print $1 }'|xargs gem uninstall -a || echo "Passing"

apt-get update

apt-get -y install puppet facter git

# Install puppetmaster, etc. …
if hostname | grep -q "ceph-mon0"; then
    apt-get install -y puppet facter puppetmaster augeas-tools puppetdb puppetdb-terminus

    # This lens seems to be broken currently on wheezy/sid ?
    # test -f /usr/share/augeas/lenses/dist/cgconfig.aug && rm -f /usr/share/augeas/lenses/dist/cgconfig.aug
    augtool << EOT
set /files/etc/puppet/puppet.conf/agent/pluginsync true
set /files/etc/puppet/puppet.conf/agent/report true
set /files/etc/puppet/puppet.conf/agent/server ceph-mon0.test
set /files/etc/puppet/puppet.conf/master/storeconfigs true
set /files/etc/puppet/puppet.conf/master/storeconfigs_backend puppetdb
set /files/etc/puppet/puppet.conf/master/reports store,puppetdb
save
EOT

    cat << EOT > /etc/puppet/puppetdb.conf
[main]
server=ceph-mon0.test
port=8081
EOT
cat << EOT > /etc/puppet/routes.yaml
---
master:
  facts:
    terminus: puppetdb
    cache: yaml
EOT

    # Autosign certificates from our test setup
    echo "*.test" > /etc/puppet/autosign.conf

    test -d /etc/puppet/modules/concat || puppet module install ripienaar/concat
    test -d /etc/puppet/modules/apt || puppet module install puppetlabs/apt
    test -d /etc/puppet/modules/ceph || git clone /vagrant /etc/puppet/modules/ceph

    test -h /etc/puppet/manifests/site.pp || ln -s /etc/puppet/modules/ceph/examples/site.pp /etc/puppet/manifests/
    pushd /etc/puppet/modules/ceph
    git pull
    popd

    service puppetdb restart
    service puppetmaster restart
    echo "******* waiting 5 seconds for services to settle *******"
sleep 5

else
    aptitude install -y augeas-tools

    # This lens seems to be broken currently on wheezy/sid ?
    test -f /usr/share/augeas/lenses/dist/cgconfig.aug && rm -f /usr/share/augeas/lenses/dist/cgconfig.aug
    augtool << EOT
set /files/etc/puppet/puppet.conf/agent/pluginsync true
set /files/etc/puppet/puppet.conf/agent/server ceph-mon0.test
save
EOT

fi

# And finally, run the puppet agent
puppet agent $AGENT_OPTIONS

# Run two more times on MON servers to generate & export the admin key
if hostname | grep -q "ceph-mon"; then
    puppet agent $AGENT_OPTIONS
    puppet agent $AGENT_OPTIONS
fi

# Run 4/5 more times on OSD servers to get the admin key, format devices, get osd ids, etc. …
if hostname | grep -q "ceph-osd"; then
    for STEP in $(seq 0 4); do
        echo ================
        echo   STEP $STEP
        echo ================
        blkid > /tmp/blkid_step_$STEP
        facter --puppet|egrep "blkid|ceph" > /tmp/facter_step_$STEP
        ceph osd dump > /tmp/ceph-osd-dump_step_$STEP

        puppet agent $AGENT_OPTIONS
    done
fi
