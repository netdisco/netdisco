import asyncio
from pysnmp.hlapi.v3arch.asyncio import (
    bulk_cmd,
    SnmpEngine,
    CommunityData,
    UsmUserData,
    UdpTransportTarget,
    Udp6TransportTarget,
    ContextData,
    ObjectType,
    ObjectIdentity,
)
from sqlalchemy import text
from netdisco.util.worklet import debug, context as c


def main():
    nonRepeaters = 0
    maxRepetitions = c.setting('bulkwalk_repeaters') or 20

    if c.setting('bulkwalk_off'):
        return c.status.info('snapshot skipped: snmp bulkwalk is disabled')

    transport = (
        UdpTransportTarget.create((c.job.device, 161))
        if '.' in c.job.device
        else Udp6TransportTarget.create((c.job.device, 161))
    )

    with c.db.begin() as conn:
        resultset = conn.execute(
            text(
                'SELECT snmp_ver, snmp_comm, snmp_auth_tag_read FROM device '
                + 'LEFT JOIN community USING(ip) WHERE ip = :dev_ip'
            ),
            [{'dev_ip': c.job.device}],
        )
        row = resultset.first()
        if row.snmp_ver == 1:
            authdata = CommunityData(row.snmp_comm, mpModel=0)
        elif row.snmp_ver == 2:
            authdata = CommunityData(row.snmp_comm, mpModel=1)
        else:
            authdata = UsmUserData()

    async def run():
        errorIndication, errorStatus, errorIndex, varBindTable = await bulk_cmd(
            SnmpEngine(),
            authdata,
            await transport,
            ContextData(),
            nonRepeaters,
            maxRepetitions,
            ObjectType(ObjectIdentity('1.0')),
            lookupMib=False,
        )
        if errorIndication or errorStatus:
            debug('there was an error')
        else:
            debug(varBindTable)

    try:
        asyncio.run(run())
        debug('finished bulkwalk')
        c.status.done('finished bulkwalk')
    except Exception as e:
        debug(e)
        c.status.error('failed bulkwalk')


if __name__ == '__main__':
    main()
