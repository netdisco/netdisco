package App::Netdisco::Web::ManagedConfig;

use Dancer ':syntax';

use App::Netdisco::Util::ManagedConfig qw(load_managed_config tenant_key);

# /t/<tenant>/ sets `var tenant` and then forwards. `vars` survives a forward
# but the `before` hooks run again, so the first pass applies the default
# tenant and the forwarded pass applies the tenant. The marker records which
# tenant this request has already applied, so a pass with nothing new to apply
# does no work at all.
hook 'before' => sub {
  return if (vars->{'managed_config_tenant'} || '') eq tenant_key();
  load_managed_config();
  var managed_config_tenant => tenant_key();
};

true;
