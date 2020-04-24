use strict;
use warnings;
use Test::More;

use List::Util qw(sum);
use ExtUtils::MakeMaker;
use ExtUtils::ParseVersion qw(parse_version);
use version ();

my $to_eval;
{
  no warnings 'redefine';
  my $get_version = \&ExtUtils::MM_Unix::get_version;
  *ExtUtils::MM_Unix::get_version = sub {
    $to_eval = $_;
    goto &$get_version;
  };
}

sub pv_to_eumm {
  my ($v) = @_;
  return 'undef'
    if !defined $v;
  if ( $v !~ /^v?[\d_\.]+$/ ) {
    require version;
    no warnings;
    my $normal = eval { version->new( $v ) };
    return $normal->stringify
      if defined $normal;
  }
  return $v;
}

if (1) {
}

my %seen = map +($_ => 1), qw(
);
my %bad;
my $total = 0;
open my $fh, '<', 't/weird-versions.dat' or die $!;
while (my $line = <$fh>) {
  $total++;
  chomp $line;
  my ($file, $statement) = split /:/, $line, 2;
  next if $seen{$file}++;
  my $eumm = do {
    local $@;
    local $SIG{__WARN__} = sub {};
    my $v = MM->parse_version(\"$statement\n");
    next if $@;
    $v;
  };
  die "bad data: $line"
    if !defined $statement;

  my ($package, $parse_version) = parse_version(\"$statement\n", allow_eval => 0, allow_safe => 0);

  $parse_version = pv_to_eumm($parse_version);

  if ("$parse_version" ne "undef") {
    if ("$parse_version" ne "$eumm") {
      use version;
      my $v = version->parse($parse_version);
      warn $v;
      use Data::Dumper;
      local $Data::Dumper::Terse = 1;
      diag "$file:  $statement";
      diag "$parse_version vs $eumm";
      diag "what the fuck :(  " . Dumper($eumm);
      exit;
    }
  }
  if ("$parse_version" ne "$eumm") {
    $statement =~ s/[0-9]+(?:\.[0-9]+)*/999999999/g;
    $statement =~ s/\$(\w+(?:::|'))*VERSION\b/\$VERSION/;
    $bad{$statement}++;
  }
}
for my $statement (sort { $bad{$a} <=> $bad{$b} } keys %bad) {
  print "$bad{$statement}    $statement\n";
}

print "bad: " . sum(values %bad) . "/$total\n";

ok 1;

done_testing;
