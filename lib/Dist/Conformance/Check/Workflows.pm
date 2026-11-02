package Dist::Conformance::Check::Workflows;

# ABSTRACT: The CI workflows exist

use 5.040;
use warnings FATAL => 'all';
use re '/aasx';
use Mojo::Base 'Dist::Conformance::Check', -signatures;

use Dist::Conformance::Schema();

=head1 IN A FLAVOR

    checks:
      Workflows:
        directory: .github/workflows
        required:
          ci.yml: templates/workflows/ci.yml

=head1 DESCRIPTION

The workflow files in C<directory>.  With none in C<required>, the check only
lists the ones present, as C<info>.  Otherwise it fails when a required
workflow is missing, and passes when none is.

The update writes each missing workflow from its template.

=head1 CONFIGURATION

=over

=item directory

Required.  The directory of the workflows.

=item required

A mapping from the file name of each workflow that must exist to its template.
A workflow whose template is C<~> must exist, and the update says to write it by
hand.  Default none.

=back

=cut

sub config_schema ($) {
    return {
        required   => ['directory'],
        properties => {
            directory => $Dist::Conformance::Schema::PATH,
            required  => { type => 'object', additionalProperties => { %$Dist::Conformance::Schema::PATH, nullable => 1 }, default => {} },
        },
    };
}

=method missing_workflows

C<($snapshot)>.  The required workflows that the snapshot does not have.

=cut

sub missing_workflows ( $self, $snapshot ) {
    my ( $directory, $required ) = @{ $self->config }{qw{directory required}};
    my @missing = grep { !$snapshot->contains("$directory/$_") } sort keys %$required;
    return @missing;
}

=method check

=cut

sub check ( $self, $snapshot ) {
    my ( $directory, $required ) = @{ $self->config }{qw{directory required}};
    if ( !%$required ) {
        my @have = grep { index( $_, q{/} ) < 0 } $snapshot->under($directory);
        return ( 'info', @have ? 'present: ' . join ', ', @have : 'none' );
    }
    my @missing = $self->missing_workflows($snapshot);
    return ( 'fail', 'missing: ' . join ', ', map { "$directory/$_" } @missing ) if @missing;
    return ( 'pass', 'all present' );
}

=method update

Writes each missing workflow from its template.

=cut

sub update ( $self, $update ) {
    my ( $directory, $required ) = @{ $self->config }{qw{directory required}};
    for my $name ( $self->missing_workflows( $update->snapshot ) ) {
        if ( defined $required->{$name} ) {
            $self->write_template( $update, "$directory/$name", $required->{$name} );
        }
        else {
            $update->by_hand("Write $directory/$name by hand: the flavor names no template for it");
        }
    }
    return;
}

=head1 SEE ALSO

L<Dist::Conformance::Check>

=cut
