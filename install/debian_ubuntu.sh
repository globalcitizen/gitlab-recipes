#!/bin/sh

# GITLAB
# Maintainer: @randx
# App Version: 2.9

# ABOUT
# This script performs only PARTIAL installation of Gitlab:
# * packages update
# * redis, git, postfix etc
# * ruby setup
# * git, gitlab users
# * gitolite fork
# It should be run as root.

# WARNINGS
# * Performs 'apt-get -y update' and 'apt-get -y upgrade'

# NOTES
# * Double check that your hostname resolves properly.
#   Lack of proper resolution may lead to incorrect installation.
#   (eg. when generating within an LXC (Linux Container), as some
#    versions of 'lxc-debian' generate guests with this issue.)

apt-get -y update
apt-get -y upgrade
apt-get -y install sudo

apt-get install -y git git-core wget curl gcc checkinstall libxml2-dev libxslt-dev sqlite3 libsqlite3-dev libcurl4-openssl-dev libreadline6-dev libc6-dev libssl-dev libmysql++-dev make build-essential zlib1g-dev libicu-dev redis-server openssh-server python-dev python-pip libyaml-dev postfix

wget http://ftp.ruby-lang.org/pub/ruby/1.9/ruby-1.9.3-p194.tar.gz
tar xfvz ruby-1.9.3-p194.tar.gz
cd ruby-1.9.3-p194
./configure
make
make install

adduser \
  --system \
  --shell /bin/sh \
  --gecos 'git version control' \
  --group \
  --disabled-password \
  --home /home/git \
  git

adduser --disabled-login --gecos 'gitlab system' gitlab

usermod -a -G git gitlab

sudo -H -u gitlab ssh-keygen -q -N '' -t rsa -f /home/gitlab/.ssh/id_rsa

cd /home/git
sudo -H -u git git clone git://github.com/gitlabhq/gitolite /home/git/gitolite

sudo -u git -H sh -c "PATH=/home/git/bin:$PATH; /home/git/gitolite/src/gl-system-install"
cp /home/gitlab/.ssh/id_rsa.pub /home/git/gitlab.pub
chmod 777 /home/git/gitlab.pub

sudo -u git -H sed -i 's/0077/0007/g' /home/git/share/gitolite/conf/example.gitolite.rc
sudo -u git -H sh -c "PATH=/home/git/bin:$PATH; gl-setup -q /home/git/gitlab.pub"

chmod -R g+rwX /home/git/repositories/
chown -R git:git /home/git/repositories/

sudo -u gitlab -H sh -c 'echo "Host localhost\n\tStrictHostKeyChecking no\n" >> ~gitlab/.ssh/config'

sudo -u gitlab -H git clone git@localhost:gitolite-admin.git /tmp/gitolite-admin
rm -rf /tmp/gitolite-admin

gem install charlock_holmes --version 0.6.8
pip install pygments
sudo gem install bundler
cd /home/gitlab

# Get gitlab code. Use this for stable setup
sudo -H -u gitlab git clone -b stable https://github.com/gitlabhq/gitlabhq.git gitlab

# Skip this for stable setup.
# Master branch (recent changes, less stable)
sudo -H -u gitlab git clone -b master https://github.com/gitlabhq/gitlabhq.git gitlab

cd gitlab

# Rename config files
sudo -u gitlab cp config/gitlab.yml.example config/gitlab.yml

# Setup SQLite as database
sudo -u gitlab cp config/database.yml.sqlite config/database.yml

# Install gems
sudo -u gitlab -H bundle install --without development test --deployment

# Initialize database
sudo -u gitlab bundle exec rake gitlab:app:setup RAILS_ENV=production

# Initialize post-receive hook (links commits to gitolite through to gitlab)
cp ./lib/hooks/post-receive /home/git/.gitolite/hooks/common/post-receive
chown git:git /home/git/.gitolite/hooks/common/post-receive
chmod g+x /home/git/.gitolite

# Check status
sudo -u gitlab bundle exec rake gitlab:app:status RAILS_ENV=production

# Setup lighttpd as frontend web server
apt-get -y install lighttpd
update-rc.d lighttpd defaults
cd /etc/lighttpd/conf-available
wget https://raw.github.com/gitlabhq/gitlab-recipes/master/lighttpd/10-gitlab.conf
#  - comment out SSL pemfile
sed -i -e 's/ *ssl.pemfile.*/# ssl.pemfile = "/some/file"/' 10-gitlab.conf
cd ../conf-enabled
ln -s ../conf-available/10-gitlab.conf
cd /home/gitlab/gitlab/config
cp unicorn.rb.example unicorn.rb
sed -i -e 's/listen.*/listen "127.0.0.1:8080"/' unicorn.rb

# Setup init script
cd /etc/init.d
wget https://raw.github.com/gitlabhq/gitlab-recipes/master/init.d/gitlab
chmod a+x gitlab
update-rc.d gitlab defaults

# Start
/etc/init.d/gitlab start
/etc/init.d/lighttpd start
echo "All done.  Now update /etc/lighttpd/conf-available/10-github.conf with FQDN & restart lighttpd."
