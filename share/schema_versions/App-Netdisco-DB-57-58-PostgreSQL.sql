BEGIN;

alter table device_port_wireless alter column ip set not null;
alter table device_port_wireless alter column port set not null;
alter table device_port_wireless add constraint device_port_wireless_pkey primary key (ip, port);

alter table device_port_ssid alter column ip set not null;
alter table device_port_ssid alter column port set not null;
alter table device_port_ssid alter column bssid set not null;
alter table device_port_ssid add constraint device_port_ssid_pkey primary key (ip, bssid, port);



COMMIT;
