package Dist::Conformance::Check::SystemPackages;

# ABSTRACT: The system packages that a repository declares in metamerge.yml are plain names

use 5.040;
use warnings FATAL => 'all';
use re '/aasx';
use Mojo::Base 'Dist::Conformance::Check', -signatures;

use Dist::Conformance::Schema();
use Dist::Conformance::Snapshot::Directory();

=head1 SYNOPSIS

    use 5.040;
    use Dist::Conformance::Check::SystemPackages;

    my $declared = Dist::Conformance::Check::SystemPackages->declared('/bogus/checkout');
    say for @{ $declared->{deb} // [] };
    say for @{ $declared->{programs} };

=head1 IN A FLAVOR

    checks:
      SystemPackages: {}

=head1 DESCRIPTION

CPAN has no field for a package of the operating system, such as F<ffmpeg> or
F<libmagic-dev>, that a distribution needs.  So a repository declares them
under C<x_system_packages> in F<metamerge.yml>, the file that C<[MetaMergeFile]>
of Dist::Zilla merges into F<META.json>:

    x_system_packages:
      deb:
        - ffmpeg
        - libmagic-dev
      programs:
        - ffmpeg -version

Each key other than C<programs> is the name of a packager: a lowercase letter,
then lowercase letters and digits.  Its value is a list of the names of the
packages that it installs.  C<programs> is optional.  It is a list of command
lines that must exit 0 once the packages are installed, because a package that
is installed is not yet a program that runs.

The declaration says what a host must install.  This check does not ask what
a host has installed.  It reads a snapshot, which can be of a repository that
is not on this machine, and does not run the programs.  Other code installs the
packages: it reads them with L</declared>, or with C<conformance packages> (see
L<conformance>).

=head2 What a package name is

A package name must be a plain name, and not an expression that the packager
reads in some other way, such as C<foo=1.2>, C<foo/sid> or two names.  Each
packager has its own rule:

=over

=item deb

The rule of the Debian policy: lowercase letters, digits, C<+>, C<-> and C<.>,
at least two characters, starting with a letter or a digit.  The name must not
end in C<->, because C<apt-get install foo-> removes F<foo>.

=item any other packager

Letters, digits, C<+>, C<.>, C<_> and C<->, starting with a letter or a digit,
and not ending in C<->, until the packager has a rule of its own here.

=back

A list of packages, and C<programs>, must hold at least one item.  A program
is a line that is not blank, so that C<conformance packages --programs> can
print one on each line.

=head1 STATUSES

The check passes when there is no F<metamerge.yml>, when it has no
C<x_system_packages>, and when the declaration is valid, because most
repositories need no system packages.  It fails when F<metamerge.yml> does not
parse, or when the declaration is not valid.  The update changes nothing: what
a repository needs is its own choice.

=head1 CONFIGURATION

None, other than L<Dist::Conformance::Check/THE KEYS THAT EVERY CHECK TAKES>.

=cut

our $FILE = 'metamerge.yml';
our $KEY  = 'x_system_packages';

# The name of a packager, as Provisioner::Packager->named takes it.  programs is not one.
our $PACKAGER = '\A(?!programs\z)[a-z][a-z0-9]*\z';

our %PACKAGE_NAME = ( deb => '\A[a-z0-9][a-z0-9+.-]*[a-z0-9+.]\z' );

our $ANY_PACKAGE_NAME = '\A[A-Za-z0-9](?:[A-Za-z0-9+._-]*[A-Za-z0-9+._])?\z';

my sub list_of ($item) { return { type => 'array', minItems => 1, items => $item } }

our $SCHEMA = {
    type                 => 'object',
    additionalProperties => 0,
    properties           => {
        programs => list_of( { type => 'string', pattern => '\A[^\n]*\S[^\n]*\z' } ),
        map { $_ => list_of( { type => 'string', pattern => $PACKAGE_NAME{$_} } ) } keys %PACKAGE_NAME,
    },
    patternProperties => { $PACKAGER => list_of( { type => 'string', pattern => $ANY_PACKAGE_NAME } ) },
};

our $DOCUMENT_SCHEMA = { type => 'object', properties => { $KEY => $SCHEMA } };

# The mapping of metamerge.yml, or an empty one when there is none.  Dies when the file does not parse.
my sub document_of ($snapshot) {
    my $text = $snapshot->content($FILE) // return {};
    return Dist::Conformance::Schema::parse_yaml( $text, $FILE );
}

my sub declaration_of ($document) { return { programs => [], %{ $document->{$KEY} // {} } } }

my sub count_of ( $count, $noun ) { return "$count $noun" . ( $count == 1 ? q{} : 's' ) }

=method declared

C<($from)>, a class method.  The validated declaration of a repository, as a
hash reference from each packager to an array reference of its package names,
and C<programs> to an array reference of the command lines, such as
C<< { deb => ['ffmpeg', 'libmagic-dev'], programs => ['ffmpeg -version'] } >>.
C<programs> is always there, and empty when the declaration has none.  So a
repository that declares nothing gives C<< { programs => [] } >>.

C<$from> is a L<Dist::Conformance::Snapshot>, such as a
L<Dist::Conformance::Snapshot::Tree> of a remote repository, or the directory
of a checkout.  Only F<metamerge.yml> is read.

Dies when F<metamerge.yml> does not parse, and when the declaration is not
valid.  Then the message starts with C<metamerge.yml is not valid:>, and gives
each error on a line of its own, as L<Dist::Conformance::Schema/validate> does.

=cut

sub declared ( $, $from ) {
    my $snapshot = builtin::blessed($from) && $from->isa('Dist::Conformance::Snapshot') ? $from : Dist::Conformance::Snapshot::Directory->new( root => $from );
    return declaration_of( Dist::Conformance::Schema::validate( document_of($snapshot), $DOCUMENT_SCHEMA, $FILE ) );
}

=method check

=cut

sub check ( $, $snapshot ) {
    return ( 'pass', "there is no $FILE, so it needs no system packages" ) if !$snapshot->contains($FILE);
    my $document = eval { document_of($snapshot) } // return ( 'fail', Dist::Conformance::Schema::first_line($@) );
    my @errors   = Dist::Conformance::Schema::errors( $document, $DOCUMENT_SCHEMA );
    return ( 'fail', "$FILE is not valid: " . join '; ', @errors ) if @errors;
    my $declaration = declaration_of($document);
    my $programs    = delete $declaration->{programs};
    my @said        = map { count_of( scalar @{ $declaration->{$_} }, "$_ package" ) } sort keys %$declaration;
    push @said, count_of( scalar @$programs, 'program' ) if @$programs;
    return ( 'pass', "$FILE declares no system packages" ) if !@said;
    my $last = pop @said;
    return ( 'pass', "$FILE declares " . ( @said ? join( ', ', @said ) . " and $last" : $last ) );
}

=head1 SEE ALSO

L<Dist::Conformance::Check>

L<conformance>

=cut
