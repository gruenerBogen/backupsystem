#!/usr/bin/perl

use strict;

sub prompt {
    my ($query) = @_;		# take a prompt string as argument
    local $| = 1;		# activate autoflush to immediately show the prompt
    print $query;
    chomp(my $answer = <STDIN>);
    return $answer;
}

sub prompt_ab {
    my ($query, $a, $b, $default) = @_;

    my $a_test = lc(substr $a, 0, 1);
    my $b_test = lc(substr $b, 0, 1);

    my $quest;
    if(defined($default)) {
	$quest = $default ? "[" . uc($a_test) . "/$b_test]" : "[$a_test/" . uc($b_test) . "]";
    }
    else {
	$quest = "[$a_test/$b_test]";
    }

    my $answer;
    while(1) {
	$answer = lc(substr prompt("$query $quest: "), 0, 1);

	if($answer eq $a_test) {
	    return 1;
	}
	elsif($answer eq $b_test) {
	    return 0;
	} 
	elsif($answer eq "" && defined($default)) {
	    return $default;
	}

	print "Please answer $a ($a_test) or $b ($b_test).\n";
    }
}

sub prompt_yn {
    my ($query, $default) = @_;

    if(defined($default)) {
	return prompt_ab($query, "yes", "no", $default);
    }
    return prompt_ab($query, "yes", "no");
}

if(@ARGV == 0) {
	print "Usage: yesNo.pl [-y|-n] Question\n";
	exit;
}

if(@ARGV == 1) {
	exit ! prompt_yn($ARGV[0]);
}

if(@ARGV == 2) {
	exit ! prompt_yn($ARGV[1], $ARGV[0] eq '-y');
}
