package ExtUtils::ParseVersion;
use strict;
use warnings;
require 5.006;
use version;

our $VERSION = '0.001000';
$VERSION =~ tr/_//d;

use Exporter (); BEGIN { *import = \&Exporter::import }

our @EXPORT_OK = qw(parse_version);


my $VSTRING_V_RE = qr{
  v[0-9][0-9_]*(?:\.[0-9][0-9_]*)*
  |
  (?:[0-9][0-9_]*)?(?:\.[0-9][0-9_]*){2,}
}x;
my $NUMERIC_V_RE = qr{
  -?[0-9][0-9_]*(?:\.[0-9_]*)?
  |
  -?\.[0-9][0-9_]*
}x;

my $VERSION_RE = qr{
  $VSTRING_V_RE
  |
  $NUMERIC_V_RE
}x;
#my $VERSION_RE = qr{[v-]?[0-9._]+};
#my $VERSION_RE = qr/v?[0-9._]+/;

my $STRICT_V_RE = qr{
  v(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]{0,2})){2,}
  |
  (?:0|[1-9][0-9]*)\.[0-9]+
}x;

my $PACKAGE_RE = qr/(?![0-9])\w+(?:(?:::|')\w+)*/;
#my $PACKAGE_RE = qr/\w[\w\:\']*/;

# matches package, optional version
our $PACKAGE_STATEMENT_RE = qr{
    (?:^|\{|;)
    \s*
    package
    \s+
    ($PACKAGE_RE)
    \s*
    \b($VERSION_RE)?
    \s*
    (?:$|\{|;)
}mx;
# should be $STRICT_V_RE, not $VERSION_RE

# matches sigil, variable, optional package
our $VERSION_VAR_RE = qr{
    ([\$*]) (($PACKAGE_RE(?:::|'))? \bVERSION)\b
}mx;

# matches sigil, variable, optional package
our $VERSION_STATEMENT_RE = qr{
    (?<!\\) $VERSION_VAR_RE .* (?<![<>=!])=[^=]
}mx;

# matches (quoting character, version) pairs
our $QUOTED_VERSION_RE = qr{
  (?:
      (['"]?) ($VERSION_RE) \1
  |
      qq? \s* (?:
        | ([^\s\w]) ($VERSION_RE) \3
        | (\s+) ([\w]) ($VERSION_RE) \5
        | (\() ($VERSION_RE) \)
        | (\<) ($VERSION_RE) \>
        | (\[) ($VERSION_RE) \]
        | (\{) ($VERSION_RE) \}
      )
  )
}x;

my %vpm_declare = (
    'qv'                => 1,
    'version::qv'       => 1,
    'version->declare'  => 1,
    'version->parse'    => 0,
    'version->new'      => 0,
);
# matches version call, (quoting character, version) pairs
our $VERSION_PM_RE = qr{
    (?:
        \b(?:version::)?qv
    |
        (?:\bversion(?:::)?|"version"|'version') \s* -> \s* (?:new|parse|declare)
    )
    \s* \( \s*
    $QUOTED_VERSION_RE
    \s* \)
}x;

sub _reader {
    my $file = shift;
    if (!defined $file) {
        die "File must be defined!";
    }
    if (ref $file eq 'CODE') {
        return $file;
    }
    if (ref $file eq 'SCALAR') {
        return sub {
            if (!defined $file) {
                return undef;
            }
            elsif ( $$file =~ /(.*(?:\n|\z))/g ) {
                return "$1";
            }
            else {
                undef $file;
                return undef;
            }
        };
    }
    my $fh;
    my $pre = '';
    if (ref $fh) {
        $fh = $file;
    }
    else {
        open $fh, '<', $file or die "can't read $file: $!";
        $pre = _handle_bom($file);
    }
    return sub {
        local $/ = "\n";
        if (defined $pre) {
            my $out = $pre . readline $fh;
            undef $pre;
            return $out;
        }
        return readline $fh;
    };
}

sub _handle_bom {
    my ($fh) = @_;

    my $encoding;
    my $count = read $fh, my $buf, 2;
    if ($count == 2) {
        if ( $buf eq "\x{FE}\x{FF}" ) {
            $encoding = 'UTF-16BE';
        }
        elsif ( $buf eq "\x{FF}\x{FE}" ) {
            $encoding = 'UTF-16LE';
        }
        elsif ( $buf eq "\x{EF}\x{BB}" ) {
            $count = read $fh, $buf, 1, 2;
            if ( defined $count and $count == 1 and $buf eq "\x{EF}\x{BB}\x{BF}" ) {
                $encoding = 'UTF-8';
            }
        }
    }
    if (defined $encoding) {
        binmode $fh, ":encoding($encoding)";
        return '';
    }
    else {
        return $buf;
    }
}

sub parse_module_version {
    my ($module, %opts) = @_;
    my @inc = @{ $opts{inc} || \@INC };
    (my $file = "$module.pm") =~ s{::|'}{/}g;
    for my $inc (@inc) {
        my $full = "$inc/$file";
        if (-e $full) {
            return parse_version($full, %opts);
        }
    }
    die "Unable to find module $module!";
}

sub parse_version {
    my ($parsefile, %opts) = @_;

    my $all           = $opts{all};
    my $stop_at_end   = $opts{stop_at_end};

    my $read = _reader($parsefile);

    my $inpod = 0;
    my @results;
    my %versions;
    my $last_package;

    while (my $line = $read->()) {
        chomp $line;
        if ($line =~ /^=/) {
            $inpod = $line =~ /^=cut/;
            next;
        }
        if ($inpod
            || $line =~ /^\s*#/
            || $line =~ /^\s*(?:if|unless|elsif)/
        ) {
            next;
        }
        if ($stop_at_end && ($line eq '__END__' || $line eq '__DATA__')) {
            last;
        }

        if ( $line =~ m/$PACKAGE_STATEMENT_RE/m ) {
            my ($package, $version) = ($1, $2);
            if (defined $version) {
                # $version = _normalize_raw_version($version);
                push @results, $package, $version;
                $versions{$package} = $version;
                last
                    if !$all;
            }
            else {
                $last_package = $package;
            }
        }
        elsif ( $line =~ m/$VERSION_STATEMENT_RE/m ) {
            my ($sigil, $variable, $package) = ($1, $2, $3);
            my $try_package = $package || $last_package || 'main';
            if (defined $versions{$try_package}) {
                next;
            }
            my ($version_package, $version)
                = _get_version($line, $sigil, $variable, $try_package, \%opts);
            if (defined $version_package) {
                push @results, $version_package, $version;
                $versions{$version_package} = $version;
                last
                    if !$all;
            }
        }
    }

    return @results;
}

sub _normalize_raw_version {
    my $version = shift;
    if ($version !~ /v/ && $version =~ tr/.// < 2) {
        $version =~ s/_//g;
        $version += 0;
    }
    return $version;
}

sub _get_version {
    my ($line, $sigil, $variable, $package, $opts) = @_;

    my $allow_eval    = exists $opts->{allow_eval} ? $opts->{allow_eval} : 0;
    my $allow_safe    = exists $opts->{allow_safe} ? $opts->{allow_safe} : 1;
    my $parse_cb      = $opts->{parse_cb};

    my @try = (
        \&_static_version,
        ($parse_cb    ? $parse_cb : ()),
        ($allow_safe  ? \&_safe_eval_version : ()),
        ($allow_eval  ? \&_eval_version : ()),
    );

    for my $try (@try) {
        my ($parse_package, $version) = $try->($line, $sigil, $variable, $package);
        if (defined $parse_package) {
              return ($parse_package, $version);
        }
    }
    return;
}

sub _static_version {
    my ($line, $sigil, $variable, $package) = @_;

    if ($line =~ m{
        (?:;|\{|^)
        \s*
        (?:our)? \s*
        \Q${sigil}${variable}\E
        \s* = \s*
        (.+?)
        \s*
        (?:;|$|\}|\#)
    }mx) {
        my $assign = $1;
        if ($sigil eq '*') {
            $assign =~ s/\A\\//
                or return;
        }
        if (my @match = $assign =~ m{\A\s*$QUOTED_VERSION_RE\s*\z}) {
            my ($version, $quote) = grep defined, reverse @match;
            $version = _normalize_raw_version($version) if !$quote;
            return ($package, $version);
        }
        if (my @match = $assign =~ m{\A\s*$VERSION_PM_RE\s*\z}) {
            my ($version, $quote) = grep defined, reverse @match;
            $version = _normalize_raw_version($version) if !$quote;
            if ($assign =~ /declare|qv/) {
                $version =~ s/\Av?/v/;
            }
            require version;
            $version = version->new($version);
            return ($package, $version);
        }
    }
    return;
}

sub _eval_version {
    my ($line, $sigil, $variable, $package) = @_;

    $line =~ m{^(.+)}s and $line = $1;

    package #hide
        ExtUtils::MakeMaker::_version;
    no strict 'refs';
    no warnings;
    undef *version; # in case of unexpected version() sub
    eval {
        require version;
        version::->import;
    };
    local *{$variable};
    my $e;
    {
        local $@;
        eval qq{
            $line;
            1;
        } or $e = $@;
    }
    if (defined $e) {
        return;
    }
    return ($package, $$variable);
}

sub _safe_eval_version {
    my ($line, $sigil, $variable, $package) = @_;
    require Safe;
    { local $@; eval { require version } }

    my $comp = Safe->new;
    $comp->permit(qw(entereval :base_math));
    $comp->deny(qw(enteriter iter unstack goto));
    no strict 'refs';
    $comp->share_from('main', [
        map {
            my $pack = $_;
            map "*${pack}::$_", grep !/^::/, keys %{"${pack}::"};
        } qw(charstar version version::vpp version::vxs version::regex)
    ]);
    $comp->share_from('version', [
        '&qv'
    ]);
    my $code = <<"END_CODE";
    local $sigil$variable;
    {;
        $line
    }
    \$$variable;
END_CODE
    my $result = $comp->reval($code);
    if ($@) {
        return;
    }
    return ($package, $result);
}

1;
__END__

=head1 NAME

ExtUtils::ParseVersion - Parse a version number from a file

=head1 SYNOPSIS

    use ExtUtils::ParseVersion qw(parse_version);
    my ($package, $version) = parse_version($file);

=head1 DESCRIPTION

Parse a version number from a file.

=head1 FUNCTIONS

=head2 parse_version

    my ($package, $version) = parse_version($file);

    my %packages = parse_version($file, all => 1);

Parse a C<$file> and return what C<$VERSION> is set in it.

Depending on what options are set, parsing will be attempted using several
mechanisms.  Static parsing will always be attempted first.

=head3 Options

=over 4

=item all

If true, all version declarations will be returned, as a list of pairs.  They
will be returned in the order they are defined in the file.

Defaults to false.

=item parse_cb

    parse_cb => sub {
        my ($full_line, $sigil, $variable, $package) = @_;
        my $version = ...;
        return ($package, $version);
    },

Can be set to a code ref to do custom parsing.  This allows implementing
additional safety measures, such as timeouts.

=item allow_safe

If true, parsing will be attempted using a L<Safe> compartment.  This restricts
what operations the code can do, but is not guaranteed secure.  This will be
attempted after static and custom parsing, if they fail to find a version.

Defaults to true.

=item allow_eval

If true, parsing will be attempted using a normal L<perlfunc/eval>.  This allows
the code to do almost anything, including loading additional modules.  Generally
unsafe.

Defaults to false.

=back

=head1 AUTHOR

haarg - Graham Knop (cpan:HAARG) <haarg@haarg.org>

=head1 CONTRIBUTORS

None so far.

=head1 COPYRIGHT

Copyright (c) 2020 the ExtUtils::ParseVersion L</AUTHOR> and L</CONTRIBUTORS>
as listed above.

=head1 LICENSE

This library is free software and may be distributed under the same terms
as perl itself. See L<https://dev.perl.org/licenses/>.

=cut
