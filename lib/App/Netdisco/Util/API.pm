package App::Netdisco::Util::API;

use Dancer ':syntax';

use base 'Exporter';
our @EXPORT = qw/
  parse_search_params
  format_data
  format_error
/;

sub parse_search_params {
    my $params = shift;
    my $search = {};
    my $partial = $params->{partial} || false;

    foreach my $param (keys %{$params}) {
        if ($param ne 'return_url' and $param ne 'partial') {
            if ($partial eq 'true') {
                $search->{"text(".$param.")"} = { -ilike => '%'.$params->{$param}.'%'};
            }
            else {
                $search->{$param} = $params->{$param};
            }
        }
    }

    return $search;
}

sub format_data {
    my $items = shift;
    my $results = {};

    if (ref($items) =~ m/ResultSet/) {
        my @hashes;

        foreach my $item ($items->all) {
            my $c = {};
            my $columns = $item->{_column_data};

            foreach my $col (keys %{$columns}) {
                $c->{$col} = $columns->{$col};
            }

            push @hashes, $c;
        }

        $results->{data} = \@hashes;
    }
    elsif (ref($items) =~ m/Result/) {
        $results->{data} = $items->{_column_data};
    }
    else {
        $results->{data} = $items;
    }

    header('Content-Type' => 'application/json');
    return to_json $results;
};

sub format_error {
    my $status = shift;
    my $message = shift;

    status $status;
    header('Content-Type' => 'application/json');
    return to_json { error => $message };
}

true;
