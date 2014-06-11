package App::Netdisco::DB::ResultSet;

use strict;
use warnings;

use base 'DBIx::Class::ResultSet';

__PACKAGE__->load_components(
    qw{Helper::ResultSet::SetOperations Helper::ResultSet::Shortcut});

=head1 ADDITIONAL METHODS

=head2 get_distinct_col( $column )

Returns an asciibetical sorted list of the distinct values in the given column
of the Device table. This is useful for web forms when you want to provide a
drop-down list of possible options.

=cut

sub get_distinct_col {
    my ( $rs, $col ) = @_;
    return $rs unless $col;

    return $rs->search(
        {},
        {   columns  => [$col],
            order_by => $col,
            distinct => 1
        }
    )->get_column($col)->all;
}

=head2 get_datatables_data( $params )

Returns a ResultSet for DataTables Server-side processing which populates
the displayed table.  Evaluates the supplied query parameters for filtering,
paging, and ordering information.  Note: query paramters are expected to be
passed as a reference to an expanded hash of hashes.

Filtering if present, will generate simple LIKE matching conditions for each
searchable column (searchability indicated by query parameters) after each
column is casted to text.  Conditions are combined as disjunction (OR).
Note: this does not match the built-in DataTables filtering which does it
word by word on any field. 

=cut

sub get_datatables_data {
    my $rs     = shift;
    my $params = shift;
    my $attrs  = shift;

    die "condition parameter to search_by_field must be hashref\n"
        if ref {} ne ref $params
            or 0 == scalar keys %$params;

    # -- Paging
    $rs = $rs->_with_datatables_paging($params);

    # -- Ordering
    $rs = $rs->_with_datatables_order_clause($params);

    # -- Filtering
    $rs = $rs->_with_datatables_where_clause($params);

    return $rs;
}

=head2 get_datatables_filtered_count( $params )

Returns the total records, after filtering (i.e. the total number of
records after filtering has been applied - not just the number of records
being returned for this page of data) for a datatables ResultSet and
query parameters.  Note: query paramters are expected to be passed as a
reference to an expanded hash of hashes.

=cut

sub get_datatables_filtered_count {
    my $rs     = shift;
    my $params = shift;

    return $rs->_with_datatables_where_clause($params)->count;

}

sub _with_datatables_order_clause {
    my $rs     = shift;
    my $params = shift;
    my $attrs  = shift;

    my @order = ();

    if ( defined $params->{'order'}{0} ) {
        for ( my $i = 0; $i < (scalar keys %{$params->{'order'}}); $i++ ) {

           # build direction, must be '-asc' or '-desc' (cf. SQL::Abstract)
           # we only get 'asc' or 'desc', so they have to be prefixed with '-'
            my $direction = '-' . $params->{'order'}{$i}{'dir'};

            # We only get the column index (starting from 0), so we have to
            # translate the index into a column name.
            my $column_name = _datatables_index_to_column( $params,
                $params->{'order'}{$i}{'column'} );

            # Prefix with table alias if no prefix
            my $csa = $rs->current_source_alias;
            $column_name =~ s/^(\w+)$/$csa\.$1/x;
            push @order, { $direction => $column_name };
        }
    }

    $rs = $rs->order_by( \@order );
    return $rs;
}

# NOTE this does not match the built-in DataTables filtering which does it
# word by word on any field.
#
# General filtering using LIKE, this will not be efficient as is will not
# be able to use indexes.

sub _with_datatables_where_clause {
    my $rs     = shift;
    my $params = shift;
    my $attrs  = shift;

    my %where = ();

    if ( defined $params->{'search'}{'value'}
        && $params->{'search'}{'value'} )
    {
        my $search_string = $params->{'search'}{'value'};
        for ( my $i = 0; $i < (scalar keys %{$params->{'columns'}}); $i++ ) {

           # Iterate over each column and check if it is searchable.
           # If so, add a constraint to the where clause restricting the given
           # column. In the query, the column is identified by it's index, we
           # need to translate the index to the column name.
            if (    $params->{'columns'}{$i}{'searchable'}
                and $params->{'columns'}{$i}{'searchable'} eq 'true' )
            {
                my $column = _datatables_index_to_column( $params, $i );
                my $csa = $rs->current_source_alias;
                $column =~ s/^(\w+)$/$csa\.$1/x;

                # Cast everything to text for LIKE search
                $column = $column . '::text';
                push @{ $where{'-or'} },
                    { $column => { -like => '%' . $search_string . '%' } };
            }
        }
    }

    $rs = $rs->search( \%where, $attrs );
    return $rs;
}

sub _with_datatables_paging {
    my $rs     = shift;
    my $params = shift;
    my $attrs  = shift;

    my $limit = $params->{'length'};

    my $offset = 0;
    if ( defined $params->{'start'} && $params->{'start'} ) {
        $offset = $params->{'start'};
    }
    $attrs->{'offset'} = $offset;

    $rs = $rs->search( {}, $attrs );
    $rs = $rs->limit($limit);

    return $rs;
}

# Use the DataTables columns.data definition to derive the column
# name from the index.

sub _datatables_index_to_column {
    my $params = shift;
    my $i      = shift;

    my $field;

    if ( !defined($i) ) {
        $i = 0;
    }
    $field = $params->{'columns'}{$i}{'data'};
    return $field;
}

1;
