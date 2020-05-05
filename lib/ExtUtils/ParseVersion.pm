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

my $NUMERIC_RE = qr{
  (?:
    [-+]?[0-9][0-9_]*(?:\.[0-9_]*)?
  |
    [-+]?\.[0-9][0-9_]*
  )
  (?:[eE][-+]?[0-9]+)?
|
  [-+]?0[xX][0-9a-zA-F]*
}x;

my $VERSION_RE = qr{
  $VSTRING_V_RE
|
  $NUMERIC_RE
}x;

my $STRICT_V_RE = qr{
  v(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]{0,2})){2,}
|
  (?:0|[1-9][0-9]*)\.[0-9]+
}x;

my $PACKAGE_RE = qr{
  (?=[^0-9'])
  (?:
    ::
  |
    \w*
    (?:'[^\W0-9]\w*)*
  )*
}x;

# matches package, optional version
my $PACKAGE_STATEMENT_RE = qr{
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
# XXX should be $STRICT_V_RE, not $VERSION_RE
# EUMM has tests for $VERSION_RE style

# matches sigil, variable, optional package
my $VERSION_VAR_RE = qr{
  ([\$*]) ((?:($PACKAGE_RE)(?:::|'))? \bVERSION)\b
}mx;

my $VAR_RE = qr{
  \$(?:$PACKAGE_RE(?:::|'))?\w+\b
}mx;

# matches sigil, variable, optional package
my $VERSION_STATEMENT_RE = qr{
  (?<!\\) $VERSION_VAR_RE .* (?<![<>=!])=[^=~>]
}mx;

# matches (quoting character, version) pairs
my $QUOTED_VERSION_RE = qr{
  (['"]?) ($VERSION_RE) \1
|
  qq? \s* (?:
      ([^\s\w]) ($VERSION_RE) \3
    | \s+ ([\w]) ($VERSION_RE) \5
    | (\() ($VERSION_RE) \)
    | (\<) ($VERSION_RE) \>
    | (\[) ($VERSION_RE) \]
    | (\{) ($VERSION_RE) \}
  )
}x;

# matches at least one quoted content
my $SIMPLE_QUOTE_RE = qr{
  ' ((?:[^'\\]|\\[^\\'])*) '
|
  " ([^"\\\$\@]*) "
|
  q \s* (?:
      \$ ([^\\\$]*) \$
    |  / ([^\\/]*)  /
    | \( ([^\\\)]*) \)
    | \< ([^\\\>]*) \>
    | \[ ([^\\\]]*) \]
    | \{ ([^\\\}]*) \}
  )
|
  qq \s* (?:
      \$ ([^\$\\\$\@]*) \$
    | /  ([^/\\\$\@]*)  /
    | \( ([^\)\\\$\@]*) \)
    | \< ([^\>\\\$\@]*) \>
    | \[ ([^\]\\\$\@]*) \]
    | \{ ([^\}\\\$\@]*) \}
  )
}x;

my $QW_RE = qr{
  qw \s* (?:
      \$ ([^\\\$]*) \$
    |  / ([^\\/]*)  /
    | \( ([^\\\)]*) \)
    | \< ([^\\\>]*) \>
    | \[ ([^\\\]]*) \]
    | \{ ([^\\\}]*) \}
  )
}x;

# matches v(quoting character, version) pairs, trailing method
my $VERSION_PM_RE = qr{
  (?:
    \b(?:version::)?qv
  |
    (?:\bversion(?:::)?|"version"|'version') \s* -> \s* (?:new|parse|declare)
  )
  \s* \(?
  \s* $QUOTED_VERSION_RE
  \s* \)?
  (?:->(?:numify|normal)\b)?
}x;

my $IGNORABLE_PRAGMA_RE = qr{
  \s* use \s+
  (?:
    vars
  |
    version
  |
    strict
  |
    warnings
  |
    utf8
  |
    v?5\.[0-9.]+
  )
  (?: \s+ [^;]* )?
  ;
}x;

my $EOL_RE = qr{\s*;?\s*(?:\#.*|\z)};

# transform a file input into an iterator sub
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
  my $pre;
  if (ref $fh) {
    $fh = $file;
  }
  else {
    open $fh, '<', $file or die "can't read $file: $!";
    (my $encoding, $pre) = _handle_bom($fh);
    if ($encoding) {
      binmode $fh, ":encoding($encoding)";
    }
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

# returns a list of (encoding, buffer), either possibly undef
# buffer will be bytes that were read but unused in BOM parsing and should be
# treated as a prefix to the file handle content.  Matches the BOM handling of
# perl when reading source files.
sub _handle_bom {
  my ($fh) = @_;

  my $encoding;
  my $count = read $fh, my $buf, 2;
  if ($count == 2) {
    if ( $buf eq "\x{FE}\x{FF}" ) {
      return 'UTF-16BE';
    }
    elsif ( $buf eq "\x{FF}\x{FE}" ) {
      return 'UTF-16LE';
    }
    elsif ( $buf eq "\x{EF}\x{BB}" ) {
      $count = read $fh, $buf, 1, 2;
      if ( defined $count and $count == 1 and $buf eq "\x{EF}\x{BB}\x{BF}" ) {
        return 'UTF-8';
      }
    }
    # try to match the byte pattern of UTF-16 without a BOM, like perl does.
    # either 00 xx 00 xx or xx 00 xx 00
    elsif (index($buf, "\0") != -1) {
      $count = read $fh, $buf, 2, 2;
      if ( defined $count and $count == 2) {
        # if we matched one of these byte patterns, we can "decode" them
        # ourselves by treating the non-null bytes as characters, without
        # needing to invoke the Encode module
        if ($buf =~ /\A\0([^\0])\0([^\0])/) {
          return ('UTF-16BE', "$1$2");
        }
        elsif ($buf =~ /\A([^\0])\0([^\0])\0/) {
          return ('UTF-16LE', "$1$2");
        }
      }
    }
  }
  return (undef, $buf);
}

sub parse_module_version {
  my ($module, %opts) = @_;
  my @inc = @{ delete $opts{inc} || \@INC };
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

  my $opts = {
    allow_static        => 1,
    allow_static_exotic => 1,
    parse_cb            => undef,
    allow_safe          => 1,
    allow_eval          => 0,
    all                 => 0,
    stop_at_end         => 0,
    stop_at_data        => 0,
    accept_undef        => 0, #TODO
    accept_invalid      => 0, #TODO
    line_cb             => undef,
    package_cb          => undef, #TODO
  };
  my @bad = sort grep !exists $opts->{$_}, keys %opts;
  die "Invalid options (@bad)!"
    if @bad;
  @{$opts}{keys %opts} = values %opts;

  my $all           = $opts->{all};
  my $stop_at_end   = $opts->{stop_at_end};
  my $stop_at_data  = $opts->{stop_at_data};
  my $line_cb       = $opts->{line_cb};
  my $package_cb    = $opts->{package_cb};

  my $read = _reader($parsefile);

  my $inpod = 0;
  my @results;
  my %versions;
  my $last_package = 'main';

  while (my $line = $read->()) {
    chomp $line;
    #XXX s/\r\z// ?
    $line_cb->($line) #XXX chomped?
      if $line_cb;
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
    if ($stop_at_end && $line =~ /\A\s*__END__\b/) {
      last;
    }
    elsif ($stop_at_data && $line =~ /\A\s*__DATA__\b/) {
      last;
    }

    if ( $line =~ m/$PACKAGE_STATEMENT_RE/m ) {
      my ($package, $version) = ($1, $2);
      $package = _normalize_package($package);
      $package_cb->($package) #XXX ???
        if $package_cb;
      if (defined $version) {
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
      my $try_package = $package || $last_package;
      if (defined $versions{$try_package}) {
        next;
      }
      my ($version_package, $version)
        = _get_version($line, $sigil, $variable, $try_package, $opts);
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

sub _normalize_package {
  my ($name, $variable) = @_;
  $name =~ s/'/::/g;

  my $var_name;
  if ($variable) {
    if ($name !~ /::/) {
      return (undef, $name);
    }
    $name =~ s/([^':]*(?:::)?)\z//;
    $var_name = $1;
  }

  $name =~ s/\A:://;
  $name = 'main'
    if !length $name;

  return wantarray ? ($name, $var_name) : $name;
}

sub _normalize_raw_number {
  my $version = shift;

  if ($version =~ /\Av/ || $version =~ tr/.// > 1) {
    $version =~ s/\Av?/v/;
    return $version;
  }

  $version =~ s/_//g;
  if ($version =~ /\A0[0-9]+\z/) {
    $version = oct $version;
  }
  elsif ($version =~ s/\A([-+]?)0x//) {
    $version = hex $version;
    $version = -$version if $1 eq '-';
  }
  return 0+$version;
}

sub _to_versionpm {
  my $version = shift;

  if ($version =~ /\Av/ || $version =~ tr/.// > 1) {
    $version =~ s/\Av?/v/;
    return $version;
  }
  else {

  }
}

sub _get_version {
  my ($line, $sigil, $variable, $package, $opts) = @_;

  my @try = (
    ($opts->{allow_static}        ? \&_static_version : ()),
    ($opts->{allow_static_exotic} ? \&_static_weird_version : ()),
    ($opts->{parse_cb}            ? $opts->{parse_cb} : ()),
    ($opts->{allow_safe}          ? \&_safe_eval_version : ()),
    ($opts->{allow_eval}          ? \&_eval_version : ()),
  );

  for my $try (@try) {
    my ($parse_package, $version) = $try->($line, $sigil, $variable, $package);
    if (defined $parse_package) {
      return ($parse_package, $version);
    }
  }
  return;
}

sub _parse_assign {
  my ($line, $sigil, $variable) = @_;

  if ($line =~ m{
      \A
      (?:
        ( \s* (?:BEGIN\s*)? \{ )
      |
        $IGNORABLE_PRAGMA_RE
      )*
      (?:
        \s* (?: our\b )?
        \s* ( \( )
        \s* (?: our\b )?
        \s* \Q${sigil}${variable}\E
        \s* \)
      |
        \s* (?: our\b )?
        \s* \Q${sigil}${variable}\E
      )
      \s* (?: // | \|\| )? =
      \s* (?: $VAR_RE \s* (?: //=? | \|\|=? | = ) )?
      \s* (.+)
    }mx) {
    my ($brace, $list, $assign) = ($1, $2, $3);

    $list = !!$list;
    my $trail_re = $brace ? qr{\s*;?\s*\}$EOL_RE} : $EOL_RE;

    if ($sigil eq '*') {
      $assign =~ s/\A\\//
        or return;
    }

    return ($assign, $trail_re, $list);
  }

  return;
}

sub _static_version {
  my ($line, $sigil, $variable, $package) = @_;

  my ($assign, $trail_re, $list) = _parse_assign($line, $sigil, $variable);

  return
    if !defined $assign;

  # bare numbers, v-strings, and quoted versions
  if (my @match = $assign =~ m{
    \A  \(?
    \s* $QUOTED_VERSION_RE
    \s* \)?
    $trail_re
  }mx) {
    my ($version, $quote) = grep defined, reverse @match;
    $version = _normalize_raw_number($version) if !$quote;
    return ($package, $version);
  }

  # assignment using version.pm
  if (my @match = grep defined, $assign =~ m{
    \A
    \s* $VERSION_PM_RE
    $trail_re
  }mx) {
    my ($version, $quote) = reverse @match;
    $version = _normalize_raw_number($version) if !$quote;

    if ($assign =~ /declare|qv/) {
      $version =~ s/\Av?/v/
        if $version =~ tr/.// == 1;
      eval {
        require version;
        $version = version::qv($version)
      };
    }
    else {
      eval {
        require version;
        $version = version->new($version);
      };
    }
    if (my ($method) = $assign =~ /(normal|numify)/) {
      eval {
        $version = $version->$method;
        1;
      } or do {
        return;
      };
    }
    return ($package, $version);
  }

  return;
}

my $RESTRICTED_ESCAPES_RE = qr{
  (?:
    [ a-zA-Z0-9:^*+?.()\[\]-]
  |
    \\[.dsS\$]
  )*
}x;

my $RESTRICTED_RE_RE = qr{
  /
  (
    (?:
      [ a-zA-Z0-9:,^*+?.()\[\]-]
    |
      \\[.dsS\$]
    )*
  )
  /
  ([msgxo]*)
}x;

sub _re_match {
  my ($match, $re, $flags) = @_;
  $flags =~ s/o//;
  my $g = $flags =~ s/g//;
  local $@;
  if (!ref $re) {
    eval {
      $re = qr{(?$flags)$re};
    } or return;
  }
  return $g ? $match =~ /$re/g : $match =~ /$re/;
}

sub _static_weird_version {
  my ($line, $sigil, $variable, $package) = @_;

  my ($assign, $trail_re, $list) = _parse_assign($line, $sigil, $variable);

  return
    if !defined $assign;

  # non-version strings
  if (my @match = grep defined, $assign =~ m{
    \A
    \(?\s*$SIMPLE_QUOTE_RE\s*\)?
    $trail_re
  }x) {
    my ($version, $quote) = @match;
    return ($package, $version);
  }

  # do { my @r = (q$Revision: 0.4 $ =~ /\d+/g); sprintf " %d." . "%02d" x $#r, @r }
  if (my @match = grep defined, $assign =~ m{
    \A
    do \s* \{
      \s* my\s*\@r\s*=
      \s* \(?
      \s* $SIMPLE_QUOTE_RE
      \s* =~ \s*$RESTRICTED_RE_RE
      \s* \)? \s* ;
      \s* sprintf\s*\(?
      \s* $SIMPLE_QUOTE_RE
      \s* \.\s*\(?\s*$SIMPLE_QUOTE_RE
      \s* x\s*\$\#r\s*\)?
      \s* ,\s*\@r\s*\)?\s*;?
    \s* \}
    $trail_re
  }mx) {
    my $format2 = pop @match;
    my $format1 = pop @match;
    my @parts = _re_match(@match);

    my $format = $format1 . (@parts ? ($format2 x $#parts) : '');
    my $version = do { no warnings; sprintf $format, @parts };
    return ($package, $version);
  }

  # q$Revision: 0.4 $ =~ /(\d+)/g
  if (my @match = grep defined, $assign =~ m{
      \A
      \(?\s*
      $SIMPLE_QUOTE_RE\s*=~\s*$RESTRICTED_RE_RE
      \s*\)?
      $trail_re
  }mx) {
    my @parts = _re_match(@match);
    my $version = $list ? $parts[0] : 0+@parts;
    return ($package, $version);
  }

  # sprintf("%d.%02d", q$Revision: 0.4 $ =~ /(\d+)\.(\d+)/)
  if (my @match = grep defined, $assign =~ m{
    \A
    sprintf\s*\(?\s*$SIMPLE_QUOTE_RE\s*,\s*$SIMPLE_QUOTE_RE\s*=~\s*
    $RESTRICTED_RE_RE
    \s*\)?
    $trail_re
  }mx) {
    my $format = shift @match;
    my @parts = _re_match(@match);
    my $version = do { no warnings; sprintf $format, @parts };
    return ($package, $version);
  }

  # (q$Revision: 6570 $ =~ /(\d+)/g)[0]
  # (qw$Revision: 0.02 $)[-1]
  if (my @match = grep defined, $assign =~ m{
    \A
    \(
    \s*
    (?:
      $SIMPLE_QUOTE_RE
      \s*=~\s*
      $RESTRICTED_RE_RE
    |
      $QW_RE
    )
    \s*
    \)
    \s*
    \[\s*($NUMERIC_RE)\s*\]
    $trail_re
  }mx) {
    my $index = _normalize_raw_number(pop @match);
    my @parts = _re_match(@match, qr{(\S+)}, 'g');
    my $version = $parts[$index];
    return ($package, $version);
  }

  # $VERSION = substr q$Revision: 0.4 $, 10, -1;
  if (my @match = grep defined, $assign =~ m{
    \A
    substr
    \s* \(?
    $SIMPLE_QUOTE_RE
    \s* , \s* ( [-+]? (?: 0 | [1-9][0-9]* ) )
    (?: \s* , \s* ( [-+]? (?: 0 | [1-9][0-9]* ) ) )?
    \)?
    $trail_re
  }mx) {
    my ($string, $offset, $length) = @match;
    my $version = defined $length ? substr($string, $offset, $length) : substr($string, $offset);
    return ($package, $version);
  }

  # $VERSION = eval{require version}?version::qv($_):$_ for(999999999);
  if (my @match = grep defined, $assign =~ m{
    \A
    eval\s*\{\s*require\s+version\s*;?\s*\}
    \s* \? \s*version::qv\( \s* \$_ \s* \) 
    \s* : \s* \$_
    \s+ for \s* \(? \s* $QUOTED_VERSION_RE \s* \)?
    $trail_re
  }mx) {
    my ($version, $quote) = reverse @match;
    $version = _normalize_raw_number($version) if !$quote;
    $version =~ s/\Av?/v/
      if $version =~ tr/.// == 1;
    return ($package, $version);
  }

  # sprintf '%i.%999999999i', split(/\./,('$Revision: 999999999 $' =~ /Revision: (\S+)\s/)[999999999]); # $Date: 999999999/999999999/999999999 999999999:999999999:999999999 $
  if (my @match = grep defined, $assign =~ m{
    \A  sprintf \s* \(?
    \s* $SIMPLE_QUOTE_RE \s* ,
    \s* split \s* \(? \s* /\\\./ \s* ,
    \s* \( \s* $SIMPLE_QUOTE_RE \s* =~ \s* $RESTRICTED_RE_RE \s * \)
    \s* \[ \s* ( $NUMERIC_RE ) \s* \] \s * \)?
    $trail_re
  }mx) {
    my $format = shift @match;
    my $index = _normalize_raw_number(pop @match);
    my $match = ( _re_match(@match) )[$index];
    my @parts = split /\./, $match;
    my $version = do { no warnings; sprintf $format, @parts };
    return ($package, $version);
  }

  if (my @match = grep defined, $assign =~ m{
    \A  qw \s* \( \s* (\S+) \s* \)
    $trail_re
  }mx) {
    my ($version) = @match;
    return ($package, $version);
  }

  return;
}

sub _eval_version {
  my ($line, $sigil, $variable, $package) = @_;

  $line =~ m{^(.+)}s and $line = $1;

  package #hide
    ExtUtils::ParseVersion::_version;
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
  my $version = $$variable;
  return ($package, $version);
}

sub _safe_eval_version {
  my ($line, $sigil, $variable, $package) = @_;
  require Safe;
  { local $@; eval { require version } }

  my $comp = Safe->new;
  $comp->permit(qw(entereval :base_math));
  $comp->deny(qw(enteriter iter unstack goto));
  $comp->share_from('main', [
    map {
      no strict 'refs';
      my $pack = $_;
        map "&$_",
        grep exists &$_,
        map "${pack}::$_", 
        grep !/::$/,
        keys %{"${pack}::"};
    } qw(
      charstar
      version
      version::vpp
      version::vxs
      version::regex
    )
  ]);

  $comp->share_from('version', [
    '&qv'
  ]);

  # reconstruct assignment to avoid "use version" prefix

  my ($assign, $trail_re, $list) = _parse_assign($line, $sigil, $variable);

  my $assign_code;
  if (my ($assign, $trail_re, $list) = _parse_assign($line, $sigil, $variable)) {
    my $assign_to = "$sigil$variable";
    $assign_to = "($assign_to)"
      if $list;
    $assign_code = "$assign_to = $assign";
  }
  else {
    $assign_code = $line;
    $assign_code =~ s{\A (?: $IGNORABLE_PRAGMA_RE )+}{};
  }

  my $root = $comp->root;

  my $code = <<"END_CODE";
    local $sigil$variable;
    {;
        $assign_code
    }
    my \$v = \$$variable;
    bless \$v, 'FakeVersion'
      if ref \$v eq '${root}::version';
    \$v;
END_CODE
  my $result = $comp->reval($code);

  if ($@) {
    return;
  }

  if (ref $result eq 'FakeVersion') {
    bless $result, 'version';
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

The file given can be a file name, a file handle, a reference to a string of
code, or an iterator code ref.  If given a file name, it will be decoded the
same way perl itself does, handling a UTF-8 or UTF-16 BOM, or attempting to
detect UTF-16BE or UTF-16LE content.

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

=item allow_static

=item allow_static_exotic

=item stop_at_end

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

=item accept_undef

=item accept_invalid

=item line_cb


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
