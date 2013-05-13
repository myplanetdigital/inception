current_dir = File.dirname(__FILE__)
# Import configs from YAML file.
yml = YAML.load_file "#{current_dir}/config.yml"

name "jenkins"
description "The base role for setting up the jenkins master with appropriate initial settings."
run_list([
  "role[base]",
  "role[apache2_mod_php]",
  "role[mysql_server]",
  "recipe[php]",
  "role[drupal]",
  "recipe[postfix]",
  "recipe[php::module_memcache]",
  "recipe[php::module_memcached]",
  "recipe[php::write_inis]",
  "recipe[drush::utils]",
  "recipe[drush::make]",
  "recipe[jenkins::server]",
  "recipe[jenkins::proxy_apache2]",
  "role[dev_tools]",
  "recipe[inception]",
  "recipe[inception::compass]",
])
default_attributes({
  "drush" => {
    "version" => "5.9.0",
  },
  # Import YAML config array directly into node object.
  "inception" => yml,
  "jenkins" => {
    "http_proxy" => {
      "variant" => "apache2",
      # Empty string disables http basic auth
      "basic_auth_password" => "",
      "host_name" => yml['domain'],
    },
    "server" => {
      "host" => "0.0.0.0",
      "plugins" => [
        "analysis-core",
        "ansicolor",
        "build-pipeline-plugin",
        "checkstyle",
        "disk-usage",
        "git",
        "git-client",
        "github",
        "github-api",
        "github-oauth",
        "greenballs",
        "instant-messaging",
        "ircbot",
        "jobConfigHistory",
        "pegdown-formatter",
        "project-description-setter",
        "token-macro",
        "ws-cleanup",
      ]
    }
  },
  "postfix" => {
    "mydomain" => "$myhostname",
  },
})
