#!/usr/bin/env perl
# Copyright 2014 Michal Špaček <tupinek@gmail.com>

# Pragmas.
use strict;
use warnings;

# Modules.
use Database::DumpTruck;
use Encode qw(decode_utf8 encode_utf8);
use English;
use HTML::TreeBuilder;
use LWP::UserAgent;

# Don't buffer.
$OUTPUT_AUTOFLUSH = 1;

# URL of service.
my $URL = 'http://www.brno.cz/sprava-mesta/dokumenty-mesta/vyhlasky-narizeni-a-opatreni-obecne-povahy/';

# Type of document.
my $TYPE_OF_DOC_HR = {
	'1' => decode_utf8('Vyhlášky'),
	'2' => decode_utf8('Zápisy ze schůzí RMB'),
	'3' => decode_utf8('Zápisy ze zasedání ZMB'),
	'4' => decode_utf8('Nařízení'),
	'10' => decode_utf8('Metodiky'),
	'14' => decode_utf8('Opatření obecné povahy'),
};

# Open a database handle.
my $dt = Database::DumpTruck->new({
	'dbname' => 'data.sqlite',
	'table' => 'data',
});

# Create a user agent object.
my $ua = LWP::UserAgent->new;

# Get page.
foreach my $type_of_doc (keys %{$TYPE_OF_DOC_HR}) {
	my $root = post($type_of_doc);
	my @telo_table = $root->find_by_attribute('id', 'telo')->find_by_tag_name('table');
	my $num = 0;
	foreach my $tr ($telo_table[3]->find_by_tag_name('tr')) {
		if ($num == 0) {
			$num = 1;
			next;
		}
		my @td = $tr->find_by_tag_name('td');
		process_and_insert($type_of_doc, @td);
	}
}

# Insert to db.
sub process_and_insert {
	my ($type_of_doc, @td) = @_;
	my ($name, $link, $date_from, $date_to, $desc);
	my $active = 1;
	if ($type_of_doc == 1 || $type_of_doc == 4 || $type_of_doc == 14) {
		$name = $td[0]->as_text;
		$link = $td[0]->find_by_tag_name('a')->attr('href');
		$desc = $td[1]->as_text;
		$date_from = $td[2]->as_text;
		$date_to = $td[3]->as_text;
		if ($date_to) {
			$active = 0;
		}
	} elsif ($type_of_doc == 2 || $type_of_doc == 3 || $type_of_doc == 10) {
		$name = $td[0]->as_text;
		$link = $td[0]->find_by_tag_name('a')->attr('href');
		$date_from = $td[1]->as_text;
		if ($td[1]->attr('class') eq 'textseznamred') {
			$active = 0;
		}
	} else {
		die 'No supported.';
	}
	if ($active != 0) {
		$active = 1;
	}
	$dt->insert({
		'Typ_dokumentu' => $TYPE_OF_DOC_HR->{$type_of_doc},
		'Jmeno' => $name,
		'Link' => $link,
		'Platnost' => $active,
		'Platnost_od' => $date_from,
		'Platnost_do' => $date_to,
		'Popis' => $desc,
	});
}

# Insert data for date.
sub post {
	my $doc_type = shift;
	my $post = $ua->post($URL, {
		'dokument' => $doc_type,
		'rok' => 'vse',
		'platnost' => 'vse',
	});
	if ($post->is_success) {
		my $tree = HTML::TreeBuilder->new;
		$tree->parse(decode_utf8($post->content));
		return $tree->elementify;
	} else {
		die "Cannot POST page.";
	}
}
