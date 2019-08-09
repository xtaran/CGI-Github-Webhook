package CGI::Github::Webhook;

# ABSTRACT: Easily create CGI based GitHub webhooks

use strict;
use warnings;
use 5.010;

# VERSION

use Moo;
use CGI;
use Data::Dumper;
use JSON;
use Try::Tiny;
use Digest::SHA qw(hmac_sha1_hex);
use File::ShareDir qw(module_dir);
use File::Copy;
use File::Basename;

=head1 SYNOPSIS

CGI::Github::Webhook allows one to easily create simple, CGI-based
GitHub webhooks.

    #!/usr/bin/perl

    use CGI::Github::Webhook;

    my $ghwh = CGI::Github::Webhook->new(
        mime_type => 'text/plain',
        trigger => '/srv/some-github-project/bin/deploy.pl',
        trigger_backgrounded => 1,
        secret => 'use a generated password here, nothing valuable',
        log => '/srv/some-github-project/log/trigger.log',
        ...
    );
    $ghwh->run();

=cut

#=head1 EXPORT
#
#A list of functions that can be exported.  You can delete this section
#if you don't export anything, such as for a purely object-oriented module.

=head1 CONSTRUCTOR

=head2 new

Constructor. Takes a configuration hash (or array) as parameters.

=head3 List of parameters for new() constructor.

They can be used as (Moo-style) accessors on the CGI::Github::Webhook
object, too.

=head4 badges_from

Path where to look for badge files. Defaults to File::ShareDir's
module_dir.

=cut

has badges_from => (
    is => 'rw',
    default => sub { module_dir(__PACKAGE__); },
    isa => sub {
        die "$_[0] needs to be an existing directory"
            unless -d $_[0];
    },
    lazy => 1,
    );

=head4 badge_to

Local path to file to which L<https://shields.io/> style badges should
be written. Defaults to undef which means the feature is disabled.

Needs to have a suffix. That suffix will then be used to look for a
file in the right format.

Currently only ".svg" and ".png" suffixes/formats are supported if no
custom badge set is used.

=cut

has badge_to => (
    is => 'rw',
    default => sub { return },
    isa => sub {
        die "$_[0] needs have a file suffix"
            if (defined($_[0]) and $_[0] !~ /\./);
    },
    );

=head4 cgi

The CGI.pm object internally used.

=cut

has cgi => (
    is => 'ro',
    default => sub { CGI->new() },
    );

=head4 log

Where to send the trigger's output to. Defaults to '/dev/stderr',
i.e. goes to the web server's error log. Use '/dev/null' to disable.

For now it needs to be a path on the file system. Passing file handles
objects doesn't work (yet).

=cut

has log => (
    is => 'ro',
    default => sub { '/dev/stderr' },
    isa => sub {
        my $dir = dirname($_[0]);
        die "$dir doesn't exist!" unless -d $dir;
    },
    );

=head4 mime_type

The mime-type used to return the contents. Defaults to 'text/plain;
charset=utf-8' for now.

=cut

has mime_type => (
    is => 'ro',
    default => sub { 'text/plain; charset=utf-8' },
    );

=head4 secret

The shared secret you entered on GitHub as secret for this
trigger. Currently required. I recommend to use the output of
L<makepasswd(1)>, L<apg(1)>, L<pwgen(1)> or using
L<Crypt::GeneratePassword> to generate a randon and secure shared
password.

=cut

has secret => (
    is => 'ro',
    required => 1,
    );

=head4 text_on_success

Text to be returned to GitHub as body if the trigger was successfully
(or at least has been spawned successfully). Defaults to "Successfully
triggered".

=cut

has text_on_success => (
    is => 'rw',
    default => sub { 'Successfully triggered' },
    );

=head4 text_on_auth_fail

Text to be returned to GitHub as body if the authentication
failed. Defaults to "Authentication failed".

=cut

has text_on_auth_fail => (
    is => 'rw',
    default => sub { 'Authentication failed' },
    );

=head4 text_on_trigger_fail

Text to be returned to GitHub as body if spawning the trigger
failed. Defaults to "Trigger failed".

=cut

has text_on_trigger_fail => (
    is => 'rw',
    default => sub { 'Trigger failed' },
    );


=head4 trigger

The script or command which should be called when the webhook is
called. Required.

=cut

has trigger => (
    is => 'rw',
    required => 1,
);

=head4 trigger_backgrounded

Boolean attribute controlling if the script or command passed as
trigger needs to be started backgrounded (i.e. if it takes longer than
a few seconds) or not. Defaults to 1 (i.e. that the trigger script is
backgrounded).

=cut

has trigger_backgrounded => (
    is => 'rw',
    default => 1,
);

=head4 auth_style

Select the style of authentication to use.  Can be one of
"github" or "gitlab" at present.  Defaults to "github".

"github" indicates that the payload should have the shared secret
appended to it, and the resulting sha1 hash should match what's
repsented in the X-Hub-Signature: header.

"gitlab" indicates that the shared secret should simply be compared to
whatever is presented in the X-Gitlab-Token: header.

=cut

has auth_style => (
    is => 'ro',
    default => sub { 'github' },
    );

=head1 OTHER PROPERTIES

=head4 authenticated

Returns true if the authentication could be
verified and false else. Read-only attribute.

=cut

has authenticated => (
    is => 'lazy',
    );

sub _build_authenticated {
    my $self = shift;

    my $logfile    = $self->log;
    my $q          = $self->cgi;
    my $secret     = $self->secret;
    my $auth_style = $self->auth_style;

    open(my $logfh, '>>', $logfile);
    say $logfh "Date: ".localtime;
    say $logfh "Remote IP: ".$q->remote_host()." (".$q->remote_addr().")";

    my $presented_credential;
    my $local_credential;
    if ("github" eq $auth_style) {
        $presented_credential =
            $q->http('X-Hub-Signature') || '<no-x-hub-signature>';
        $local_credential = 'sha1='.
            hmac_sha1_hex($self->payload // '', $secret);
    }
    elsif ("gitlab" eq $auth_style) {
        $presented_credential =
            $q->http('X-Gitlab-Token') || '<no-x-gitlab-token>';
        $local_credential = $secret;
    }
    else {
        $presented_credential = '<unrecognised-auth-style>';
        $local_credential = "auth_style=" . $auth_style ;
    }
    print $logfh Dumper($self->payload_perl,
                        $presented_credential, $local_credential);
    close $logfh;

    return $presented_credential eq $local_credential;
}

=head4 payload

The payload as passed as payload in the POST request

=cut

has payload => (
    is => 'lazy',
    );

sub _build_payload {
    my $self = shift;
    my $q    = $self->cgi;

    if ($q->param('POSTDATA')) {
        return ''.$q->param('POSTDATA');
    } else {
        return;
    }
}

=head4 payload_json

The payload as passed as payload in the POST request if it is valid
JSON, else an error message in JSON format.

=cut

has payload_json => (
    is => 'lazy',
    );

sub _build_payload_json {
    my $self = shift;
    my $q    = $self->cgi;

    my $payload = qq({"payload":"none"});
    if ($self->payload) {
        $payload = $self->payload;
        try {
            decode_json($payload);
        } catch {
            s/\"/\'/g; s/\n/ /gs;
            $payload = qq({"error":"$_"});
        };
    }

    return $payload;
}

=head4 payload_perl

The payload as perl data structure (hashref) as decoded by
decode_json. If the payload was no valid JSON, it returns a hashref
containing either { payload => 'none' } if there was no payload, or {
error => ... } in case of a decode_json error had been caught.

=cut

has payload_perl => (
    is => 'lazy',
    );

sub _build_payload_perl {
    my $self = shift;

    return decode_json($self->payload_json);
}

=head1 SUBROUTINES/METHODS

=head2 deploy_badge

Copies file given as parameter to path given via badge_to
attribute. The parameter needs to be given without file suffix. The
file suffix from the badges attribute will be appended.

Doesn't do anything if badge_to is not set.

=cut

sub deploy_badge {
    my $self = shift;
    return unless $self->badge_to;

    my $basename = shift;
    die "No basename provided" unless defined($basename);

    my $suffix = $self->badge_to;
    $suffix =~ s/^.*(\.[^.]*?)$/$1/;
    my $badge = $self->badges_from.'/'.$basename.$suffix;

    my $logfile = $self->log;
    open(my $logfh, '>>', $logfile);

    my $file_copied = copy($badge, $self->badge_to);
    if ($file_copied) {
        say $logfh "$badge successfully copied to ".$self->badge_to;
        return 1;
    } else {
        say $logfh "Couldn't copy $badge  to ".$self->badge_to.": $!";
        return;
    }
}

=head2 header

Passes arguments to and return value from $self->cgi->header(), i.e. a
shortcut for $self->cgi->header().

If no parameters are passed, $self->mime_type is passed.

=cut

sub header {
    my $self = shift;
    if (@_) {
        return $self->cgi->header(@_);
    } else {
        return $self->cgi->header($self->mime_type);
    }
}

=head2 send_header

Passes arguments to $self->header and prints result to STDOUT.

=cut

sub send_header {
    my $self = shift;

    print $self->header(@_);
}

=head2 run

Start the authentication verification and run the trigger if the
authentication succeeds.

Returns true on success, false on error. More precisely it returns a
defined false on error launching the trigger and undef on
authentication error.

=cut

sub run {
    local $| = 1;
    my $self = shift;

    $self->send_header();

    my $logfile = $self->log;
    open(my $logfh, '>>', $logfile);

    if ($self->authenticated) {
        my $trigger = $self->trigger.' >> '.$logfile.' 2>&1 '.
            ($self->trigger_backgrounded ? '&' : '');
        my $rc = system($trigger);
        if ($rc != 0) {
            say $logfh $trigger;
            say $self->text_on_trigger_fail;
            say $logfh $self->text_on_trigger_fail;
            if ($? == -1) {
                say $logfh "Trigger failed to execute: $!";
                $self->deploy_badge('errored');
            } elsif ($? & 127) {
                printf $logfh "child died with signal %d, %s coredump\n",
                ($? & 127),  ($? & 128) ? 'with' : 'without';
                $self->deploy_badge('errored');
            } else {
                printf $logfh "child exited with value %d\n", $? >> 8;
                $self->deploy_badge('failed');
            }
            close $logfh;
            return 0;
        } else {
            $self->deploy_badge('success');
            say $self->text_on_success;
            say $logfh $self->text_on_success;

            close $logfh;
            return 1;
        }
    } else {
        say $self->text_on_auth_fail;
        say $logfh $self->text_on_auth_fail;
        close $logfh;
        return; # undef or empty list, i.e. false
    }
}

=head1 AUTHOR

Axel Beckert, C<< <abe@deuxchevaux.org> >>

=head1 BUGS

Please report any bugs, either via via GitHub Issues at
L<https://github.com/xtaran/CGI-Github-Webhook/issues> or via the CPAN
Request Tracker by sending an e-mail to
C<bug-cgi-github-webhook@rt.cpan.org> or submitting a bug report
through the CPAN Request Tracker web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=CGI-Github-Webhook>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc CGI::Github::Webhook

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=CGI-Github-Webhook>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/CGI-Github-Webhook>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/CGI-Github-Webhook>

=item * Search CPAN

L<https://metacpan.org/release/CGI-Github-Webhook>

=back


=head1 LICENSE AND COPYRIGHT

Copyright 2016 Axel Beckert.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<http://dev.perl.org/licenses/> for more information.


=cut

1; # End of CGI::Github::Webhook
