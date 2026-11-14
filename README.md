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

Every command answers `--help` with what it does, its options and examples; `mbm-help`
lists them all on your own computer, `mbm-help docker` only the lines that mention docker,
and `mbm-help --check` says which of them can run on this machine and what is missing.

Commands that delete, stop or overwrite something list what they will do and ask first.
They all have `-n` (dry run: show, change nothing) and `-y` (do not ask). Without a
terminal they refuse instead of guessing, so **a script or scheduled job must pass `--yes`**.

### macOS and network

| Command | What it does |
| --- | --- |
| `mbm-dns-flush` | Flush the macOS DNS cache and restart the DNS service (asks for your Mac password). |
| `mbm-btvpn` | Connect to your company's Cisco VPN with one command (Keychain password, SMS code from Messages). |
| `mbm-multivpn` | Keep a second VPN connected next to the company one (openconnect + ocproxy). |
| `mbm-print-route` | Show the routing table in short form, or the route used to reach one destination. |
| `mbm-interface-bounce` | Take a network interface down for some seconds, then bring it up again (asks first). |
| `mbm-sslkeylog-capture` | Record a browser session as a packet capture plus the TLS keys that decrypt it. |
| `mbm-eth-conv` | Count the frames between each pair of Ethernet addresses in a capture file. |
| `mbm-extract-time-info-w-tshark` | Show first and last packet time, duration and packet count of capture files. |
| `mbm-logger` | Record the terminal session to a dated log file, or list the logs. |

### Files and folders

| Command | What it does |
| --- | --- |
| `mbm-find-file` | Find files and folders by name or part of a name under a folder, ignoring case. |
| `mbm-find-files-over-100m` | List the files over 100 MB (or another size) under a folder, largest first. |
| `mbm-find-and-delete-duplicates` | Find files with identical content and delete all but one of each, asking first. |
| `mbm-list-folders-with-pdf` | List the folders that contain PDF files, or files with another extension. |
| `mbm-du` | Show the disk space used by a folder and the folders in it, largest first. |
| `mbm-cp-dir-structure` | Copy the folders of a tree to another place, without the files in them. |
| `mbm-cp-dir-structure-w-files` | Copy a folder tree with all its files or only matching ones, never overwriting a file. |

### Copying between machines

| Command | What it does |
| --- | --- |
| `mbm-sync-git-msp` | Mirror a local folder to a remote host with rsync, with progress and a history of runs. |
| `mbm-my-sync` | Copy a folder to another place with rsync, now and again after every change. |
| `mbm-my-sync-fswatch` | Pull a folder from another machine with rsync, now and after every change there. |
| `mbm-copy-zsh-settings` | Copy your zsh configuration to another machine over ssh, with a backup there. |

### Markdown and documentation sites

| Command | What it does |
| --- | --- |
| `mbm-insert-date` | Replace the placeholder {{DATE}} in files with today's date. |
| `mbm-change-filename` | Rename DDMMYYYY.md files under a folder to YYYYMMDD.md so that they sort by date. |
| `mbm-replace-heading` | Rewrite a first-line heading # DDMMYYYY as # YYYYMMDD in the Markdown files of a folder. |
| `mbm-create-outline-markdown` | Turn the list items of a Markdown outline into links to stub pages it creates. |
| `mbm-nextra-setup` | Create a Nextra 4 documentation site project in a new folder, for Docker or (--podman) Podman. |
| `mbm-mkdocs-serve` | Serve a mkdocs documentation project locally while you edit it. |
| `mbm-run-docker-web` | Build a mkdocs site, copy it to a remote host and serve it there with nginx in Docker. |

### Containers and models

| Command | What it does |
| --- | --- |
| `mbm-docker-cmdline` | Print the command line a container or image runs, quoted for pasting into a shell. |
| `mbm-docker-compose-start-services` | Start Docker Compose projects by folder name under a base folder, or list them. |
| `mbm-docker-compose-stop-services-all` | Stop or take down every running Docker Compose project, after listing and asking. |
| `mbm-compose-up` | Start the Docker Compose project in a folder in the background, or stop it. |
| `mbm-lima-podman-w-target` | Start the Lima podman machine kept in a disk image on an external volume (macOS). |
| `mbm-delete-old-models` | Delete the ollama models pulled or changed at least N days ago, after listing them. |

`mbm-btvpn` and `mbm-multivpn` are the tools from
[btvpn-multivpn](https://github.com/bbmorten/btvpn-multivpn). That repository has the
step-by-step guide for them, in [English](https://github.com/bbmorten/btvpn-multivpn/blob/main/README.md)
and [Turkish](https://github.com/bbmorten/btvpn-multivpn/blob/main/README.tr.md); read
`btvpn` as `mbm-btvpn` and `multivpn` as `mbm-multivpn`.

[CHANGES.md](CHANGES.md) lists, per command, what was wrong with the old version and what
behaves differently now.

## Your own settings

Some commands need a value that is different for everyone, such as the host to sync to. Put
those in `~/.<name>/local.env`. The installer never touches that file, and both shells load it.

```sh
# ~/.mbmscripts/local.env
export MBM_REMOTE_HOST="192.0.2.10"           # sync-git-msp, copy-zsh-settings (or --host)
export MBM_REMOTE_USER="me"                   # default: your local user name
export MBM_SYNC_SOURCE_DIR="$HOME/git-msp/"   # sync-git-msp --source; default ~/git-msp/
export MBM_SYNC_REMOTE_DIR="git-msp/"         # sync-git-msp --dest; default git-msp/
export MBM_SYNC_REMOTE_HOST="192.0.2.11"      # sync-git-msp only; default: MBM_REMOTE_HOST
export MBM_CONTAINER_ENGINE="podman"          # the docker-* commands; default docker
export MBM_COMPOSE_BASE_DIR="$HOME/projects"  # docker-compose-start-services; default ~/git-repos
export MBM_COMPOSE_UP_DIR="$HOME/git-repos/mydocs"    # compose-up; this is the default
export MBM_MKDOCS_SERVE_DIR="$HOME/git-repos/docker"  # mkdocs-serve; this is the default
export MBM_DOCKER_WEB_DIR="$HOME/git-repos/docker"      # run-docker-web; this is the default
export MBM_DOCKER_WEB_USER="vm"               # run-docker-web, the user on the host; default vm
export MBM_DOCKER_WEB_REMOTE_DIR="site"       # run-docker-web; default: the project folder's name
export MBM_LIMA_VOLUME="MyDisk"               # lima-podman-w-target; default External
export MBM_LIMA_TEMPLATE="template://podman"  # lima-podman-w-target; this is the default
export MBM_LOGGER_DIR="$HOME/TerminalLogs"    # logger; default ~/Documents/Temp/TerminalLogs
export MBM_REPLACE_HEADING_DIR="$HOME/notes"  # replace-heading, when no folder is given
export MBM_SSLKEYLOG_DIR="$HOME/captures"     # sslkeylog-capture; default ~/.local/share/sslkeylog-capture
export MBM_SSLKEYLOG_CHROME="/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"
export MBM_SSLKEYLOG_FIREFOX="/usr/bin/firefox"
```

Every one of them can also be given as an option on the command line; `--help` of each
command names its settings.

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
tests/run.sh            # every check, offline
tests/run.sh du         # the checks of one command
./install.sh            # the commands then point at this clone
```

- `bin/mbm-<name>` is a command. The file name always carries `mbm-`; the installer creates
  `<prefix><name>` for whatever prefix the user chose.
- Lines 2 and following of a command are one comment block that IS its `--help`: a first
  line `mbm-<name> - what it does`, then `Usage:`, `Options:`, `Examples:` and, where they
  say something, `Needs:`, `Settings:`, `Exit status:`. `tests/run.sh` checks that `--help`
  and `-h` print it and exit 0 without doing anything, that it follows another prefix, that
  an unknown option exits 2, and that `shellcheck` is clean. Copy the preamble of any
  command in `bin/` for a new one.
- Exit status: 0 done, 1 could not do the job, 2 called wrongly. Errors go to standard error.
- `libexec/descriptions.txt` holds one line per command: name, a tab, the one-line
  description, and optionally a tab and what it needs (program names, `os:macos`,
  `os:linux`) for `mbm-help --check`. The tests check that every command has a line.
- `tests/commands/<name>.sh` tests one command. Tests run in a sandbox (`tests/lib.sh`): an
  empty temporary home folder, no `MBM_*` settings, and fakes in place of everything that
  reaches outside (ssh, rsync, sudo, docker, ollama, ...), so they never touch your machine.
  `tests/sandbox.sh` runs any command by hand in the same sandbox.
- Scripts run under the `/bin/bash` 3.2 that macOS ships, and use only what macOS and Linux
  provide (BSD and GNU sed, awk, date, find).

## License

[MIT](LICENSE). Not affiliated with or endorsed by Cisco; Cisco, Cisco Secure Client and
AnyConnect are trademarks of Cisco Systems, Inc.
