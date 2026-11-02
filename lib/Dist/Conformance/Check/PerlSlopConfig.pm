package Dist::Conformance::Check::PerlSlopConfig;

# ABSTRACT: .perl-slop.json parses and matches its schema

use 5.040;
use warnings FATAL => 'all';
use re '/aasx';
use Mojo::Base 'Dist::Conformance::Check', -signatures;

use Dist::Conformance::Schema();

=head1 SYNOPSIS

    checks:
      PerlSlopConfig:
        file: .perl-slop.json
        missing: info
        schema:
          type: object
          additionalProperties: false
          properties:
            before_edit:
              type: object
            before_commit:
              type: object

=head1 DESCRIPTION

F<.perl-slop.json> adds the skills of a repository to the hooks of the
perl-slop plugin.  A key that the plugin does not know is ignored without a
word, so a misspelling turns a rule off.  The check reports C<missing> when the
file is absent, fails when it does not parse as a JSON object or does not match
C<schema>, and passes otherwise.

The schema is in the flavor, so that it changes in the commit of the plugin
that changes the file it describes.  It is an OpenAPI v3 schema, as
L<Dist::Conformance::Schema> describes.

What a file should say is the repository's own choice, so the update changes
nothing.  It says what is wrong when the check fails.

=head1 CONFIGURATION

=over

=item file

Required.  The path of the file.

=item schema

Required.  The schema that its content must match.

=item missing

The status when the file is absent.  Default C<info>, because the file is
optional.

=back

=cut

sub config_schema ($) {
    return {
        required   => [qw{file schema}],
        properties => {
            file    => $Dist::Conformance::Schema::PATH,
            schema  => { type                                         => 'object' },
            missing => { %$Dist::Conformance::Schema::STATUS, default => 'info' },
        },
    };
}

=method check

=cut

sub check ( $self, $snapshot ) {
    my ( $file, $schema ) = @{ $self->config }{qw{file schema}};
    my $text   = $snapshot->content($file)                                      // return ( $self->config->{missing}, "there is no $file" );
    my $data   = eval { Dist::Conformance::Schema::parse_json( $text, $file ) } // return ( 'fail',                   Dist::Conformance::Schema::first_line($@) );
    my @errors = Dist::Conformance::Schema::errors( $data, $schema );
    return ( 'fail', "$file does not match the schema: " . join '; ', @errors ) if @errors;
    return ( 'pass', 'valid' );
}

=head1 SEE ALSO

L<Dist::Conformance::Check>

=cut
