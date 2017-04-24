BEGIN;

-- admin table - Queue for admin tasks sent from front-end for back-end processing.

CREATE TABLE admin (
    job         serial,
    entered     TIMESTAMP DEFAULT now(),
    started     TIMESTAMP,
    finished    TIMESTAMP,
    device      inet,
    port        text,
    action      text,
    subaction   text,
    status      text,
    username    text,
    userip      inet,
    log         text,
    debug       boolean
                   );

CREATE INDEX idx_admin_entered ON admin(entered);
CREATE INDEX idx_admin_status  ON admin(status);
CREATE INDEX idx_admin_action  ON admin(action);

CREATE TABLE device (
    ip           inet PRIMARY KEY,
    creation     TIMESTAMP DEFAULT now(),
    dns          text,
    description  text,
    uptime       bigint,
    contact      text,
    name         text,
    location     text,
    layers       varchar(8),
    ports        integer,
    mac          macaddr,
    serial       text,
    model        text,
    ps1_type     text,
    ps2_type     text,
    ps1_status   text,
    ps2_status   text,
    fan          text,
    slots        integer,
    vendor       text,      
    os           text,
    os_ver       text,
    log          text,
    snmp_ver     integer,
    snmp_comm    text,
    snmp_class   text,
    vtp_domain   text,
    last_discover TIMESTAMP,
    last_macsuck  TIMESTAMP,
    last_arpnip   TIMESTAMP
);

-- Indexing for speed-ups
CREATE INDEX idx_device_dns    ON device(dns);
CREATE INDEX idx_device_layers ON device(layers);
CREATE INDEX idx_device_vendor ON device(vendor);
CREATE INDEX idx_device_model  ON device(model);

CREATE TABLE device_ip (
    ip          inet,
    alias       inet,
    subnet      cidr,
    port        text,
    dns         text,
    creation    TIMESTAMP DEFAULT now(),
    PRIMARY KEY(ip,alias)
);

-- Indexing for speed ups
CREATE INDEX idx_device_ip_ip      ON device_ip(ip);
CREATE INDEX idx_device_ip_alias   ON device_ip(alias);
CREATE INDEX idx_device_ip_ip_port ON device_ip(ip,port);

CREATE TABLE device_module (
    ip            inet not null,
    index         integer,
    description   text,
    type          text,
    parent        integer,
    name          text,
    class         text,
    pos           integer,
    hw_ver        text,
    fw_ver        text,
    sw_ver        text,
    serial        text,
    model         text,
    fru           boolean,
    creation      TIMESTAMP DEFAULT now(),
    last_discover TIMESTAMP,
    PRIMARY KEY(ip,index)
    );

CREATE TABLE device_port (
    ip          inet,
    port        text,
    creation    TIMESTAMP DEFAULT now(),
    descr       text,
    up          text,
    up_admin    text,
    type        text,
    duplex      text,
    duplex_admin text,
    speed       text, 
    name        text,
    mac         macaddr,
    mtu         integer,
    stp         text,
    remote_ip   inet,
    remote_port text,
    remote_type text,
    remote_id   text,
    vlan        text,
    pvid        integer,
    lastchange  bigint,
    PRIMARY KEY(port,ip) 
);

CREATE INDEX idx_device_port_ip ON device_port(ip);
CREATE INDEX idx_device_port_remote_ip ON device_port(remote_ip);
-- For the duplex mismatch finder :
CREATE INDEX idx_device_port_ip_port_duplex ON device_port(ip,port,duplex);
CREATE INDEX idx_device_port_ip_up_admin ON device_port(ip,up_admin);
CREATE INDEX idx_device_port_mac ON device_port(mac);

CREATE TABLE device_port_log (
    id          serial, 
    ip          inet,
    port        text,
    reason      text,
    log         text, 
    username    text,
    userip      inet,
    action      text,
    creation    TIMESTAMP DEFAULT now()
                             );

CREATE INDEX idx_device_port_log_1 ON device_port_log(ip,port);
CREATE INDEX idx_device_port_log_user ON device_port_log(username);

CREATE TABLE device_port_power (
    ip          inet,
    port        text,
    module      integer,
    admin       text,
    status      text,
    class       text,
    power       integer,
    PRIMARY KEY(port,ip)
);

CREATE TABLE device_port_ssid (
    ip          inet,
    port        text,
    ssid        text,
    broadcast   boolean,
    bssid       macaddr
);

CREATE INDEX idx_device_port_ssid_ip_port ON device_port_ssid(ip,port);

CREATE TABLE device_port_vlan (
    ip          inet,
    port        text,
    vlan        integer,
    native      boolean not null default false,
    creation    TIMESTAMP DEFAULT now(),
    last_discover TIMESTAMP DEFAULT now(),
    vlantype    text,
    PRIMARY KEY(ip,port,vlan)
);

CREATE TABLE device_port_wireless (
    ip          inet,
    port        text,
    channel     integer,
    power       integer
);

CREATE INDEX idx_device_port_wireless_ip_port ON device_port_wireless(ip,port);

CREATE TABLE device_power (
    ip          inet,
    module      integer,
    power       integer,
    status      text,
    PRIMARY KEY(ip,module)
);

CREATE TABLE device_vlan (
    ip          inet,
    vlan        integer,
    description text,
    creation    TIMESTAMP DEFAULT now(),
    last_discover TIMESTAMP DEFAULT now(),
    PRIMARY KEY(ip,vlan)
);


CREATE TABLE log (
    id          serial,
    creation    TIMESTAMP DEFAULT now(),
    class       text,
    entry       text,
    logfile     text
);

CREATE TABLE node (
    mac         macaddr,
    switch      inet,
    port        text,
    vlan        text default '0',
    active      boolean,
    oui         varchar(8),
    time_first  timestamp default now(),
    time_recent timestamp default now(),
    time_last   timestamp default now(),
    PRIMARY KEY(mac,switch,port,vlan) 
);

-- Indexes speed things up a LOT
CREATE INDEX idx_node_switch_port_active ON node(switch,port,active);
CREATE INDEX idx_node_switch_port ON node(switch,port);
CREATE INDEX idx_node_switch      ON node(switch);
CREATE INDEX idx_node_mac         ON node(mac);
CREATE INDEX idx_node_mac_active  ON node(mac,active);
-- CREATE INDEX idx_node_oui         ON node(oui);

CREATE TABLE node_ip (
    mac         macaddr,
    ip          inet,
    active      boolean,
    time_first  timestamp default now(),
    time_last   timestamp default now(),
    PRIMARY KEY(mac,ip)
);

-- Indexing speed ups.
CREATE INDEX idx_node_ip_ip          ON node_ip(ip);
CREATE INDEX idx_node_ip_ip_active   ON node_ip(ip,active);
CREATE INDEX idx_node_ip_mac         ON node_ip(mac);
CREATE INDEX idx_node_ip_mac_active  ON node_ip(mac,active);

CREATE TABLE node_monitor (
    mac         macaddr,
    active      boolean,
    why         text,
    cc          text,
    date        TIMESTAMP DEFAULT now(),
    PRIMARY KEY(mac)
);

-- node_nbt - Hold Netbios information for each node.

CREATE TABLE node_nbt (
    mac         macaddr PRIMARY KEY,
    ip          inet,
    nbname      text,
    domain      text,
    server      boolean,
    nbuser      text,
    active      boolean,
    time_first  timestamp default now(),
    time_last   timestamp default now()
);

-- Indexing speed ups.
CREATE INDEX idx_node_nbt_mac         ON node_nbt(mac);
CREATE INDEX idx_node_nbt_nbname      ON node_nbt(nbname);
CREATE INDEX idx_node_nbt_domain      ON node_nbt(domain);
CREATE INDEX idx_node_nbt_mac_active  ON node_nbt(mac,active);

-- Add "vlan" column to node table
-- ALTER TABLE node ADD COLUMN vlan text default '0';

alter table node drop constraint node_pkey;
alter table node add primary key (mac, switch, port, vlan);

CREATE TABLE node_wireless (
    mac         macaddr,
    ssid        text default '',
    uptime      integer,
    maxrate     integer,
    txrate      integer,
    sigstrength integer,
    sigqual     integer,
    rxpkt       integer,
    txpkt       integer,
    rxbyte      bigint,
    txbyte      bigint,
    time_last   timestamp default now(),
    PRIMARY KEY(mac,ssid)
);


-- Add "ssid" column to node_wireless table
-- ALTER TABLE node_wireless ADD ssid text default '';

alter table node_wireless drop constraint node_wireless_pkey;
alter table node_wireless add primary key (mac, ssid);



CREATE TABLE oui (
    oui         varchar(8) PRIMARY KEY,
    company     text
);


-- process table - Queue to coordinate between processes in multi-process mode.

CREATE TABLE process (
    controller  integer not null,
    device      inet not null,
    action      text not null,
    status      text,
    count       integer,
    creation    TIMESTAMP DEFAULT now()
    );

CREATE TABLE sessions (
    id          char(32) NOT NULL PRIMARY KEY,
    creation    TIMESTAMP DEFAULT now(),
    a_session   text
                       );

CREATE TABLE subnets (
    net cidr NOT NULL,
    creation timestamp default now(),
    last_discover timestamp default now(),
    PRIMARY KEY(net)
);

-- Add "topology" table to augment manual topo file
CREATE TABLE topology (
    dev1   inet not null,
    port1  text not null,
    dev2   inet not null,
    port2  text not null
);



-- This table logs login and logout / change requests for users

CREATE TABLE user_log (
    entry           serial,
    username        varchar(50),
    userip          inet,
    event           text,
    details         text,
    creation        TIMESTAMP DEFAULT now()
                      );

CREATE TABLE users (
    username        varchar(50) PRIMARY KEY,
    password        text,
    creation        TIMESTAMP DEFAULT now(),
    last_on         TIMESTAMP,
    port_control    boolean DEFAULT false,
    ldap            boolean DEFAULT false,
    admin           boolean DEFAULT false,
    fullname        text,
    note            text
                    );

COMMIT;
