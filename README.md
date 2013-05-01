Inception
=========

![Build pipeline
screenshot](https://www.evernote.com/shard/s27/sh/80368a8d-62c5-4739-b33e-3e986f145bd3/8d7d0f7730534611b0c5bfa1bbcb3af4/res/054729d9-d034-4a29-aae8-89017d74cf94/skitch.png)

**Current status: STABLE BUT UNDOCUMENTED.** (We use the tool internally
at Myplanet, but still need to document features and assumptions.)

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

We'll be building this out based on a set of assumptions regarding how
to best build a Drupal site. This set of assumptions will take the form
of the [Skeletor][skeletor] install profile skeleton. The goal will be
build a totally self-contained base profile, which other projects can
use as a foundation. Ideally, only slight configurations of the Jenkins
CI environment (ie. project name, and git repo URL) will be needed in
order to build any project that uses the Skeletor install profile as
a base.

Features
--------

  - Jenkins integration with Github project via commit links.
  - [Authentications via GitHub credentials.][plugin-github-oauth]
    Anyone in a specified GitHub organization will be given access to
    the Jenkins UI. **This will not work locally on Vagrant.**
  - Various [rake][about-rake] tasks for helping with everything from
    creating new Rackspace servers to adding GitHub service hooks. Type
    `rake -D` or `rake -T` to see available tasks.
  - Configured to boot the base demo of Skeletor install profile,
    right off the bat.
  - Testing tools configured:
    - PhantomJS
    - CasperJS
    - Xserver Virtual Framebuffer (xvfb)

Quickstart
----------

- Install Xcode with Command Line Tools from Apple Developer website.

    git clone https://github.com/myplanetdigital/jenkins-inception.git
    cd jenkins-inception
    [sudo] gem install bundler
    bundle install
    bundle exec rake team:configure
    bundle exec rake team:generate_users
    bundle exec rake team:fork_skeletor
    bundle exec rake admin:create_server
    bundle exec rake admin:create_subdomain
    bundle exec rake team:add_deploy_key
    bundle exec rake team:service_hook

### Configuration

The first thing you'll want to do is run the helper task to set up the
configuration file that will be used to provision Jenkins:

    bundle exec rake team:configure

While the default demo stack will boot without any custom configuration, you'll
likely want to tailor it to your needs.

  - Customize the `data_bags/users` entries, which will be used to set
    up Jenkins and linux users (with SSH access). A sample entry
    `patcon.json` is provided. If you would like to easily generate your
    own user files, there is an interactive helper task to help you generate
    these files for a team in your github organization.

        bundle exec rake "team:generate_users[myorganization]"

The next steps vary based on how you'd like to launch the Inception
stack.

### Vagrant

If you have Vagrant installed, you can test the setup on local virtual
machines:

    vagrant up  # Spin up the VM
    vagrant ssh # SSH into the VM

You can now view the Jenkins UI at: http://localhost:8080

A built site can be viewed at: http://JOB_NAME.inception.dev:8080

Currently, the latter requires adding entries to your host machine's
`/etc/hosts` file. (ie. `127.0.0.1 build-int.inception.dev`)

Please see the [known issue](#known-issues) below regarding problems
with Jenkins when restarting the VM with `vagrant reload`.

You can also access this virtual jenkins through the command-line by
running:

    jenkins configure --host=localhost --port=8080
    jenkins --help

### Cloud

If you have an Amazon Web Services or Rackspace account, there are
several ways to host Inception in the cloud (going from simplest to more
complex):

  - Provisioned as a standalone server with Chef Solo.
  - Provisioned as part of a hosted Chef Server setup via Opscode
    Platform.
  - Provisioned as part of a self-hosted Chef Server setup.

Keep in mind that you will need to self-host the *Jenkins* server
regardless. It is only the Chef Server hosting that varies: none,
hosted, or self-hosted. If you have no plans to expand your
infrastructure, provisioning a server via Chef Solo should work fine,
and there will be less overhead to worry about. This is what we'll focus
on.

#### Stand-alone Chef Solo

If you have a Rackspace account, you can easily spin up a stock server.
You'll need to have environment variables set for `RACKSPACE_USERNAME` and
`RACKSPACE_API_KEY`, and once logged in you can retrieve the latter at:

    https://mycloud.rackspace.com/a/RACKSPACE_USERNAME/account/api-keys

When you've set these environment variables in your shell, you may run:

   bundle exec rake "team:create_server[server-name]"

(The server name will be used to identify the instance in the Rackspace
web interface.)

As you recall from the configuration step above, you'll have a domain
where you plan to host your Jenkins instance. This requires the setup of
a DNS A-record using an external DNS provider. If this is not possible,
you may also edit your `/etc/hosts` file, but GitHub service hook won't
work out of the box. If you set the `domain` value in `config.yml` to be
`ci.example.com`, this is what you would use in your `hosts` file:

    123.123.123.123 ci.example.com

Jenkins will be available at `http://ci.example.com` from your local
machine.

Assuming you have received credentials (root password and IP address)
for a fresh server running Ubuntu Lucid, run the commands below, substituting
appropriate environment variables.

    export INCEPTION_PROJECT=projectname
    export INCEPTION_USER=patcon # Your username from the users data bag
    export INCEPTION_IP=123.45.67.89
    echo -e "\nHost $INCEPTION_PROJECT\n  User $INCEPTION_USER\n  HostName $INCEPTION_IP" >> ~/.ssh/config
    brew install ssh-copy-id
    ssh-copy-id root@$INCEPTION_IP
    knife solo bootstrap root@$INCEPTION_PROJECT --omnibus-version 10.16.6-1 --run-list 'role[jenkins]'

    # Subsequent runs can be carried out like so:
    knife solo cook $INCEPTION_PROJECT --skip-chef-check

**Notes:** The [chef-solo-search][chef-solo-search] cookbook is simply a
container for a library that allows for chef-server search functions
that are not available in native chef-solo. See that project's README
for documentation.

Provided that you've modified the `config.yml` to your needs, you may
use this helper task to add a service hook to your GitHub project:

   bundle exec rake "team:service_hook[mygithubuser/myproject]"

This will ensure that pushed to GitHub kick off the build pipeline.

Notes
-----

  - When GitHub authentication isn't set up, Jenkins will use the Unix
    user database from the server itself, which is set up based on the
    `users` databag entries with passwords.
  - Unfortunately, it seems that global read permissions need to be open
    for anonymous users in order for build jobs to be created
    programmatically by Chef. For now, the solution is to manually
    correct this after each Chef run:
    https://www.evernote.com/shard/s27/sh/de933bb2-4177-48f7-90f7-e3a7f9945c44/c0baf21b5502a1f87358487281ea20c8

Known Issues
------------

  - When using GitHub authorization, there is [an outstanding
    issue][github-auth-issue] that prevents us from authorizing
    programmatically, and therefore Chef cannot run authorized actions like
    updating builds. GitHub auth not recommended until this is fixed.
  - Every once in awhile, ruby 1.8.7 in the VM will throw a
    segmentation fault while installing `libmysql-ruby` during the chef
    run. It's sporadic, and reprovisioning should move past it.
  - LogMeIn Hamachi is known to cause issues with making `pear.php.net`
    unreachable, and so the environment won't build.
  - Generally, both ruby and its gems should be compiled using the same
    version of Xcode. If you get odd errors, remove ruby and its gems
    and recompile.

To Do
-----

  - Include a base Drupal install profile to show file structure and
    bare minimum scripting expectations.
  - Add feature to create DNS a-record if DynDNS API credentials are
    supplied in `config.yml`.
  - Add note on port forwarding 8080. (:auto?)
  - Add [spiceweasel][spiceweasel-project] support for launching into
    the cloud when using chef-server.
  - Provide instructions on using with Opscode hosted Chef server?
  - Create a chef server as a multi-VM Vagrant environment (or use
    [Hatch][hatch-project]?)
  - Investigate using [preSCMbuildstep plugin][plugin-preSCMbuildstep]
    for running `jenkins-setup.sh`
  - Investigate [hosted chef gem][hosted-chef-gem].
  - Create role hierarchy like in Ariadne.
  - Set up varnish.
  - Determine public vs private git repo and change job git url
    accordingly.

<!-- Links -->
   [hatch-project]:            http://xdissent.github.com/chef-hatch-repo/
   [spiceweasel-project]:      http://wiki.opscode.com/display/chef/Spiceweasel
   [chef-solo-search]:         https://github.com/edelight/chef-solo-search#readme
   [user-cookbook]:            https://github.com/fnichol/chef-user#readme
   [plugin-github-oauth]:      https://wiki.jenkins-ci.org/display/JENKINS/Github+OAuth+Plugin
   [plugin-preSCMbuildstep]:   https://wiki.jenkins-ci.org/display/JENKINS/pre-scm-buildstep
   [about-rake]:               http://en.wikipedia.org/wiki/Rake_(software)
   [skeletor]:                 https://github.com/myplanetdigital/drupal-skeletor/blob/master/SKELETOR-README.md
   [hosted-chef-gem]:          https://github.com/opscode/hosted-chef-gem#readme
   [github-auth-issue]:        https://github.com/mocleiri/github-oauth-plugin/issues/18
