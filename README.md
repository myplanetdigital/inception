Inception
=========

  - Source: https://github.com/myplanetdigital/inception

A Drupal continuous integration infrastructure in a box. This currently
includes:

  - Jenkins
  - Drush
  - PHP
  - a simple build job (configured via `roles/config.yml`)

**Inception is in active development at Myplanet Digital, and should be
considered alpha code. Stability and full documentation not yet
guaranteed.**

Goals
-----

Why don't most developers use continuous integration? We think it's
because it's hard to know where to start. We'd like to make it as simple
as entering your cloud provider credentials (Rackspace/AWS/whatever) and
running a single command.

Features
--------

  - Jenkins integration with Github project via commit links.
  - [Authentications via GitHub credentials.][plugin-github-oauth]
    Anyone in a specified GitHub organization will be given access to
    the Jenkins UI. **This will not work locally on Vagrant.**

Quickstart
----------

### Setup

    $ curl -L get.rvm.io | bash -s 1.14.1
    $ source ~/.rvm/scripts/rvm
    $ git clone https://github.com/myplanetdigital/inception.git
    $ cd inception
    $ bundle exec librarian-chef install

### Configuration

While the default demo stack will boot without any custom configuration, you'll
likely want to tailor it to your needs.

  - Configure the build job settings in `roles/config.yml`. You'll need
    to register a GitHub application in order to enter credentials.
  - Customize the `data_bags/users` entries, which will be used by the
    [`user` cookbook][user-cookbook] to set up linux users with SSH
keys.  A sample entry `patcon.json` is provided, but please see the
cookbook documentation for more advanced configuration. Also, I enjoy
access to random machines, so please feel free to deploy my keys. (My
`ascii-clowns.sh` script has not been getting nearly enough use lately.
And who *doesn't* want ASCII clowns randomly inserted into every file in
their home directory?)

The next steps vary based on how you'd like to launch the Inception
stack.

### Vagrant

If you have Vagrant installed, you can test the setup on local virtual
machines:

    $ bundle exec vagrant up  # Spin up the VM
    $ bundle exec vagrant ssh # SSH into the VM

You can now view the Jenkins UI at: http://localhost:8080

Please see the [known issue](#known-issues) below regarding problems
with Jenkins when restarting the VM with `vagrant reload`.

You can also access this virtual jenkins through the command-line by
running:

    $ bundle exec jenkins configure --host=localhost --port=8080
    $ bundle exec jenkins --help

### Cloud

If you have an Amazon Web Services or Rackspace account, there are
several ways to host Inception in the cloud (going from simplest to more
complex):

  - Provisioned as a standalone server with Chef Solo.
  - Provisioned as part of a hosted Chef Server setup via Opscode
    Platform.
  - Provisioned as part of a self-hosted Chef Server setup.

Keep in mind that you will need to self-host the Jenkins server
regardless. It is only the Chef Server hosting that varies: none,
hosted, or self-hosted. If you have no plans to expand your
infrastructure, provisioning a server via Chef Solo should work fine,
and there will be less overhead to worry about.

#### Stand-alone Chef Solo

Assuming you have received credentials (root password and IP address)
for a fresh server running Ubuntu Lucid, run these commands substituting
an appropriate PROJECT name:

    $ echo -e "Host IP_ADDRESS\n  StrictHostKeyChecking no" >> ~/.ssh/config
    $ bundle exec ssh-forever root@<IP_ADDRESS> -i /path/to/ssh_key.pub -n jenkins-PROJECT
    $ # Enter root password when prompted.
    $ ssh jenkins-PROJECT "curl -L http://www.opscode.com/chef/install.sh | bash /dev/stdin -v 0.10.8-3"
    $ ssh jenkins-PROJECT "apt-get install rsync"
    $ rsync -avz cookbooks data_bags cookbooks-override roles misc jenkins-PROJECT:/tmp/chef-solo/
    $ ssh jenkins-PROJECT "chef-solo -c /tmp/chef-solo/misc/solo.rb -j /tmp/chef-solo/misc/solo-dna.json"

**Notes:** The [chef-solo-search][chef-solo-search] cookbook is simply a
container for a library that allows for chef-server search functions
that are not available in native chef-solo. See that project's README
for documentation.

More coming soon...

#### Hosted via Opscode Platform

Opscode platform is a hosted Chef server that is free for managing up to
5 servers. This should be more than enough for each project-specific CI
setup.

We'll be including various Rake tasks to automate the setup process as
much as possible. These rake tasks will attempt to use a browser
webdriver to fill out web forms and perform simple setup tasks for you.

You may view the available tasks from the project root by running `rake
-D` (for full descriptions) or `rake -T` (for short descriptions)

More coming soon...

#### Self-hosted Chef Server

Coming soon...

Known Issues
------------

  - Seems that any restart of Jenkins in a VM causes it to be
    unavailable from the host, even though it's still running. This is
    not an issue when deployed to an actual server. Since chef can't
    programmatically restart Jenkins in order to load some initial
    configuration, we'll need to do this manually through the UI after boot:

    Manage Jenkins > Reload Configuration from Disk

  - Current timezone is hardcoded for `America/Toronto` in
    `/etc/timezone`. Perhaps better to set a JAVA_ARG in
    `/etc/default/jenkins`.
  - When GitHub authentication isn't set up, default security allows
    free-for-all signups with immediate access. You'll want to signup
    your first admin user, and then lock down Jenkins:

    Manage Jenkins > Configure System > Security Realm >
    Jenkin's own user database > Allow users to sign up (UNCHECK)

To Do
-----

  - Convert chef-solo provisioning steps to rake task.
  - Include a base Drupal install profile to show file structure and
    bare minimum scripting expectations.
  - Figure out why jenkins in VM can't be restarted. Maybe add apache
    webserver to solve?
  - Use `cap` instead of ssh-forever. (For one, ssh-forever doesn't
    allow for turning of StrictHostKeyChecking.)
  - Add [spiceweasel][spiceweasel-project] support for launching into
    the cloud when using chef-server.
  - Provide instructions on using with Opscode hosted Chef server?
  - Use watir-webdriver and rake to create an opscode hosted chef
    account and/or create a new hosted chef organization.
  - Create a chef server as a multi-VM Vagrant environment (or use
    [Hatch][hatch-project]?)

<!-- Links -->
   [hatch-project]:            http://xdissent.github.com/chef-hatch-repo/
   [spiceweasel-project]:      http://wiki.opscode.com/display/chef/Spiceweasel
   [chef-solo-search]:         https://github.com/edelight/chef-solo-search#readme
   [user-cookbook]:            https://github.com/fnichol/chef-user#readme
   [plugin-github-oauth]:      https://wiki.jenkins-ci.org/display/JENKINS/Github+OAuth+Plugin
