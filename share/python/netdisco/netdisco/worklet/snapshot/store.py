from sqlalchemy import text
from netdisco.util.worklet import debug, context as c


def main():
    with c.db.begin() as conn:
        resultset = conn.execute(
            text(
                'DELETE from device_browser WHERE ip = :dev_ip'
            ),
            [{'dev_ip': c.job.device}],
        )
        resultset = conn.execute(
            text(
                'INSERT INTO device_browser (ip, oid, oid_parts, value) '
                + 'VALUES (:ip, :oid, :oid_parts, :value)'
            ),
            [{'dev_ip': c.job.device}],
        )


if __name__ == '__main__':
    main()
