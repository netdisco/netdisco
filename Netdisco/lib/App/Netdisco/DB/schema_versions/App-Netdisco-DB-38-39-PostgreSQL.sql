-- clean up node table where vlan = 0 and vlan = <another number>
-- 
-- DELETE n1.*
--   FROM node n1 INNER JOIN
--     (SELECT mac, switch, port from node
--       GROUP BY mac, switch, port
--       HAVING count(*) > 1) n2
--     ON n1.mac = n2.mac
--       AND n1.switch = n2.switch
--       AND n1.port = n2.port
--       AND n1.vlan = '0';

BEGIN;

DELETE n1.* FROM node n1 INNER JOIN (SELECT mac, switch, port from node GROUP BY mac, switch, port HAVING count(*) > 1) n2 ON n1.mac = n2.mac AND n1.switch = n2.switch AND n1.port = n2.port AND n1.vlan = '0';

COMMIT;
