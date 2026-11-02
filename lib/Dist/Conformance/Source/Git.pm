package Dist::Conformance::Source::Git;

# ABSTRACT: Standards fetched from a git repository into a cache directory

use 5.040;
use warnings FATAL => 'all';
use re '/aasx';
use Mojo::Base 'Dist::Conformance::Source', -signatures;

use Carp ();
use Digest::SHA();
use IPC::Run3();
use Mojo::File();

=head1 SYNOPSIS

    use 5.040;
    use Dist::Conformance::Source::Git;

    my $source = Dist::Conformance::Source::Git->new(
        url  => 'https://forge.test.test/standards.git',
        ref  => 'main',
        path => 'skills/packaging-perl',
    );
    my $flavor = $source->file('conformance/troglodyne.yml');    # fetches first

=head1 DESCRIPTION

A tree of standards in a git repository.  The first read through L</root>
fetches the latest commit of L</ref> into a clone under L</cache>, and checks it
out.  Later reads by the same object use that checkout, so one run sees one
commit, however many files it reads.

Each URL and ref has a clone of its own, in a directory named by the SHA-1 of
the two, so two flavors at two refs of one repository do not fight over a
checkout.  The clone is a cache: deleting it costs one full clone the next time.

=attr url

Required.  Anything that C<git clone> takes: a URL, or the path of a
repository on this machine.

=attr ref

The branch, tag or commit to fetch.  Default C<HEAD>, the default branch of the
remote.

=attr cache

The directory that holds the clones.  Default F<dist-conformance> under
C<$XDG_CACHE_HOME>, or under F<~/.cache> when that is not set.

=attr offline

When true, L</root> fetches nothing, and uses the clone as the last fetch left
it.  Dies when there is no clone yet.

=cut

has 'url';
has ref     => 'HEAD';
has offline => 0;
has cache   => sub {
    my $base = $ENV{XDG_CACHE_HOME} || Mojo::File->new( $ENV{HOME} // Carp::croak('Neither XDG_CACHE_HOME nor HOME is set') )->child('.cache');
    return Mojo::File->new($base)->child('dist-conformance')->to_string;
};

=method new

Dies unless L</url> is given, and on a URL or a ref that git would take for an
option.

=cut

sub new ( $class, @args ) {
    my $self = $class->SUPER::new(@args);
    Carp::croak('url is required')                            if !defined $self->url || $self->url eq q{};
    Carp::croak( 'The url ' . $self->url . ' starts with -' ) if index( $self->url, q{-} ) == 0;
    Carp::croak( 'The ref ' . $self->ref . ' starts with -' ) if index( $self->ref, q{-} ) == 0;
    return $self;
}

=method clone_dir

The directory of the clone of this URL and ref, as a L<Mojo::File>.

=cut

sub clone_dir ($self) {
    return Mojo::File->new( $self->cache )->child( Digest::SHA::sha1_hex( $self->url . "\n" . $self->ref ) );
}

=method root

The checkout, after a L</fetch> unless L</offline>.  Memoized on the object.

=cut

sub root ($self) {
    return $self->{root} //= do {
        my $dir = $self->clone_dir;
        if ( $self->offline ) {
            Carp::croak( 'Offline, and there is no cached copy of ' . $self->describe ) if !-d $dir->child('.git');
        }
        else {
            $self->fetch;
        }
        $dir;
    };
}

=method fetch

Clones the repository if there is no clone yet, fetches L</ref>, and checks out
what it fetched, discarding any change in the checkout.  Dies with what git
said when a step fails.

=cut

sub fetch ($self) {
    my $dir = $self->clone_dir;
    if ( !-d $dir->child('.git') ) {
        $dir->remove_tree;
        $dir->dirname->make_path;
        git( qw{clone --quiet --no-checkout --}, $self->url, "$dir" );
    }
    git( '-C', "$dir", qw{fetch --quiet origin}, $self->ref );
    git( '-C', "$dir", qw{checkout --quiet --force --detach FETCH_HEAD} );
    return $dir;
}

=method describe

The URL and the ref.

=cut

sub describe ($self) {
    return $self->url . ' at ' . $self->ref . ( $self->path ne q{} ? ' (path ' . $self->path . ')' : q{} );
}

=func git

C<(@arguments)>.  Runs C<git> with C<@arguments>, and dies with its standard
error when it fails.  Every call to git goes through this function, so a test
can replace it.

=cut

# A clone and a fetch need the transports, the credential helpers and the
# configuration of the real git, which no CPAN module reproduces.
sub git (@arguments) {
    local $ENV{GIT_TERMINAL_PROMPT} = 0;
    my ( $out, $err ) = ( q{}, q{} );
    IPC::Run3::run3( [ 'git', @arguments ], \undef, \$out, \$err );
    my $status = $?;
    Carp::croak( "git @arguments failed: " . ( $err =~ s/\s+\z//r ) ) if $status;
    return $out;
}

=head1 SEE ALSO

L<Dist::Conformance::Source>

=cut
