#!perl

use strict;
use warnings;
use Test::More;

use Test::More tests => 2;
use Alien::Tidyp;
use File::Temp qw(tempdir tempfile);
use ExtUtils::CBuilder;

my $cb = ExtUtils::CBuilder->new(quiet => 0);

my $dir = tempdir( CLEANUP => 1 );
my ($fs, $src) = tempfile( DIR => $dir, SUFFIX => '.c' );
syswrite($fs, <<MARKER); # write test source code
#include <tidyp.h>
int func() { tidyVersion(); return 0; }

MARKER
close($fs);

my $i = Alien::Tidyp->config('INC');
my $l = Alien::Tidyp->config('LIBS');

open(my $olderr, '>&', STDERR);
open(STDERR, '>', "output.stderr.txt");

my $obj = $cb->compile( source => $src, extra_compiler_flags => $i );
isnt( $obj, undef, 'Testing compilation' );

my $lib = $cb->link( objects => $obj, extra_linker_flags => $l, module_name => 'test' );
isnt( $lib, undef, 'Testing linking' );

open(STDERR, '>&', $olderr);
diag "STDERR from compile/link was rediercted to output.stderr.txt";
