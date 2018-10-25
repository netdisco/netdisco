package App::Netdisco::Web::Plugin::API::Util;
#Collection of API utilities

use Dancer ':syntax';

use base 'Exporter';
our @EXPORT = qw/parse_search_params format_data format_error/;

sub parse_search_params {
    my $params = shift;
    my $search = {};
    my $partial = $params->{partial} || 0; 
    foreach my $param (keys %{$params}) {
        if ($param ne 'return_url' and $param ne 'partial') {
            if ($partial == 1) { 
                $search->{"text(".$param.")"} = { like => '%'.$params->{$param}.'%'};
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

    header( 'Content-Type' => 'application/json');
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
    return to_json $results;
};

sub format_error {
    my $status = shift;
    my $message = shift;
    header( 'Content-Type' => 'application/json');
    status $status;
    return to_json { error => $message };
}

true;
