#!/bin/bash

# This script will upgrade node to v8 if not already on that version
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

die() {
  echo "$@"
  exit 1
}

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

