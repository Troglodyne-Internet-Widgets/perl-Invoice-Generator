package Invoice::Encryptor;

# ABSTRACT: Manage SSH keys used to encrypt/decrypt values put into the invoice DB
use strict;
use warnings;

use feature qw{signatures state};
no warnings qw{experimental};

use File::Which;
use File::Path qw{make_path};
use Capture::Tiny qw{capture_merged};
use Crypt::PK::RSA;

my $path = "$ENV{HOME}/.invoice/keys";

sub build_key ($passphrase, $bits=2048, $file='invoice_key') {

	return "$path/$file" if -f "$path/$file";

	make_path($path) unless -d $path;
	chmod 0600 $path;

 	state $SSH_KEYGEN = which('ssh-keygen');
	die "cannot locate ssh-keygen!" unless $SSH_KEYGEN;
	my $keygen_cmd = "$SSH_KEYGEN -P $passphrase -t rsa -b $bits -f $path/$file";
	 
	my $code = 255;
	my $out = capture_merged { $code = system($keygen_cmd;) };
	$code = $code >> 8;
	 
	if (($code != 0) && ($code != 1)) {
	  die "Error: ssh-keygen command has exited with value $code\n$out";
	}
	chmod 0600 "$path/file";
	return "$path/$file";
}

sub encrypt ($data, $passphrase, $file='invoice_key') {
	my $pk = _pk($file, $passphrase);
	return $pk->encrypt($data);
}

sub decrypt ($data, $passphrase, $file='invoice_key') {
	my $pk = _pk($file, $passphrase);
	return $pk->decrypt($data);
}

sub _pk ($file, $pass) {
	die "run build_key first" unless -f "$path/$file";
	my $pk = Crypt::PK::RSA->new();
	$pk->import_key("$path/$file", $passphrase);
}

1;
