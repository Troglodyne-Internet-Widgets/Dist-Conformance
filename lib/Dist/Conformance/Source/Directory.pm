package Dist::Conformance::Source::Directory;

# ABSTRACT: Standards read from a directory on this machine

use 5.040;
use warnings FATAL => 'all';
use re '/aasx';
use Mojo::Base 'Dist::Conformance::Source', -signatures;

use Mojo::File();

=head1 SYNOPSIS

    use 5.040;
    use Dist::Conformance::Source::Directory;

    my $source = Dist::Conformance::Source::Directory->new( directory => '/bogus/standards' );
    my $flavor = $source->file('conformance/troglodyne.yml');

=head1 DESCRIPTION

A tree of standards that is already on this machine, such as a checkout of the
standards repository that you are editing.  Nothing is fetched, so it works
offline, and the tests use it.

=attr directory

Required.  The top of the tree.

=cut

has 'directory';

=method new(@args)

A new source.

=over 4

=item args - Hash - the attributes, such as L</directory> and C<path>, as named arguments

=back

Returns a Dist::Conformance::Source::Directory object.

Dies unless L</directory> is given.

    my $source = Dist::Conformance::Source::Directory->new( directory => '/bogus/standards' );

=cut

sub new ( $class, @args ) {
    my $self = $class->SUPER::new(@args);
    die "directory is required\n" if !defined $self->directory;
    return $self;
}

=method root

L</directory>, as a L<Mojo::File>.

Returns a Mojo::File object.

Dies when it is not a directory.

    my $top = $source->root;

=cut

sub root ($self) {
    my $root = Mojo::File->new( $self->directory );
    die "The standards directory $root does not exist\n" if !-d $root;
    return $root;
}

=method describe

The directory, and the path inside it.

Returns Str.

    say 'Flavor from ', $source->describe;

=cut

sub describe ($self) {
    return $self->directory . ( $self->path ne q{} ? ' (path ' . $self->path . ')' : q{} );
}

=head1 SEE ALSO

L<Dist::Conformance::Source>

=cut
