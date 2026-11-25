# entra-ip.ps1 - the Microsoft Graph half of mbm-entra-ip. Run by that command; not on its own.
#
# Reads and changes the IP ranges of one Microsoft Entra Conditional Access named location
# through Microsoft Graph (identity/conditionalAccess/namedLocations). Needs PowerShell 7 and
# the Microsoft.Graph.Authentication module; the Graph calls are plain Invoke-MgGraphRequest.
#
# Every change shows the ranges added (+) and removed (-) first, asks (unless -Yes), saves the
# location as it was to a JSON file in -BackupDir, then writes the WHOLE new list (Graph has
# no call that adds or removes one range) and reads the location back to prove it.
#
# Exit status: 0 done (or nothing to do, or answered no), 1 failed, 2 bad input.

param(
  [Parameter(Mandatory = $true)][ValidateSet('list', 'add', 'remove', 'edit', 'restore')][string]$Action,
  [Parameter(Mandatory = $true)][string]$Location,
  [string]$Tenant = '',
  [string]$Cidrs = '',
  [string]$MyIp = '',
  [string]$BackupDir = '',
  [string]$RestoreFile = '',
  [string]$Me = 'mbm-entra-ip',
  [switch]$DryRun,
  [switch]$Yes,
  [switch]$Force,
  [switch]$DeviceCode
)

$ErrorActionPreference = 'Stop'
$Graph = 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/namedLocations'

function Say([string]$text = '') { [Console]::Out.WriteLine($text) }
function Warn([string]$text) { [Console]::Error.WriteLine("${Me}: $text") }
class BadInput : System.Exception { BadInput([string]$m) : base($m) {} }

# ---------------------------------------------------------------- ranges

# The bytes of an address with every bit after the first $prefix cleared.
function Get-Masked([byte[]]$bytes, [int]$prefix) {
  $out = [byte[]]::new($bytes.Length)
  for ($i = 0; $i -lt $bytes.Length; $i++) {
    $bits = [Math]::Min(8, [Math]::Max(0, $prefix - 8 * $i))
    $mask = if ($bits -eq 0) { 0 } else { (0xFF -shl (8 - $bits)) -band 0xFF }
    $out[$i] = $bytes[$i] -band $mask
  }
  return , $out
}

# A range from text: "203.0.113.7", "203.0.113.0/24", "2001:db8::/48". A bare address is a
# single host (/32 or /128). Host bits are cleared: 203.0.113.7/24 becomes 203.0.113.0/24.
# -Existing reads a range already in the location: it is never refused, and keeps its text.
function ConvertTo-Range([string]$text, [switch]$Existing) {
  $t = $text.Trim()
  $parts = $t.Split('/', 2)
  $addrText = $parts[0]
  $ip = $null
  $looksV4 = $addrText -match '^\d{1,3}(\.\d{1,3}){3}$'
  $looksV6 = $addrText.Contains(':') -and -not $addrText.Contains('%')
  if (-not ($looksV4 -or $looksV6) -or -not [System.Net.IPAddress]::TryParse($addrText, [ref]$ip)) {
    throw [BadInput]::new("not an IP address or range: '$t'")
  }
  $bytes = $ip.GetAddressBytes()
  $max = $bytes.Length * 8
  if ($parts.Length -eq 1) { $prefix = $max }
  elseif ($parts[1] -match '^\d{1,3}$' -and [int]$parts[1] -le $max) { $prefix = [int]$parts[1] }
  else { throw [BadInput]::new("bad prefix in '$t': it must be /0 to /$max") }
  if (-not $Existing -and $prefix -lt 8) {
    throw [BadInput]::new("'$t' is too wide: Entra accepts ranges from /8 to /$max")
  }
  $net = Get-Masked $bytes $prefix
  $cidr = '{0}/{1}' -f [System.Net.IPAddress]::new($net), $prefix
  $type = if ($max -eq 128) { '#microsoft.graph.iPv6CidrRange' } else { '#microsoft.graph.iPv4CidrRange' }
  [pscustomobject]@{
    Cidr    = $cidr
    Text    = if ($Existing) { $t } else { $cidr }
    Bytes   = $net
    Prefix  = $prefix
    V6      = ($max -eq 128)
    Type    = $type
    Cleared = (-not $Existing) -and ([System.Linq.Enumerable]::SequenceEqual($net, $bytes) -eq $false)
  }
}

# Does range $outer hold every address of range $inner?
function Test-Holds($outer, $inner) {
  if ($outer.V6 -ne $inner.V6 -or $outer.Prefix -gt $inner.Prefix) { return $false }
  $a = Get-Masked $inner.Bytes $outer.Prefix
  return [System.Linq.Enumerable]::SequenceEqual([byte[]]$a, [byte[]]$outer.Bytes)
}

function Find-Holder($ranges, $r) {
  foreach ($x in $ranges) { if (Test-Holds $x $r) { return $x } }
  return $null
}

$MyRange = $null
if ($MyIp) { try { $MyRange = ConvertTo-Range $MyIp } catch { $MyRange = $null } }

function Format-Range($r) {
  if ($MyRange -and (Test-Holds $r $MyRange)) { return "$($r.Text)    <- holds your IP $MyIp" }
  return $r.Text
}

# ---------------------------------------------------------------- Graph

function Connect-Graph([switch]$Write) {
  if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    throw "the PowerShell module Microsoft.Graph.Authentication is not installed. Install it with:`n  pwsh -c 'Install-Module Microsoft.Graph.Authentication -Scope CurrentUser'"
  }
  Import-Module Microsoft.Graph.Authentication
  $scopes = @('Policy.Read.All')
  if ($Write) { $scopes += 'Policy.ReadWrite.ConditionalAccess' }
  $ctx = Get-MgContext
  $have = if ($ctx) { @($ctx.Scopes) } else { @() }
  $tenantOk = (-not $Tenant) -or ($ctx -and $ctx.TenantId -eq $Tenant)
  if (-not $ctx -or -not $tenantOk -or @($scopes | Where-Object { $have -notcontains $_ }).Count -gt 0) {
    $connect = @{ Scopes = $scopes; NoWelcome = $true }
    if ($Tenant) { $connect.TenantId = $Tenant }
    if ($DeviceCode) { $connect.UseDeviceCode = $true }
    Connect-MgGraph @connect | Out-Null
    $ctx = Get-MgContext
  }
  if (-not $ctx) {
    $hint = if ($Tenant) { " to tenant '$Tenant'. If the browser said AADSTS90002 (tenant not found), that is not a tenant ID: a subscription ID from 'az account list' looks the same. Use the tenant's domain (name.onmicrosoft.com) or 'az account show --query tenantId'" } else { '' }
    throw "sign-in to Microsoft Graph failed or was cancelled$hint"
  }
  $missing = @($scopes | Where-Object { @($ctx.Scopes) -notcontains $_ })
  if ($missing.Count -gt 0) {
    throw "the sign-in did not grant $($missing -join ', '). An administrator must consent to it for the app 'Microsoft Graph Command Line Tools', or sign in with an account that may consent."
  }
  return $ctx
}

function Get-Location {
  $all = @()
  $uri = $Graph
  while ($uri) {
    $page = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType Hashtable
    $all += @($page.value)
    $uri = $page['@odata.nextLink']
  }
  $hits = @($all | Where-Object { $_.displayName -eq $Location })
  if ($hits.Count -eq 0) {
    $names = ($all | ForEach-Object { $_.displayName } | Sort-Object) -join ', '
    throw "no named location called '$Location'. The tenant has: $names"
  }
  if ($hits.Count -gt 1) { throw "$($hits.Count) named locations are called '$Location'; rename one in the portal first" }
  $loc = $hits[0]
  if ($loc['@odata.type'] -ne '#microsoft.graph.ipNamedLocation') {
    throw "'$Location' is not an IP ranges location (it is $($loc['@odata.type']))"
  }
  return $loc
}

function Get-Ranges($loc) {
  return @($loc.ipRanges | ForEach-Object { ConvertTo-Range $_.cidrAddress -Existing })
}

function Show-Location($loc, $ranges) {
  $trusted = if ($loc.isTrusted) { 'yes' } else { 'no' }
  Say "Named location: $($loc.displayName)   (trusted: $trusted, last changed: $($loc.modifiedDateTime))"
  Say "$($ranges.Count) IP range(s):"
  foreach ($r in $ranges) { Say "  $(Format-Range $r)" }
  if ($MyRange -and -not (Find-Holder $ranges $MyRange)) { Say "Your IP $MyIp is not in any of them." }
}

# Show the change, ask, back up, write, read back. Returns nothing; throws on failure.
function Save-Ranges($loc, $old, $new) {
  $oldKeys = @($old | ForEach-Object Cidr)
  $newKeys = @($new | ForEach-Object Cidr)
  $added = @($new | Where-Object { $oldKeys -notcontains $_.Cidr })
  $removed = @($old | Where-Object { $newKeys -notcontains $_.Cidr })
  if ($added.Count -eq 0 -and $removed.Count -eq 0) { Say 'Nothing to change.'; return }
  if ($new.Count -eq 0) { throw 'that would leave the location with no range at all; Entra does not allow it (delete the location in the portal instead)' }

  Say "Changes to '$($loc.displayName)':"
  foreach ($r in $added) { Say "  + $(Format-Range $r)" }
  foreach ($r in $removed) { Say "  - $(Format-Range $r)" }
  Say "It will then have $($new.Count) range(s)."
  if ($MyRange -and (Find-Holder $old $MyRange) -and -not (Find-Holder $new $MyRange)) {
    Warn "WARNING: your current IP $MyIp will no longer be in '$($loc.displayName)'. If a Conditional Access policy allows sign-in only from this location, you can lock yourself out."
  }
  if ($DryRun) { Say 'Dry run: nothing was changed.'; return }
  if (-not $Yes) {
    [Console]::Out.Write("Save these changes to '$($loc.displayName)'? [y/N] ")
    $a = [Console]::In.ReadLine()
    if ($a -notmatch '^(y|yes)$') { Say 'Cancelled; nothing was changed.'; return }
  }

  # Someone may have changed it since we read it (the portal, another run): then stop.
  $now = Invoke-MgGraphRequest -Method GET -Uri "$Graph/$($loc.id)" -OutputType Hashtable
  if ("$($now.modifiedDateTime)" -ne "$($loc.modifiedDateTime)") {
    throw "'$($loc.displayName)' was changed by someone else at $($now.modifiedDateTime) while this ran; nothing was written. Run the command again."
  }

  New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $safe = ($loc.displayName -replace '[^A-Za-z0-9._-]', '_')
  $backup = Join-Path $BackupDir "$stamp-$safe.json"
  $now | ConvertTo-Json -Depth 10 | Set-Content -Path $backup -Encoding utf8
  Say "Backup of the location as it was: $backup"

  $body = @{
    '@odata.type' = '#microsoft.graph.ipNamedLocation'
    ipRanges      = [object[]]@($new | ForEach-Object { @{ '@odata.type' = $_.Type; cidrAddress = $_.Text } })
  } | ConvertTo-Json -Depth 5
  Invoke-MgGraphRequest -Method PATCH -Uri "$Graph/$($loc.id)" -Body $body -ContentType 'application/json' | Out-Null

  $after = Invoke-MgGraphRequest -Method GET -Uri "$Graph/$($loc.id)" -OutputType Hashtable
  $afterRanges = Get-Ranges $after
  $got = (@($afterRanges | ForEach-Object Cidr) | Sort-Object) -join ' '
  $want = ($newKeys | Sort-Object) -join ' '
  if ($got -ne $want) { throw "Graph accepted the change but the location now reads: $got (expected: $want). Restore with: $Me restore '$backup'" }
  Say "Saved. Read back from Entra:"
  Show-Location $after $afterRanges
  Say "New sign-ins see the change within a few minutes; sessions already open keep their tokens until they refresh."
}

# ---------------------------------------------------------------- actions

# Ranges to add: skips one already in the list; skips one inside a wider range unless -Force.
function Add-To($list, [string[]]$texts) {
  $out = @($list)
  foreach ($t in $texts) {
    $r = ConvertTo-Range $t
    if ($r.Cleared) { Warn "'$t' has host bits set; using $($r.Cidr)" }
    if (@($out | ForEach-Object Cidr) -contains $r.Cidr) { Say "$($r.Cidr) is already in the list."; continue }
    $holder = Find-Holder $out $r
    if ($holder -and -not $Force) { Say "$($r.Cidr) is already covered by $($holder.Text); not added (add -f to add it anyway)."; continue }
    $out += $r
  }
  return , $out
}

function Remove-From($list, [string[]]$texts) {
  $out = @($list)
  foreach ($t in $texts) {
    $r = ConvertTo-Range $t
    $hit = @($out | Where-Object { $_.Cidr -eq $r.Cidr })
    if ($hit.Count -eq 0) {
      $holder = Find-Holder $out $r
      if ($holder) { throw [BadInput]::new("$($r.Cidr) is not in the list itself; it is inside $($holder.Text). Remove $($holder.Text) to drop it.") }
      throw [BadInput]::new("$($r.Cidr) is not in the list")
    }
    $out = @($out | Where-Object { $_.Cidr -ne $r.Cidr })
  }
  return , $out
}

function Invoke-Edit($loc, $old) {
  $work = @($old)
  $help = @'
Commands:
  a RANGE      add a range (a bare address means a single host, /32)
  d N | d RANGE  delete the range with that number, or that range
  me           add your current IP (/32)
  s            save: shows the changes and asks once more
  q            quit without saving
'@
  Say $help
  while ($true) {
    Say ''
    Say "'$($loc.displayName)' (not saved yet):"
    $oldKeys = @($old | ForEach-Object Cidr)
    $workKeys = @($work | ForEach-Object Cidr)
    for ($i = 0; $i -lt $work.Count; $i++) {
      $mark = if ($oldKeys -notcontains $work[$i].Cidr) { '+' } else { ' ' }
      Say ('  {0,2}{1} {2}' -f ($i + 1), $mark, (Format-Range $work[$i]))
    }
    foreach ($r in @($old | Where-Object { $workKeys -notcontains $_.Cidr })) { Say "      - $($r.Text)   (deleted)" }
    [Console]::Out.Write('a RANGE / d N / me / s / q > ')
    $line = [Console]::In.ReadLine()
    if ($null -eq $line) { Say ''; Say 'Quit; nothing was changed.'; return }
    $parts = @($line.Trim() -split '\s+', 2)
    $cmd = $parts[0]
    $arg = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '' }
    try {
      switch -Regex ($cmd) {
        '^$' { }
        '^(q|quit)$' { Say 'Quit; nothing was changed.'; return }
        '^(s|save)$' { Save-Ranges $loc $old $work; return }
        '^me$' {
          if (-not $MyRange) { Warn 'your IP is not known (no lookup service answered)'; break }
          $work = Add-To $work @($MyIp)
        }
        '^(a|add)$' { if (-not $arg) { Warn 'a needs a range, e.g. a 203.0.113.0/24'; break }; $work = Add-To $work @($arg) }
        '^(d|del|delete|rm)$' {
          if ($arg -match '^\d+$') {
            $n = [int]$arg
            if ($n -lt 1 -or $n -gt $work.Count) { Warn "no range number $n"; break }
            $drop = $work[$n - 1].Cidr
            $work = @($work | Where-Object { $_.Cidr -ne $drop })
          }
          elseif ($arg) { $work = Remove-From $work @($arg) }
          else { Warn 'd needs a number or a range' }
        }
        '^(\?|h|help)$' { Say $help }
        default { Warn "unknown command '$cmd' (? for help)" }
      }
    }
    catch [BadInput] { Warn $_.Exception.Message }
  }
}

try {
  $list = @()
  if ($Cidrs) { $list = @($Cidrs.Split(',') | Where-Object { $_.Trim() -ne '' }) }
  # Bad ranges are refused before any sign-in.
  foreach ($t in $list) { [void](ConvertTo-Range $t) }
  $restoreRanges = $null
  if ($Action -eq 'restore') {
    $saved = Get-Content -Raw -Path $RestoreFile | ConvertFrom-Json -AsHashtable
    if (-not $saved.ipRanges) { throw [BadInput]::new("$RestoreFile holds no ipRanges; is it a backup made by $Me?") }
    if ($saved.displayName -and $saved.displayName -ne $Location) {
      throw [BadInput]::new("$RestoreFile is a backup of '$($saved.displayName)', not of '$Location' (use -l '$($saved.displayName)')")
    }
    $restoreRanges = @($saved.ipRanges | ForEach-Object { ConvertTo-Range $_.cidrAddress -Existing })
  }

  $null = Connect-Graph -Write:($Action -ne 'list' -and -not $DryRun)
  $loc = Get-Location
  $old = Get-Ranges $loc

  switch ($Action) {
    'list' { Show-Location $loc $old }
    'add' { Save-Ranges $loc $old (Add-To $old $list) }
    'remove' { Save-Ranges $loc $old (Remove-From $old $list) }
    'edit' { Show-Location $loc $old; Invoke-Edit $loc $old }
    'restore' { Save-Ranges $loc $old $restoreRanges }
  }
  exit 0
}
catch [BadInput] {
  Warn $_.Exception.Message
  exit 2
}
catch {
  Warn $_.Exception.Message
  exit 1
}
