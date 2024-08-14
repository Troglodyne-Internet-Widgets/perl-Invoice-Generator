package Invoice::Generator;

# ABSTRACT: Library for securely generating invoices
use strict;
use warnings;

use feature qw{signatures state};
no warnings qw{experimental};

use DBI;
use DBD::SQLite;
use File::Touch;

use Invoice::Encryptor;
use Invoice::Denomination;
use Invoice::Entity;
use Invoice::Relationship;
use Invoice::Charge;
use Invoice::Payment;

=head1 DESCRIPTION

Generates persistent, secure invoices via a local sqlite db and RSA encryption.

Supports multiple clients in the same invoice, late fee schedules, and currency conversions.

Also supports intake of payments and application to any outstanding charges, even to other clients.

=head1 SYNOPSIS

	# To handle your various denomination conversion needs, you'll need to setup a quoter
	use Finance::Quote;
	my $quote = Finance::Quote->new(...);

	# You need to craft a suitable invoice template.
	my $template = <DATA>;
	my $gen = Invoice::Generator->new(
		template => $template,
		# If all txn are in the same denomination, this may be omitted.
		quoter => $quote,
		# It is your responsibility to prompt for this in your application.
		# This will decrypt the PII / Sensitive information stored in DB.
		passphrase => ...,
	);

	# The address and identification hashes can be essentially anything you want, adjust the template
	# The name is basically just shortand for forms to select on
	my $entity = $gen->add_entity(
		name => "My LLC",
		# Both of these are PII, and encrypted in DB
		address => { street_address => "362 Wharf Avenue", "state" => "NJ", zip_code => 66666 },
		identification => { tin => 'abc-123-456', actual_name => "Joe Bob's plumbing" },
	);

	# You need at least one payee and payor to build an invoice.
	my $client = $gen->add_entity(
		name => "Not My LLC",
		address => { street_address => "8888 Yee Haw", "state" => "TX", zip_code => 77777 },
		identification => { tin => 'eee-000-000' },
	);

	# Get list of entities, optionally with a filter
	my @entities = $gen->entities( regexp => 'LLC' );

	# A reasonably unique description will prevent harmful things like double-submits of carts.
	my $relationship = $gen->new_relationship(
		description => "Payments from Not My LLC to My LLC since 9/9/99",
		payee => $entity,
		payor => $client,
	);
	my $relationships = $gen->relationships( regexp => 'My LLC' );

	# Figure out the units of account involved
	my $gold = $gen->denomination(
		description => 'Ounce of Gold',
		code   => 'AU',
		symbol => 'OzAu',
	);
	my $silver = $gen->denomination(
		description => 'Ounce of Silver',
		code   => 'AG',
		symbol => 'OzAg',
	);

	# Add some means by which payments can be made for the given entities
	my $e_acct = $entity->add_account(
		denomination => $gold,
		# PII, encrypted in DB
		counterparty_info => { 'type' => 'merchant account', counterparty => 'SUS payment processor, LLC', 'num' => '328y94234830sszz' },
	);
	my $c_acct = $client->add_account(
		denomination => $silver;
		counterparty_info => { 'type' => 'cc', counterparty => 'Visa', 'num' => '1234-5678-1234-5678' },
	);

	# Add a late fee / interest schedule
	my $fee_schedule = $gen->fee_schedule(
		interest_rate => '.01',
		compounding_period => ( 60 * 60 * 24 * 30 ),
	);

	# Charge them up.  Description should be unique enough to prevent double charges.
	my $charge = $relationship->add_charge(
		description => "Gave client a Hug",
		payload => { sku => 'big-hug', amt => 1 },
		amount => 100.00,
		denomination => $gold,
		due_date => time() + ( 60 * 60 * 24 * 30 ),
		fee_schedule => $fee_schedule,
	);
	# If the charge was in error...
	$charge->active(0) if $charge->active();
	# But maybe not
	$charge->active(1);
	# See the other charges, say related to a particular booking.
	my @charges = $relationship->charges( regexp => 'b_id=abx77tyvz2' );

	# Get paid at some point later
	my $pmt = $client->pay(
		description => "Payment from Not My LLC for big hugs on 9/9/99",
		amount => 1000.00,
		# Denomination is implied by the from_account
		from_account => $c_acct,
		to_acct => $e_acct,
		# You are expected to handle the actual 'hard' part of reaching out and touching your payment processor, updating your inventory etc
		hook_before => \&do_charge(),
		hook_after  => \&ship_items_if_charges_sated(),
		# Which charges ought the payment apply to, applied either LIFO/FIFO.
		# This allows us to pay other invoices' charges to other entities, which is common
		to_charges => [$relationship->charges()],
		# Apply to said charges in what order
		apply_order => 'LIFO',
	);
	sub do_charge { ... }
	sub ship_items_if_charges_sated { ... }

	# See other payments & get status
	my @payments  = $client->payments();
	my $remaining = $relationship->outstanding();

	# Agglomerate multiple
	my $other_relationship = ...;
	my $composite_remaining = $gen->outstanding($relationship->charges(), $other_relationship->charges());

	# Actually spit out the invoice based on our template
	$gen->generate($relationship->charges(), $other_relationship->charges());

=head1 CONSTRUCTOR

=head2 new

=cut

sub new (%options) {

}

=head1 METHODS

=head2 generate(@charges)

=cut

sub generate (@charges) {

}

sub add_entity (%options) {

}

sub entities (%options) {

}

sub add_relationship (%options) {

}

sub relationships (%options) {

}

sub denomination (%options) {

}

#convenience methods

sub outstanding (@charges) {

}

sub writeoff (@charges) {

}

sub archive (@charges) {

}

my $dbh = {};

sub _dbh {
    my ($self) = @_;
    my $dbname = $self->{dbname};
    return $dbh->{$dbname} if exists $dbh->{$dbname};

    # Some systems splash down without this.  YMMV.
    File::Touch::touch($dbname) if $dbname ne ':memory:' && !-f $dbname;

	local $/='';
	my $SCHEMA=<DATA>;

    my $db = DBI->connect( "dbi:SQLite:dbname=$dbname", "", "" );
    $db->{sqlite_allow_multiple_statements} = 1;
    $db->do($SCHEMA) or die "Could not ensure database consistency: " . $db->errstr;
    $db->{sqlite_allow_multiple_statements} = 0;
    $dbh->{$dbname} = $db;

    # Turn on fkeys
    $db->do("PRAGMA foreign_keys = ON") or die "Could not enable foreign keys";

    # Turn on WALmode, performance
    $db->do("PRAGMA journal_mode = WAL") or die "Could not enable WAL mode";

    return $db;
}

1;

__DATA__

-- A party which will either send or recieve a charge.
CREATE TABLE IF NOT EXISTS entity (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	name TEXT NOT NULL UNIQUE,
	address TEXT NOT NULL,
	identification TEXT DEFAULT NULL
);

CREATE TABLE IF NOT EXISTS denomination (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	description TEXT NOT NULL,
	code TEXT NOT NULL,
	symbol TEXT NOT NULL
);

-- How much is the given currency worth in relation to a given unit of account?  Ought to be updated frequently by a cron.
CREATE TABLE IF NOT EXISTS conversion_rate (
	unit_of_account INTEGER NOT NULL REFERENCES(denomination.id),
	denomination_id INTEGER NOT NULL REFERENCES(denomination.id),
	basis INTEGER DEFAULT 1000
);

-- A means by which a charge is paid.  counterparty_info will store various information about the counterparty, e.g. cc_type, num, check_num, routing no etc.
CREATE TABLE IF NOT EXISTS account (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	entity_id INTEGER NOT NULL REFERENCES(entity.id) ON DELETE CASCADE,
	denomination_id INTEGER NOT NULL REFERENCES(denomination.id) ON DELETE RESTRICT,
	counterparty_info TEXT NOT NULL
);

-- relationships are sets of charges.  The UUID is to prevent things like double-submits.
CREATE TABLE IF NOT EXISTS relation (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	description TEXT NOT NULL UNIQUE,
	payee INTEGER NOT NULL REFERENCES(entity.id) ON DELETE CASCADE,
	payor INTEGER NOT NULL REFERENCES(entity.id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS fee_schedule (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	compounding_period INTEGER NOT NULL,
	interest_rate INTEGER NOT NULL
);

-- A charge is an amount in a denomination which is due on a particular date,
-- which will accrue interest past the provided fee schedule if it exists.
-- The payload is JSON, which will contain product or service information relevant to the charge.
CREATE TABLE IF NOT EXISTS charge (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	relation_id INTEGER NOT NULL REFERENCES(relation.id) ON DELETE CASCADE,
	denomination_id INTEGER NOT NULL REFERENCES(denomination.id),
	description TEXT NOT NULL UNIQUE,
	payload JSON NOT NULL,
	amount INTEGER NOT NULL,
	due_date INTEGER NOT NULL DEFAULT current_timestamp,
	fee_schedule_id INTEGER REFERENCES(fee_schedule.id),
	active INTEGER NOT NULL DEFAULT 1
);

-- Payments don't necessarily apply to any given relationship, and may satisfy multiple charges.
-- They should be applied on a FIFO or LIFO basis to outstanding charges.
-- payments from/to the same account are for writeoffs of uncollectable charges.
CREATE TABLE IF NOT EXISTS payment (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	from_account_id INTEGER NOT NULL REFERENCES(account.id) ON DELETE CASCADE,
	to_account_id INTEGER NOT NULL REFERENCES(account.id) ON DELETE CASCADE,
	description TEXT NOT NULL UNIQUE,
	date INTEGER NOT NULL,
	amount INTEGER NOT NULL,
	active INTEGER NOT NULL DEFAULT 1
);

-- Scan this table to see if charges have been satisfied by any payments
-- This also allows entities to pay charges owed by other entities, which is a common occurrence
CREATE TABLE IF NOT EXISTS payment_application (
	charge_id INTEGER NOT NULL REFERENCES(charge.id) ON DELETE CASCADE,
	payment_id INTEGER NOT NULL REFERENCES(payment.id) ON DELETE CASCADE,
	amount INTEGER NOT NULL,
	date INTEGER NOT NULL,
	active INTEGER NOT NULL DEFAULT 1
);


