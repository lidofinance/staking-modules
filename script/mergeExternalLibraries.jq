# Merges the libraries deployed by a forge script into the `ExternalLibraries` key of a deployment artifact.
# Usage: jq --slurpfile tx <transactions.json> -f script/mergeExternalLibraries.jq <deploy-config.json>

def to_library:
  . as $entry
  | split(":") as $parts
  | if ($parts | length) != 3 or $parts[1] == "" or $parts[2] == ""
    then error("Invalid library entry: \($entry)")
    else { name: $parts[1], address: $parts[2] }
    end;

def to_entry:
  if (map(.address | ascii_downcase) | unique | length) > 1
  then error("Conflicting addresses for \(.[0].name): \(map(.address) | join(" and "))")
  else { key: .[0].name, value: .[0].address }
  end;

.ExternalLibraries = (($tx[0].libraries // []) | map(to_library) | group_by(.name) | map(to_entry) | from_entries)
