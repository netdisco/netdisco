import asyncio
from pysnmp.error import PySnmpError
from pyasn1.error import PyAsn1Error
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


async def run():
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

    nonRepeaters = 0
    maxRepetitions = c.setting('bulkwalk_repeaters') or 20
    snmp_engine = SnmpEngine()
    varBinds = []

    try:
        errorIndication, errorStatus, errorIndex, varBinds = await bulk_cmd(
            snmp_engine,
            authdata,
            await transport,
            ContextData(),
            nonRepeaters,
            maxRepetitions,
            ObjectType(ObjectIdentity('1.0')),
            lookupMib=False,
        )

    except PySnmpError as e:
        c.status.error(f'PySnmpError error: {e}')
    except PyAsn1Error as e:
        c.status.error(f'PyAsn1Error error: {e}')
    else:
        if errorIndication:
            c.status.error(f'SNMP engine error: {errorIndication}')
        elif errorStatus:
            c.status.error(
                'SNMP PDU error: {} at {}'.format(
                    errorStatus.prettyPrint(),
                    errorIndex and varBinds[int(errorIndex) - 1][0] or '?',
                )
            )
    finally:
        snmp_engine.transport_dispatcher.close_dispatcher()

    return varBinds


def main():
    if c.setting('bulkwalk_off'):
        return c.status.info('snapshot skipped: SNMP bulkwalk is disabled')

    result = asyncio.run(run())
    if c.status.level() == 0:
        # debug(result)
        c.status.done('finished bulkwalk')
    else:
        debug(c.status.log)


if __name__ == '__main__':
    main()
