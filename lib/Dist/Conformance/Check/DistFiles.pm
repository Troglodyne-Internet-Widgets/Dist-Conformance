package Dist::Conformance::Check::DistFiles;

# ABSTRACT: A distribution has the files that its build needs

use 5.040;
use warnings FATAL => 'all';
use re '/aasx';
use Mojo::Base 'Dist::Conformance::Check::ToolConfiguration', -signatures;

use Dist::Conformance::Schema();

=head1 IN A FLAVOR

    checks:
      DistFiles:
        marker: dist.ini
        absent: info
        files:
          weaver.ini: templates/weaver.ini
          Changes: templates/Changes
          prereqs.yml: templates/prereqs.yml

=head1 DESCRIPTION

L<Dist::Conformance::Check::ToolConfiguration>, for a repository that has a
marker file.  A repository without F<dist.ini> is not a Dist::Zilla
distribution, so it needs no F<weaver.ini>.  Without the marker the check
reports C<absent> and the update does nothing.  With it, it is the same as
L<Dist::Conformance::Check::ToolConfiguration>.

A flavor for a repository that is never a distribution can remove this check
with C<DistFiles: ~>.

=head1 CONFIGURATION

=over

=item marker

Required.  The path whose presence makes the repository one that needs the
files.

=item absent

The status without the marker.  Default C<info>.

=item files

Required.  As in L<Dist::Conformance::Check::ToolConfiguration>.

=back

=cut

sub config_schema ($class) {
    my $schema = $class->SUPER::config_schema;
    return {
        required   => [ 'marker', @{ $schema->{required} } ],
        properties => {
            %{ $schema->{properties} },
            marker => $Dist::Conformance::Schema::PATH,
            absent => { %$Dist::Conformance::Schema::STATUS, default => 'info' },
        },
    };
}

=method check

=cut

sub check ( $self, $snapshot ) {
    my $marker = $self->config->{marker};
    return ( $self->config->{absent}, "no $marker" ) if !$snapshot->contains($marker);
    return $self->SUPER::check($snapshot);
}

=method update

Does nothing without the marker.

=cut

sub update ( $self, $update ) {
    return if !$update->snapshot->contains( $self->config->{marker} );
    return $self->SUPER::update($update);
}

=head1 SEE ALSO

L<Dist::Conformance::Check>

=cut
