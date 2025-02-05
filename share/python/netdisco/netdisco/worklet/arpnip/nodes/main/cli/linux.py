from netdisco.util.worklet import context as c
from netdisco.util.ssh import net_connect


def main():
    command = 'arp -a'
    with net_connect:
        output = net_connect.send_command(command, use_textfsm=True)

    arps = []
    if output is not None:
        # debug(output)
        for record in output:
            arps.append(
                {'dns': record['rev_dns'], 'ip': record['ip_address'], 'mac': record['mac_address']}
            )

    # debug(arps)
    if len(arps) > 0:
        c.stash.set('arps', arps)
        c.status.done('Gathered arp caches from ' + c.job.device)
    else:
        c.status.info('No arp cache retrieved from ' + c.job.device)


if __name__ == '__main__':
    main()
