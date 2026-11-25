package Dist::Conformance::Source::Git;

# ABSTRACT: Standards fetched from a git repository into a cache directory

use 5.040;
use warnings FATAL => 'all';
use re '/aasx';
use Mojo::Base 'Dist::Conformance::Source', -signatures;

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
    my $base = $ENV{XDG_CACHE_HOME} || Mojo::File->new( $ENV{HOME} // die("Neither XDG_CACHE_HOME nor HOME is set\n") )->child('.cache');
    return Mojo::File->new($base)->child('dist-conformance')->to_string;
};

=method new(@args)

A new source.  It fetches nothing until the first read.

=over 4

=item args - Hash - the attributes, such as L</url> and L</ref>, as named arguments

=back

Returns a Dist::Conformance::Source::Git object.

Dies unless L</url> is given, and on a URL or a ref that git would take for an
option.

    my $source = Dist::Conformance::Source::Git->new( url => 'https://forge.test.test/standards.git' );

=cut

sub new ( $class, @args ) {
    my $self = $class->SUPER::new(@args);
    die "url is required\n"                             if !defined $self->url || $self->url eq q{};
    die( 'The url ' . $self->url . " starts with -\n" ) if index( $self->url, q{-} ) == 0;
    die( 'The ref ' . $self->ref . " starts with -\n" ) if index( $self->ref, q{-} ) == 0;
    return $self;
}

# The directory of the clone of this URL and ref, which may not exist yet.
# @returns InstanceOf["Mojo::File"]  the directory
# @throws  when neither C<$XDG_CACHE_HOME> nor C<$HOME> is set and no L</cache> is given
# @example my $clone = $source->clone_dir;
sub clone_dir ($self) {
    return Mojo::File->new( $self->cache )->child( Digest::SHA::sha1_hex( $self->url . "\n" . $self->ref ) );
}

=method root

The checkout, after a L</fetch> unless L</offline>.  Memoized on the object.

Returns a Mojo::File object.

Dies when it is L</offline> and there is no clone yet, and when the fetch
fails.

    my $top = $source->root;

=cut

sub root ($self) {
    return $self->{root} //= do {
        my $dir = $self->clone_dir;
        if ( $self->offline ) {
            die( 'Offline, and there is no cached copy of ' . $self->describe, "\n" ) if !-d $dir->child('.git');
        }
        else {
            $self->fetch;
        }
        $dir;
    };
}

# Clones the repository if there is no clone yet, fetches L</ref>, and checks out
# what it fetched, discarding any change in the checkout.
# @returns InstanceOf["Mojo::File"]  the directory of the clone
# @throws  with what git said when a step fails
# @example $source->fetch;
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

The URL and the ref, and the path inside the repository.

Returns Str.

    say 'Flavor from ', $source->describe;

=cut

sub describe ($self) {
    return $self->url . ' at ' . $self->ref . ( $self->path ne q{} ? ' (path ' . $self->path . ')' : q{} );
}

=func git(@arguments)

Runs C<git> with C<@arguments>.  Every call to git goes through this function,
so a test can replace it.

=over 4

=item arguments - Array - the arguments of git

=back

Returns Str, the standard output of git.

Dies with its standard error when git fails.

    my $head = Dist::Conformance::Source::Git::git( qw{-C /bogus/checkout rev-parse HEAD} );

=cut

# A clone and a fetch need the transports, the credential helpers and the
# configuration of the real git, which no CPAN module reproduces.
sub git (@arguments) {
    local $ENV{GIT_TERMINAL_PROMPT} = 0;
    my ( $out, $err ) = ( q{}, q{} );
    IPC::Run3::run3( [ 'git', @arguments ], \undef, \$out, \$err );
    my $status = $?;
    die( "git @arguments failed: " . ( $err =~ s/\s+\z//r ), "\n" ) if $status;
    return $out;
}

=head1 SEE ALSO

L<Dist::Conformance::Source>

=cut
