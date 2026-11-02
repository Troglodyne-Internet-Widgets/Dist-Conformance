package Dist::Conformance::Check::ToolConfiguration;

# ABSTRACT: The configuration files of the tools exist

use 5.040;
use warnings FATAL => 'all';
use re '/aasx';
use Mojo::Base 'Dist::Conformance::Check', -signatures;

use Dist::Conformance::Schema();

=head1 IN A FLAVOR

    checks:
      ToolConfiguration:
        files:
          .perltidyrc: templates/perltidyrc
          .preferred_modules.ini: templates/preferred_modules.ini
          .pod_stopwords: templates/pod_stopwords
          .tests-covering-map.pl: templates/tests-covering-map.pl

=head1 DESCRIPTION

Files that the tools of the harness read, such as perltidy, perlcritic and
tests-covering.  The check passes when every file exists, and fails with the
list of those that do not.  Their content is the repository's own: a stopword
list grows with the repository, so the check does not compare it with the
template.

The update writes each missing file from its template, and leaves a file that
exists alone.

=head1 CONFIGURATION

=over

=item files

Required.  A mapping from each path to its template.  A path whose template is
C<~> must exist, and the update says to write it by hand.

=back

=cut

sub config_schema ($) {
    return {
        required   => ['files'],
        properties => { files => { type => 'object', additionalProperties => { %$Dist::Conformance::Schema::PATH, nullable => 1 } } },
    };
}

=method check

=cut

sub check ( $self, $snapshot ) {
    my @missing = $self->missing( $snapshot, sort keys %{ $self->config->{files} } );
    return ( 'fail', 'missing: ' . join ', ', @missing ) if @missing;
    return ( 'pass', 'all present' );
}

=method update

Writes each missing file from its template.

=cut

sub update ( $self, $update ) {
    my $files = $self->config->{files};
    for my $path ( $self->missing( $update->snapshot, sort keys %$files ) ) {
        if ( defined $files->{$path} ) {
            $self->write_template( $update, $path, $files->{$path} );
        }
        else {
            $update->by_hand("Write $path by hand: the flavor names no template for it");
        }
    }
    return;
}

=head1 SEE ALSO

L<Dist::Conformance::Check>

L<Dist::Conformance::Check::DistFiles>

=cut
