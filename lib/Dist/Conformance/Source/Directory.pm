package Dist::Conformance::Source::Directory;

# ABSTRACT: Standards read from a directory on this machine

use 5.040;
use warnings FATAL => 'all';
use re '/aasx';
use Mojo::Base 'Dist::Conformance::Source', -signatures;

use Carp ();
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

=method new

Dies unless L</directory> is given.

=cut

sub new ( $class, @args ) {
    my $self = $class->SUPER::new(@args);
    Carp::croak('directory is required') if !defined $self->directory;
    return $self;
}

=method root

L</directory>, as a L<Mojo::File>.  Dies when it is not a directory.

=cut

sub root ($self) {
    my $root = Mojo::File->new( $self->directory );
    Carp::croak("The standards directory $root does not exist") if !-d $root;
    return $root;
}

=method describe

The directory, and the path inside it.

=cut

sub describe ($self) {
    return $self->directory . ( $self->path ne q{} ? ' (path ' . $self->path . ')' : q{} );
}

=head1 SEE ALSO

L<Dist::Conformance::Source>

=cut
