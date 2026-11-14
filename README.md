# mbmscripts

A collection of small command-line tools for macOS (a few are for Linux), installed so that
every command starts with the same prefix: `mbm-help`, `mbm-dns-flush`, `mbm-btvpn`, ...

Type `mbm-` and press `Tab` in your terminal to see them all, or run `mbm-help`.

You choose the prefix when you install. If you prefer `xyz-`, the same tools are called
`xyz-help`, `xyz-dns-flush`, and so on.

## Install

You need a Mac (or Linux) with `bash` or `zsh`. No administrator rights are needed.

Open a terminal, paste this line and press `Return`:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/bbmorten/mbmscripts/main/install.sh)"
```

The installer asks two questions. Press `Return` to accept the value in brackets.

| Question | What it decides | Default |
| --- | --- | --- |
| `Name` | What this installation is called. Everything it creates lives in the folder `~/.<name>`. | `mbmscripts` (folder `~/.mbmscripts`) |
| `Prefix` | What every command starts with. | `mbm-` |

Then **open a new terminal window** and type:

```sh
mbm-help
```

To answer the questions on the command line instead, or to change your mind later, run the
installer again with options. It replaces the old commands with the newly named ones.

```sh
./install.sh --name mytools --prefix my-     # commands become my-help, my-dns-flush, ...
./install.sh --yes                           # no questions, all defaults
```

### What the installer changes on your computer

1. It creates `~/.<name>/bin` with one entry per command.
2. It writes `~/.<name>/env.sh`, a small file that adds that folder to the end of your `PATH`.
   It is at the end on purpose, so a command from here can never hide a system command.
3. It adds this block to `~/.zshrc` and `~/.bashrc`, so both shells load `env.sh`:

   ```sh
   # >>> mbmscripts >>>
   [ -r "$HOME/.mbmscripts/env.sh" ] && . "$HOME/.mbmscripts/env.sh"
   # <<< mbmscripts <<<
   ```

   A file it changes is first copied to `<file>.bak-<name>-<time>`. If a login `bash` on your
   computer does not read `~/.bashrc`, the block also goes into your bash login file.

That covers Terminal, iTerm2, the terminal inside VS Code and oh-my-zsh: they all start `zsh`
or `bash`, which read these files. Nothing needs to be set inside those programs.

## The commands

`mbm-help` prints this list on your own computer; `mbm-help docker` shows only the lines that
mention `docker`.

### macOS and network

| Command | What it does |
| --- | --- |
| `mbm-dns-flush` | Flushes the macOS DNS cache and restarts the DNS service. It runs `sudo dscacheutil -flushcache; sudo killall mDNSResponder` and asks for your Mac password. |
| `mbm-btvpn` | Connects to your company's Cisco VPN with one command: password from the Keychain, SMS code read from Messages. Start with `mbm-btvpn setup`. |
| `mbm-multivpn` | Keeps a second VPN connected next to the company one (needs `openconnect` and `ocproxy`). |
| `mbm-print-route` | Prints one line of the routing table for the interface you name. |
| `mbm-sslkeylog-capture` | Starts a browser with TLS keys logged while `tshark` captures the packets. |
| `mbm-eth-conv` | Counts the Ethernet conversations in a capture file. |
| `mbm-extract-time-info-w-tshark` | First packet, last packet and duration of a capture file. |
| `mbm-interface-test` | Takes the `ens160` interface down for 60 seconds, then up again (Linux). |
| `mbm-logger` | Records the terminal session to a log file. |

`mbm-btvpn` and `mbm-multivpn` are the tools from
[btvpn-multivpn](https://github.com/bbmorten/btvpn-multivpn). That repository has the
step-by-step guide for them, in [English](https://github.com/bbmorten/btvpn-multivpn/blob/main/README.md)
and [Turkish](https://github.com/bbmorten/btvpn-multivpn/blob/main/README.tr.md); read
`btvpn` as `mbm-btvpn` and `multivpn` as `mbm-multivpn`.

### Files and folders

| Command | What it does |
| --- | --- |
| `mbm-find-file` | Finds a file by name under a starting folder. |
| `mbm-find-files-over-100m` | Lists the files larger than 100 MB under a folder. |
| `mbm-find-and-delete-duplicates` | Finds files with identical content and offers to delete the copies. |
| `mbm-list-folders-with-pdf` | Lists the folders that contain PDF files. |
| `mbm-du` | Saves the size of each subdirectory, largest first, to a file. |
| `mbm-cp-dir-structure` | Copies a directory tree without its files. |
| `mbm-cp-dir-structure-w-files` | Copies a directory, optionally adding an `index.md`. |
| `mbm-sync-git-msp` | Rsyncs a local folder to a remote host (dry run, watch mode). |
| `mbm-sync-git-msp-v2` | The same with live progress and a history. |
| `mbm-my-sync` | Rsyncs a folder each time it changes (Linux, `inotifywait`). |
| `mbm-my-sync-fswatch` | Pulls a remote folder when it changes. Its author marked it "not working". |
| `mbm-copy-zsh-settings` | Copies your zsh configuration to a remote Mac over ssh. |

### Markdown and documentation

| Command | What it does |
| --- | --- |
| `mbm-insert-date` | Replaces `{{DATE}}` in a file with today's date. |
| `mbm-change-filename` | Renames `DDMMYYYY.md` files in a folder to `YYYYMMDD.md`. |
| `mbm-replace-heading` | Rewrites `# DDMMYYYY` first-line headings as `# YYYYMMDD`. |
| `mbm-create-outline-markdown` | Turns the list items of a Markdown file into links to generated pages. |
| `mbm-nextra-setup` | Scaffolds a Nextra documentation project. |
| `mbm-nextra-setup-w-podman` | The same, set up to run with Podman. |
| `mbm-sdd` | Serves the mkdocs site in `~/git-repos/docker`. |
| `mbm-srd` | Starts the Docker Compose stack in `~/git-repos/mydocs`. |
| `mbm-run-docker-web`, `mbm-run-docker-web3` | Build an mkdocs site and serve it with nginx on a remote host. |

### Containers and models

| Command | What it does |
| --- | --- |
| `mbm-docker-cmdline` | Prints the entrypoint and command of a container. |
| `mbm-docker-compose-start-services` | Starts the Docker Compose projects you name. |
| `mbm-docker-compose-stop-services-all` | Stops every running Docker Compose project. |
| `mbm-lima-podman-w-target` | Starts Lima with Podman from a sparsebundle on an external volume. |
| `mbm-delete-old-models` | Deletes ollama models that were not modified for more than a week. |

These are personal tools published as they are. Several assume a particular folder layout or
need other programs (`tshark`, `docker`, `rsync`, `ollama`, ...). Read a script before you rely
on it; each is a single readable file in [`bin/`](bin/).

## Your own settings

Some commands need a value that is different for everyone, such as the host to sync to. Put
those in `~/.<name>/local.env`. The installer never touches that file, and both shells load it.

```sh
# ~/.mbmscripts/local.env
export MBM_REMOTE_HOST="192.0.2.10"          # mbm-sync-git-msp, mbm-copy-zsh-settings
export MBM_REMOTE_USER="me"                  # default: your local user name
export MBM_SYNC_SOURCE_DIR="$HOME/git-msp/"  # default: ~/git-msp/
export MBM_SYNC_REMOTE_DIR="git-msp/"        # default: git-msp/ in the remote home folder
export MBM_SYNC_V2_REMOTE_HOST="192.0.2.11"  # mbm-sync-git-msp-v2 only; default: MBM_REMOTE_HOST
export MBM_SSLKEYLOG_DIR="$HOME/captures"    # default: ~/.local/share/mbm-sslkeylog-capture
export MBM_LIMA_VOLUME="MyDisk"              # default: External
export MBM_REPLACE_HEADING_DIR="$HOME/notes" # default: the current folder
```

These variable names always start with `MBM_`, whatever prefix you chose for the commands.

## Your own private commands

If you work from a clone of this repository, put scripts you do not want to publish in
`local/bin/`, named `mbm-<something>`. The folder `local/` is ignored by git; the installer
picks those scripts up like the others. A line `<something><TAB>description` in
`local/descriptions.txt` makes `mbm-help` describe them.

## Update

- Installed with the one-line command: run it again.
- Installed from a clone: `git pull`. The commands point at the clone, so they are up to date
  at once. Run `./install.sh --yes` again only when a command was added or removed.

## Remove

```sh
./uninstall.sh                 # the installation called mbmscripts
./uninstall.sh --name mytools  # an installation with another name
./uninstall.sh --purge         # also delete your local.env
```

It removes the commands, `env.sh` and the block in your shell startup files (each changed file
is copied first). Without a clone, download `uninstall.sh` from this page and run it with `bash`.

## For developers

```sh
git clone https://github.com/bbmorten/mbmscripts.git
cd mbmscripts
tests/run.sh      # offline: no sudo, no VPN, no Keychain; installs only into a temporary HOME
./install.sh      # the commands then point at this clone
```

- `bin/mbm-<name>` is a command. The file name always carries `mbm-`; the installer creates
  `<prefix><name>` for whatever prefix the user chose. A script that prints its own name
  should use `$(basename "$0")`.
- `libexec/` holds helper files that are not commands, and `descriptions.txt`, one
  `<name><TAB>description` line per command (the tests check that it is complete).
- Scripts are `bash` or `zsh`, chosen by their first line; they sit side by side in `bin/`.

## License

[MIT](LICENSE). Not affiliated with or endorsed by Cisco; Cisco, Cisco Secure Client and
AnyConnect are trademarks of Cisco Systems, Inc.
