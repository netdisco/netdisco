package App::Netdisco::Web::ManagedConfig;

use Dancer ':syntax';

use App::Netdisco::Util::ManagedConfig 'load_managed_config';

# /t/<tenant>/ sets `var tenant` and then forwards, and the `before` hooks run
# again: the first pass applies the default tenant and the forwarded pass
# applies the tenant. A pass whose counter has not moved reads only the
# counter; the overlay comes from the cache.
hook 'before' => sub { load_managed_config() };

true;
