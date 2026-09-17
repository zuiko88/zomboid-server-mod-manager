# Zomboid Server Mod Manager

`build-mods.sh` discovers Project Zomboid mods installed on the local machine through the Steam Workshop, updates the configured server INI file setting both WorkshopItems and Mods, packages the Workshop content, and copies the generated files to a remote server. It is designed for a linux client (where this is run) and a linux server (where the files are pushed to). The mods are pushed to the server in a tar.gz that can be extracted to the zomboid server mods directory.

## What the script does

When run, the script:

1. Reads settings from `build-mods.json`.
2. Loads the configured blacklist and ignores matching mod IDs.
3. Lists the Workshop item IDs from `paths.workshop_dir` and writes them to `WorkshopItems`.
4. Searches each Workshop item for `mods/*/mod.info` files and collects each `id=` value.
5. Orders configured priority mods first, followed by the remaining discovered mods.
6. Comments out existing `WorkshopItems` and `Mods` lines in the server INI file and inserts updated values.
7. Creates the archive output directory if necessary.
8. Creates a compressed archive of the Workshop directory.
9. Copies the server configuration files and archive to the configured remote destinations.

The script expects each mod's `mod.info` file to contain an `id=` entry. Mod IDs in the blacklist are excluded, and priority IDs are only included when they are found in the Workshop content.

## Requirements

- Bash
- Python 3, used to read and validate the JSON configuration
- Standard tools: `ls`, `find`, `grep`, `cut`, `sed`, `tar`, `mktemp`, `scp`, and `ssh` tooling
- A populated Steam Workshop directory for Project Zomboid
- A writable local server configuration and archive destination
- SSH key-based access for the configured `scp` destinations

## Configuration

By default, the script reads `build-mods.json` from the same directory as the script. A different JSON file can be supplied as the first argument:

```bash
./build-mods.sh
./build-mods.sh /path/to/custom-build-mods.json
```

Paths beginning with the literal `$HOME` are expanded using the current user's home directory. Other paths are used as written.

### `paths`

| Option | Required | Description |
| --- | --- | --- |
| `workshop_dir` | Yes | Local Steam Workshop content directory. The script lists its immediate item directories and searches them for mods. |
| `ini_file` | Yes | Server INI file to update. Existing `WorkshopItems` and `Mods` entries are commented out before new values are inserted. |
| `archive` | Yes | Full local path for the generated `zomboid-mods.tar.gz` archive. Its parent directory is created automatically if needed. |
| `temp_dir` | Yes | Directory used for the temporary archive before it is moved to `archive`. |

### `remote`

| Option | Required | Description |
| --- | --- | --- |
| `configs` | Yes | `scp` destination for all files in the directory containing `ini_file`. Use normal `scp` syntax, such as `user@host:/path`. |
| `archive` | Yes | `scp` destination for the generated archive. Use normal `scp` syntax. |

### `mods`

| Option | Required | Description |
| --- | --- | --- |
| `blacklist` | Yes | JSON array of mod IDs to exclude. Matching IDs are never written to the `Mods` setting. Use an empty array when no mods should be excluded. |
| `priority` | Yes | JSON array of mod IDs to place first in the `Mods` setting. IDs not found in the Workshop content are skipped; duplicates are not added. |

## Example configuration

See the repository's [example.build-mods.json](example.build-mods.json) file for a complete configuration example.

## Notes

- The script modifies the INI file in place. Existing matching settings are preserved as commented lines.
- The archive contains the contents of `workshop_dir` itself, not the parent directory.
- The remote config copy includes every file in the directory containing `ini_file`, not only the INI file.
- The remote directories must already exist; the script creates only the local parent directory for the archive.
- The old standalone `blacklist-mods.txt` and `priority-mods.txt` files are no longer used.
