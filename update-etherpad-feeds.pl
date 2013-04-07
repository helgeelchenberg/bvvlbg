#!/usr/bin/env perl

# Copyright (c) 2013 Helge Eichelberg
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
# associated documentation files (the "Software"), to deal in the Software without restriction,
# including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all copies or substantial
# portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
# LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

use strict;
use warnings;
use utf8;

use HTML::Entities;
use POSIX qw( strftime );
use Data::UUID;
use local::lib;
use LWP::UserAgent;
use URI::Encode qw(uri_encode uri_decode);

# Dieses Skript hat die Aufgabe, aus der Liste der öffentlichen Pads eines
# Teamspaces (z.B. https://bvvpiratenlbg.piratenpad.de) Atom-Feeds zu
# generieren, die mit Hilfe von Plugins (z.B RSSimport 
# http://wordpress.org/extend/plugins/rss-import/) in einen Wordpress-Blog
# eingebunden werden können. Es ist vermutlich nicht empfehlenswert, die
# durch dieses Skript generierten Feeds in Feedreader einzubinden.

# Dateinamen definieren
my $html = "all-pads.html"; # Überssichtsseite aller Pads im Teamspace
my $cookies = "cookies.txt"; # Cookies für den Teamspace
my $xml = "public-pads.xml"; # Feed aller öffentlichen Pads
my $xmlf = "public-pads-fraktionssitzungen.xml"; # Feed der Fraktionssitzungen
my $xmla = "public-pads-ausschusssitzungen.xml"; # Feed der Ausschusssitzungen
my $xmli = "public-pads-initiativen.xml"; # Feed der Anträge und Anfragen
my $xmls = "public-pads-sonstiges.xml"; # alle übrigen Pads

# In der folgenden Datei stehen die Login-Daten für den Teamspace
# in der Form "email=$email&password=$password" (ohne Anführungszeichen):
my $loginfile = "/home/helge/.my.bvvpiratenlbg.piratenpad.de";

# URLs definieren
my $teampad = "https://bvvpiratenlbg.piratenpad.de";
my $padlist = $teampad . "/ep/padlist/all-pads";

# Gegebenenfalls existierende XML-Datei öffnen und Veröffentlichungsdatum der
# bereits bekannten Pads auslesen.
my %padrev0;
if(-e $xml){
	open(OXML, "< :encoding(UTF-8)", $xml);
	while(<OXML>){
		my $line = $_;
		if ($line =~ m/<link href=".*?" title="(.*?)"\/>.*?<updated>(.{20})<\/updated>/sg){
			my $id = $1;
			my $date = $2;
			$padrev0{$id} = $date;
		}
	}
	close(OXML);
}

# Login-Daten auslesen
my $login = "";
open(LOGIN, "< :encoding(UTF-8)", $loginfile) or die "cannot open < $login-file: $!";
while(<LOGIN>){
	chomp($_);
	my $line = $_;
	if($line =~ m/password/){
		$login = $line;
	}
}
close(LOGIN);

# Cookies des Piratenpads speichern
my @wget1 = ("wget",
	"--spider",
	"--keep-session-cookies",
	"--save-cookies=$cookies",
	"--no-check-certificate",
	"--quiet",
	"$teampad");
system(@wget1) == 0 or die "system(@wget1) failed: $?";

# Mithilfe der Cookies die aktuellste Padliste herunterladen
unless (-e $cookies){
	print "cannot find $cookies\n";
	exit;
}
my @wget2 = ("wget",
	"--load-cookies=$cookies",
	"--keep-session-cookies",
	"--post-data=$login",
	"--quiet",
	"--no-check-certificate",
	"--output-document=$html",
	$teampad . "/ep/account/sign-in?cont=" . uri_encode($padlist));
system(@wget2) == 0 or die "system(@wget2) failed: $?";

# heruntergeladene Padliste einlesen
open(HTML, "<", $html) or die "cannot open < $html: $!";
my $source = "";
while(<HTML>){
	my $line = $_;
	$source = $source . $line;
}
close HTML;

# die HTML-Datei und die Cookies werden nun nicht mehr gebraucht
my @rm = ("rm", $html, $cookies);
system(@rm);

# Zeilenumbrüche aus dem HTML-Quelltext entfernen
$source = join("",split("\n",$source));

# Array für die Feed-Entrys vorbereiten
my @feedentries;
$feedentries[0] = "<feed>\n";

# Padliste nach allen Pads durchsuchen, die öffentlich sind und bearbeitet
# wurden und die entsprechenden Zeilen der Tabelle weiterverarbeiten.
my $uuid;
while (($source =~ m/(<tr id="padmeta-.*?">.*?<\/tr.*?>)/sg)
        && ($1 !~ m/<td class="lastEditedDate">never<\/td>/s)){
	my $padsrc = $1;
	# Pads ignorieren, die nicht öffentlich sind.
	unless ($padsrc =~ m/public\.gif/){ $padsrc = "";}
	if($padsrc =~ m/id="padmeta-(.*?)"><.*?><a href="(.*?)">(.*?)<\/a>/){
		my $padid = $1;
		my $url = $2; # Nur ein relativer Pfad.
		my $padurl = $teampad . $url; # Jetzt ist es ein absoluter Pfad.
		my $padtitle = decode_entities($3);

		# Nun wird der Zeitpunkt der Erstellung des Pads ermittelt. Wenn dieser
		# nicht bereits in der alten XML-Datei vorhanden ist, wird dazu die
		# Seite mit der ersten Revision des entsprechenden Pads heruntergeladen.
		my $paddate;
		if(defined $padrev0{$padid}){
				$paddate = $padrev0{$padid};
		}
		else {
			my $revisionurl = $teampad . "/ep/pad/view" . $url . "/rev.0";
			my $useragent = LWP::UserAgent->new;
			$useragent->cookie_jar( {} );
			my $htmltmp = $useragent->get("$revisionurl");
			$htmltmp = $htmltmp->decoded_content;
			# Falls die Seite eine Angabe über den Erstellungszeitpunkt enthält, wird dieser genommen, ...
			if ($htmltmp =~ m/<div id="timer">.*?(\d+).*?(\d+).*?(\d+).*?(\d+.*?\d+.*?\d+).*?<\/div>/s){
				$paddate = "$3-$1-$2T$4Z";
			}
			# ... andernfalls wird ein Standard-Erstellungsdatum gesetzt.
			else {
				$paddate = "2011-10-27T17:00:00Z"; # Konstituierungsdatum der BVV ;)
			}
		}
		
		# Neue Unique ID generieren.
		$uuid = new Data::UUID->create_str();
		$uuid =~ tr/[A-Z]/[a-z]/;

		# Nun werden mit den ermittelten Angaben die Feed-Einträge formuliert...
		my $xmlentry = "<entry><title>" . $padtitle . "</title>" .
			'<link href="' . $padurl . '" title="' . $padid . '"/>' . 
			'<id>urn:uuid:' . $uuid . '</id>' . 
			'<updated>' . $paddate . '</updated><content></content></entry>';

		# ... und die Einträge werden im Array gesammelt.
		push @feedentries, $xmlentry . "\n";
	}
}
push @feedentries, "</feed>";

# Kurz durchzählen, wie viele Zeilen die XML enthalten wird.
my $entrycount = scalar(@feedentries);

# Nun werden die Einträge in die jeweiligen Feed-Dateien geschrieben.
open(NXML, "+> :encoding(UTF-8)", $xml); # Alles
open(XMLF, "+> :encoding(UTF-8)", $xmlf); # Fraktionssitzungen
open(XMLA, "+> :encoding(UTF-8)", $xmla); # Ausschussitzungen
open(XMLI, "+> :encoding(UTF-8)", $xmli); # Anträge und Anfragen
open(XMLS, "+> :encoding(UTF-8)", $xmls); # alle übrigen Pads

my $i = 0;
while($i < $entrycount){
	if($i == 0){
		my $now = strftime '%Y-%m-%dT%H:%M:%SZ', gmtime;

		$uuid = new Data::UUID->create_str();
		$uuid =~ tr/[A-Z]/[a-z]/;
		print NXML '<?xml version="1.0" encoding="utf-8"?>' . 
		'<feed xmlns="http://www.w3.org/2005/Atom">' . 
		'<title>Alle öffentlichen Etherpads der Fraktion PIRATEN Lichtenberg</title>' . 
		'<link href="https://bvvpiratenlbg.piratenpad.de/ep/padlist/all-pads"/>' . 
		'<updated>' . $now . '</updated>' . 
		'<author><name>Helge Eichelberg</name>' . 
		'<email>helge.eichelberg@fraktion-piraten-lichtenberg.de</email>' . 
		'<uri>http://fraktion-piraten-lichtenberg.de.de</uri></author>' . 
		'<id>urn:uuid:' . $uuid . '</id>' . "\n";

		$uuid = new Data::UUID->create_str();
		$uuid =~ tr/[A-Z]/[a-z]/;
		print XMLF '<?xml version="1.0" encoding="utf-8"?>' . 
		'<feed xmlns="http://www.w3.org/2005/Atom">' . 
		'<title>Alle öffentlichen Etherpads der Fraktion PIRATEN Lichtenberg ' .
		'in denen Fraktionssitzungen protokolliert wurden</title>' . 
		'<link href="https://bvvpiratenlbg.piratenpad.de/ep/padlist/all-pads"/>' . 
		'<updated>' . $now . '</updated>' . 
		'<author><name>Helge Eichelberg</name>' . 
		'<email>helge.eichelberg@fraktion-piraten-lichtenberg.de</email>' . 
		'<uri>http://fraktion-piraten-lichtenberg.de.de</uri></author>' . 
		'<id>urn:uuid:' . $uuid . '</id>' . "\n";

		$uuid = new Data::UUID->create_str();
		$uuid =~ tr/[A-Z]/[a-z]/;
		print XMLA '<?xml version="1.0" encoding="utf-8"?>' . 
		'<feed xmlns="http://www.w3.org/2005/Atom">' . 
		'<title>Alle öffentlichen Etherpads der Fraktion PIRATEN Lichtenberg ' .
		'in denen Ausschusssitzungen protokolliert wurden</title>' . 
		'<link href="https://bvvpiratenlbg.piratenpad.de/ep/padlist/all-pads"/>' . 
		'<updated>' . $now . '</updated>' . 
		'<author><name>Helge Eichelberg</name>' . 
		'<email>helge.eichelberg@fraktion-piraten-lichtenberg.de</email>' . 
		'<uri>http://fraktion-piraten-lichtenberg.de.de</uri></author>' . 
		'<id>urn:uuid:' . $uuid . '</id>' . "\n";

		$uuid = new Data::UUID->create_str();
		$uuid =~ tr/[A-Z]/[a-z]/;
		print XMLI '<?xml version="1.0" encoding="utf-8"?>' . 
		'<feed xmlns="http://www.w3.org/2005/Atom">' . 
		'<title>Alle öffentlichen Etherpads der Fraktion PIRATEN Lichtenberg ' .
		'in denen Anträge und Anfragen erarbeitet wurden</title>' . 
		'<link href="https://bvvpiratenlbg.piratenpad.de/ep/padlist/all-pads"/>' . 
		'<updated>' . $now . '</updated>' . 
		'<author><name>Helge Eichelberg</name>' . 
		'<email>helge.eichelberg@fraktion-piraten-lichtenberg.de</email>' . 
		'<uri>http://fraktion-piraten-lichtenberg.de.de</uri></author>' . 
		'<id>urn:uuid:' . $uuid . '</id>' . "\n";

		$uuid = new Data::UUID->create_str();
		$uuid =~ tr/[A-Z]/[a-z]/;
		print XMLS '<?xml version="1.0" encoding="utf-8"?>' . 
		'<feed xmlns="http://www.w3.org/2005/Atom">' . 
		'<title>Alle sonstigen öffentlichen Etherpads der Fraktion ' .
		'PIRATEN Lichtenberg</title>' . 
		'<link href="https://bvvpiratenlbg.piratenpad.de/ep/padlist/all-pads"/>' . 
		'<updated>' . $now . '</updated>' . 
		'<author><name>Helge Eichelberg</name>' . 
		'<email>helge.eichelberg@fraktion-piraten-lichtenberg.de</email>' . 
		'<uri>http://fraktion-piraten-lichtenberg.de.de</uri></author>' . 
		'<id>urn:uuid:' . $uuid . '</id>' . "\n";
	}
	else {
		print NXML $feedentries[$i];
		if($feedentries[$i] =~ m/fraktionssitzung/i){
			print XMLF $feedentries[$i];		
		}
		elsif($feedentries[$i] =~ m/(ausschuss|vorstand|aeltestenrat|ältestenrat|auschuss|aussschuss)/i){
			print XMLA $feedentries[$i];
		}
		elsif(($feedentries[$i] =~ m/(antrag|anfrage|anträge|antraege)/i) 
			&& ($feedentries[$i] !~ m/(how-to|howto)/i)){
			print XMLI $feedentries[$i];
		}
		else{
			print XMLS $feedentries[$i];
		}
		if($feedentries[$i] =~ m/\/feed/i){
			print XMLF $feedentries[$i];
			print XMLA $feedentries[$i];
			print XMLI $feedentries[$i];
		}
	}
	$i++;
}
close(NXML);
close(XMLF);
close(XMLA);
close(XMLI);
close(XMLS);

__END__
