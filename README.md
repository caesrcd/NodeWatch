# NodeWatch

![NodeWatch Screenshot](https://github.com/caesrcd/NodeWatch/blob/master/screenshot.png)

NodeWatch is a CLI dashboard for monitoring your Bitcoin fullnode, providing essential information such as node status, transaction fee estimate, bitcoin price, and more.

## Features

- **Node Info:** Displays detailed information from the Bitcoin Core `getinfo` command, providing an overview of the state of your node.
- **Debug Logs:** Displays the contents of the Bitcoin `debug.log` file, allowing you to monitor and diagnose issues.
- **Fullnode Processes:** Displays `htop` filtered to show only processes related to the fullnode, making it easier to monitor resource usage.
- **Peer Connections:** Provides a list of peer connections, including details about each active connection.
- **Transaction Fee Estimate:** Displays the current transaction fee estimate, helping you adjust your transactions for efficiency and cost.
- **Bitcoin Price:** Displays the current Bitcoin price and includes an audible alarm scheme for notifications when the price reaches certain thresholds.

These features provide comprehensive insight and control over your Bitcoin fullnode, improving the efficiency and monitoring of your cryptocurrency infrastructure.

## Installation and Usage

1. For full operation, the list of dependent packages follows:

   - BitcoinCore ([website](https://bitcoin.org/en/download))
   - tmux ([github](https://github.com/tmux/tmux/wiki))
   - sysstat ([website](https://sysstat.github.io/))
   - MultiTail ([website](https://vanheusden.com/multitail/))
   - FIGlet ([website](http://www.figlet.org/))
   - SoX ([sourceforge](https://sourceforge.net/projects/sox/))
   - jq ([website](https://jqlang.github.io/jq/))
   - bc ([website](https://www.gnu.org/software/bc/))

2. Configure the config.env file to connect to your fullnode.

3. After configuring, run the command below:

   ```bash
   ./NodeWatch
   ```

4. Use the following shortcuts to control the session:

   - Press `q` to end the session.
   - Press `z` to detach the session.

## Configuration

Edit the config.env file to adjust the settings according to your environment. Example content:

```bash
SIZE_SCREEN=220x47
BITCOIN_DATADIR=/mnt/bitcoin
IOSTAT_DEVICE=/dev/disk/by-uuid/fa4b95ba-5878-4830-98ed-4a28f39fad2b
IOSTAT_DEVICE=/dev/disk/by-uuid/3f102c82-3118-4867-8aa9-6d30a167a4c4
```

## License

This project is licensed under the [MIT License](https://opensource.org/license/MIT).

