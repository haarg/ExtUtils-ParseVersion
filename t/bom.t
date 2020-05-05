use strict;
use warnings;

use Test::More;
use ExtUtils::ParseVersion qw(parse_version);

for my $file (qw(utf-8-bom utf-16be utf-16be-bom utf-16le utf-16le-bom)) {
  my $name = uc $file;
  my $bom = $name =~ s/-BOM\z//;
  $name .= ' ' . ($bom ? 'with' : 'without') . ' BOM';

  my ($p, $v) = parse_version("t/corpus/$file.pm");

  is $v, '1.003', $name;
}

done_testing;
