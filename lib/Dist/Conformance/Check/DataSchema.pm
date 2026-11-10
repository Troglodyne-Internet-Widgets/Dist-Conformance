package Dist::Conformance::Check::DataSchema;

# ABSTRACT: A JSON, YAML or INI file parses and matches a schema

use 5.040;
use warnings FATAL => 'all';
use re '/aasx';
use Mojo::Base 'Dist::Conformance::Check', -signatures;

use Dist::Conformance::Schema();

=head1 IN A FLAVOR

    checks:
      PerlSlopConfig:
        module: DataSchema
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

Some programs read a configuration file that a person writes by hand, and
ignore a key that they do not know without a word.  In such a file a
misspelling turns a rule off.  F<.perl-slop.json> of the perl-slop plugin is
one, as above.  This check reports C<missing> when the file is absent.  It
fails when the file does not parse as a JSON object, a YAML mapping or an INI
file, or does not match C<schema>, and passes otherwise.

An INI file, such as F<dist.ini>, is a hash of its sections by their whole
header, as L<Dist::Conformance::Schema/parse_ini> says.  So a schema can refuse
a key of a plugin:

    checks:
      GithubMetaFromRemote:
        module: DataSchema
        file: dist.ini
        schema:
          type: object
          patternProperties:
            '\AGithubMeta(?:\s*/.*)?\z':
              type: object
              properties:
                user:
                  not: {}
                  x-errorMessage:
                    not: overrides the account in the URL of the origin remote

The update cannot remove such a key, because a schema says what is wrong and
not how to fix it.  L<Dist::Conformance::Check::RefusedIniKeys> refuses a key
of a plugin and removes it.

The schema is in the flavor, so that it changes in the same commit as the
standards that describe the file.  It is an OpenAPI v3 schema, as
L<Dist::Conformance::Schema> describes.

What a file should say is the repository's own choice, so the update changes
nothing.  It says what is wrong when the check fails.

=head1 CONFIGURATION

=over

=item file

Required.  The path of the file.

=item schema

Required.  The schema that its content must match.

=item format

C<json>, C<yaml> or C<ini>: how to parse the file.  Default C<json> for a file
whose name ends in F<.json>, C<yaml> for one whose name ends in F<.yml> or
F<.yaml>, and C<ini> for one whose name ends in F<.ini>.  A file with any other
name needs it.

=item missing

The status when the file is absent.  Default C<info>, because a file of this
kind is usually optional.

=back

=cut

my %PARSER = (
    json => \&Dist::Conformance::Schema::parse_json,
    yaml => \&Dist::Conformance::Schema::parse_yaml,
    ini  => \&Dist::Conformance::Schema::parse_ini,
);

my %FORMAT_OF_EXTENSION = ( json => 'json', yml => 'yaml', yaml => 'yaml', ini => 'ini' );

sub config_schema ($) {
    return {
        required   => [qw{file schema}],
        properties => {
            file    => $Dist::Conformance::Schema::PATH,
            schema  => { type => 'object' },
            format  => { type => 'string', enum => [ sort keys %PARSER ] },
            missing => { %$Dist::Conformance::Schema::STATUS, default => 'info' },
        },
    };
}

=method from_config

The same as L<Dist::Conformance::Check/from_config>.  It also dies when there
is no C<format> and the name of C<file> does not say one.

=cut

sub from_config ( $class, %arguments ) {
    my $where = $arguments{where} // "the check $arguments{name}";
    my $self  = $class->SUPER::from_config(%arguments);
    my $file  = $self->config->{file};
    die "$where is not valid:\n  /format: $file does not end in .json, .yml, .yaml or .ini, so give json, yaml or ini\n" if !defined $self->file_format;
    return $self;
}

=method file_format

C<json> or C<yaml>: C<format>, or the format that the extension of C<file>
says.  Undefined when neither says one.

=cut

sub file_format ($self) {
    my $config = $self->config;
    return $config->{format} if defined $config->{format};
    my ($extension) = $config->{file} =~ m/[.]([^.\/]+)\z/;
    return defined $extension ? $FORMAT_OF_EXTENSION{ lc $extension } : undef;
}

=method check

C<($snapshot)>.  The status and the message that L</DESCRIPTION> says, for the
file in C<$snapshot>.

=cut

sub check ( $self, $snapshot ) {
    my ( $file, $schema ) = @{ $self->config }{qw{file schema}};
    my $text   = $snapshot->content($file)                                // return ( $self->config->{missing}, "there is no $file" );
    my $data   = eval { $PARSER{ $self->file_format }->( $text, $file ) } // return ( 'fail',                   Dist::Conformance::Schema::first_line($@) );
    my @errors = Dist::Conformance::Schema::errors( $data, $schema );
    return ( 'fail', "$file does not match the schema: " . join '; ', @errors ) if @errors;
    return ( 'pass', 'valid' );
}

=head1 SEE ALSO

L<Dist::Conformance::Check>

=cut
