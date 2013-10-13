package RT::Interface::Web;

use strict;
no warnings qw(redefine);

package HTML::Mason::Commands;

use vars qw/$r $m %session/;


# {{{ sub LoadAsset - loads an asset

=head2  LoadAsset id

Takes an asset id as its only variable. if it's handed an array, it takes
the first value.

Returns an RTx::AssetTracker::Asset object as the current user.

=cut

sub LoadAsset {
    my $id = shift;

    if ( ref($id) eq "ARRAY" ) {
        $id = $id->[0];
    }

    unless ($id) {
        Abort("No asset specified");
    }

    my $Asset = RTx::AssetTracker::Asset->new( $session{'CurrentUser'} );
    $Asset->Load($id);
    unless ( $Asset->id ) {
        Abort("Could not load asset $id");
    }
    return $Asset;
}

# }}}



=head2 ProcessAssetBasics ( AssetObj => $Asset, ARGSRef => \%ARGS );

Returns an array of results messages.

=cut

sub ProcessAssetBasics {

    my %args = (
        AssetObj => undef,
        ARGSRef   => undef,
        TransactionData => undef,
        @_
    );

    my $AssetObj = $args{'AssetObj'};
    my $ARGSRef  = $args{'ARGSRef'};

    # Set basic fields 
    my @attribs = qw(
        Name
        Description
        Status
        Type
    );

    # Canonicalize Type to its ID if it isn't numeric
    if ( $ARGSRef->{'Type'} and ( $ARGSRef->{'Type'} !~ /^(\d+)$/ ) ) {
        my $temp = RTx::AssetTracker::Type->new(RT->SystemUser);
        $temp->Load( $ARGSRef->{'Type'} );
        if ( $temp->id ) {
            $ARGSRef->{'Type'} = $temp->id;
        }
    }

    # Status isn't a field that can be set to a null value.
    # RT core complains if you try
    delete $ARGSRef->{'Status'} unless $ARGSRef->{'Status'};

    my @results = UpdateRecordObject(
        AttributesRef => \@attribs,
        Object        => $AssetObj,
        ARGSRef       => $ARGSRef
    );

    # }}}

    return (@results);
}


# {{{ sub ProcessAssetIPs

=head2 ProcessAssetIPs ( AssetObj => $Asset, ARGSRef => \%ARGS );

Returns an array of results messages.

=cut

sub ProcessAssetIPs {

    my %args = (
        AssetObj => undef,
        ARGSRef   => undef,
        IPComment => undef,
        @_
    );

    my $AssetObj = $args{'AssetObj'};
    my $ARGSRef   = $args{'ARGSRef'};

    my @results;
    my %ips;
    foreach my $key ( keys %$ARGSRef ) {

        if ($key =~ /^Asset-(\d+)-DeleteIP-(\d+)$/) {
            my ($rc, $msg) = $AssetObj->DeleteIP(IP => $2, TransactionData => $ARGSRef->{IPComment} || $ARGSRef->{GlobalComment});
            push @results, $msg;
            #delete $ARGSRef->{$key};
            next;
        }

        next unless ($key =~ /^Asset-(\d+)-Add(Interface|IP|MAC|TCPPorts|UDPPorts)(\d+)$/);
        $ips{$3}{$2} = $ARGSRef->{$key};
        delete $ARGSRef->{$key};

    }

    foreach my $ip (keys %ips) {
        next unless ( $ips{$ip}{IP} or $ips{$ip}{Interface} or $ips{$ip}{MAC} );
        
        $ips{$ip}{TCPPorts} =~ s/,/ /g;
        $ips{$ip}{UDPPorts} =~ s/,/ /g;
        my @TCPPorts = split(/\s+/, $ips{$ip}{TCPPorts});
        my @UDPPorts = split(/\s+/, $ips{$ip}{UDPPorts});

        # We should check for valid port numbers!

        my (undef, $msg) = $AssetObj->AddIP( IP => $ips{$ip}{IP},
                                             Interface => $ips{$ip}{Interface},
                                             MAC => $ips{$ip}{MAC},
                                             TCPPorts => \@TCPPorts,
                                             UDPPorts => \@UDPPorts,
                                             TransactionData => $ARGSRef->{IPComment} || $ARGSRef->{GlobalComment});
        push @results, $msg;
    }


    return (@results);
}

# }}}

sub ProcessAssetPorts {

    my %args = (
        AssetObj => undef,
        ARGSRef   => undef,
        IPComment => undef,
        @_
    );

    my $AssetObj = $args{'AssetObj'};
    my $ARGSRef   = $args{'ARGSRef'};

    my @results;
    my %ips;
    foreach my $key ( keys %$ARGSRef ) {

        next unless ($key =~ /^Asset-(\d+)-IP-(\d+)-(TCP|UDP)Ports$/);
            my ($asset, $ipid, $transport) = ($1, $2, $3);

        next if $ARGSRef->{"Asset-$asset-DeleteIP-$ipid"};
            my $ports = $ARGSRef->{$key};
            $ports =~ s/,/ /g;
            my @new_ports = split /\s+/, $ports;
            @new_ports = grep { /^\d+$/ } @new_ports;

            my $ip = RTx::AssetTracker::IP->new( $session{ CurrentUser } );
            $ip->Load($ipid);
            my $method = $transport."Ports";
            my @current_ports = $ip->$method();

            $method = "Delete".$transport."Port";
            foreach my $port (@current_ports) {
                next if  grep { $_ eq $port } @new_ports;
                    my ($rv, $msg) = $ip->$method($port, TransactionData => $ARGSRef->{IPComment} || $ARGSRef->{GlobalComment});
                    if ($rv) {
                        push @results, "$transport port $port deleted from IP " . $ip->IP;
                    } else {
                        push @results, "$transport port $port could not be deleted from IP " . $ip->IP . ": $msg";
                    }
            }

            $method = "Add".$transport."Port";
            foreach my $port (@new_ports) {
                next if grep { $_ eq $port } @current_ports;
                    my ($rv, $msg) = $ip->$method($port, TransactionData => $ARGSRef->{IPComment} || $ARGSRef->{GlobalComment});
                    if ($rv) {
                        push @results, "$transport port $port added to IP " . $ip->IP;
                    } else {
                        push @results, "$transport port $port could not be added to IP " . $ip->IP . ": $msg";
                    }
            }
    }

    return @results;
}

# {{{ sub ProcessAssetWatchers

=head2 ProcessAssetWatchers ( AssetObj => $Asset, ARGSRef => \%ARGS );

Returns an array of results messages.

=cut

sub ProcessAssetWatchers {
    my %args = (
        AssetObj => undef,
        ARGSRef   => undef,
        @_
    );
    my (@results);
$RT::Logger->debug("Processing asset watchers");

    my $Asset  = $args{'AssetObj'};
    my $ARGSRef = $args{'ARGSRef'};

    # {{{ Munge watchers

    foreach my $key ( keys %$ARGSRef ) {

        # {{{ Delete deletable watchers
        if ( ( $key =~ /^Asset-DeleteWatcher-Type-(.*)-Principal-(\d+)$/ )  ) {
            my ( $code, $msg ) = 
                $Asset->DeleteWatcher(PrincipalId => $2,
                                       Type => $1, TransactionData => $ARGSRef->{PeopleComment} || $ARGSRef->{GlobalComment});
            push @results, $msg;
        }

        # Delete watchers in the simple style demanded by the bulk manipulator
        elsif ( $key =~ /^Delete(\w+)$/ ) {	    
            my ( $code, $msg ) = $Asset->DeleteWatcher( Email => $ARGSRef->{$key}, Type => $1, TransactionData => $ARGSRef->{PeopleComment} || $ARGSRef->{GlobalComment} );
            push @results, $msg;
        }

        # }}}

        # Add new wathchers
        elsif ( ( $key =~ /^AddWatcher-Type-(\w+)$/ ) )
        {
            my $type = $1;
            foreach my $watcher (
                ref( $ARGSRef->{$key} ) ? @{ $ARGSRef->{$key} } : ( $ARGSRef->{$key} ) )
            {
                next unless ( $watcher =~ /^Principal-(\d+)$/ );
                my $WatcherId = $1;
                my ( $code, $msg ) = $Asset->AddWatcher(
                    PrincipalId => $WatcherId,
                    Type  => $type,
                    TransactionData => $ARGSRef->{PeopleComment} || $ARGSRef->{GlobalComment}
                );
                push @results, $msg;
            }
        }

        #Add requestors in the simple style demanded by the bulk manipulator
        elsif ( $key =~ /^Add(\w+)$/ ) {
            my ( $code, $msg ) = $Asset->AddWatcher(
                Type  => $1,
                Email => $ARGSRef->{$key},
                TransactionData => $ARGSRef->{PeopleComment} || $ARGSRef->{GlobalComment},
            );
            push @results, $msg;
        }

        # Add new  watchers by owner
        elsif ( ( $ARGSRef->{$key} =~ /^(AdminCc|Cc|Requestor)$/ )
            and ( $key =~ /^Asset-AddWatcher-Principal-(\d*)$/ ) ) {

            #They're in this order because otherwise $1 gets clobbered :/
            my ( $code, $msg ) =
              $Asset->AddWatcher( Type => $ARGSRef->{$key}, PrincipalId => $1, TransactionData => $ARGSRef->{PeopleComment} || $ARGSRef->{GlobalComment} );
            push @results, $msg;
        }
    }

    # }}}
    # Modify Asset watchers as given by Grid.html
    my $id = $Asset->id;
    for my $role ( RTx::AssetTracker::Type->RoleGroupTypes() ) {
        if (  $ARGSRef->{"Asset-$id-$role"}  ) {
            $ARGSRef->{"Asset-$id-$role"} =~ s/\r\n/\n/g;
            my $watchers = [split('\n', $ARGSRef->{"Asset-$id-$role"})];
            push @results,
                SetWatchers(
                   Asset => $Asset, Watchers => $watchers, Type => $role,
                   TransactionData => $ARGSRef->{PeopleComment}
                                   || $ARGSRef->{GlobalComment} );
        }
    }

    return (@results);
}

sub SetWatchers {

    my %args = @_;
    my $Asset = $args{Asset};
    my $Data  = $args{TransactionData};
    my @Watchers = @{$args{Watchers}};
    my $Type = $args{Type};
    my @results;

    my $TypeGroup = $Type."Group";
    my $Group   = $Asset->$TypeGroup;

    # Process user additions
    my $UserMembers = $Group->MembersObj;
    $UserMembers->LimitToUsers;
    foreach my $watcher (@Watchers) {
        next if $watcher =~ /^Group:/;
        my $user = RT::User->new( $session{CurrentUser} );
        my ($rv, $msg);
        if ($watcher =~ /\@/) {
           ($rv, $msg) = $user->LoadByEmail($watcher);
        }
        else {
           ($rv, $msg) = $user->Load($watcher);
        }
        unless ($rv) {
            push @results, "User: $watcher could not be found";
            next;
        }

        ($rv, $msg) = $Asset->AddWatcher(Type => $Type, PrincipalId => $user->PrincipalId);
        if ($rv) {
            push @results, "Added user: $watcher to $TypeGroup of " . $Asset->Name;
        }
        else {
            push @results, "Error adding user: $watcher to $TypeGroup: $msg"
                unless $msg =~ /principal is already/;
        }
    }

    # Process group additions
    my $GroupMembers = $Group->MembersObj;
    $GroupMembers->LimitToGroups;
    foreach my $watcher (@Watchers) {
        next unless $watcher =~ /^Group: *(.*)/;
        my $watcher_name = $1;
        my $group = RT::Group->new( $session{CurrentUser} );
        my ($rv, $msg);
        ($rv, $msg) = $group->LoadUserDefinedGroup($watcher_name);
        unless ($rv) {
            push @results, "Group: '$watcher_name' $msg";
            next;
        }

        ($rv, $msg) = $Asset->AddWatcher(Type => $Type, PrincipalId => $group->PrincipalId);
        if ($rv) {
            push @results, "Added group: '$watcher_name' to $TypeGroup of " . $Asset->Name;
        }
        else {
            push @results, "Error adding group: '$watcher_name' to $TypeGroup: $msg"
                unless $msg =~ /principal is already/;
        }
    }

    # Remove each watcher from the group if they aren't in @Watchers
    my $Members = $Group->MembersObj;
    while (my $member = $Members->Next) {

        my ($rv, $msg);
        my $principal = $member->MemberObj;
        if ($principal->IsGroup) {
            my $name = $principal->Object->Name;
            unless (grep {/Group\:\s*$name$/i} @Watchers) {
                ($rv, $msg) = $Asset->DeleteWatcher(Type => $Type, PrincipalId => $principal->Id);
                if ($rv) {
                    push @results, "Deleted group: '$name' from $TypeGroup of " . $Asset->Name;
                }
                else {
                    push @results, "Error deleting group: '$name' from $TypeGroup: $msg";
                }
            }
        }
        else {
            my $name  = $principal->Object->Name;
            my $email = $principal->Object->EmailAddress;
            unless ( (grep {/^$name$/i} @Watchers) || (grep {/^$email$/i} @Watchers)) {
                ($rv, $msg) = $Asset->DeleteWatcher(Type => $Type, PrincipalId => $principal->Id);
                if ($rv) {
                    push @results, "Deleted user: '$name' from $TypeGroup of " . $Asset->Name;
                }
                else {
                    push @results, "Error deleting user: '$name' from $TypeGroup: $msg";
                }
            }
        }
        
    }

    return @results;
}

# }}}

# {{{ sub CreateAsset

=head2 CreateAsset ARGS

Create a new asset, using Mason's %ARGS.  returns @results.

=cut

sub CreateAsset {
    my %ARGS = (@_);

    my (@Actions);

    my $Asset = new RTx::AssetTracker::Asset( $session{'CurrentUser'} );

    my $Type = new RTx::AssetTracker::Type( $session{'CurrentUser'} );
    unless ( $Type->Load( $ARGS{'Type'} ) ) {
        Abort('Type not found');
    }

    unless ( $Type->CurrentUserHasRight('CreateAsset') ) {
        Abort('You have no permission to create assets of that type.');
    }

    my %create_args = (
        Type            => $ARGS{'Type'},
        Name            => $ARGS{'Name'},
        Owner           => [],
        Admin           => [],
        Description     => $ARGS{'Description'},
        Status          => $ARGS{'Status'},
        TransactionData => $ARGS{'GlobalComment'},
    );
    foreach my $arg (keys %ARGS) {
            next if ($arg =~ /-Magic$/);
       #Object-RT::Ticket--CustomField-3-Values
        if ($arg =~ /^Object-RT::Transaction--CustomField-/) {
            $create_args{$arg} = $ARGS{$arg};
        }
        elsif ($arg =~ /^Object-RTx::AssetTracker::Asset--CustomField-(\d+)(.*?)$/) {
            my $cfid = $1;
            my $cf = RT::CustomField->new( $session{'CurrentUser'});
            $cf->Load($cfid);

            if ($cf->Type eq 'FreeformMultiple') {
                $ARGS{$arg} =~ s/\r\n/\n/g;
                $ARGS{$arg} = [split('\n', $ARGS{$arg})];
            }

            if ( $arg =~ /-Upload$/ ) {
                $create_args{"CustomField-".$cfid} = _UploadedFile($arg);
            }
            else {
                $create_args{"CustomField-".$cfid} = $ARGS{"$arg"};
            }
        }
        elsif ($arg =~ /^AddWatcher-Type-(\w+)$/) {
            my $role = $1;
            push(@{$create_args{$role}}, map { s/Principal-//; $_ } 
                 ref( $ARGS{$arg} ) ? @{ $ARGS{$arg} } : ( $ARGS{$arg} ) );
        }
    }


    my ( $id, $Trans, $ErrMsg ) = $Asset->Create(%create_args);
    unless ( $id && $Trans ) {
        Abort($ErrMsg);
    }

    push ( @Actions, split("\n", $ErrMsg) );
    unless ( $Asset->CurrentUserHasRight('ShowAsset') ) {
        Abort( "No permission to view newly created asset #"
            . $Asset->id . "." );
    }
    return ( $Asset, @Actions );

}

# }}}

# {{{ Sub ProcessCustomFieldUpdates

sub ProcessBulkCustomFieldUpdates {
    my %args = (
        Object  => undef,
        ARGSRef => undef,
        TransactionData => undef,
        @_
    );

    my $Object  = $args{'Object'};
    my $ARGSRef = $args{'ARGSRef'};

    my @results;

    my @NoUpdate = grep { /^\d+-DoNotUpdate$/ } keys %$ARGSRef;
    foreach (@NoUpdate) {
        /^(\d+)-/;
        my $cfid = $1;
        if ($ARGSRef->{$_}) {
            #push @results, "Will not update $_";
            foreach my $key ( keys %$ARGSRef ) {
                $key =~ /^$cfid-/ and delete $ARGSRef->{$key};
            }
        }
    }

    # We should do this once and cache it
    my %CFsToProcess;
    foreach my $key ( keys %$ARGSRef ) {
        if ($key =~ /^(\d+)-Value/) { $CFsToProcess{$1} = 1; }
    }

    foreach my $cfid (keys %CFsToProcess) {

        my ($rv, $msg);
        if (exists $ARGSRef->{"$cfid-Value"} and $ARGSRef->{"$cfid-Value"}) {
            #Add the value or delete it if false
            ($rv, $msg) = $Object->AddCustomFieldValue( Field => $cfid, Value => $ARGSRef->{"$cfid-Value"});
            push @results, $msg;
        }
        elsif (exists $ARGSRef->{"$cfid-Value-Magic"}) {
            #Delete the value
            ($rv, $msg) = $Object->DeleteCustomFieldValue( Field => $cfid, Value => $Object->FirstCustomFieldValue($cfid));
            push @results, $msg;
        }
        elsif (exists $ARGSRef->{"$cfid-Values"} and $ARGSRef->{"$cfid-Values"}) {
            #Add the value or delete it if false
            ($rv, $msg) = $Object->AddCustomFieldValue( Field => $cfid, Value => $ARGSRef->{"$cfid-Values"});
            push @results, $msg;
        }
        elsif (exists $ARGSRef->{"$cfid-Values-Magic"}) {
            #Delete the value
            ($rv, $msg) = $Object->DeleteCustomFieldValue( Field => $cfid, Value => $Object->FirstCustomFieldValue($cfid));
            push @results, $msg;
        }
        elsif (exists $ARGSRef->{"$cfid-Values-AddValues-Magic"}) {
            # If the arg is one value with newlines then we need to split and add/delete each value
            if (exists $ARGSRef->{"$cfid-Values-AddValues"}) {
                my @values = ( ref $ARGSRef->{"$cfid-Values-AddValues"} eq 'ARRAY' )
                      ? @{$ARGSRef->{"$cfid-Values-AddValues"}}
                      :  ($ARGSRef->{"$cfid-Values-AddValues"});
                if (@values == 1) {
                    $values[0] =~ s/\r\n/\n/g;
                    @values = split(/\n/, $values[0]);
                }
                foreach my $value (@values) {
                    ($rv, $msg) = $Object->AddUniqueCustomFieldValue( Field => $cfid, Value => $value);
                    push @results, $msg;
                }
            }
            else {
            }

            if (exists $ARGSRef->{"$cfid-Values-DeleteValues"}) {
                my @values = ( ref $ARGSRef->{"$cfid-Values-DeleteValues"} eq 'ARRAY' )
                      ? @{$ARGSRef->{"$cfid-Values-DeleteValues"}}
                      :  ($ARGSRef->{"$cfid-Values-DeleteValues"});
                if (@values == 1) {
                    $values[0] =~ s/\r\n/\n/g;
                    @values = split(/\n/, $values[0]);
                }
                foreach my $value (@values) {
                    ($rv, $msg) = $Object->DeleteCustomFieldValue( Field => $cfid, Value => $value);
                    push @results, $msg;
                }
            }
            else {
            }
        }
        else {
        }
    }

    return (@results);
}

# }}}

# {{{ sub ProcessAssetLinks

=head2 ProcessAssetLinks ( AssetObj => $Asset, ARGSRef => \%ARGS );

Returns an array of results messages.

=cut

sub ProcessAssetLinks {
    my %args = (
        AssetObj => undef,
        ARGSRef   => undef,
        @_
    );

    my @results;

    my $AssetObj = $args{'AssetObj'};
    my $ARGSRef   = $args{'ARGSRef'};

    my $all_links = join('|', keys %RT::Link::TYPEMAP);
    my $all_bases = join('|', keys %RT::Link::DIRMAP);
    foreach my $arg (keys %$ARGSRef) {

        if ($arg =~ /^AddLink-Asset-(.+)$/) {
            my $id = $1;
            next unless $ARGSRef->{$arg} =~ /($all_links)/;
            my $linktype = $1;
            if ($linktype =~ /^($all_bases)$/) {
                my ( $val, $msg ) = $AssetObj->AddLink( Target => $id, Type   => $linktype, TransactionData => $ARGSRef->{LinkComment} || $ARGSRef->{GlobalComment} );
                push @results, $msg;
            } else {
                $linktype = $RT::Link::TYPEMAP{$linktype}{Type} if $RT::Link::TYPEMAP{$linktype}{Mode} eq 'Base';
                my ( $val, $msg ) = $AssetObj->AddLink( Base => $id, Type   => $linktype, TransactionData => $ARGSRef->{LinkComment} || $ARGSRef->{GlobalComment} );
                push @results, $msg;
            }
        }
        elsif ($arg =~ /^DeleteLink-(.*?)-($all_bases)-(.*)$/) {
            my $base   = $1;
            my $type   = $2;
            my $target = $3;

            my ( $val, $msg ) = $AssetObj->DeleteLink( Base   => $base,
                                                     Type   => $type,
                                                     Target => $target, TransactionData => $ARGSRef->{LinkComment} || $ARGSRef->{GlobalComment} );

            if ($val) {
                push @results,
                  "Deleted link: Base: $base Target: $target Type: $type";
            }
            else {
                push @results, $msg;
            }
        }
    }

    foreach my $linktype ( keys %RT::Link::DIRMAP ) {
        if ( $ARGSRef->{ $AssetObj->Id . "-$linktype" } ) {
            $ARGSRef->{ $AssetObj->Id . "-$linktype" } = join( ' ', @{ $ARGSRef->{ $AssetObj->Id . "-$linktype" } } )
                if ref( $ARGSRef->{ $AssetObj->Id . "-$linktype" } );

            for my $luri ( split( / /, $ARGSRef->{ $AssetObj->Id . "-$linktype" } ) ) {
                next unless $luri;
                $luri =~ s/\s+$//;    # Strip trailing whitespace
                my ( $val, $msg ) = $AssetObj->AddLink(
                    Target => $luri,
                    Type   => $linktype
                );
                push @results, $msg;
            }
        }
        if ( $ARGSRef->{ "$linktype-" . $AssetObj->Id } ) {
            $ARGSRef->{ "$linktype-" . $AssetObj->Id } = join( ' ', @{ $ARGSRef->{ "$linktype-" . $AssetObj->Id } } )
                if ref( $ARGSRef->{ "$linktype-" . $AssetObj->Id } );

            for my $luri ( split( / /, $ARGSRef->{ "$linktype-" . $AssetObj->Id } ) ) {
                next unless $luri;
                my ( $val, $msg ) = $AssetObj->AddLink(
                    Base => $luri,
                    Type => $linktype
                );

                push @results, $msg;
            }
        }
    }

    return (@results);
}

# }}}

# Just a copy of ProcessObjectCustomFieldUpdates
sub ProcessATObjectCustomFieldUpdates {
    my %args = @_;
    my $ARGSRef = $args{'ARGSRef'};
    my @results;

    # Build up a list of objects that we want to work with
    my %custom_fields_to_mod;
    foreach my $arg ( keys %$ARGSRef ) {

        # format: Object-<object class>-<object id>-CustomField-<CF id>-<commands>
        next unless $arg =~ /^Object-([\w:]+)-(\d*)-CustomField-(\d+)-(.*)$/;

        # For each of those objects, find out what custom fields we want to work with.
        $custom_fields_to_mod{$1}{ $2 || 0 }{$3}{$4} = $ARGSRef->{$arg};
    }

    # For each of those objects
    foreach my $class ( keys %custom_fields_to_mod ) {
        foreach my $id ( keys %{ $custom_fields_to_mod{$class} } ) {
            my $Object = $args{'Object'};
            $Object = $class->new( $session{'CurrentUser'} )
                unless $Object && ref $Object eq $class;

            $Object->Load($id) unless ( $Object->id || 0 ) == $id;
            unless ( $Object->id ) {
                $RT::Logger->warning("Couldn't load object $class #$id");
                next;
            }

            foreach my $cf ( keys %{ $custom_fields_to_mod{$class}{$id} } ) {
                my $CustomFieldObj = RT::CustomField->new( $session{'CurrentUser'} );
                $CustomFieldObj->LoadById($cf);
                unless ( $CustomFieldObj->id ) {
                    $RT::Logger->warning("Couldn't load custom field #$cf");
                    next;
                }
                push @results,
                    _ProcessATObjectCustomFieldUpdates(
                    Prefix      => "Object-$class-$id-CustomField-$cf-",
                    Object      => $Object,
                    CustomField => $CustomFieldObj,
                    ARGS        => $custom_fields_to_mod{$class}{$id}{$cf},
                    ARGSRef     => $ARGSRef
                );
            }
        }
    }
    return @results;
}

# Just a copy of _ProcessObjectCustomFieldUpdates with the Data parameter passed
# to various calls to Add/DeleteCustomFieldValue
sub _ProcessATObjectCustomFieldUpdates {
    my %args    = @_;
    my $cf      = $args{'CustomField'};
    my $cf_type = $cf->Type;
    my $ARGSRef = $args{'ARGSRef'};

    # Normalise - remove blank Values since magic value will take care of this. This is
    # because sometimes, the browser gives you a blank value and also a magic value
    # which causes CFs to be processed twice by the code below.
    if (   defined $args{'ARGS'}->{'Values'}
        && !length $args{'ARGS'}->{'Values'}
        && $args{'ARGS'}->{'Values-Magic'} )
    {
        delete $args{'ARGS'}->{'Values'};
    }

    my @results;
    foreach my $arg ( keys %{ $args{'ARGS'} } ) {

        # skip category argument
        next if $arg eq 'Category';

        # since http won't pass in a form element with a null value, we need
        # to fake it
        if ( $arg eq 'Values-Magic' ) {

            # We don't care about the magic, if there's really a values element;
            next if defined $args{'ARGS'}->{'Value'}  && length $args{'ARGS'}->{'Value'};
            next if defined $args{'ARGS'}->{'Values'} && length $args{'ARGS'}->{'Values'};

            # "Empty" values does not mean anything for Image and Binary fields
            next if $cf_type =~ /^(?:Image|Binary)$/;

            $arg = 'Values';
            $args{'ARGS'}->{'Values'} = undef;
        }

        my @values = ();
        if ( ref $args{'ARGS'}->{$arg} eq 'ARRAY' ) {
            @values = @{ $args{'ARGS'}->{$arg} };
        } elsif ( $cf_type =~ /text/i ) {    # Both Text and Wikitext
            @values = ( $args{'ARGS'}->{$arg} );
        } else {
            @values = split /\r*\n/, $args{'ARGS'}->{$arg}
                if defined $args{'ARGS'}->{$arg};
        }
        @values = grep length, map {
            s/\r+\n/\n/g;
            s/^\s+//;
            s/\s+$//;
            $_;
            }
            grep defined, @values;

        if ( $arg eq 'AddValue' || $arg eq 'Value' ) {
            foreach my $value (@values) {
                my ( $val, $msg ) = $args{'Object'}->AddCustomFieldValue(
                    Field => $cf->id,
                    Value => $value,
                    Data  => $ARGSRef->{'FieldComment'} || $ARGSRef->{'GlobalComment'},
                );
                push ( @results, $msg );
            }
        } elsif ( $arg eq 'Upload' ) {
            my $value_hash = _UploadedFile( $args{'Prefix'} . $arg ) or next;
            my ( $val, $msg ) = $args{'Object'}->AddCustomFieldValue( %$value_hash, Field => $cf,
                Data  => $ARGSRef->{'FieldComment'} || $ARGSRef->{'GlobalComment'},);
            push ( @results, $msg );
        } elsif ( $arg eq 'DeleteValues' ) {
            foreach my $value (@values) {
                my ( $val, $msg ) = $args{'Object'}->DeleteCustomFieldValue(
                    Field => $cf,
                    Value => $value,
                    Data  => $ARGSRef->{'FieldComment'} || $ARGSRef->{'GlobalComment'},
                );
                push ( @results, $msg );
            }
        } elsif ( $arg eq 'DeleteValueIds' ) {
            foreach my $value (@values) {
                my ( $val, $msg ) = $args{'Object'}->DeleteCustomFieldValue(
                    Field   => $cf,
                    ValueId => $value,
                    Data  => $ARGSRef->{'FieldComment'} || $ARGSRef->{'GlobalComment'},
                );
                push ( @results, $msg );
            }
        } elsif ( $arg eq 'Values' && !$cf->Repeated ) {
            my $cf_values = $args{'Object'}->CustomFieldValues( $cf->id );

            my %values_hash;
            foreach my $value (@values) {
                if ( my $entry = $cf_values->HasEntry($value) ) {
                    $values_hash{ $entry->id } = 1;
                    next;
                }

                my ( $val, $msg ) = $args{'Object'}->AddCustomFieldValue(
                    Field => $cf,
                    Value => $value,
                    Data  => $ARGSRef->{'FieldComment'} || $ARGSRef->{'GlobalComment'},
                );
                push ( @results, $msg );
                $values_hash{ $val } = 1 if $val;
            }

            # For Date Cfs, @values is empty when there is no changes (no datas in form input)
            return @results if ( $cf->Type =~ /^Date(?:Time)?$/ && ! @values );

            $cf_values->RedoSearch;
            while ( my $cf_value = $cf_values->Next ) {
                next if $values_hash{ $cf_value->id };

                my ( $val, $msg ) = $args{'Object'}->DeleteCustomFieldValue(
                    Field   => $cf,
                    ValueId => $cf_value->id,
                    Data  => $ARGSRef->{'FieldComment'} || $ARGSRef->{'GlobalComment'},
                );
                push ( @results, $msg);
            }
        } elsif ( $arg eq 'Values' ) {
            my $cf_values = $args{'Object'}->CustomFieldValues( $cf->id );

            # keep everything up to the point of difference, delete the rest
            my $delete_flag;
            foreach my $old_cf ( @{ $cf_values->ItemsArrayRef } ) {
                if ( !$delete_flag and @values and $old_cf->Content eq $values[0] ) {
                    shift @values;
                    next;
                }

                $delete_flag ||= 1;
                $old_cf->Delete;
            }

            # now add/replace extra things, if any
            foreach my $value (@values) {
                my ( $val, $msg ) = $args{'Object'}->AddCustomFieldValue(
                    Field => $cf,
                    Value => $value,
                    Data  => $ARGSRef->{'FieldComment'} || $ARGSRef->{'GlobalComment'},
                );
                push ( @results, $msg );
            }
        } else {
            push(
                @results,
                loc("User asked for an unknown update type for custom field [_1] for [_2] object #[_3]",
                    $cf->Name, ref $args{'Object'},
                    $args{'Object'}->id
                )
            );
        }
    }
    return @results;
}


=head2 LimitToRolesForQueue QUEUE_ID

Limits the set of groups found to role groups for queue QUEUE_ID

=cut

sub RT::Groups::LimitToRolesForAssetType {
    my $self = shift;
    my $type = shift;
    $self->Limit(FIELD => 'Domain', OPERATOR => '=', VALUE => 'RTx::AssetTracker::Type-Role');
    $self->Limit(FIELD => 'Instance', OPERATOR => '=', VALUE => $type);
}


=head2 GetPrincipalsMap OBJECT, CATEGORIES

Gets the Role principals for Asset Types, or falls back on the
original version.

=cut

my $Orig_GetPrincipalsMap = __PACKAGE__->can('GetPrincipalsMap')
    or die "API change? Can't find method 'GetPrincipalsMap'";
*GetPrincipalsMap = sub {
    my $object = shift;
    my @map;
    for (@_) {
        if (/Roles/ && $object->isa('RTx::AssetTracker::Type')) {
            my $roles = RT::Groups->new($session{'CurrentUser'});
            $roles->LimitToRolesForAssetType($object->Id);
            $roles->OrderBy( FIELD => 'Type', ORDER => 'ASC' );
            push @map, [
                'Roles' => $roles,  # loc_left_pair
                'Type'  => 1
            ];
        }
        else {
            push @map, $Orig_GetPrincipalsMap->( $object, $_ );
        }
    }
    return @map;
};


=head2 SplitCamelCase

=cut

sub SplitCamelCase {
    my $str = shift;

    my @parts = $str =~ /[A-Z](?:[A-Z]+|[a-z]*)(?=$|[A-Z])/g;

    return join ' ', @parts;
}


1;
