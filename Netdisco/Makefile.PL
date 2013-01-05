use inc::Module::Install;
 
name     'App-Netdisco';
license  'bsd';
all_from 'lib/App/Netdisco.pm';
 
requires 'DBD::Pg' => 0;
requires 'DBD::SQLite' => 0;
requires 'DBIx::Class' => 0;
requires 'DBIx::Class::Helper::Row::SubClass' => 0;
requires 'Daemon::Control' => 0;
requires 'Dancer' => 0;
requires 'Dancer::Plugin::DBIC' => 0;
requires 'File::ShareDir' => 0;
requires 'HTML::Entities' => 0;
requires 'HTTP::Tiny' => 0;
requires 'JSON' => 0;
requires 'List::MoreUtils' => 0;
requires 'MCE' => 1.304;
requires 'Net::MAC' => 0;
requires 'NetAddr::IP' => 0;
requires 'Path::Class' => 0;
requires 'Plack' => 0;
requires 'Role::Tiny' => 0;
requires 'SNMP::Info' => '2.11';
requires 'SQL::Translator' => 0;
requires 'Socket6' => 0;
requires 'Template' => 0;
requires 'YAML' => 0;
requires 'namespace::clean' => 0;
requires 'version' => 0;

install_share 'share';

install_script 'bin/netdisco-daemon-fg';
install_script 'bin/netdisco-daemon';
install_script 'bin/netdisco-db-deploy';
install_script 'bin/netdisco-deploy';
install_script 'bin/netdisco-web';

resources
  homepage => 'http://netdisco.org/',
  bugtracker => 'http://sourceforge.net/tracker/?group_id=80033&atid=558508',
  repository => 'git://netdisco.git.sourceforge.net/gitroot/netdisco/netdisco-ng',
  MailingList => 'https://lists.sourceforge.net/lists/listinfo/netdisco-users';

WriteAll;
