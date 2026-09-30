<#
.SYNOPSIS
    Provisions the "Purchase Requests" SharePoint list used by the purchase
    request approval automation.

.DESCRIPTION
    Creates (or updates, the script is safe to re-run):
      * The "Purchase Requests" custom list with all columns the flows rely on
      * Views: My Requests, Awaiting CEO Approval, Pending Purchase, Completed, All Requests
      * A "Submit Purchase Request" permission level (Read + Add Items)
      * A "Purchase Request Managers" SharePoint group (CEO + Finance) with Edit rights
      * Unique list permissions so requesters can submit and see only their own
        requests, but cannot change them after submission.

    Requires the PnP.PowerShell module (v2+) and an Entra ID app registration
    for interactive login. See docs/01-sharepoint-setup.md.

.EXAMPLE
    ./Deploy-PurchaseRequestList.ps1 `
        -SiteUrl "https://contoso.sharepoint.com/sites/Operations" `
        -ClientId "00000000-0000-0000-0000-000000000000" `
        -CeoEmail "ceo@contoso.com" `
        -FinanceEmails "finance1@contoso.com","finance2@contoso.com"
#>
#Requires -Modules PnP.PowerShell
[CmdletBinding()]
param(
    # SharePoint site that will host the list.
    [Parameter(Mandatory)] [string] $SiteUrl,

    # Client ID of the Entra ID app registration used by PnP.PowerShell.
    [Parameter(Mandatory)] [string] $ClientId,

    # CEO (approver). Added to the managers group.
    [Parameter(Mandatory)] [string] $CeoEmail,

    # Finance team members who make purchases and mark requests as done.
    [Parameter(Mandatory)] [string[]] $FinanceEmails,

    # Who may submit requests. Defaults to the site's Members group.
    # Accepts SharePoint group names.
    [string[]] $RequesterGroups = @(),

    [string] $ListTitle = 'Purchase Requests',
    [string] $ListUrl = 'Lists/PurchaseRequests',
    [string] $ManagersGroupName = 'Purchase Request Managers',
    [string] $SubmitRoleName = 'Submit Purchase Request',

    # Locale ID that controls the currency symbol, e.g. 1033 = USD ($),
    # 16393 = INR (₹), 2057 = GBP (£), 1031 = EUR (€), 14337 = AED.
    [int] $CurrencyLcid = 1033
)

$ErrorActionPreference = 'Stop'

Write-Host "Connecting to $SiteUrl ..." -ForegroundColor Cyan
Connect-PnPOnline -Url $SiteUrl -ClientId $ClientId -Interactive

# ---------------------------------------------------------------------------
# 1. List
# ---------------------------------------------------------------------------
$list = Get-PnPList -Identity $ListUrl -ErrorAction SilentlyContinue
if (-not $list) {
    Write-Host "Creating list '$ListTitle' ..." -ForegroundColor Cyan
    $list = New-PnPList -Title $ListTitle -Url $ListUrl -Template GenericList -EnableVersioning
}
else {
    Write-Host "List '$ListTitle' already exists, updating ..." -ForegroundColor Yellow
}

Set-PnPList -Identity $list -EnableVersioning $true -EnableAttachments $true | Out-Null
Set-PnPField -List $list -Identity 'Title' -Values @{ Title = 'Item / Service Requested' } | Out-Null

# ---------------------------------------------------------------------------
# 2. Columns
#    ShowInNewForm="FALSE" hides workflow/finance columns from requesters when
#    they submit. They remain editable for managers in the edit form.
# ---------------------------------------------------------------------------
$fields = @(
    @{ Name = 'ItemDescription'; Xml = '<Field Type="Note" Name="ItemDescription" StaticName="ItemDescription" DisplayName="Description" NumLines="6" RichText="FALSE" Required="TRUE" />' }
    @{ Name = 'Quantity'; Xml = '<Field Type="Number" Name="Quantity" StaticName="Quantity" DisplayName="Quantity" Min="1" Decimals="0" Required="TRUE"><Default>1</Default></Field>' }
    @{ Name = 'EstimatedCost'; Xml = "<Field Type=`"Currency`" Name=`"EstimatedCost`" StaticName=`"EstimatedCost`" DisplayName=`"Estimated Total Cost`" Min=`"0`" Decimals=`"2`" LCID=`"$CurrencyLcid`" Required=`"TRUE`" />" }
    @{ Name = 'Vendor'; Xml = '<Field Type="Text" Name="Vendor" StaticName="Vendor" DisplayName="Preferred Vendor / Link" MaxLength="255" />' }
    @{ Name = 'Justification'; Xml = '<Field Type="Note" Name="Justification" StaticName="Justification" DisplayName="Business Justification" NumLines="6" RichText="FALSE" Required="TRUE" />' }
    @{ Name = 'Department'; Xml = '<Field Type="Choice" Name="Department" StaticName="Department" DisplayName="Department" Format="Dropdown" FillInChoice="TRUE" Required="TRUE"><CHOICES><CHOICE>Administration</CHOICE><CHOICE>Finance</CHOICE><CHOICE>HR</CHOICE><CHOICE>IT</CHOICE><CHOICE>Marketing</CHOICE><CHOICE>Operations</CHOICE><CHOICE>Sales</CHOICE><CHOICE>Other</CHOICE></CHOICES></Field>' }
    @{ Name = 'NeededBy'; Xml = '<Field Type="DateTime" Name="NeededBy" StaticName="NeededBy" DisplayName="Needed By" Format="DateOnly" />' }
    @{ Name = 'Urgency'; Xml = '<Field Type="Choice" Name="Urgency" StaticName="Urgency" DisplayName="Urgency" Format="Dropdown" FillInChoice="FALSE"><Default>Normal</Default><CHOICES><CHOICE>Low</CHOICE><CHOICE>Normal</CHOICE><CHOICE>High</CHOICE><CHOICE>Critical</CHOICE></CHOICES></Field>' }

    # --- Workflow columns (hidden on the new form) -------------------------
    @{ Name = 'RequestStatus'; Xml = '<Field Type="Choice" Name="RequestStatus" StaticName="RequestStatus" DisplayName="Status" Format="Dropdown" FillInChoice="FALSE" ShowInNewForm="FALSE"><Default>Submitted</Default><CHOICES><CHOICE>Submitted</CHOICE><CHOICE>Pending CEO Approval</CHOICE><CHOICE>Approved - Pending Purchase</CHOICE><CHOICE>Purchased</CHOICE><CHOICE>Rejected</CHOICE><CHOICE>Approval Expired</CHOICE><CHOICE>Cancelled</CHOICE></CHOICES></Field>' }
    @{ Name = 'CEOComments'; Xml = '<Field Type="Note" Name="CEOComments" StaticName="CEOComments" DisplayName="CEO Comments" NumLines="4" RichText="FALSE" ShowInNewForm="FALSE" />' }
    @{ Name = 'DecisionDate'; Xml = '<Field Type="DateTime" Name="DecisionDate" StaticName="DecisionDate" DisplayName="CEO Decision Date" Format="DateTime" ShowInNewForm="FALSE" />' }

    # --- Finance columns (hidden on the new form) --------------------------
    @{ Name = 'PurchasedOn'; Xml = '<Field Type="DateTime" Name="PurchasedOn" StaticName="PurchasedOn" DisplayName="Purchased On" Format="DateOnly" ShowInNewForm="FALSE" />' }
    @{ Name = 'PONumber'; Xml = '<Field Type="Text" Name="PONumber" StaticName="PONumber" DisplayName="PO / Invoice Number" MaxLength="100" ShowInNewForm="FALSE" />' }
    @{ Name = 'ActualCost'; Xml = "<Field Type=`"Currency`" Name=`"ActualCost`" StaticName=`"ActualCost`" DisplayName=`"Actual Cost`" Min=`"0`" Decimals=`"2`" LCID=`"$CurrencyLcid`" ShowInNewForm=`"FALSE`" />" }
    @{ Name = 'FinanceNotes'; Xml = '<Field Type="Note" Name="FinanceNotes" StaticName="FinanceNotes" DisplayName="Finance Notes" NumLines="4" RichText="FALSE" ShowInNewForm="FALSE" />' }

    # --- System columns maintained by the flows ----------------------------
    @{ Name = 'ReminderCount'; Xml = '<Field Type="Number" Name="ReminderCount" StaticName="ReminderCount" DisplayName="Reminders Sent" Decimals="0" ShowInNewForm="FALSE" ShowInEditForm="FALSE"><Default>0</Default></Field>' }
    @{ Name = 'LastReminder'; Xml = '<Field Type="DateTime" Name="LastReminder" StaticName="LastReminder" DisplayName="Last Reminder" Format="DateTime" ShowInNewForm="FALSE" ShowInEditForm="FALSE" />' }
    @{ Name = 'CompletionNotified'; Xml = '<Field Type="Boolean" Name="CompletionNotified" StaticName="CompletionNotified" DisplayName="Completion Notified" ShowInNewForm="FALSE" ShowInEditForm="FALSE"><Default>0</Default></Field>' }
)

foreach ($f in $fields) {
    $existing = Get-PnPField -List $list -Identity $f.Name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  Column '$($f.Name)' exists, skipping" -ForegroundColor DarkGray
        continue
    }
    Write-Host "  Adding column '$($f.Name)'" -ForegroundColor Green
    Add-PnPFieldFromXml -List $list -FieldXml $f.Xml | Out-Null
}

# Index the column used by every flow filter so queries stay fast past 5,000 items.
Set-PnPField -List $list -Identity 'RequestStatus' -Values @{ Indexed = $true } | Out-Null

# ---------------------------------------------------------------------------
# 3. Views
# ---------------------------------------------------------------------------
$viewFieldsBase = @('ID', 'LinkTitle', 'Author', 'Department', 'EstimatedCost', 'Urgency', 'RequestStatus', 'Created')

$views = @(
    @{
        Title  = 'My Requests'
        Fields = @('ID', 'LinkTitle', 'EstimatedCost', 'RequestStatus', 'CEOComments', 'PurchasedOn', 'Created')
        Query  = '<Where><Eq><FieldRef Name="Author" /><Value Type="Integer"><UserID Type="Integer" /></Value></Eq></Where><OrderBy><FieldRef Name="ID" Ascending="FALSE" /></OrderBy>'
    }
    @{
        Title  = 'Awaiting CEO Approval'
        Fields = $viewFieldsBase + @('NeededBy')
        Query  = '<Where><Eq><FieldRef Name="RequestStatus" /><Value Type="Choice">Pending CEO Approval</Value></Eq></Where><OrderBy><FieldRef Name="Created" Ascending="TRUE" /></OrderBy>'
    }
    @{
        Title  = 'Pending Purchase'
        Fields = @('ID', 'LinkTitle', 'Author', 'Department', 'EstimatedCost', 'Vendor', 'Urgency', 'NeededBy', 'DecisionDate', 'ReminderCount', 'LastReminder')
        Query  = '<Where><Eq><FieldRef Name="RequestStatus" /><Value Type="Choice">Approved - Pending Purchase</Value></Eq></Where><OrderBy><FieldRef Name="DecisionDate" Ascending="TRUE" /></OrderBy>'
    }
    @{
        Title  = 'Completed'
        Fields = @('ID', 'LinkTitle', 'Author', 'Department', 'EstimatedCost', 'ActualCost', 'PONumber', 'PurchasedOn')
        Query  = '<Where><Eq><FieldRef Name="RequestStatus" /><Value Type="Choice">Purchased</Value></Eq></Where><OrderBy><FieldRef Name="PurchasedOn" Ascending="FALSE" /></OrderBy>'
    }
    @{
        Title  = 'All Requests'
        Fields = $viewFieldsBase + @('DecisionDate', 'PurchasedOn')
        Query  = '<OrderBy><FieldRef Name="ID" Ascending="FALSE" /></OrderBy>'
    }
)

foreach ($v in $views) {
    $existing = Get-PnPView -List $list -Identity $v.Title -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  View '$($v.Title)' exists, updating columns" -ForegroundColor DarkGray
        Set-PnPView -List $list -Identity $v.Title -Fields $v.Fields | Out-Null
        continue
    }
    Write-Host "  Adding view '$($v.Title)'" -ForegroundColor Green
    Add-PnPView -List $list -Title $v.Title -Fields $v.Fields -Query $v.Query -Paged -RowLimit 100 | Out-Null
}

# Make "My Requests" the default so requesters land on their own items.
Set-PnPView -List $list -Identity 'My Requests' -Values @{ DefaultView = $true } | Out-Null

# ---------------------------------------------------------------------------
# 4. Permissions
# ---------------------------------------------------------------------------
Write-Host "Configuring permissions ..." -ForegroundColor Cyan

# 4a. Permission level: Read + Add Items (no edit/delete).
if (-not (Get-PnPRoleDefinition -Identity $SubmitRoleName -ErrorAction SilentlyContinue)) {
    Add-PnPRoleDefinition -RoleName $SubmitRoleName -Clone 'Read' -Include AddListItems `
        -Description 'Can submit new purchase requests and view them. Cannot edit or delete after submitting.' | Out-Null
}

# 4b. Managers group (CEO + Finance).
$managers = Get-PnPGroup -Identity $ManagersGroupName -ErrorAction SilentlyContinue
if (-not $managers) {
    $managers = New-PnPGroup -Title $ManagersGroupName -Description 'CEO and Finance team: approve, purchase and close purchase requests.'
}
foreach ($email in @($CeoEmail) + $FinanceEmails) {
    Add-PnPGroupMember -Group $ManagersGroupName -LoginName $email -ErrorAction SilentlyContinue
}

# 4c. Unique permissions on the list.
if (-not $RequesterGroups -or $RequesterGroups.Count -eq 0) {
    $RequesterGroups = @((Get-PnPGroup -AssociatedMemberGroup).Title)
}
$ownersGroup = (Get-PnPGroup -AssociatedOwnerGroup).Title

Set-PnPList -Identity $list -BreakRoleInheritance -CopyRoleAssignments:$false | Out-Null
Set-PnPListPermission -Identity $list -Group $ownersGroup -AddRole 'Full Control'
# "Edit" includes Manage Lists, which lets managers see and edit every item
# regardless of the item-level settings below.
Set-PnPListPermission -Identity $list -Group $ManagersGroupName -AddRole 'Edit'
foreach ($g in $RequesterGroups) {
    Set-PnPListPermission -Identity $list -Group $g -AddRole $SubmitRoleName
}

# 4d. Item-level security: requesters only see and touch their own items.
Set-PnPList -Identity $list -ReadSecurity 2 -WriteSecurity 2 | Out-Null

$web = Get-PnPWeb
Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "List URL : $($web.Url.TrimEnd('/'))/$ListUrl"
Write-Host "Managers : $ManagersGroupName ($CeoEmail, $($FinanceEmails -join ', '))"
Write-Host "Requesters: $($RequesterGroups -join ', ') (role '$SubmitRoleName')"
Write-Host ""
Write-Host "Next: build the Power Automate flows - see docs/02-flow-ceo-approval.md" -ForegroundColor Cyan
