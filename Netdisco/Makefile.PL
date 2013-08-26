use inc::Module::Install;
 
name     'App-Netdisco';
license  'bsd';
all_from 'lib/App/Netdisco.pm';
 
requires 'Algorithm::Cron' => 0.07;
requires 'App::cpanminus' => 1.6108;
requires 'App::local::lib::helper' => 0.07;
requires 'DBD::Pg' => 0;
requires 'DBD::SQLite' => 1.37;
requires 'DBIx::Class' => 0.08210;
requires 'DBIx::Class::Helpers' => 2.016006;
requires 'Daemon::Control' => 0.001000;
requires 'Dancer' => 1.3112;
requires 'Dancer::Plugin::DBIC' => 0.1802;
requires 'Dancer::Plugin::Auth::Extensible' => 0.20;
requires 'File::ShareDir' => 1.03;
requires 'HTML::Parser' => 3.70;
requires 'HTTP::Tiny' => 0.029;
requires 'JSON' => 0;
requires 'List::MoreUtils' => 0.33;
requires 'MIME::Base64' => 3.13;
requires 'Moo' => 1.001000;
requires 'MCE' => 1.408;
requires 'Net::Domain' => 1.23;
requires 'Net::DNS' => 0.72;
requires 'Net::MAC' => 2.103622;
requires 'NetAddr::IP' => 4.068;
requires 'Path::Class' => 0.32;
requires 'Plack' => 1.0023;
requires 'Plack::Middleware::Expires' => 0.03;
requires 'Role::Tiny' => 1.002005;
requires 'Socket6' => 0.23;
requires 'Starman' => 0.3008;
requires 'SNMP::Info' => 3.05;
requires 'SQL::Translator' => 0.11016;
requires 'Template' => 2.24;
requires 'YAML' => 0.84;
requires 'YAML::XS' => 0.41;
requires 'namespace::clean' => 0.24;
requires 'version' => 0.9902;

install_share 'share';

install_script 'bin/nd-import-topology';
install_script 'bin/netdisco-db-deploy';
install_script 'bin/netdisco-deploy';
install_script 'bin/netdisco-do';
install_script 'bin/netdisco-daemon-fg';
install_script 'bin/netdisco-daemon';
install_script 'bin/netdisco-web-fg';
install_script 'bin/netdisco-web';

resources
  homepage => 'http://netdisco.org/',
  bugtracker => 'http://sourceforge.net/p/netdisco/bugs/',
  repository => 'git://git.code.sf.net/p/netdisco/netdisco-ng',
  MailingList => 'https://lists.sourceforge.net/lists/listinfo/netdisco-users';

WriteAll;
