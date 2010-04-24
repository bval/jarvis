#!/usr/bin/perl
$ENV{'PATH'}='/usr/local/bin:/usr/bin:/bin';
$ENV{'IFS'}=' \t\n';
BEGIN { unshift @INC, './lib' if -d './lib'; }

use Data::Dumper;
use Jarvis::IRC;
use Jarvis::Jabber;
#use Jarvis::Personality::Jarvis;
#use Jarvis::Personality::Crunchy;
#use Jarvis::Personality::Watcher;
use POE::Builder;

my $session = new POE::Builder( 
                                {
                                  'alias' => 'interactive', 
                                  'debug' => '0',
                                  'trace' => '1',
                                } 
                              );
   $session->create();
   $session->add_poe_object( 
                             new Jarvis::IRC(
                                              {
                                                'alias'        => 'irc_client',
                                                'nickname'     => 'fapestniegd',
                                                'ircname'      => 'Optimus Prime',
                                                'server'       => 'irc.debian.org',
                                                'channel_list' => [ 
                                                                    '#puppies',
                                                                  ]
                                              }
                                            ), 
                           );
   $session->add_poe_object( 
                             new Jarvis::Jabber(
                                                 {
                                                   'ip'              => 'thor.websages.com',
                                                   'port'            => '5222',
                                                   'domain'          => 'websages.com',
                                                   'username'        => 'crunchy',
                                                   'password'        => $ENV{'XMPP_PASSWORD'},
                                                   'alias'           => 'xmpp_client',
                                                   'parent_session'  => 'interactive',
                                                 }
                                               ), 
                           );

POE::Kernel->run();

print STDERR "\n\n\n\n\n".Data::Dumper->Dump([$session]);