use inc::Module::Install;
 
name     'App-NetdiscoX-Web-Plugin-Observium';
license  'bsd';
all_from 'lib/App/NetdiscoX/Web/Plugin/Observium.pm';
 
install_share 'share';

resources
  homepage => 'http://netdisco.org/',
  bugtracker => 'http://sourceforge.net/p/netdisco/bugs/',
  repository => 'git://git.code.sf.net/p/netdisco/netdisco-ng',
  MailingList => 'https://lists.sourceforge.net/lists/listinfo/netdisco-users';

WriteAll;
