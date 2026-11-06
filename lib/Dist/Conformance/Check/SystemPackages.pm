package Dist::Conformance::Check::SystemPackages;

# ABSTRACT: The system packages that a repository declares in metamerge.yml, validated, and resolved for a host

use 5.040;
use warnings FATAL => 'all';
use re '/aasx';
use Mojo::Base 'Dist::Conformance::Check', -signatures;

use List::Util();

use Dist::Conformance::Schema();
use Dist::Conformance::Snapshot::Directory();

=head1 SYNOPSIS

    use 5.040;
    use Dist::Conformance::Check::SystemPackages;

    my $declared = Dist::Conformance::Check::SystemPackages->declared('/bogus/checkout');
    my $host     = Dist::Conformance::Check::SystemPackages->resolve(
        $declared,
        packager => 'deb',
        distro   => 'ubuntu',
        release  => '24.04',
        codename => 'noble',
    );
    say for @{ $host->{packages} };

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
        - name: libssl3
          ubuntu/24.04: libssl3t64
        - ubuntu/24.04: libfoo-t64
        - debian: libbar
      sources:
        deb:
          - name: jellyfin
            uri: https://repo.test.test/ubuntu
            suites: ['{codename}']
            components: [main]
            key: https://repo.test.test/key.gpg
            fingerprint: 0123456789ABCDEF0123456789ABCDEF01234567
            distros: [ubuntu/24.04, ubuntu/22.04]
      programs:
        - ffmpeg -version

Each key other than C<programs> and C<sources> is the name of a packager: a
lowercase letter, then lowercase letters and digits, as
C<< Provisioner::Packager->named >> takes it.  Its value is a list of entries,
and each entry says which package to install.  C<sources> holds the
third-party archives that the packages come from, for each packager.
C<programs> is optional.  It is a list of command lines that must exit 0 once
the packages are installed, because a package that is installed is not yet a
program that runs.

The declaration says what a host must install.  This check does not ask what
a host has installed.  It reads a snapshot, which can be of a repository that
is not on this machine, and does not run the programs.  Other code installs the
packages: it reads them with L</declared> and L</resolve>, or with
C<conformance packages> (see L<conformance>).

=head2 An entry

An entry is a package name, which applies to every host, or a mapping.  A key
of the mapping is C<name>, C<DISTRO> or C<DISTRO/RELEASE>, and its value is a
package name.  C<DISTRO> is the C<ID> of F</etc/os-release>, such as C<ubuntu>
or C<debian>, and C<RELEASE> is its C<VERSION_ID>, such as C<24.04> or C<12>.
Both are lowercase letters, digits, C<.>, C<_> and C<->.  For a host, the most
specific key wins: C<DISTRO/RELEASE>, then C<DISTRO>, then C<name>.  An entry
without a key that matches the host is skipped on that host.  A mapping with
no key is not valid.

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

A list of entries, a list of sources, and C<programs> must hold at least one
item.  A program is a line that is not blank, so that
C<conformance packages --programs> can print one on each line.

=head2 A source

Only C<deb> takes sources.  A source of C<deb> is an apt archive, with the keys
of a source of C<Provisioner::Packager::Deb>, and two more:

=over

=item name

The base name of the files of the source: lowercase letters, digits, C<.> and
C<->, from a letter or a digit.

=item C<uri>, C<key>

The archive, and the URL of its signing key, as C<http> or C<https>.

=item suites

At least one suite.  C<{codename}> in a suite is replaced by the
C<VERSION_CODENAME> of the host.  No other placeholder is allowed.

=item components

A list of components.

=item architectures

Optional.  A list of architectures: lowercase letters and digits.

=item pin

Optional.  A mapping with an integer C<priority>, and C<packages>, a glob of
package names.

=item fingerprint

Required.  The full fingerprint of the signing key, as 40 hex digits.  The
archive gets the trust of root on the host, and a key URL can serve another
key later, so the installer refuses a key with another fingerprint.

=item distros

Optional.  A list of C<DISTRO> and C<DISTRO/RELEASE>, as in L</An entry>.  The
source applies only to a host that one of them matches.  Default every host.

=back

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

# The name of a packager, as Provisioner::Packager->named takes it.  programs and sources are not one.
our $PACKAGER = '\A(?!(?:programs|sources)\z)[a-z][a-z0-9]*\z';

our %PACKAGE_NAME = ( deb => '\A[a-z0-9][a-z0-9+.-]*[a-z0-9+.]\z' );

our $ANY_PACKAGE_NAME = '\A[A-Za-z0-9](?:[A-Za-z0-9+._-]*[A-Za-z0-9+._])?\z';

# DISTRO or DISTRO/RELEASE, in the characters that os-release allows in ID and VERSION_ID.
our $HOST = '\A[a-z0-9._-]+(?:/[a-z0-9._-]+)?\z';

my sub list_of ($item) { return { type => 'array', minItems => 1, items => $item } }

my sub entry_of ($pattern) {
    my $name = { type => 'string', pattern => $pattern };
    return {
        anyOf => [
            $name,
            {
                type                 => 'object',
                minProperties        => 1,
                additionalProperties => 0,
                properties           => { name                 => $name },
                patternProperties    => { '(?!name\z)' . $HOST => $name },
            },
        ],
    };
}

our $URL = { type => 'string', pattern => '\Ahttps?://[^/\s]+\S*\z' };

our %SOURCE = (
    deb => {
        type                 => 'object',
        required             => [qw{name uri suites components key fingerprint}],
        additionalProperties => 0,
        properties           => {
            name          => { type => 'string', pattern => '\A[a-z0-9][a-z0-9.-]*\z' },
            uri           => $URL,
            key           => $URL,
            suites        => list_of( { type => 'string', pattern => '\A(?:[^\s{}]|\{codename\})+\z' } ),
            components    => { type => 'array',  items   => { type => 'string', pattern => '\A\S+\z' } },
            architectures => { type => 'array',  items   => { type => 'string', pattern => '\A[a-z0-9]+\z' } },
            fingerprint   => { type => 'string', pattern => '\A[0-9A-Fa-f]{40}\z' },
            distros       => list_of( { type => 'string', pattern => $HOST } ),
            pin           => {
                type                 => 'object',
                required             => ['priority'],
                additionalProperties => 0,
                properties           => { priority => { type => 'integer' }, packages => { type => 'string', pattern => '\A\S+\z' } },
            },
        },
    },
);

our $SCHEMA = {
    type                 => 'object',
    additionalProperties => 0,
    properties           => {
        programs => list_of( { type => 'string', pattern => '\A[^\n]*\S[^\n]*\z' } ),
        sources  => {
            type                 => 'object',
            additionalProperties => 0,
            properties           => { map { $_ => list_of( $SOURCE{$_} ) } keys %SOURCE },
        },
        map { $_ => list_of( entry_of( $PACKAGE_NAME{$_} ) ) } keys %PACKAGE_NAME,
    },
    patternProperties => { $PACKAGER => list_of( entry_of($ANY_PACKAGE_NAME) ) },
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

C<($from)>, a class method.  The validated declaration of a repository, as it
is written: a hash reference from each packager to an array reference of its
entries, C<sources> to a hash reference from each packager to an array
reference of its sources, when there are any, and C<programs> to an array
reference of the command lines, such as
C<< { deb => ['ffmpeg', { name => 'libssl3', 'ubuntu/24.04' => 'libssl3t64' }], programs => ['ffmpeg -version'] } >>.
C<programs> is always there, and empty when the declaration has none.  So a
repository that declares nothing gives C<< { programs => [] } >>.  L</resolve>
gives what one host installs.

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

=method resolve

C<($declared, %host)>, a class method.  What one host installs, from
C<$declared> as L</declared> returns it.  C<%host> has:

=over

=item packager

Required.  The packager of the host, such as C<deb>.

=item distro, release

The C<ID> and the C<VERSION_ID> of F</etc/os-release>.  Without them, only
C<name> matches an entry, and only a source without C<distros> applies.

=item codename

The C<VERSION_CODENAME> of F</etc/os-release>, for C<{codename}> in a suite.

=back

Returns a hash reference with three array references: C<packages>, the package
name of each entry that matches the host, without duplicates and in their
order; C<sources>, each source of the packager that applies to the host, with
C<{codename}> filled in and without C<distros>; and C<programs>.  Dies on a
source that applies and needs a codename that C<%host> does not give.

=cut

sub resolve ( $, $declared, %host ) {
    my ( $packager, $distro, $release, $codename ) = @host{qw{packager distro release codename}};
    die "resolve needs a packager\n" if !defined $packager;
    my @keys    = ( ( defined $distro && defined $release ? "$distro/$release" : () ), ( defined $distro ? $distro : () ), 'name' );
    my %on_host = map { $_ => 1 } grep { $_ ne 'name' } @keys;

    my @packages;
    for my $entry ( @{ $declared->{$packager} // [] } ) {
        if ( !ref $entry ) {
            push @packages, $entry;
            next;
        }
        my ($key) = grep { defined $entry->{$_} } @keys;
        push @packages, $entry->{$key} if defined $key;
    }
    @packages = List::Util::uniq(@packages);

    my @sources;
    for my $source ( @{ $declared->{sources}{$packager} // [] } ) {
        next if $source->{distros} && !List::Util::any( sub { $on_host{$_} }, @{ $source->{distros} } );
        my %resolved = %$source;
        delete $resolved{distros};
        $resolved{suites} = [
            map {
                my $suite = $_;
                die "The source $source->{name} needs the codename of the host, for the suite $suite\n" if index( $suite, '{codename}' ) >= 0 && !defined $codename;
                $suite =~ s/\{codename\}/$codename/gr;
            } @{ $source->{suites} }
        ];
        push @sources, \%resolved;
    }
    return { packages => \@packages, sources => \@sources, programs => [ @{ $declared->{programs} // [] } ] };
}

=func os_release

C<($text)>.  The variables of the text of an F</etc/os-release>, as a hash
reference from each name to its value, such as
C<< { ID => 'ubuntu', VERSION_ID => '24.04', VERSION_CODENAME => 'noble' } >>.
A value can be bare, in single quotes, or in double quotes with C<\>
escapes, as the shell reads it.  Blank lines and comments are skipped.

=cut

sub os_release ($text) {
    my %variables;
    for my $line ( split /\n/, $text ) {
        my ( $name, $value ) = $line =~ m/\A\s*([[:alpha:]_]\w*)=(.*?)\s*\z/ or next;
        my ($double) = $value =~ m/\A"((?:[^"\\]|\\.)*)"\z/;
        my ($single) = $value =~ m/\A'([^']*)'\z/;
        $variables{$name} = defined $double ? $double =~ s/\\(.)/$1/gr : $single // $value;
    }
    return \%variables;
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
    my $sources     = delete $declaration->{sources} // {};
    my @said        = map { count_of( scalar @{ $declaration->{$_} }, "$_ package" ) } sort keys %$declaration;
    push @said, map { count_of( scalar @{ $sources->{$_} }, "$_ source" ) } sort keys %$sources;
    push @said, count_of( scalar @$programs, 'program' ) if @$programs;
    return ( 'pass', "$FILE declares no system packages" ) if !@said;
    my $last = pop @said;
    return ( 'pass', "$FILE declares " . ( @said ? join( ', ', @said ) . " and $last" : $last ) );
}

=head1 SEE ALSO

L<Dist::Conformance::Check>

L<conformance>

=cut
