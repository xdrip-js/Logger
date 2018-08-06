#!/bin/bash

#install/upgrade to node 8
if ! nodejs --version | grep 'v8.'; then
    echo "Node version not at v8 - upgrading ..."
    if grep -qa "Explorer HAT" /proc/device-tree/hat/product &>/dev/null ; then
        mkdir $HOME/src/node && cd $HOME/src/node
        wget https://nodejs.org/dist/v8.10.0/node-v8.10.0-linux-armv6l.tar.xz
        tar -xf node-v8.10.0-linux-armv6l.tar.xz || die "Couldn't extract Node"
        cd *6l && sudo cp -R * /usr/local/ || die "Couldn't copy Node to /usr/local"
    else
        sudo bash -c "curl -sL https://deb.nodesource.com/setup_8.x | bash -" || die "Couldn't setup
 node 8" 
        sudo apt-get install -y nodejs || die "Couldn't install nodejs" 
    fi
else
    echo "Node version already at v8 - good to go"
fi

