use inc::Module::Install;
 
name     'App-Netdisco';
license  'bsd';
all_from 'Netdisco/lib/App/Netdisco.pm';

build_subdirs 'Netdisco';

resources
  homepage => 'http://netdisco.org/',
  bugtracker => 'http://sourceforge.net/p/netdisco/bugs/',
  repository => 'git://git.code.sf.net/p/netdisco/netdisco-ng',
  MailingList => 'https://lists.sourceforge.net/lists/listinfo/netdisco-users';

WriteAll;
