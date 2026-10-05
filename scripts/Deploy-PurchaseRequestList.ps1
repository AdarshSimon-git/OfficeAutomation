<#
.SYNOPSIS
    Provisions the "Purchase Requests" SharePoint list used by the purchase
    request approval automation.

.DESCRIPTION
    Creates (or updates, the script is safe to re-run):
      * The "Purchase Requests" custom list with all columns the flows rely on
      * "Projects" and "Suppliers" lists that requests link to (lookups)
      * Views: My Requests, Awaiting CEO Approval, Pending Purchase, Awaiting Delivery,
        Overdue Deliveries, Received, By Project, Pending Purchase by Supplier,
        All Requests
      * A "Submit Purchase Request" permission level (Read + Add Items)
      * A "Purchase Request Managers" SharePoint group (CEO + Finance + Inventory)
        with Edit rights
      * Unique list permissions so requesters can submit and see only their own
        requests, but cannot change them after submission.

    Requires the PnP.PowerShell module (v2+) and an Entra ID app registration
    for interactive login. See docs/01-sharepoint-setup.md.

.EXAMPLE
    ./Deploy-PurchaseRequestList.ps1 `
        -SiteUrl "https://contoso.sharepoint.com/sites/Operations" `
        -ClientId "00000000-0000-0000-0000-000000000000" `
        -CeoEmail "ceo@contoso.com" `
        -FinanceEmails "finance1@contoso.com","finance2@contoso.com" `
        -InventoryEmails "stores@contoso.com"
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

    # Inventory / stores managers who track deliveries and mark goods as received.
    [Parameter(Mandatory)] [string[]] $InventoryEmails,

    # Who may submit requests. Defaults to the site's Members group.
    # Accepts SharePoint group names.
    [string[]] $RequesterGroups = @(),

    [string] $ListTitle = 'Purchase Requests',
    [string] $ListUrl = 'Lists/PurchaseRequests',
    [string] $ProjectsListTitle = 'Projects',
    [string] $ProjectsListUrl = 'Lists/Projects',
    [string] $SuppliersListTitle = 'Suppliers',
    [string] $SuppliersListUrl = 'Lists/Suppliers',
    [string] $ManagersGroupName = 'Purchase Request Managers',
    [string] $SubmitRoleName = 'Submit Purchase Request',

    # Locale ID that controls the currency symbol, e.g. 1033 = USD ($),
    # 16393 = INR (₹), 2057 = GBP (£), 1031 = EUR (€), 14337 = AED.
    [int] $CurrencyLcid = 1033
)

$ErrorActionPreference = 'Stop'

Write-Host "Connecting to $SiteUrl ..." -ForegroundColor Cyan
Connect-PnPOnline -Url $SiteUrl -ClientId $ClientId -Interactive

function Get-OrCreateList([string] $Title, [string] $Url) {
    $l = Get-PnPList -Identity $Url -ErrorAction SilentlyContinue
    if (-not $l) {
        Write-Host "Creating list '$Title' ..." -ForegroundColor Cyan
        $l = New-PnPList -Title $Title -Url $Url -Template GenericList -EnableVersioning
    }
    else {
        Write-Host "List '$Title' already exists, updating ..." -ForegroundColor Yellow
    }
    Set-PnPList -Identity $l -EnableVersioning $true | Out-Null
    return $l
}

function Add-MissingFields($TargetList, [array] $Definitions) {
    foreach ($f in $Definitions) {
        if (Get-PnPField -List $TargetList -Identity $f.Name -ErrorAction SilentlyContinue) {
            Write-Host "  Column '$($f.Name)' exists, skipping" -ForegroundColor DarkGray
            continue
        }
        Write-Host "  Adding column '$($f.Name)'" -ForegroundColor Green
        Add-PnPFieldFromXml -List $TargetList -FieldXml $f.Xml | Out-Null
    }
}

# ---------------------------------------------------------------------------
# 1. Lists
# ---------------------------------------------------------------------------

# 1a. Projects - requests can be linked to a project for cost tracking.
$projects = Get-OrCreateList $ProjectsListTitle $ProjectsListUrl
Set-PnPField -List $projects -Identity 'Title' -Values @{ Title = 'Project' } | Out-Null
Add-MissingFields $projects @(
    @{ Name = 'ProjectCode'; Xml = '<Field Type="Text" Name="ProjectCode" StaticName="ProjectCode" DisplayName="Project Code" MaxLength="50" EnforceUniqueValues="TRUE" Indexed="TRUE" />' }
    @{ Name = 'ProjectManager'; Xml = '<Field Type="User" Name="ProjectManager" StaticName="ProjectManager" DisplayName="Project Manager" UserSelectionMode="PeopleOnly" />' }
    @{ Name = 'Budget'; Xml = "<Field Type=`"Currency`" Name=`"Budget`" StaticName=`"Budget`" DisplayName=`"Budget`" Min=`"0`" Decimals=`"2`" LCID=`"$CurrencyLcid`" />" }
    @{ Name = 'ProjectStatus'; Xml = '<Field Type="Choice" Name="ProjectStatus" StaticName="ProjectStatus" DisplayName="Project Status" Format="Dropdown" FillInChoice="FALSE"><Default>Active</Default><CHOICES><CHOICE>Active</CHOICE><CHOICE>On Hold</CHOICE><CHOICE>Closed</CHOICE></CHOICES></Field>' }
)
# Catch-all project so every request can be linked to something.
if (-not (Get-PnPListItem -List $projects -PageSize 1 | Select-Object -First 1)) {
    Add-PnPListItem -List $projects -Values @{ Title = 'GEN - General / Overhead'; ProjectCode = 'GEN' } | Out-Null
}

# 1b. Suppliers - Finance assigns one to each request so orders can be batched per supplier.
$suppliers = Get-OrCreateList $SuppliersListTitle $SuppliersListUrl
Set-PnPField -List $suppliers -Identity 'Title' -Values @{ Title = 'Supplier' } | Out-Null
Add-MissingFields $suppliers @(
    @{ Name = 'ContactName'; Xml = '<Field Type="Text" Name="ContactName" StaticName="ContactName" DisplayName="Contact Name" MaxLength="255" />' }
    @{ Name = 'SupplierEmail'; Xml = '<Field Type="Text" Name="SupplierEmail" StaticName="SupplierEmail" DisplayName="Orders Email" MaxLength="255" />' }
    @{ Name = 'Phone'; Xml = '<Field Type="Text" Name="Phone" StaticName="Phone" DisplayName="Phone" MaxLength="50" />' }
    @{ Name = 'Website'; Xml = '<Field Type="Text" Name="Website" StaticName="Website" DisplayName="Website / Portal" MaxLength="255" />' }
    @{ Name = 'PaymentTerms'; Xml = '<Field Type="Text" Name="PaymentTerms" StaticName="PaymentTerms" DisplayName="Payment Terms" MaxLength="100" />' }
    @{ Name = 'SupplierNotes'; Xml = '<Field Type="Note" Name="SupplierNotes" StaticName="SupplierNotes" DisplayName="Notes" NumLines="4" RichText="FALSE" />' }
    @{ Name = 'SupplierActive'; Xml = '<Field Type="Boolean" Name="SupplierActive" StaticName="SupplierActive" DisplayName="Active"><Default>1</Default></Field>' }
)

# 1c. Purchase Requests
$list = Get-OrCreateList $ListTitle $ListUrl
Set-PnPList -Identity $list -EnableAttachments $true | Out-Null
Set-PnPField -List $list -Identity 'Title' -Values @{ Title = 'Item / Service Requested' } | Out-Null

# ---------------------------------------------------------------------------
# 2. Columns
#    ShowInNewForm="FALSE" hides workflow/finance columns from requesters when
#    they submit. They remain editable for managers in the edit form.
# ---------------------------------------------------------------------------
# Request lifecycle, in order. Flows filter on these exact strings.
$statusChoices = @(
    'Submitted'
    'Pending CEO Approval'
    'Approved - Pending Purchase'
    'Purchased'            # order placed by Finance
    'In Transit'           # set by Inventory when shipped / tracking available
    'Delayed'              # set by Inventory; requester is notified
    'Partially Received'
    'Received'             # set by Inventory; requester is notified
    'Rejected'
    'Approval Expired'
    'Cancelled'
    'Merged'               # duplicate merged into another request (PR-06)
)

$fields = @(
    @{ Name = 'ItemDescription'; Xml = '<Field Type="Note" Name="ItemDescription" StaticName="ItemDescription" DisplayName="Description" NumLines="6" RichText="FALSE" Required="TRUE" />' }
    @{ Name = 'Quantity'; Xml = '<Field Type="Number" Name="Quantity" StaticName="Quantity" DisplayName="Quantity" Min="1" Decimals="0" Required="TRUE"><Default>1</Default></Field>' }
    @{ Name = 'EstimatedCost'; Xml = "<Field Type=`"Currency`" Name=`"EstimatedCost`" StaticName=`"EstimatedCost`" DisplayName=`"Estimated Total Cost`" Min=`"0`" Decimals=`"2`" LCID=`"$CurrencyLcid`" Required=`"TRUE`" />" }
    @{ Name = 'Vendor'; Xml = '<Field Type="Text" Name="Vendor" StaticName="Vendor" DisplayName="Suggested Vendor / Link" MaxLength="255" />' }
    @{ Name = 'Project'; Xml = "<Field Type=`"Lookup`" Name=`"Project`" StaticName=`"Project`" DisplayName=`"Project`" List=`"{$($projects.Id)}`" ShowField=`"Title`" />" }
    @{ Name = 'Justification'; Xml = '<Field Type="Note" Name="Justification" StaticName="Justification" DisplayName="Business Justification" NumLines="6" RichText="FALSE" Required="TRUE" />' }
    @{ Name = 'Department'; Xml = '<Field Type="Choice" Name="Department" StaticName="Department" DisplayName="Department" Format="Dropdown" FillInChoice="TRUE" Required="TRUE"><CHOICES><CHOICE>Administration</CHOICE><CHOICE>Finance</CHOICE><CHOICE>HR</CHOICE><CHOICE>IT</CHOICE><CHOICE>Marketing</CHOICE><CHOICE>Operations</CHOICE><CHOICE>Sales</CHOICE><CHOICE>Other</CHOICE></CHOICES></Field>' }
    @{ Name = 'NeededBy'; Xml = '<Field Type="DateTime" Name="NeededBy" StaticName="NeededBy" DisplayName="Needed By" Format="DateOnly" />' }
    @{ Name = 'Urgency'; Xml = '<Field Type="Choice" Name="Urgency" StaticName="Urgency" DisplayName="Urgency" Format="Dropdown" FillInChoice="FALSE"><Default>Normal</Default><CHOICES><CHOICE>Low</CHOICE><CHOICE>Normal</CHOICE><CHOICE>High</CHOICE><CHOICE>Critical</CHOICE></CHOICES></Field>' }

    # --- Workflow columns (hidden on the new form) -------------------------
    @{ Name = 'RequestStatus'; Xml = "<Field Type=`"Choice`" Name=`"RequestStatus`" StaticName=`"RequestStatus`" DisplayName=`"Status`" Format=`"Dropdown`" FillInChoice=`"FALSE`" ShowInNewForm=`"FALSE`"><Default>Submitted</Default><CHOICES>$(($statusChoices | ForEach-Object { "<CHOICE>$_</CHOICE>" }) -join '')</CHOICES></Field>" }
    @{ Name = 'CEOComments'; Xml = '<Field Type="Note" Name="CEOComments" StaticName="CEOComments" DisplayName="CEO Comments" NumLines="4" RichText="FALSE" ShowInNewForm="FALSE" />' }
    @{ Name = 'DecisionDate'; Xml = '<Field Type="DateTime" Name="DecisionDate" StaticName="DecisionDate" DisplayName="CEO Decision Date" Format="DateTime" ShowInNewForm="FALSE" />' }

    # --- Finance columns (hidden on the new form) --------------------------
    @{ Name = 'PurchasedOn'; Xml = '<Field Type="DateTime" Name="PurchasedOn" StaticName="PurchasedOn" DisplayName="Purchased On" Format="DateOnly" ShowInNewForm="FALSE" />' }
    @{ Name = 'PONumber'; Xml = '<Field Type="Text" Name="PONumber" StaticName="PONumber" DisplayName="PO / Invoice Number" MaxLength="100" ShowInNewForm="FALSE" />' }
    @{ Name = 'ActualCost'; Xml = "<Field Type=`"Currency`" Name=`"ActualCost`" StaticName=`"ActualCost`" DisplayName=`"Actual Cost`" Min=`"0`" Decimals=`"2`" LCID=`"$CurrencyLcid`" ShowInNewForm=`"FALSE`" />" }
    @{ Name = 'FinanceNotes'; Xml = '<Field Type="Note" Name="FinanceNotes" StaticName="FinanceNotes" DisplayName="Finance Notes" NumLines="4" RichText="FALSE" ShowInNewForm="FALSE" />' }

    # Finance picks the supplier; used to group and batch orders (PR-07).
    @{ Name = 'Supplier'; Xml = "<Field Type=`"Lookup`" Name=`"Supplier`" StaticName=`"Supplier`" DisplayName=`"Supplier`" List=`"{$($suppliers.Id)}`" ShowField=`"Title`" ShowInNewForm=`"FALSE`" />" }

    # --- Duplicate merge columns (Finance, PR-06) ---------------------------
    @{ Name = 'MergeInto'; Xml = '<Field Type="Number" Name="MergeInto" StaticName="MergeInto" DisplayName="Merge Into Request #" Min="1" Decimals="0" ShowInNewForm="FALSE" />' }
    @{ Name = 'MergeMode'; Xml = '<Field Type="Choice" Name="MergeMode" StaticName="MergeMode" DisplayName="Merge Mode" Format="Dropdown" FillInChoice="FALSE" ShowInNewForm="FALSE"><Default>Combine quantities and cost</Default><CHOICES><CHOICE>Combine quantities and cost</CHOICE><CHOICE>Exact duplicate - keep target unchanged</CHOICE></CHOICES></Field>' }
    @{ Name = 'MergeState'; Xml = '<Field Type="Choice" Name="MergeState" StaticName="MergeState" DisplayName="Merge State" Format="Dropdown" FillInChoice="FALSE" ShowInNewForm="FALSE"><CHOICES><CHOICE>Awaiting Requester Approval</CHOICE><CHOICE>Merged</CHOICE><CHOICE>Declined</CHOICE><CHOICE>Invalid</CHOICE></CHOICES></Field>' }
    @{ Name = 'MergedRequests'; Xml = '<Field Type="Note" Name="MergedRequests" StaticName="MergedRequests" DisplayName="Merged Requests" NumLines="3" RichText="FALSE" ShowInNewForm="FALSE" />' }
    # Requesters of merged duplicates; the flows copy them on every update of the surviving request.
    @{ Name = 'AdditionalRecipients'; Xml = '<Field Type="Note" Name="AdditionalRecipients" StaticName="AdditionalRecipients" DisplayName="Additional Recipients" NumLines="2" RichText="FALSE" ShowInNewForm="FALSE" ShowInEditForm="FALSE" />' }

    # --- Delivery tracking columns (Finance / Inventory) --------------------
    @{ Name = 'ExpectedDelivery'; Xml = '<Field Type="DateTime" Name="ExpectedDelivery" StaticName="ExpectedDelivery" DisplayName="Expected Delivery Date" Format="DateOnly" ShowInNewForm="FALSE" />' }
    @{ Name = 'RevisedDelivery'; Xml = '<Field Type="DateTime" Name="RevisedDelivery" StaticName="RevisedDelivery" DisplayName="Revised Delivery Date" Format="DateOnly" ShowInNewForm="FALSE" />' }
    @{ Name = 'Carrier'; Xml = '<Field Type="Text" Name="Carrier" StaticName="Carrier" DisplayName="Carrier / Courier" MaxLength="100" ShowInNewForm="FALSE" />' }
    @{ Name = 'TrackingNumber'; Xml = '<Field Type="Text" Name="TrackingNumber" StaticName="TrackingNumber" DisplayName="Tracking Number / Link" MaxLength="255" ShowInNewForm="FALSE" />' }
    @{ Name = 'DelayReason'; Xml = '<Field Type="Note" Name="DelayReason" StaticName="DelayReason" DisplayName="Delay Reason" NumLines="3" RichText="FALSE" ShowInNewForm="FALSE" />' }
    # AppendOnly keeps a dated history of every update (needs versioning, enabled above).
    @{ Name = 'DeliveryUpdates'; Xml = '<Field Type="Note" Name="DeliveryUpdates" StaticName="DeliveryUpdates" DisplayName="Delivery Updates" NumLines="4" RichText="FALSE" AppendOnly="TRUE" ShowInNewForm="FALSE" />' }
    @{ Name = 'QuantityReceived'; Xml = '<Field Type="Number" Name="QuantityReceived" StaticName="QuantityReceived" DisplayName="Quantity Received" Min="0" Decimals="0" ShowInNewForm="FALSE" />' }
    @{ Name = 'ReceivedOn'; Xml = '<Field Type="DateTime" Name="ReceivedOn" StaticName="ReceivedOn" DisplayName="Received On" Format="DateOnly" ShowInNewForm="FALSE" />' }
    @{ Name = 'ReceivedBy'; Xml = '<Field Type="User" Name="ReceivedBy" StaticName="ReceivedBy" DisplayName="Received By" UserSelectionMode="PeopleOnly" ShowInNewForm="FALSE" />' }
    @{ Name = 'ReceiptNotes'; Xml = '<Field Type="Note" Name="ReceiptNotes" StaticName="ReceiptNotes" DisplayName="Receipt Notes / Condition" NumLines="3" RichText="FALSE" ShowInNewForm="FALSE" />' }
    # Revised date if set, otherwise expected date. Used by the Overdue Deliveries view.
    @{ Name = 'DeliveryDue'; Xml = '<Field Type="Calculated" Name="DeliveryDue" StaticName="DeliveryDue" DisplayName="Delivery Due" ResultType="DateTime" Format="DateOnly" ReadOnly="TRUE"><Formula>=IF(ISBLANK([Revised Delivery Date]),[Expected Delivery Date],[Revised Delivery Date])</Formula><FieldRefs><FieldRef Name="ExpectedDelivery" /><FieldRef Name="RevisedDelivery" /></FieldRefs></Field>' }

    # --- System columns maintained by the flows ----------------------------
    @{ Name = 'ReminderCount'; Xml = '<Field Type="Number" Name="ReminderCount" StaticName="ReminderCount" DisplayName="Reminders Sent" Decimals="0" ShowInNewForm="FALSE" ShowInEditForm="FALSE"><Default>0</Default></Field>' }
    @{ Name = 'LastReminder'; Xml = '<Field Type="DateTime" Name="LastReminder" StaticName="LastReminder" DisplayName="Last Reminder" Format="DateTime" ShowInNewForm="FALSE" ShowInEditForm="FALSE" />' }
    @{ Name = 'CompletionNotified'; Xml = '<Field Type="Boolean" Name="CompletionNotified" StaticName="CompletionNotified" DisplayName="Completion Notified" ShowInNewForm="FALSE" ShowInEditForm="FALSE"><Default>0</Default></Field>' }
    @{ Name = 'ReceivedNotified'; Xml = '<Field Type="Boolean" Name="ReceivedNotified" StaticName="ReceivedNotified" DisplayName="Received Notified" ShowInNewForm="FALSE" ShowInEditForm="FALSE"><Default>0</Default></Field>' }
    @{ Name = 'LastDelayNotice'; Xml = '<Field Type="Text" Name="LastDelayNotice" StaticName="LastDelayNotice" DisplayName="Last Delay Notice" MaxLength="100" ShowInNewForm="FALSE" ShowInEditForm="FALSE" />' }
    # ID of the request's thread in the Purchase Requests Teams channel; later updates reply to it.
    @{ Name = 'TeamsThreadId'; Xml = '<Field Type="Text" Name="TeamsThreadId" StaticName="TeamsThreadId" DisplayName="Teams Thread ID" MaxLength="100" ShowInNewForm="FALSE" ShowInEditForm="FALSE" />' }
)

Add-MissingFields $list $fields

# Existing lists: the requester's vendor column is now a suggestion; Finance sets Supplier.
Set-PnPField -List $list -Identity 'Vendor' -Values @{ Title = 'Suggested Vendor / Link' } | Out-Null

# Existing lists (created by an earlier version of this script): make sure the
# Status column has every lifecycle choice.
Set-PnPField -List $list -Identity 'RequestStatus' -Values @{ Choices = [string[]]$statusChoices } | Out-Null

# Index the column used by every flow filter so queries stay fast past 5,000 items.
foreach ($indexed in 'RequestStatus', 'Project', 'Supplier') {
    Set-PnPField -List $list -Identity $indexed -Values @{ Indexed = $true } | Out-Null
}

# ---------------------------------------------------------------------------
# 3. Views
# ---------------------------------------------------------------------------
$viewFieldsBase = @('ID', 'LinkTitle', 'Author', 'Department', 'EstimatedCost', 'Urgency', 'RequestStatus', 'Created')

# Ordered but not yet fully received.
$awaitingDeliveryCaml = '<In><FieldRef Name="RequestStatus" /><Values><Value Type="Choice">Purchased</Value><Value Type="Choice">In Transit</Value><Value Type="Choice">Delayed</Value><Value Type="Choice">Partially Received</Value></Values></In>'
$deliveryViewFields = @('ID', 'LinkTitle', 'Author', 'RequestStatus', 'Supplier', 'PONumber', 'PurchasedOn', 'ExpectedDelivery', 'RevisedDelivery', 'DeliveryDue', 'Carrier', 'TrackingNumber')

$views = @(
    @{
        Title  = 'My Requests'
        Fields = @('ID', 'LinkTitle', 'Project', 'EstimatedCost', 'RequestStatus', 'CEOComments', 'MergeInto', 'PurchasedOn', 'DeliveryDue', 'ReceivedOn', 'Created')
        Query  = '<Where><Eq><FieldRef Name="Author" /><Value Type="Integer"><UserID Type="Integer" /></Value></Eq></Where><OrderBy><FieldRef Name="ID" Ascending="FALSE" /></OrderBy>'
    }
    @{
        Title  = 'Awaiting CEO Approval'
        Fields = $viewFieldsBase + @('NeededBy')
        Query  = '<Where><Eq><FieldRef Name="RequestStatus" /><Value Type="Choice">Pending CEO Approval</Value></Eq></Where><OrderBy><FieldRef Name="Created" Ascending="TRUE" /></OrderBy>'
    }
    @{
        Title  = 'Pending Purchase'
        Fields = @('ID', 'LinkTitle', 'Author', 'Project', 'Quantity', 'EstimatedCost', 'Supplier', 'Vendor', 'Urgency', 'NeededBy', 'DecisionDate', 'MergeState', 'ReminderCount')
        Query  = '<Where><Eq><FieldRef Name="RequestStatus" /><Value Type="Choice">Approved - Pending Purchase</Value></Eq></Where><OrderBy><FieldRef Name="DecisionDate" Ascending="TRUE" /></OrderBy>'
    }
    @{
        Title  = 'Awaiting Delivery'
        Fields = $deliveryViewFields
        Query  = "<Where>$awaitingDeliveryCaml</Where><OrderBy><FieldRef Name=`"DeliveryDue`" Ascending=`"TRUE`" /></OrderBy>"
    }
    @{
        Title  = 'Overdue Deliveries'
        Fields = $deliveryViewFields + @('DelayReason')
        Query  = "<Where><And>$awaitingDeliveryCaml<Lt><FieldRef Name=`"DeliveryDue`" /><Value Type=`"DateTime`"><Today /></Value></Lt></And></Where><OrderBy><FieldRef Name=`"DeliveryDue`" Ascending=`"TRUE`" /></OrderBy>"
    }
    @{
        Title  = 'Received'
        Fields = @('ID', 'LinkTitle', 'Author', 'Department', 'Quantity', 'QuantityReceived', 'ActualCost', 'PONumber', 'PurchasedOn', 'ReceivedOn', 'ReceivedBy')
        Query  = '<Where><Eq><FieldRef Name="RequestStatus" /><Value Type="Choice">Received</Value></Eq></Where><OrderBy><FieldRef Name="ReceivedOn" Ascending="FALSE" /></OrderBy>'
    }
    @{
        # Finance: pick a supplier group, then batch-order it with PR-07.
        Title        = 'Pending Purchase by Supplier'
        Fields       = @('ID', 'LinkTitle', 'Quantity', 'EstimatedCost', 'Author', 'Project', 'Vendor', 'Urgency', 'NeededBy')
        Query        = '<GroupBy Collapse="FALSE" GroupLimit="100"><FieldRef Name="Supplier" /></GroupBy><Where><Eq><FieldRef Name="RequestStatus" /><Value Type="Choice">Approved - Pending Purchase</Value></Eq></Where><OrderBy><FieldRef Name="Title" Ascending="TRUE" /></OrderBy>'
        Aggregations = '<FieldRef Name="LinkTitle" Type="COUNT" /><FieldRef Name="EstimatedCost" Type="SUM" />'
    }
    @{
        # Spend per project. Excludes rejected, expired, cancelled and merged requests.
        Title        = 'By Project'
        Fields       = @('ID', 'LinkTitle', 'Author', 'RequestStatus', 'Supplier', 'EstimatedCost', 'ActualCost', 'PurchasedOn')
        Query        = '<GroupBy Collapse="TRUE" GroupLimit="100"><FieldRef Name="Project" /></GroupBy><Where><In><FieldRef Name="RequestStatus" /><Values><Value Type="Choice">Pending CEO Approval</Value><Value Type="Choice">Approved - Pending Purchase</Value><Value Type="Choice">Purchased</Value><Value Type="Choice">In Transit</Value><Value Type="Choice">Delayed</Value><Value Type="Choice">Partially Received</Value><Value Type="Choice">Received</Value></Values></In></Where><OrderBy><FieldRef Name="ID" Ascending="FALSE" /></OrderBy>'
        Aggregations = '<FieldRef Name="EstimatedCost" Type="SUM" /><FieldRef Name="ActualCost" Type="SUM" />'
    }
    @{
        Title  = 'All Requests'
        Fields = $viewFieldsBase + @('Project', 'Supplier', 'DecisionDate', 'PurchasedOn', 'DeliveryDue', 'ReceivedOn')
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
    $viewArgs = @{ List = $list; Title = $v.Title; Fields = $v.Fields; Query = $v.Query; Paged = $true; RowLimit = 100 }
    if ($v.Aggregations) { $viewArgs.Aggregations = $v.Aggregations }
    Add-PnPView @viewArgs | Out-Null
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
    $managers = New-PnPGroup -Title $ManagersGroupName -Description 'CEO, Finance and Inventory: approve, purchase, track and receive purchase requests.'
}
foreach ($email in @($CeoEmail) + $FinanceEmails + $InventoryEmails) {
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

# 4e. Projects and Suppliers: everyone reads (to pick a project), managers maintain.
foreach ($lookupList in $projects, $suppliers) {
    Set-PnPList -Identity $lookupList -BreakRoleInheritance -CopyRoleAssignments:$false | Out-Null
    Set-PnPListPermission -Identity $lookupList -Group $ownersGroup -AddRole 'Full Control'
    Set-PnPListPermission -Identity $lookupList -Group $ManagersGroupName -AddRole 'Edit'
    foreach ($g in $RequesterGroups) {
        Set-PnPListPermission -Identity $lookupList -Group $g -AddRole 'Read'
    }
}

$web = Get-PnPWeb
Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "List URL : $($web.Url.TrimEnd('/'))/$ListUrl"
Write-Host "Projects : $($web.Url.TrimEnd('/'))/$ProjectsListUrl"
Write-Host "Suppliers: $($web.Url.TrimEnd('/'))/$SuppliersListUrl"
Write-Host "Managers : $ManagersGroupName ($((@($CeoEmail) + $FinanceEmails + $InventoryEmails) -join ', '))"
Write-Host "Requesters: $($RequesterGroups -join ', ') (role '$SubmitRoleName')"
Write-Host ""
Write-Host "Next: build the Power Automate flows - see docs/02-flow-ceo-approval.md" -ForegroundColor Cyan
