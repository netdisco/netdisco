import asyncio
from pysnmp.hlapi.v3arch.asyncio import (
    bulk_cmd,
    SnmpEngine,
    CommunityData,
    UdpTransportTarget,
    ContextData,
    ObjectType,
    ObjectIdentity,
)
from netdisco.util.worklet import debug, context as c


def main():
    nonRepeaters = 0
    maxRepetitions = 20

    async def run():
        errorIndication, errorStatus, errorIndex, varBindTable = await bulk_cmd(
            SnmpEngine(),
            CommunityData('public', mpModel=1),
            await UdpTransportTarget.create(('demo.pysnmp.com', 161)),
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
