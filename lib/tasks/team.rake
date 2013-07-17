namespace :team do
  task :github_auth do
    require 'hub'
    require './lib/ext/hub'
    require 'octokit'

    github_host = ENV['GITHUB_HOST'] || 'github.com'
    hub_config_file = ENV['HUB_CONFIG'] || '~/.config/hub'

    puts "Authorizing with GitHub..."

    unless File.exists? File.expand_path(hub_config_file)
      puts "You will be asked for your GitHub credentials."
      puts "These will NOT be stored on disk, but will be used to generate an access token."

      # Force auth with hub gem, ensuring hub config file present.
      Hub::Commands.send(:api_client).force_auth
    end

    hub_config = load_yaml File.expand_path(hub_config_file)

    @github_user = hub_config[github_host][0]['user']
    github_token = hub_config[github_host][0]['oauth_token']

    # Authenticate github client.
    @client = Octokit::Client.new(:login => @github_user, :oauth_token => github_token)
  end

  desc "Create and update config file."
  task :configure do
    Rake::Task["load_config"].invoke
    require 'highline/import'
    require './lib/ext/highline'
    require 'hashery/ordered_hash'
    require 'pwqgen'

    config_defaults = Hashery::OrderedHash.new
    config_defaults['project'] = 'newproject'
    config_defaults['domain'] = "ci.newproject.example.com"
    config_defaults['repo'] = "https://github.com/myplanetdigital/drupal-skeletor.git"
    config_defaults['branch'] = 'develop'
    config_defaults['password'] = Pwqgen.generate(4)
    config_defaults['timezone'] = 'America/Toronto'
    config_defaults['build_jobs'] = [
      'commit',
      'deploy-dev',
      'deploy-stage',
      'deploy-prod',
    ]
    config_defaults['manual_trigger_jobs'] = [
      'deploy-stage',
      'deploy-prod',
    ]

    config_defaults.each_key do |key|
      @config[key] = ask("#{key}?  ") do |q|

        # If Array, convert to string for easy default display.
        # (We'll convert back later.)
        q.default = @config[key] || config_defaults[key]
        if config_defaults[key].kind_of?(Array)
          q.default = q.default.join(',')
        end

        # Make sure we don't have whitespace, especially for joined arrays.
        q.whitespace = :remove

      end.to_s # << See: https://github.com/engineyard/engineyard/pull/152
    end

    # Split the string into an array if the default is of that type.
    config_defaults.delete_if { |k,v| !v.kind_of?(Array) }.each do |key, array_string|
      @config[key] = @config[key].split(',')
    end

    # Write config.yml
    File.open(@config_file, 'w') do |out|
      YAML::dump(@config, out)
    end
  end

  desc "Generate users from team in GitHub organization."
  task :generate_users, :github_org do |t, args|
    Rake::Task["load_config"].invoke
    Rake::Task["team:github_auth"].invoke
    repo_url = @config['repo']
    github_org = /.*[:\/](.+)\/(.+)\.git/.match(repo_url)[1]
    args.with_defaults(:github_org => github_org)

    require 'json'
    require 'highline/import'

    # Prevents odd 'input stream is exhausted' error in ruby-1.8.7.
    HighLine.track_eof = false

    github_org = args.github_org

    # Get a listing of teams for GitHub organization and present to user.
    all_teams_data = @client.organization_teams(github_org)

    selected_team_index = ''
    choose do |menu|
      menu.prompt = "We will use one of the above #{github_org} GitHub teams to generate the appropriate user files.\n"
      menu.prompt << "Please enter the number corresponding to a team:  "

      team_names = all_teams_data.collect { |team| team['name'] }
      menu.choices(*team_names) do |choice|
        say "Generating files for team '#{choice}'..." 
        selected_team_index = team_names.index(choice)
      end
    end

    selected_team_data = all_teams_data[selected_team_index]

    # Get team members and generate username.json files for each.
    team_members_data = @client.team_members(selected_team_data['id'])
    team_members_data.each do |team_member|

      # Generate json user file
      user_file_path = "data_bags/users/#{team_member['login']}.json"
      unless File.exists?(user_file_path)
        user_data = @client.user(team_member['login'])
        # This call doesn't exist yet, so calling manually.
        user_keys_data = Octokit.get("users/#{user_data['login'].downcase}/keys", {})

        file = File.open(user_file_path, "w")
        user_data_bag_item = {
          :id => user_data['login'].downcase,
          :comment => user_data['name'] || '',
          :shell => "/bin/zsh",
          :groups => ["sysadmin"],
          :ssh_keys => user_keys_data.collect { |entry| entry['key'] },
        }
        file.puts JSON.pretty_generate(user_data_bag_item)
        file.close
        say "Generated file for #{team_member['login']}."
      else
        say "File for #{team_member['login']} already exists. Skipping..."
      end
    end
  end

  desc "Creates and/or enables Jenkins service hook on GitHub.

  This can be run at any time, and will create/modify a new or existing service
  hook."
  task :service_hook, :github_repo  do |t, args|
    Rake::Task["load_config"].invoke
    repo_url = @config['repo']
    github_org = /.*[:\/](.+)\/(.+)\.git/.match(repo_url)[1]
    github_repo = /.*[:\/](.+)\/(.+)\.git/.match(repo_url)[2]
    args.with_defaults(:github_repo => "#{github_org}/#{github_repo}")

    if args.github_repo.nil? || args.github_repo.split('/').length < 2
      raise "Requires :github_repo argument in format `username/repo`!"
    end

    # Use hub gem to authenticate against API.
    Rake::Task["team:github_auth"].invoke

    require 'ostruct'

    project = OpenStruct.new
    project.host = 'github.com'
    project.owner = args.github_repo.split('/')[0]
    project.name = args.github_repo.split('/')[1]

    hook_data = {
      :name => 'jenkins',
      :config => {
        :jenkins_hook_url => "http://#{@config['domain']}/github-webhook/"
      }
    }

    puts "Creating service hook..."
    Hub::Commands.send(:api_client).create_webhook(project, hook_data)

    puts "Jenkins commit hook successfully created/activated for GitHub project #{args.github_repo}:"
    puts hook_data[:config][:jenkins_hook_url]

  end

  desc "Fork the Skeletor project into a new repo.

  Creates a new private repo for an organization. Requires an argument be
  passed in the format of 'organization/repo'.

  Example: myplanetdigital/newproject"
  task :fork_skeletor, :github_repo do |t, args|
    Rake::Task["load_config"].invoke
    Rake::Task["team:github_auth"].invoke
    repo_url = @config['repo']
    github_org = /.*[:\/](.+)\/(.+)\.git/.match(repo_url)[1]
    github_repo = /.*[:\/](.+)\/(.+)\.git/.match(repo_url)[2]
    args.with_defaults(:github_repo => "#{github_org}/#{github_repo}")

    options = {}
    options[:private] = true
    if args.github_repo.split('/').length == 1
      repo = args.github_repo
    else
      org, repo = args.github_repo.split('/')
      options[:organization] = org
    end
    response = @client.create_repo(repo, options)

    # See: http://stackoverflow.com/a/8791484/504018
    def in_tmpdir
      require 'tmpdir'
      path = File.expand_path "#{Dir.tmpdir}/#{Time.now.to_i}#{rand(1000)}/"
      FileUtils.mkdir_p path
      yield path
    ensure
      FileUtils.rm_rf( path ) if File.exists?( path )
    end

    in_tmpdir do |tmpdir|
      skeletor_uri = 'git://github.com/myplanetdigital/drupal-skeletor.git'
      FileUtils.cd(tmpdir) do
        system "git init"
        system "git remote add upstream #{skeletor_uri}"
        system "git remote add origin #{response['ssh_url']}"
        system "git pull upstream master"
        system "git submodule update --init --recursive"
        system "PATH=$PATH:$PWD/tmp/scripts/rerun/core RERUN_MODULES=$PWD/tmp/scripts/rerun/custom_modules rerun renamer:rename --to #{repo} --repo #{org}/#{repo}"
        system "git push origin master"
      end
    end

  end

  desc "Adds Jenkins deploy key to GitHub repo."
  task :add_deploy_key, :github_repo, :ssh_username do |t, args|
    Rake::Task["load_config"].invoke
    Rake::Task["team:github_auth"].invoke
    repo_url = @config['repo']
    github_org = /.*[:\/](.+)\/(.+)\.git/.match(repo_url)[1]
    github_repo = /.*[:\/](.+)\/(.+)\.git/.match(repo_url)[2]
    args.with_defaults(:github_repo => "#{github_org}/#{github_repo}", :ssh_username => @github_user)

    # SSH into jenkins server and get pub key contents.
    puts "Retrieving Jenkins user public key from #{@config['domain']}..."
    contents = %x[ssh #{args.ssh_username}@#{@config['domain']} 'sudo cat ~jenkins/.ssh/id_rsa.pub'].chomp
    title = 'jenkins'

    puts "Adding deploy key..."
    @client.add_deploy_key(args.github_repo, title, contents)
    puts "Successfully added '#{title}' deploy key to repo '#{args.github_repo}'!"
    puts "You can view the key at: https://github.com/#{args.github_repo}/settings/keys"
  end

  desc "Rsync project config files into place.

  This task is only useful when the Inception project is nested within a
  project repo as a submodule."
  task :rsync_project_configs do
    puts "Attempting to rsync inception config files from containing project..."
    if File.exists? File.expand_path('../../conf/jenkins-inception')
      puts "Detected containing project. Rsync'ing files into place."
      system "rsync --recursive ../../conf/jenkins-inception/* ."
    else
      puts "Inception does not appear to be nested within a project, or config files not present."
      puts "No rsync action taken."
    end
  end

  desc "Sync files with remote server, and start chef run.

  First syncs cookbooks and project config files with remote server, then
  initializes chef run to converge jenkins server on desired state."
  task :update_jenkins, :ssh_user do |t, args|
    Rake::Task["load_config"].invoke
    Rake::Task["team:github_auth"].invoke
    Rake::Task["team:rsync_project_configs"].invoke
    args.with_defaults(:ssh_user => @github_user)
    system "rm nodes/#{@config['domain']}.json"
    system "bundle exec knife solo bootstrap #{args.ssh_user}@#{@config['domain']} --run-list='role[jenkins]'"
  end
end
