from netdisco.util.worklet import debug, context as c
from netdisco.util.ssh import net_connect

def main():
    command = "show bgp summary"
    with net_connect:
        output = net_connect.send_command(command, use_textfsm=True)

    neighbors = []
    if output is not None:
        debug(output)
        for record in output:
            neighbors.append(record['peer_ip'])

    debug(neighbors)
    c.stash.set('next_hops', neighbors)
    c.status.info('gathered bgp next hops')


if __name__ == '__main__':
    main()
