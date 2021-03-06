package Jarvis::Persona::System;
use parent Jarvis::Persona::Base;
use AI::MegaHAL;
use POE;
use POSIX qw( setsid );
use POE::Builder;
use LWP::UserAgent;
use LDAP::Simple;
use YAML;
use Sys::Hostname::Long;

sub known_personas{
    my $self=shift;
    my $host=hostname_long();
    $host=~s/\..*//g;
    $self->{'known_personas'} = $self->indented_yaml(<<"    ...");
    ---
     - name: crunchy
       persona:
         class: Jarvis::Persona::Crunchy
         init:
           alias: crunchy
           ldap_domain: websages.com
           ldap_binddn: cn=$host,ou=Hosts,dc=websages,dc=com
           ldap_bindpw: ${ENV{'LDAP_PASSWORD'}}
           twitter_name: capncrunchbot
           password: ${ENV{'TWITTER_PASSWORD'}}
           retry: 150
           start_twitter_enabled: 0
       connectors:
         - class: Jarvis::IRC
           init:
             alias: irc_client
             nickname: crunchy
             ircname: "Cap'n Crunchbot"
             server: 127.0.0.1
             domain: websages.com
             channel_list:
               - #soggies
             persona: crunchy
     - name: berry
       persona:
         class: Jarvis::Persona::Crunchy
         init:
           alias: berry
           ldap_domain: websages.com
           ldap_binddn: cn=$host,ou=Hosts,dc=websages,dc=com
           ldap_bindpw: ${ENV{'LDAP_PASSWORD'}}
           twitter_name: capncrunchbot
           password: ${ENV{'TWITTER_PASSWORD'}}
           retry: 150
           start_twitter_enabled: 1
       connectors:
         - class: Jarvis::IRC
           init:
             alias: berry_irc
             nickname: berry
             ircname: "beta Cap'n Crunchbot"
             server: 127.0.0.1
             domain: websages.com
             channel_list:
               - #twoggies
             persona: berry
    ...
}
    
sub must {
    my $self = shift;
    return  [ ];
}

################################################################################
# These are conventions for the way we set up hosts...
################################################################################
sub dnsdomainname{
    $self = shift;
    open DOMAIN, "dnsdomainname|"; 
    my $domain=<DOMAIN>; 
    close DOMAIN; 
    if($domain=~m/(.*)/){
        return $1;
    }
    return undef;
}

sub secret{
    $self = shift;
    open SECRET, "/usr/local/sbin/secret|"; 
    my $secret=<SECRET>; 
    close SECRET; 
    return $secret; 
}

sub binddn{
    $self = shift;
    open FQDN, "hostname -f|"; 
    my $fqdn=<FQDN>; 
    close FQDN; 
    my $bindn=$fqdn;
    my @bindparts=split(/\./,$fqdn);
    my $basename = shift(@bindparts);
    my $basedn = "ou=Hosts,dc=". join(",dc=",@bindparts);
    $binddn = "cn=". $basename . "," . $basedn;
    return $binddn;
}

################################################################################
# This depends on websages internal conventions if you don't define them...
################################################################################
sub may {
    my $self = shift;
    return  { 
              'brainpath' => '/dev/shm/brain/system' ,
              'ldap_domain'  => $self->dnsdomainname(),
              'ldap_binddn'  => $self->binddn(),
              'ldap_bindpw'  => $self->secret(),         #only works if run as root, supply instead
              'peer_group'   => "cn=bot_managed",
            };
    
}

sub peers{
    my $self = shift;
    return undef unless $self->{'ldap_domain'};
    return undef unless $self->{'ldap_binddn'};
    return undef unless $self->{'ldap_bindpw'};
    
    my $ldap = LDAP::Simple->new({ 
                                   'domain' => $self->{'ldap_domain'},
                                   'binddn' => $self->{'ldap_binddn'},
                                   'bindpw' => $self->{'ldap_bindpw'},
                                 });
    @peer_dns = $ldap->unique_members($self->{'peer_group'});
    while(my $dn=shift(@peer_dns)){
        $dn=~s/,.*//;
        $dn=~s/.*cn=//;
        push(@{ $self->{'peers'} },$dn);
    }
    return $self;
}

sub states{
     my $self = $_[OBJECT]||shift;
     return $self->{'states'};
}

sub persona_start{
    my $self=shift;
    my @brainpath = split('/',$self->{'brainpath'}); 
    shift(@brainpath); # remove the null in [0]
    # mkdir -p
    my $bpath="";
    while(my $append = shift(@brainpath)){
        $bpath = $bpath.'/'.$append;
        if(! -d $bpath ){ mkdir($bpath); }
    }
    if(! -f $self->{'brainpath'}."/megahal.trn"){ 
        my $agent = LWP::UserAgent->new();
        $agent->agent( 'Mozilla/5.0' );
        my $response = $agent->get("http://github.com/cjg/megahal/raw/master/data/megahal.trn");
        if ( $response->content ne '0' ) {
            my $fh = FileHandle->new("> $self->{'brainpath'}/megahal.trn");
            if (defined $fh) {
                print $fh $response->content;
                $fh->close;
            }
        }
    }
    $self->{'megahal'} = new AI::MegaHAL(
                                          'Path'     => $self->{'brainpath'},
                                          'Banner'   => 0,
                                          'Prompt'   => 0,
                                          'Wrap'     => 0,
                                          'AutoSave' => 1
                                        );
    $self->known_personas();
    $self->peers();
    return $self;
}

sub persona_states{
    my $self = $_[OBJECT]||shift;
    return { 
             'peer_check'            => 'peer_check',
           };
}

sub input{
    my ($self, $kernel, $heap, $sender, $msg) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0];
    # un-wrap the $msg
    my ( $sender_alias, $respond_event, $who, $where, $what, $id ) =
       ( 
         $msg->{'sender_alias'},
         $msg->{'reply_event'},
         $msg->{'conversation'}->{'nick'},
         $msg->{'conversation'}->{'room'},
         $msg->{'conversation'}->{'body'},
         $msg->{'conversation'}->{'id'},
       );
    my $direct=$msg->{'conversation'}->{'direct'}||0;
    if(defined($what)){
        if(defined($heap->{'locations'}->{$sender_alias}->{$where})){
            foreach my $chan_nick (@{ $heap->{'locations'}->{$sender_alias}->{$where} }){
                if($what=~m/^\s*$chan_nick\s*:*\s*/){
                    $what=~s/^\s*$chan_nick\s*:*\s*//;
                    $direct=1;
                }
            }
        }
        my $replies=[];
        ########################################################################
        #                                                                      #
        ########################################################################
        for ( $what ) {
            /^\s*!*help\s*/          && do { $replies = [ "i need a help routine" ] if($direct); last; };
            /^\s*!*spawn\s*(.*)/     && do { $replies = [ $self->spawn($1) ] if($direct); last;};
            /^\s*!*terminate\s*(.*)/ && do { 
                                             my $persona=$1; $persona=~s/^\s+//;
                                             if($direct){
                                                 my $r="stopping $persona [ ";
                                                 for (@{ $self->{'spawned'}->{$persona} }){ 
                                                     $r.="$_ ";
                                                     $kernel->post($_,'_stop'); 
                                                 }
                                                 $r.="]";
                                                 $replies = [ $r ];
                                                 delete $self->{'spawned'}->{$persona};
                                                 last;
                                             }
                                           };
            /ping/                   && do { $kernel->post($sender,'say_public',$where,"$who: pong") if($direct); last; };
            /pong/                   && do { 
                                             $kernel->post(
                                                            $self->{'alias'},
                                                            'pending',
                                                            {
                                                              'reply_event' => 'pong',
                                                              'session'     => $sender->ID,
                                                              'sender_nick' => $who,
                                                              'channel'     => $where,
                                                            }
                                                          ) if($direct);
                                             last; 
                                           }; # bot storm!
            #/reload/                 && do { 
            #                                 # for each persona that has operator status
            #                                 #     join the room as the system persona
            #                                 #     have that persona op the system persona
            #                                 #     terminate the persona
            #                                 #     tell peer to spawn persona in control channel
            #                                 #     when persona shows up, give it operator status
            #                                 # quit the channel
            #                                 # reload
            #                               };
            /i don't understand/     && do { last; }; # bot storm!
            /.*/                     && do { $replies = [ "i don't understand"    ] if($direct); last; };
            /.*/                     && do { last; }
        }
        ########################################################################
        #                                                                      #
        ########################################################################
        if($direct==1){
            foreach my $line (@{ $replies }){
                if($msg->{'conversation'}->{'direct'} == 0){
                    if( defined($line) && ($line ne "") ){ $kernel->post($sender, $respond_event, $msg, $who.': '.$line); }
                }else{
                    if( defined($line) && ($line ne "") ){ $kernel->post($sender, $respond_event, $msg, $line); }
                }
            }
        }else{
            foreach my $line (@{ $replies }){
                    if( defined($line) && ($line ne "") ){ $kernel->post($sender, $respond_event, $msg, $line); }
            }
        }
    }
    return $self->{'alias'};
}

sub spawn{
    my $self=shift;
    my $persona = shift if @_;
    $persona=~s/^\s+//;
    my $found=0;
    if(defined( $self->{'spawned'}->{$persona} )){
        return "Please terminate existing $persona sessons before attempting to spawn another.";
    }
    foreach my $p (@{ $self->{'known_personas'} }){
        if($p->{'name'} eq $persona){
            my $poe = new POE::Builder({ 'debug' => '0','trace' => '1' });
            return undef unless $poe;
            $poe->object_session( $p->{'persona'}->{'class'}->new( $p->{'persona'}->{'init'} ) );
            push( @{ $self->{'spawned'}->{$persona} }, $p->{'persona'}->{'init'}->{'alias'} );

            foreach my $conn (@{ $p->{'connectors'} }){
                push( @{ $self->{'spawned'}->{$persona} }, $conn->{'init'}->{'alias'} );
                $poe->object_session( $conn->{'class'}->new( $conn->{'init'} ) );
            }
            return "$persona spawned."
        }
    }
    return "I don't know how to become $persona." if(!$found);
}

################################################################################
# let the personality know that the connector is now watching a channel
################################################################################
sub channel_add{
     #expects a constructor hash of { alias => <sender_alias>, channel => <some_tag>, nick => <nick in channel> }
    my ($self, $kernel, $heap, $construct) = @_[OBJECT, KERNEL, HEAP, ARG0];
         push ( 
                @{ $heap->{'locations'}->{ $construct->{'alias'} }->{ $construct->{'channel'} } },
                $construct->{'nick'}
              );
    $kernel->post($construct->{'alias'},'channel_members',$construct->{'channel'},'peer_check');
}

sub peer_check{
    my ($self, $kernel, $heap, $sender, $channel, $members) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0, ARG1];
    foreach my $peer (@{ $self->{'peers'} }){
        my $connector_alias=$kernel->alias_list($sender);
        my $thatsme=0;
        foreach my $nick (@{ $heap->{'locations'}->{$connector_alias}->{$channel} }){
            if($nick eq $peer){ $thatsme = 1; }
        }
        next if($thatsme);
        my $found=0;
        foreach my $member (@{ $members }){
            if($peer eq $member){ $found = 1; }
        }
        if($found == 1){
            $kernel->post(
                           $self->alias(),
                           'queue',
                           {
                             'session'      => $sender->ID,                 # to what session we post
                             'event'        => 'say_public',                # the event we post
                             'args'         => [ $channel ,"$peer: ping" ], # event arguments
                             'reply_event'  => 'pong',                      # the expected reply event
                             'next_event'   => undef,                       # the action to take on return event
                             'expire_event' => [                            # the action to take on return event expire
                                                 $sender->ID, 
                                                 'peer_no_reply',
                                                 $peer,
                                               ],
                             'expire'       => time() + 10,                 # when the return event expires
                           }
                         );

        }else{
            print STDERR "$peer not found in $channel\n";
        }
    }
}

# As long as the yaml lines up with itself, 
# you can indent as much as you want to keep the here statements pretty
sub indented_yaml{
     my $self = shift;
     my $iyaml = shift if @_;
     return undef unless $iyaml;
     my @lines = split('\n', $iyaml);
     my $min_indent=-1;
     foreach my $line (@lines){   
         my @chars = split('',$line);
         my $spcidx=0;
         foreach my $char (@chars){
             if($char eq ' '){
                 $spcidx++;
             }else{
                 if(($min_indent == -1) || ($min_indent > $spcidx)){
                     $min_indent=$spcidx;
                 }
             }
         }
     }
     foreach my $line (@lines){
         $line=~s/ {$min_indent}//;
     }
     my $yaml=join("\n",@lines)."\n";
     return YAML::Load($yaml);
}

1;
