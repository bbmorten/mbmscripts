# Changes

## 2026-11-15: every command reworked

Every command except `mbm-btvpn` and `mbm-multivpn` was tested as it was, fixed, given a standard `--help`, and given its own test file in `tests/commands/`. Commands that delete, stop or overwrite something now list what they will do, ask first, and offer `-n` (dry run) and `-y` (no question). **A script or a scheduled job that runs one of those must now add `--yes`**: without a terminal they refuse instead of guessing.

Below, per command: what was wrong with the old version (as found by running it), and how the new one behaves differently.

### mbm-find-file

`mbm-find-file [options] [START] PATTERN`

Old version: **worked with defects**. Found:

- exact, case-sensitive name only: report.pdf does not find report.PDF
- no default folder; exactly two arguments required
- --help and -h exit 1 with a one-line usage that shows the full script path
- a missing START gives no message at all (find's error is thrown away), only exit 1
- exit status is find's: 1 whenever any folder is unreadable even though results were printed, 0 when nothing is found
- a START that begins with a dash is taken as find options: silent failure
- a START that is a symbolic link to a folder (/tmp on macOS) is not searched

What behaves differently now:

- A name without wildcards now matches as a part of the name and in any case, so the old two-argument call returns a superset of what it returned; use -e for the old exact match.
- Nothing found is now exit 1 with a message on standard error (was exit 0 and silence).
- Unreadable folders no longer turn the exit status to 1 when something was found.
- A missing START now prints 'not a folder' (was silent).
- One argument is now a PATTERN searched from the current folder (was a usage error).
- A PATTERN containing / is refused with exit 2 (was: silently found nothing).
- A START that is a symlink to a folder is now searched.

### mbm-find-files-over-100m

`mbm-find-files-over-100m [-s SIZE] [-o FILE] [DIR]`

Old version: **worked with defects**. Found:

- always writes Filesover100M.txt into the current folder, also when nothing is found
- when that file cannot be written it reports 'No files over 100MB found' and exits 0: a wrong answer
- sizes come from du (disk usage) while the selection is by length: sparse files such as disk images are listed as 0B and sorted last
- threshold fixed at 100M; folder required
- --help is treated as a folder name; errors go to standard output
- status lines are mixed into standard output, in the way of piping the list

What behaves differently now:

- Filesover100M.txt is no longer written; use -o FILE to save the list.
- The 'Searching...', 'Found files...', 'Results saved...' lines are gone; standard output is the list only.
- Sizes are file lengths, not disk usage: a sparse 3 GB disk image shows as 3.0G (was 0B) and sorts first.
- Without DIR it searches the current folder (was a usage error).
- Permission errors of find are no longer shown.
- With -o, nothing is printed on standard output (the old version printed the list and saved it).

### mbm-find-and-delete-duplicates

`mbm-find-and-delete-duplicates [-r] [-n] [-y] [DIR]`

Old version: **worked with defects**. Found:

- no folder argument: any argument other than -r/--recursive is silently ignored and the current folder is scanned; --help starts a scan
- the kept file is whichever comes first out of a hash table: in the test the copy in a subfolder was kept and the original in the top folder deleted
- descends into .git and deletes objects there
- all empty files count as duplicates of each other
- a file whose name contains a line break or backslash is never matched (shasum escapes the line)
- every file is hashed, one shasum process per file
- `eval` of the find command; `read -q` (zsh only) with a prompt that needs no Enter
- no dry run, no --yes; exit 0 whatever happened; no summary of what was deleted

What behaves differently now:

- The answer now needs Enter (y or yes); the old one reacted to a single key.
- Without a terminal it now exits 1 with a message instead of listing the groups and exiting 0; use -n to list.
- Empty files, symlinks, .git contents and hard links of the kept file are no longer offered for deletion.
- Which file is kept is now fixed by rule (shortest path, then byte order); the old choice was arbitrary.
- An argument is now the folder to check; an unknown option or a second folder is an error (old: silently ignored).
- Output wording changed completely (no 'Scanning...' line, no hash shown; keep/delete lists and a total).
- Sets are processed largest first.

### mbm-list-folders-with-pdf

`mbm-list-folders-with-pdf [-e EXT] [-c] [DIR]`

Old version: **worked with defects**. Found:

- case-sensitive glob: REPORT.PDF is not found
- hidden folders are not searched
- the heading line is on standard output, in the way of piping the list (wc -l counts one too many)
- a folder that does not exist, and --help, give the heading and exit 0
- a trailing slash on the folder gives paths with //
- a folder whose own name ends in .pdf is counted as a PDF file
- starting folder required; extension fixed

What behaves differently now:

- The heading line 'Folder names containing PDF files:' is gone.
- PDF files with an extension in capitals are now found, and hidden folders are searched, so more folders may be listed.
- A folder that does not exist is now an error (exit 1) instead of an empty list.
- Without an argument it lists from the current folder (was an error).
- Sorting is now by bytes with ASCII case folded, not by the locale's collation.
- A folder whose name ends in .pdf no longer makes its parent appear.

### mbm-du

`mbm-du [-d DEPTH] [-o FILE] [DIR]`

Old version: **worked with defects**. Found:

- always writes a file and never shows the table; without a file name it drops directory_sizes_<timestamp>.txt (with colons in the name) into the current folder
- --help runs du --help, reports success and writes (or overwrites) an output file
- a folder that does not exist still reports 'saved', exits 0 and leaves an empty file
- the second positional argument is overwritten without question (mbm-du a.txt b.txt destroys b.txt)
- depth fixed at 1; folder required
- under a Turkish locale du prints 1,5M (checked: LC_ALL=tr_TR.UTF-8 du -h)
- a DIR that is a symlink to a folder (for example /tmp) is reported as 0B

What behaves differently now:

- The table is printed; no file is written unless -o FILE is given (no more directory_sizes_<timestamp>.txt).
- `mbm-du DIR FILE` is now an error (exit 2) that points to -o FILE.
- The line 'Directory sizes saved to ...' is gone; with -o nothing is printed.
- Without an argument it measures the current folder (was an error).
- DIR must be a folder: a file argument is refused (the old one printed the file's size).
- Exit status 1 when du could not read everything (was always 0).

### mbm-cp-dir-structure

`mbm-cp-dir-structure [-n] [-v] SRC DST`

Old version: **worked with defects**. Found:

- A trailing slash on SRC creates the folders beside DST with DST's name glued on (dst2a, dst2empty) instead of inside it
- SRC containing [ ] or * is treated as a pattern: nothing is created, success is reported
- A missing SRC, or SRC that is a file, still creates DST, says 'copied' and exits 0
- DST inside SRC is copied into itself one level (in/copy/copy)
- read without -r and IFS=: a backslash in a folder name is dropped, a trailing space is stripped
- SRC starting with a dash is read by find as an option; still exits 0
- No help: --help prints a usage line and exits 1
- No dry run, no count, no error status when a folder cannot be read

What behaves differently now:

- A missing SRC (or a file as SRC) is now an error (exit 1) and DST is not created; before it created DST and exited 0
- SRC with a trailing slash now gives the same tree inside DST; before it scattered folders next to DST
- The final line is now 'Folders made in DST: N; there already: M.' instead of 'Directory structure copied from SRC to DST'
- Wrong number of arguments exits 2 (was 1); SRC and DST being the same folder is refused
- An argument starting with '-' is an option unless it follows `--`

### mbm-cp-dir-structure-w-files

`mbm-cp-dir-structure-w-files [-n] [-v] [-c] [-i PATTERN]... SRC DST`

Old version: **worked with defects**. Found:

- The same command gives two different results: DST missing -> DST is the copy; DST existing -> SRC is put inside it
- -t does nothing but print a sentence; -c only touches DST/index.md
- A missing SRC prints cp's error, then 'Done.', and exits 0
- Existing files in DST are overwritten silently
- Symbolic links are copied as regular files (cp -r)
- No help (--help: 'Invalid option: --', exit 1); no dry run; nothing to select files

What behaves differently now:

- With an existing DST the content of SRC now goes directly into DST; before, SRC itself was placed inside DST (DST/SRCNAME/...)
- SRC must be a folder; before, a single file could be copied
- An existing file in DST is never overwritten; before it was overwritten silently. A differing file gives exit 1
- -t is no longer accepted (exit 2)
- -c creates index.md in every copied folder without one, not only in DST itself, and no longer touches an existing index.md
- Symbolic links stay links instead of becoming copies of their targets
- A missing SRC exits 1 (was 0); wrong argument count exits 2 (was 1)
- Output is one summary line (plus 'kept' lines) instead of 'Done.'

### mbm-change-filename

`mbm-change-filename [-n] [-e EXT] DIR`

Old version: **worked with defects**. Found:

- Every eight-digit name matches, so files that are YYYYMMDD already are scrambled (20240101 -> 01012420) and a second run scrambles the whole folder
- mv overwrites an existing target silently: a file was lost in the test
- No date validation: 31022024 becomes 20240231, 99999999 is 'renamed' to itself
- With no argument it prompts for a folder (blocks in a script)
- Errors go to standard output; no help, no dry run, no count

What behaves differently now:

- Without a folder argument it no longer asks for one: exit 2
- Names that are not a valid DDMMYYYY date in 1900-2099 are left alone (before: every eight-digit name was renamed, including YYYYMMDD ones)
- A file whose new name already exists is skipped with exit 1 instead of overwriting it
- Each rename is printed as 'old -> new' (was "Renaming old to 'new'"), followed by a count line
- 'Invalid directory path.' on stdout became 'not a folder: DIR' on stderr; wrong usage exits 2

### mbm-replace-heading

`mbm-replace-heading [-n] [DIR]`

Old version: **worked with defects**. Found:

- An & in the heading corrupts it (sed replacement); a / makes sed fail while success is reported
- Not idempotent: a heading that is YYYYMMDD already is scrambled on the next run; no date validation
- The prompt is broken: a typed folder is always replaced by the empty $1 ('Invalid directory path'); only an EMPTY answer works, falling back to MBM_REPLACE_HEADING_DIR or the current folder
- sed -i '' is BSD-only (fails with GNU sed) and replaces the file: new inode, read-only files rewritten
- One 'Date format not found' line per non-matching file; no help, no dry run, unused log_file variable

What behaves differently now:

- With no argument it no longer prompts and no longer falls back to the current folder: MBM_REPLACE_HEADING_DIR is used, and without it the command exits 2
- Headings whose eight digits are not a valid DDMMYYYY date in 1900-2099, or are followed by a ninth digit, are left alone
- Output is one 'file: old -> new' line per changed file and a count; the per-file 'Date format not found' lines are gone
- A read-only file is no longer rewritten (BSD sed -i used to replace it); it is reported and the exit status is 1
- Wrong usage exits 2; 'Invalid directory path.' became 'not a folder: DIR' on stderr

### mbm-insert-date

`mbm-insert-date [-n] [-f FORMAT] [-p TEXT] FILE...`

Old version: **worked with defects**. Found:

- mktemp + mv: the file comes back with mode 0600 and a new inode
- A symbolic link is replaced by a regular file and its target is left unchanged
- A missing file is created empty and the exit status is 0
- Only the first file is read; further arguments are ignored silently
- --help creates a file called --help
- A read-only file is replaced all the same; no dry run; fixed format and placeholder

What behaves differently now:

- Prints one line per file ('FILE: 3 x {{DATE}} replaced with 2026-11-14' or 'no {{DATE}} in it, not changed'); the old version printed nothing
- Every file named is processed, not only the first
- A missing file is an error (exit 1) and is no longer created empty
- A read-only file is refused instead of being replaced
- The file keeps its permissions and stays the same file; a symlink's target is edited
- No argument exits 2 (was 1); an argument starting with '-' is an option unless after `--`
- The interpreter is bash, not zsh

### mbm-create-outline-markdown

`mbm-create-outline-markdown [-n] [-y] [-d PAGES_DIR] [-p PREFIX] OUTLINE.md [OUTPUT.md]`

Old version: **broken**. Found:

- The usage message names two arguments, the check demands three
- Only works when run from inside the folder with DIR = '.': `cp $2 $3` uses the current folder; from elsewhere it errors, exits 0 and leaves the input outline modified
- Each item is substituted with sed over the whole file: an item that is part of another is linked inside it, text in titles is linked too
- /, & and other special characters in an item break the sed expression or corrupt the text; / also breaks the page name
- Edits the input in place and juggles input, output and .bak; unquoted variables break on spaces
- Items that are links already get a page and a broken name; nested, * and + items are ignored; no help, no dry run

What behaves differently now:

- An existing OUTPUT.md is no longer overwritten silently: it asks on a terminal, and in a script it needs --yes (this also applies to the old three-argument form)
- Nested items and '*' / '+' items are now linked too; the old version only saw top-level '-' items
- A page now holds '# <item text>'; the old pages were empty files
- Characters other than letters, digits, . _ - become '_' in the page name and runs are squeezed: "What's new" was gen_what's_new.md and is now gen_what_s_new.md; two spaces give one '_'; capital letters outside A-Z are no longer lower-cased
- Items that already hold a link are left alone; text outside list items (titles, paragraphs) is never linked
- The three-argument form reads and writes inside DIR whatever the current folder is, and leaves no .bak file
- It prints which pages it created and a count; wrong usage exits 2

### mbm-docker-cmdline

`mbm-docker-cmdline [-e ENGINE] CONTAINER...`

Old version: **worked with defects**. Found:

- A null entrypoint or command (every image with only a CMD) prints a jq error on standard error; the other half is still printed, so the coordinator's hint 'prints an error instead of the command' is only half right
- The result is echoed unquoted: a * in an argument is replaced by the file names of the current folder and runs of spaces are squeezed
- Arguments are joined with plain spaces, so the line cannot be pasted back when an argument holds a space or a quote
- Exit status 0 for a container that does not exist, for no argument, and when jq is missing
- Needs jq, which older macOS and many Linux systems do not have
- No help: --help is looked up as a container; two docker calls per container

What behaves differently now:

- Arguments that need it are now quoted (nginx -g 'daemon off;' instead of nginx -g daemon off;)
- Exit status is 1, not 0, when the container does not exist
- No argument is an error (exit 2) instead of an empty line
- With more than one container each output line starts with 'NAME: '
- jq is no longer used

### mbm-docker-compose-start-services

`mbm-docker-compose-start-services [-b BASE_DIR] [-e ENGINE] [-n] PROJECT...`

Old version: **worked with defects**. Found:

- Only docker-compose.yml is recognised; compose.yaml (the name Docker recommends), compose.yml and docker-compose.yaml are reported as missing
- The exit status is that of the last project only: 0 when an earlier project was missing or failed
- The base folder ~/git-repos is fixed
- No arguments does nothing, silently, with exit 0
- Warnings go to standard output
- No help, no way to list the projects, no dry run

What behaves differently now:

- Compose now runs inside the project folder without -f, so a compose.override.yaml / docker-compose.override.yml next to the file is merged, as with 'docker compose up -d' typed by hand; the old '-f docker-compose.yml' ignored override files
- Folders with compose.yaml, compose.yml or docker-compose.yaml are now started instead of skipped
- Exit status 1 when any project was missing or failed (was the status of the last docker call)
- No arguments is an error (exit 2)
- Warnings go to standard error and are worded differently; the progress line is 'Starting project NAME (DIR)'
- A name containing a slash is a path, not a sub-folder of the base folder

### mbm-docker-compose-stop-services-all

`mbm-docker-compose-stop-services-all [-s] [-n] [-y] [-e ENGINE]`

Old version: **worked with defects**. Found:

- Asked for --help (or given any argument) it takes every project down
- 'down' removes the containers and networks of every running project immediately: nothing is listed first and nothing is asked
- The exit status is that of the last project only; a failing 'compose ls' (Docker not running) gives exit 0
- The names are cut out of the human-readable table with awk instead of 'compose ls -q'
- No way to only stop the containers and keep them

What behaves differently now:

- It now asks before doing anything; a script or cron job that called it must add --yes (without a terminal it refuses)
- An argument is an error (exit 2) instead of being ignored
- Output is different: a list of the projects, then 'Project NAME: down' per project
- Exit status 1 when any project failed, or when the answer was no

### mbm-delete-old-models

`mbm-delete-old-models [-d DAYS] [-n] [-y]`

Old version: **worked with defects**. Found:

- Unit 'week(s)' is unknown and counts as 0 seconds, so every model shown as 'N weeks ago' is kept; days and months are deleted correctly, so the gap is in the middle of the range the script exists for (as far as I remember ollama's code that is 14 to 59 days; not checked against a real ollama)
- It deletes immediately: nothing is listed first, nothing is asked, and --help or any argument does the same
- 'About a minute' / 'About an hour' / 'Less than a second' put a word where a number is expected; they give the right answer only because the word counts as 0
- The threshold of one week is fixed
- Exit status 0 when ollama is not running or a delete fails
- Nothing says that MODIFIED is the pull date, not the last use

What behaves differently now:

- Models shown as 'N weeks ago' are now deleted (the old version kept them)
- It asks before deleting; a script or cron job that called it must add --yes
- The per-model lines 'Keeping model: ...' are gone: only the models to delete are listed
- An argument is an error (exit 2)
- Exit status 1 when ollama fails, a delete fails, or the answer was no

### mbm-lima-podman-w-target

`mbm-lima-podman-w-target [-v VOLUME] [-e NAME] [-c SIZE] [--no-test] [-n]`

Old version: **could not run**. Found:

- -h exits 1 and --help is an error
- LIMA_HOME is exported inside the script only; it prints 'Set LIMA_HOME to: ...' and never says that the calling shell does not have it, so a later limactl in that shell looks in ~/.lima
- LIMA_HOME is assumed to be /Volumes/NAME; it is not taken from what hdiutil mounted, so an image whose volume has another name (or mounts as 'NAME 1') gives a wrong LIMA_HOME
- By reading, not run: on a new image there is no machine yet, and 'limactl start podman' then creates a machine named podman from Lima's DEFAULT template (as I remember Lima's start command; its docs say to use the template form for the first start), which has no podman socket - although the script itself offers to create a new image
- When the image is missing it asks for a path and creates the image THERE, not where the next run will look for it
- A failed test container is only a warning with exit 0; the test container is left behind on every run (no --rm)
- Errors go to standard output; a surplus argument is ignored; no dry run; nothing refuses on Linux

What behaves differently now:

- When the image is missing it no longer asks for a path: it stops and says to add -c SIZE, which creates the image at /Volumes/VOLUME/NAME.sparsebundle
- A failed test container is now an error (exit 1) and the container is removed after the test (--rm)
- On an image without a machine it now creates one from Lima's podman template instead of running 'limactl start podman'
- A machine that is already running is not started again
- LIMA_HOME follows the folder hdiutil reports instead of always /Volumes/NAME
- -h exits 0; a surplus argument is refused; the output is the list of commands instead of the 'Using volume: ...' lines

### mbm-sdd

`mbm-sdd [DIR] [-- MKDOCS_ARGUMENTS...]`

Old version: **worked with defects**. Found:

- Folder fixed to ~/git-repos/docker; every argument is ignored, so no way to pass an address or port to mkdocs
- --help (and any other argument) starts mkdocs serve
- A project without .venv prints a raw shell error and carries on
- A missing folder or missing mkdocs gives raw zsh errors, no explanation
- No check that the folder is a mkdocs project

What behaves differently now:

- Arguments now mean something: a first argument is the project folder, and anything else before -- is refused with exit 2 (the old script ignored all arguments)
- Prints one extra line ('<name>: serving DIR with /path/to/mkdocs - Ctrl-C stops it') before mkdocs starts
- A project without .venv no longer prints a shell error; it uses the mkdocs on the PATH silently
- The venv is no longer 'activated' by sourcing its activate file (no PS1 change etc.); only PATH and VIRTUAL_ENV are set for mkdocs
- A folder without mkdocs.yml is refused instead of letting mkdocs fail

### mbm-srd

`mbm-srd [-n] [DIR]`

Old version: **worked with defects**. Found:

- Folder fixed to ~/git-repos/mydocs; arguments ignored
- --help (and the word 'down') runs 'docker compose up -d'
- Sources a Python venv that has no effect on docker compose, and prints a raw shell error when it is missing
- No way to stop what it started; no status shown
- No check for a compose file or for docker; raw shell errors

What behaves differently now:

- The Python venv in the project is no longer activated (it never affected docker compose); a project without .venv no longer prints an error
- After starting, the service list ('docker compose ps') is printed
- An extra, read-only 'docker compose version' call runs before the real one
- Arguments now mean something: the first is the folder; an unknown option exits 2 (the old script ignored everything)
- A folder without a compose file is refused before docker is called

### mbm-run-docker-web

`mbm-run-docker-web [-d PROJECT_DIR] [-u USER] [-t REMOTE_DIR] [-p PORT] [-n] HOST [PORT]`

Old version: **broken**. Found:

- The default port never applies ('port=$2 || 5500'): with HOST alone docker gets '-p :80', a random host port
- No argument check: with no HOST it builds and runs rsync/ssh against 'vm@'; --help is taken as the host name
- Nothing stops after a failure: a failed build or a failed rsync is followed by the next steps, and the exit status is 0
- When the project folder is missing, 'mkdocs build' runs in whatever folder the user is in
- Remote user 'vm' and mount path /home/vm/docker are fixed
- Every run starts a new anonymous container; nothing replaces the old one
- Shares the remote folder ~/docker with mbm-run-docker-web3, so two sites on one host overwrite each other and both containers serve the mixture

What behaves differently now:

- With HOST alone the site is published on port 5500 (before: a random port, because the port was empty)
- The container is named docs-web-PORT, is no longer started with --rm, and an earlier container of that name is removed first. A container started by the OLD script is anonymous: it keeps the port until removed by hand, and the new run then fails with a hint
- The nginx container mounts the real path of the remote folder instead of /home/vm/docker
- The remote folder is named after the project folder (unchanged, ~/docker, for the default project)
- It stops with exit 1 when mkdocs build, rsync or the remote docker fails (before: went on, exit 0)
- No HOST, a third argument, a bad port or an unknown option exit 2 and run nothing
- Progress lines ('1/3 building ...') and a final line with the URL are printed
- A project without .venv no longer prints a shell error

### mbm-run-docker-web3

`mbm-run-docker-web3 [options] HOST [PORT]`

Old version: **broken**. Found:

- A copy of mbm-run-docker-web with one path changed: every defect of that script
- It copies into the same remote folder ~/docker as the first site, so on one host each deploy overwrites the other site's files

What behaves differently now:

- The site is copied to ~/docker-v3 on the remote instead of ~/docker (so it no longer overwrites the first site); the old ~/docker content stays where it is
- Everything listed for run-docker-web: default port 5500, container docs-web-PORT replaced on rerun and no longer --rm, stops at the first failing step, exit 2 on wrong use, progress lines
- Errors that come from the shared implementation carry the name mbm-run-docker-web

### mbm-logger

`mbm-logger [-d DIR]`

Old version: **worked with defects**. Found:

- Fails when ~/Documents/Temp/TerminalLogs does not exist; never creates it
- File name runs date and time together (terminal_2026-11-14175254.log)
- --help and any other argument start a recording
- Says nothing itself about where the log goes or how to stop
- Folder fixed; absolute /usr/bin/script and /bin/date (wrong on some Linux systems)
- Started inside a recording it records again; a second start in the same second would overwrite the first log

What behaves differently now:

- The log name has an underscore between date and time: terminal_2026-11-14_171500.log (before: terminal_2026-11-14171500.log)
- The folder is created when missing (before: an error)
- New logs are created with mode 600 and a newly created folder with mode 700 (before: the user's umask, usually 644)
- Two lines are printed before the recording starts
- Started inside a recording (SCRIPT is set) it refuses with exit 1 (before: it recorded inside the recording)
- An argument that is not an option exits 2 (before: ignored)

### mbm-nextra-setup

`mbm-nextra-setup [options] [PROJECT_DIR]`

Old version: **worked with defects**. Found:

- No help: --help tries to create a project called --help and dies in mkdir (exit 64)
- "Overwrite" means rm -rf of the whole existing folder after one keypress; a piped 'y' deletes it with no terminal involved
- The sample API page is written to pages/api/, which Next.js reserves for request handlers: Nextra ignores it and /api answers 500, while the home page and the sidebar link to it
- Dockerfile runs `npm ci` but no package-lock.json is generated: the image cannot build until something else has run npm install (verified: npm ci fails with EUSAGE)
- package.json has an `export` script (`next export`) that Next 14 no longer has
- Versions are caret ranges two majors behind (Nextra 2 / Next 14 / React 18); container images are node:18-alpine (end of life; current Next.js needs Node 20.9+)
- package.json name is always nextra-docs whatever folder is given; container names are fixed (nextra-docs, nextra-nginx), so two projects collide
- The compose 'production' profile is nginx in front of the development server, not a production build
- Colour escape codes are printed even when the output is not a terminal; the script runs chmod +x on itself at the end
- Hint checked and not a defect: next.config.js does ask for output: 'standalone'

What behaves differently now:

- The generated project is Nextra 4 / Next.js 16 / React 19 with pages in content/ and configuration in app/layout.jsx; there is no pages/ folder, no theme.config.tsx, no next.config.js, no TypeScript dependencies and no components/ folder
- An existing folder is never deleted. Before: asked 'overwrite? (y/N)' and removed the folder. Now: asks whether to write into it, replaces only same-named files, and refuses without a terminal unless --yes is given
- No nginx.conf and no nginx 'production' profile on port 8080; docker-compose.yml has one service (the development server). Production is the image built from the Dockerfile
- package.json name and the container names follow the folder name instead of always being nextra-docs
- Container images are node:24-slim instead of node:18-alpine
- package.json has no `export` script; `dev` and `start` no longer pass -H 0.0.0.0 (Next.js listens on all interfaces by default)
- Output is plain text: 'Wrote 19 files into DIR ...' and two next-step lines, instead of coloured [INFO] lines
- A second argument, an empty name, a bad port or an unknown option is an error (exit 2); before, extra arguments were ignored

### mbm-nextra-setup-w-podman

`mbm-nextra-setup-w-podman [options] [PROJECT_DIR]`

Old version: **worked with defects**. Found:

- Everything listed for mbm-nextra-setup (no help, rm -rf on 'overwrite', /api page answers 500, npm ci without a lock file, old caret versions, node:18-alpine, fixed names)
- The runner mounts `-v .:/app`: called from another folder it mounts that folder, not the project
- `podman-run.sh cleanup` runs `podman image prune -f` and `podman volume prune -f`, which remove every unused volume and dangling image on the machine, not just this project's
- `prod` starts the development server behind nginx; the Dockerfile it writes is never used by the runner
- Fixed container, network and volume names (nextra-docs, nextra-nginx, nextra-network): a second project stops and replaces the first one's container
- The runner and README advertise things nothing implements (systemd service generation, node_modules_cache / next_cache folders that are never created and always show as missing in `status`)
- About 480 lines of runner with emoji and colour for seven commands

What behaves differently now:

- Everything listed for mbm-nextra-setup (Nextra 4 project layout, no folder deletion, confirmation or --yes for a non-empty folder, names from the folder, node:24-slim)
- podman-run.sh: `prod` now builds and runs the production image instead of the dev server behind nginx on port 8080; there is no nginx container and no nextra-network
- podman-run.sh: the commands rebuild/restart and fix-perms, and the aliases develop, up, down, production, log, clean, ps, are gone; an unknown command exits 2
- podman-run.sh: cleanup no longer runs `podman image prune` / `podman volume prune`
- podman-run.sh: the same container setup on macOS and Linux (bind mount plus a node_modules volume, `npm install && npm run dev` inside); no --userns=keep-id, no --restart unless-stopped, no separate install container
- No PODMAN_GUIDE.md and no nginx.conf in the project

### mbm-eth-conv

`mbm-eth-conv [-j] [-t N] FILE`

Old version: **broken**. Found:

- Calls gawk, which a stock Mac does not have: no output, exit 127. Plain awk runs the same program.
- --help and -h are taken as a file name (exit 1); usage errors exit 1 and go to standard output
- No check that tshark is installed; a tshark failure is not noticed (the pipeline reports awk's status)
- Output is one JSON object per line in awk's arbitrary order: not a table and not one JSON document
- A frame without an Ethernet header becomes a pair of two empty addresses
- From reading the code, not run on ORIG: a frame with Ethernet inside a tunnel makes tshark print 'outer,inner' in each field, and the script splits its key on commas. In the new script, dropping '-E occurrence=f' makes my real-tshark GRE check fail.

What behaves differently now:

- Default output is a table, not one JSON object per line; the JSON form needs -j and is one array (each object still on its own line, same keys)
- Lines are sorted by frame count, then address; before the order was arbitrary
- Frames without an Ethernet header no longer appear as a pair of empty addresses
- Usage errors exit 2 (before 1) and are written to standard error
- An unreadable capture file now exits 1 (before 0 with empty output)

### mbm-extract-time-info-w-tshark

`mbm-extract-time-info-w-tshark FILE...`

Old version: **broken**. Found:

- With the installed tshark (ISO time text) the date parse fails: error messages, an empty 'Elapsed:', and still exit 0
- Even with the old time text: elapsed wraps after 24 hours (25 h shown as 01:00:00), the fraction of a second is dropped with a warning per time, and the English month name does not parse under a Turkish locale
- Reads the capture three times (first frame, all frame numbers, a filtered pass)
- date -j -f is macOS only
- --help and -h are taken as a file name; no tshark check; one file only

What behaves differently now:

- Output layout is new: a 'File:' line first, times as 'YYYY-MM-DD HH:MM:SS.nnnnnnnnn +ZZZZ  (… UTC)' instead of tshark's own text, 'Elapsed:' with days and nanoseconds plus seconds in brackets, and a new 'Packets:' line. The labels 'First packet:', 'Last packet:' and 'Elapsed:' are kept.
- Accepts several files (before exactly one)
- First/Last are the earliest/latest time stamp, not the first/last frame in file order (the same for an ordinary capture)
- Usage errors exit 2 and go to standard error; an unreadable file exits 1

### mbm-sslkeylog-capture

`mbm-sslkeylog-capture [-b chrome|firefox] [-i INTERFACE | -r] [-f FILTER] [-d SECONDS] [-o DIR]`

Old version: **worked with defects**. Found:

- --help is refused ('Unknown option: --', exit 1); only -h works
- When tshark cannot start (for example no capture permission) it prints the error, then the normal 'Session finished' summary naming files that do not exist, and exits 0
- A TERM signal during -d SECONDS is not acted on until the sleep ends (29 s in the test)
- -d 0 stops at once although the code comment says 0 means wait; a non-numeric -d gives a sleep error and exit 0
- At the end it runs pkill -f for BOTH browsers' profile folders, also when no browser was started, with the folder name used as an unescaped regular expression (a '|' in the folder name would widen the match)
- Browser programs are fixed macOS paths; the default route lookup is macOS only
- The built-in default folder is named after the command with its prefix
- No umask: the key log, which decrypts the capture, gets the default file mode

What behaves differently now:

- Default folder without MBM_SSLKEYLOG_DIR is ~/.local/share/sslkeylog-capture (before: ~/.local/share/mbm-sslkeylog-capture). Sessions and browser profiles in the old folder are not found there; move the folder or set MBM_SSLKEYLOG_DIR.
- Unknown option, -b other than chrome/firefox, non-numeric -d and a surplus argument exit 2 (before 1 or 0)
- Capture cannot start: exit 1 and no summary (before exit 0 with a summary)
- Capture died during the session: exit 1 with a message (before exit 0)
- -d 0 waits for Enter (before: stopped at once)
- Refuses to start when a browser of an earlier session still runs on the same profile folder
- New files and folders are created private (umask 077)
- No default route: tshark chooses the interface (before: en0)
- Without -b and without a terminal the 'Which browser?' menu is no longer printed; chrome is used as before
- Screen output is reworded and shorter; the final lines say 'TLS keys:' and 'Capture:'
- With MBM_SSLKEYLOG_CHROME or MBM_SSLKEYLOG_FIREFOX set, that program is started instead of the app in /Applications

### mbm-print-route

`mbm-print-route [-6] [-a] [-i IFACE]`

Old version: **broken**. Found:

- The argument is appended unquoted to a pattern right after the gateway column, so on macOS it filters on the Flags text; an interface name such as en0 never matches
- Prints a single line, whichever sorts last by gateway; default routes can never match (the pattern wants a numeric destination)
- Exit status is always 0, also when nothing is printed
- No help: --help prints nothing

What behaves differently now:

- Without an argument it prints the whole IPv4 table with a header line, not one line
- An argument is now a destination (address or host name), no longer a text matched against the Flags column: `mbm-print-route UGSc` now fails with exit 1
- Output columns are destination, gateway, interface; the flags are no longer printed
- Exit status 1 when no route is found (was always 0)
- macOS neighbour and cloned host entries are hidden unless -a is given

### mbm-interface-test

`mbm-interface-test [-t SECONDS] [-n] [-y] IFACE`

Old version: **worked with defects**. Found:

- --help (any argument) takes the interface down
- Interrupted during the wait, the interface stays down
- Interface name ens160 and the 60 seconds are fixed in the code
- Needs ifconfig, which current Linux distributions do not install
- No checks: prints Done. and exits 0 even when sudo or ifconfig failed; a missing interface is not noticed
- Two separate sudo calls: the second one, 60 seconds later, can need a password again

What behaves differently now:

- Called without an argument it now exits 2; the old default ens160 is gone (use `mbm-interface-test ens160`)
- It asks before taking the interface down; in a script or over a pipe add --yes
- On Linux it uses ip instead of ifconfig when ip is installed
- sudo is called once, for the command itself, instead of twice for ifconfig
- An interface that does not exist or is already down is refused with exit 1
- Exit status is no longer always 0: 1 on failure, 2 on wrong use, 130/143/129 after INT/TERM/HUP (with the interface up again)
- Messages changed

### mbm-dns-flush

`mbm-dns-flush`

Old version: **worked with defects**. Found:

- An unknown option or any argument is ignored and the flush runs; -h works only as the first argument
- Claims `DNS cache flushed` with exit 0 when `sudo dscacheutil -flushcache` failed but the service restarted
- When sudo fails it still waits 10 seconds before saying the service was not restarted, and does not say which step failed
- Help has no Usage and Examples sections; prefix rewriting only for its own name

What behaves differently now:

- An unknown option or an argument is now exit 2; before, the flush ran anyway
- When a sudo step fails it exits 1 immediately and names the step; before, it could report success (flush failed, service restarted) or wait 10 seconds first
- The not-restarted message now reads `... was not restarted within 10 seconds (...)`

### mbm-help

`mbm-help [-c] [WORD]`

Old version: **worked with defects**. Found:

- An unknown option is taken as the search word: prints nothing, exit 0
- Nothing matches: prints nothing, exit 0; a second word is silently ignored
- A folder (anything) whose name starts with the prefix is listed as a command
- Help has no Usage and Examples sections; only its own name is rewritten for another prefix
- Runs one awk per command over two files and a grep per line; name column fixed at 40 characters

What behaves differently now:

- No match now prints `no command matches "WORD"` on standard error and exits 1 (was silent, exit 0)
- An unknown option is exit 2 (was treated as the search word); more than one word is exit 2 (extra words were ignored)
- The description column starts two spaces after the longest name instead of at a fixed column 41
- Folders whose name starts with the prefix are no longer listed; a command without a description is printed without trailing spaces

### mbm-sync-git-msp

`mbm-sync-git-msp [options]`

Old version: **broken**. Found:

- Plain sync and --watch abort under the stock macOS bash 3.2 (empty array expanded with set -u); only --dry-run works there
- --help fails with exit 1 when the source folder is missing, and creates the log folder and a log file
- Only the first argument is looked at; a second option is silently ignored
- Colour escape codes are printed even when the output is not a terminal; errors go to standard output
- Passes --delete but the header comment does not say that remote files are deleted (only show_help mentions 'mirror with --delete')
- No way to choose source, host, user or destination except through the environment; no guard against an empty source folder or a destination that is the whole remote home
- A source setting without a trailing slash makes rsync create a subfolder and delete everything else in the destination
- Watch: only 8 of the 20 excludes are given to fswatch; each queued event batch causes its own sync; changes during the first sync are missed; killing the script leaves fswatch and the loop running (read from the code and seen with the same pipeline in my first rework)
- The log file name is fixed at start, so a watch that runs past midnight keeps writing into the old day's file (read from the code, not run)

What behaves differently now:

- A real sync now asks 'Mirror SRC to DEST? ... [y/N]' on a terminal and refuses (exit 1) without --yes when standard input is not a terminal - a cron or launchd job needs --yes
- Exit status is 1 for any rsync failure (rsync's own code is in the message and the log) instead of rsync's code; wrong usage and a missing host are exit 2 instead of 1
- An empty source folder is refused (exit 1); --dest '', '.', '/', '~' is refused (exit 2)
- MBM_SYNC_SOURCE_DIR without a trailing slash now sends the folder's contents (before, rsync made a subfolder of that name in the destination)
- The rsync command line gains '--' before the paths and the source is always an absolute path
- Output has no colours; line wording changed ('[INFO] SRC -> DEST', '[OK] done in Ns'); the full command appears only in the log as a [RUN] line; failures are reported on standard error
- An unknown option no longer prints the whole help and no longer writes to the log
- --dry-run --watch now does both (each sync is a dry run); before, the second option was ignored
- Watch: several changes within a second make one sync instead of one each; fswatch is called with -o -r -E and 20 exclude expressions instead of 8; the command ends with exit 1 when fswatch fails
- --help no longer needs the source folder or a host and creates nothing

### mbm-sync-git-msp-v2

`mbm-sync-git-msp-v2 [options]`

Old version: **broken**. Found:

- Plain sync and --watch abort under bash 3.2 (empty array with set -u); the abort leaves a temp file behind
- --help and --history fail without the source folder or a host; --help creates stats.csv and a log file
- Always passes --info=progress2, which needs rsync 3.1: with the rsync that macOS ships (openrsync; its usage text has no --info) every run would fail
- The history numbers are wrong with rsync 3: -h makes rsync print 12.35M, and stripping non-digits turns that into 1235; a file count of 1,234 is recorded as 1; the rate is stored as text like 700.82K
- --history prints broken units ('105.0 B KB MB GB TB', or none) because awk's split uses the comma separator
- Dry runs are recorded in the history as if they were syncs
- The dry run lists no files (no -v), so it does not show what would be sent or deleted
- Progress lines with carriage returns are appended to the daily log
- Same argument, colour, --delete documentation and watch defects as sync-git-msp

What behaves differently now:

- Everything listed for sync-git-msp (asks before a real sync, --yes needed without a terminal, exit codes 0/1/2, empty source and whole-home destination refused, trailing-slash handling, no colours, combined options, watch coalescing)
- rsync is called without --human-readable; with an rsync older than 3.1 or openrsync it gets --progress instead of --info=progress2
- --dry-run now passes -v --dry-run (file list, no progress line), prints no summary and is no longer recorded in the history
- New history rows hold real byte counts and a numeric rate; rows written by the old version stay as they are and still show their old (wrong) values
- --history has a different layout (ENDED SECONDS SENT DELETED BYTES SENT RATE EXIT), works without a host, and does not create the file
- The run summary is one [STAT] line instead of ten
- The daily log no longer contains progress lines
- With an old rsync the deleted-files number is counted from the 'deleting' lines rsync prints, since those versions do not report it

### mbm-my-sync

`mbm-my-sync [options] SRC DST`

Old version: **broken**. Found:

- On macOS it cannot run: inotifywait does not exist there; it prints 'command not found' and exits 0 having copied nothing
- Nothing is copied until the first change (no first sync)
- --delete is always on: a wrong destination loses files, with no dry run and no question
- A source folder that does not exist ends with exit 0 and no message
- --help is treated as a wrong argument count (exit 1); usage text shows the full path of the script
- The four-argument form assigns to USER, the shell's own exported variable, so rsync and ssh run with a changed USER
- From reading the code, not run for real: inotifywait without -e fires on every event including reads, and is restarted for each change, so a change made while rsync runs is missed

What behaves differently now:

- Files that disappear from SRC are no longer removed from DST unless -D is given; -D asks first (or needs --yes)
- It copies immediately when started; the old one waited for the first change
- On macOS it now works (with fswatch); on Linux fswatch is preferred when both watchers are installed
- inotifywait is now run once in monitor mode for modify/create/delete/move/attrib only; reads no longer trigger a copy
- Changes less than a second apart are copied together, so a copy starts about one second after the last change
- A wrong number of arguments exits 2 (was 1); a missing source folder exits 1 with a message (was 0)
- Ctrl-C ends with 'stopped' on standard error and exit 0; the watcher ending by itself is exit 1
- The four-argument form no longer changes USER for the programs it starts

### mbm-my-sync-fswatch

`mbm-my-sync-fswatch [options] USER HOST REMOTE_FOLDER`

Old version: **broken**. Found:

- ssh -N runs no remote command, so the remote fswatch is never started and no change line can ever arrive
- Even with change lines, `read path` in zsh overwrites PATH, so rsync is 'command not found' every time
- No first pull: nothing is copied until a change
- A port forward to local port 1234 and a remote socat that nothing listens to
- rsync ran with StrictHostKeyChecking=no and a forced -p 22
- --help is a usage error (exit 1); no option for the local folder; a user argument such as -oProxyCommand=... is handed to ssh unchecked

What behaves differently now:

- It works now; the old one never pulled anything
- StrictHostKeyChecking=no is gone: an unknown or changed host key is now asked about or refused by ssh, as usual. Connect once by hand first
- The forced port 22 is gone: the port now comes from ~/.ssh/config like every other ssh setting
- The other machine needs fswatch or inotifywait (the old one asked for fswatch and socat)
- It pulls once immediately when started
- It is a bash script now, not zsh
- Exit status 2 for wrong arguments (was 1); a user name that is empty or starts with a dash is refused

### mbm-copy-zsh-settings

`mbm-copy-zsh-settings [options]`

Old version: **broken**. Found:

- On a stock Mac (/bin/bash 3.2) it dies silently at the first ssh, exit 1, for every real use
- --dry-run creates folders on the remote (mkdir -p over ssh)
- The oh-my-zsh install command line is wrong and always fails (exit 127) after the backup was made, so nothing is copied to a machine without oh-my-zsh
- It tries to install oh-my-zsh even when this machine does not use it; the user is told in one log line, the question does not mention that a script is fetched from the network and run
- No terminal: a `y` on a pipe is taken as consent, empty input exits 1 without a word; there is no --yes
- The host comes only from MBM_REMOTE_HOST; no option; no way to leave a file out, and .zshenv (API keys) travels with only an after-the-fact hint
- --help writes a log folder into the home folder; an unknown option exits 1 and writes a log file; colour codes are printed when the output is not a terminal
- Backup misses .oh-my-zsh/custom (which rsync overwrites) and stores .config/zsh as plain 'zsh'
- One rsync and up to two ssh connections per item, plus four ssh probes
- From reading, not run: rsync -a sends a symlinked dotfile as a symlink, which dangles on the other machine

What behaves differently now:

- Without a terminal it now refuses unless --yes is given; a `y` on a pipe no longer counts
- Answering no ends with exit 1 and 'nothing was copied' (was exit 0)
- No log file is written to ~/.local/log/copy-zsh-settings any more, and the output has no colours or timestamps
- No host is exit 2 (was 1); an unknown option is exit 2 and does nothing
- oh-my-zsh is installed on the other machine only when this machine uses it (and never with --no-omz); the old one always tried, and failed
- With --no-omz and no oh-my-zsh there, .oh-my-zsh/custom is not sent
- rsync runs as `rsync -avzL` (was `-avz --human-readable`): symbolic links are followed; all dotfiles go in one call to REMOTE: instead of one call each
- The backup holds only what is about to be replaced, under its relative path (.config/zsh is at <backup>/.config/zsh, was <backup>/zsh), and now includes .oh-my-zsh/custom
- --dry-run no longer creates folders on the other machine
- The remote login shell is read from $SHELL there instead of dscl, so a Linux machine is reported correctly
- -H USER@HOST wins over -u and MBM_REMOTE_USER

