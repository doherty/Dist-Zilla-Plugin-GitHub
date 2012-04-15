package Dist::Zilla::Plugin::GitHub;
use strict;
use warnings;
use JSON;
use Moose;
use Try::Tiny;
use Net::Github 0.44;


has 'repo' => (
	is      => 'ro',
	isa     => 'Maybe[Str]'
);

has 'config_file' => (
    is => 'ro',
    isa => 'Str',
    default => sub {
        require File::Spec;
        require Dist::Zilla::Util;

        return File::Spec->catfile(
            Dist::Zilla::Util->_global_config_root(),
            'github.ini'
        );
    }
);

has 'username' => (
    is  => 'ro',
    isa => 'Str',
    default => sub {
        my $user = `git config github.user`;
        chomp $user;
        unless ($user) {
            warn <<'END';
Couldn't get your github username from git config; run:

    $ git config --global github.user

Guessing from the 'origin' remote...
END
            require List::MoreUtils;
            my @git_remotes =                           # Read from the bottom up:
                map { URI->new("ssh://$_") }            # 5. turn into a URI::ssh
                List::MoreUtils::uniq map { $_->[1] }   # 4. uniq by the middle element (the url)
                map { [split /\s/] }                    # 3. split on whitespace
                grep { m/^origin\s+git\@/ }             # 2. take only ones called origin which are ssh
                split /\n/, `git remote -v`;            # 1. get all the git remotes
            foreach my $remote_url (@git_remotes) {
                $user = (split /:/, $remote_url->authority)[1];
                last if $user;
            }
        }
        return $user;
    } # end sub
);

has 'api'  => (
	is      => 'ro',
	isa     => 'Net::Github::V3',
	lazy    => 1,
	builder => '_build_api',
);

=head1 NAME

Dist::Zilla::Plugin::GitHub - Set of plugins for working with GitHub

=head1 DESCRIPTION

B<Dist::Zilla::Plugin::GitHub> ships a bunch of L<Dist::Zilla> plugins, aimed at
easing the maintainance of Dist::Zilla-managed modules with L<GitHub|https://github.com>.

The following is the list of the plugins shipped in this distribution:

=over 4

=item * L<Dist::Zilla::Plugin::GitHub::Create> Create GitHub repo on dzil new

=item * L<Dist::Zilla::Plugin::GitHub::Update> Update GitHub repo info on release

=item * L<Dist::Zilla::Plugin::GitHub::Meta> Add GitHub repo info to META.{yml,json}

=back
=cut

sub _build_api {
    my $self = shift;
    my $token = try {
        require Config::INI::Reader;
        my $access = Config::INI::Reader->read_file( $self->config_file );
        $access->{'api.github.com'}->{token};
    }
    catch {
        $self->log("Error: $_");

        require Term::ReadKey;
        Term::ReadKey::ReadMode('noecho');
        my $pass = $self->zilla->chrome->term_ui->get_reply(
            prompt => 'GitHub password for ' . $self->user,
            allow  => sub { defined $_[0] and length $_[0] }
        );
        Term::ReadKey::ReadMode('normal');

        my $gh = Net::GitHub::V3->new( login => $user, pass => $pass );
        my $oauth = $gh->oauth;
        my $o = $oauth->create_authorization( {
            scopes => ['user', 'public_repo', 'repo'],
            note   => __PACKAGE__,
        });

        require Config::INI::Writer;
        Config::INI::Writer->write_file( {
            'api.github.com' => { token => $o->{token} }
        }, $self->config_file );
        try {
            chmod 0600, $self-> config_file;
        }
        catch {
            print "Couldn't make @{[ $self->config_file ]} private: $_";
        };

        $o->{token}; # return
    };

    die "Couldn't obtain api.github.com token"
        unless $token;

    return Net::GitHub->new( access_token => $token );
}

=head1 ACKNOWLEDGMENTS

Both the GitHub::Create and the GitHub::Update modules used to be standalone
modules (named respectively L<Dist::Zilla::Plugin::GithubCreate> and
L<Dist::Zilla::Plugin::GithubUpdate>) that are now deprecated.

=head1 AUTHOR

Alessandro Ghedini <alexbio@cpan.org>

=head1 LICENSE AND COPYRIGHT

Copyright 2011 Alessandro Ghedini.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

1; # End of Dist::Zilla::Plugin::GitHub
