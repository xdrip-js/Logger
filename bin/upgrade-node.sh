#!/bin/bash

# This script will upgrade node to v8 if not already at least on that version
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

#install/upgrade to latest node 8 if neither node 8 nor node 10+ LTS are installed
if ! nodejs --version | grep -e 'v8\.' -e 'v1[02468]\.' &> /dev/null ; then
        echo "Node version not at v8 - upgrading ..."
        if ! uname -a | grep -e 'armv6' &> /dev/null ; then
            sudo bash -c "curl -sL https://deb.nodesource.com/setup_8.x | bash -" || die "Couldn't setup node 8"
            sudo apt-get install -y nodejs=8.* || die "Couldn't install nodejs"
        else
            sudo apt-get install -y nodejs npm || die "Couldn't install nodejs and npm"
            npm install npm@latest -g || die "Couldn't update npm"
        fi
else
    echo "Node version already at v8 - good to go"
fi
