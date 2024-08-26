from netdisco.util.worklet import debug, context as c
from netdisco.util.ssh import net_connect

def main():
    command = "show route forwarding-table | match ucst | match /32"
    with net_connect:
        output = net_connect.send_command(command, use_textfsm=True)

    neighbors = []
    if output is not None:
        # debug(output)
        for record in output:
            neighbors.append(record['next_hop'])

    # debug(neighbors)
    c.stash.set('next_hops', neighbors)
    c.status.done('gathered route neighbors')


if __name__ == '__main__':
    main()
