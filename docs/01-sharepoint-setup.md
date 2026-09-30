# 01 – SharePoint list setup

The **Purchase Requests** list is where all the data lives. Set it up with the
script (recommended) or by hand.

## Option A – Script (recommended)

### One-time prerequisites

1. Install PowerShell 7+ and the PnP module:
   ```powershell
   Install-Module PnP.PowerShell -Scope CurrentUser
   ```
2. PnP.PowerShell needs your own Entra ID app registration for interactive
   sign-in. A **Global Admin / Application Admin** runs this once:
   ```powershell
   Register-PnPEntraIDAppForInteractiveLogin -ApplicationName "PnP PowerShell" -Tenant yourorg.onmicrosoft.com
   ```
   Note the **Client ID** it prints.
3. You need **Site Owner** rights on the target site.

### Run it

```powershell
./scripts/Deploy-PurchaseRequestList.ps1 `
    -SiteUrl       "https://yourorg.sharepoint.com/sites/Operations" `
    -ClientId      "<client id from step 2>" `
    -CeoEmail      "ceo@yourorg.com" `
    -FinanceEmails "alice@yourorg.com","bob@yourorg.com" `
    -InventoryEmails "stores@yourorg.com" `
    -CurrencyLcid  1033   # 1033 = $, 16393 = ₹, 2057 = £, 1031 = €
```

Optional parameters:

| Parameter | Default | Notes |
|---|---|---|
| `-RequesterGroups` | Site *Members* group | SharePoint groups allowed to submit. To let the whole company submit, add *Everyone except external users* to the site Members group, or name another group here. |
| `-ListTitle` / `-ListUrl` | `Purchase Requests` / `Lists/PurchaseRequests` | If you change the URL, update the flows to match. |
| `-ManagersGroupName` | `Purchase Request Managers` | CEO + Finance + Inventory group with Edit rights on the list. |

It's safe to run again: it skips columns and views that already exist, and
it adds any missing *Status* choices. If you deployed an earlier version
(before delivery tracking), just re-run it with `-InventoryEmails` to add the
new columns, views and statuses.

## Option B – Manual setup

### Projects and Suppliers lists (create these first, since the lookups need them)

**Projects** (URL `Lists/Projects`): rename *Title* to **Project**, then add
`ProjectCode` (*Project Code*, single line, enforce unique values),
`ProjectManager` (*Project Manager*, Person), `Budget` (Currency) and
`ProjectStatus` (*Project Status*, Choice: Active, On Hold, Closed; default
Active). Add a project **GEN - General / Overhead**.

**Suppliers** (URL `Lists/Suppliers`): rename *Title* to **Supplier**, then
add `ContactName` (*Contact Name*), `SupplierEmail` (*Orders Email*), `Phone`,
`Website` (*Website / Portal*), `PaymentTerms` (*Payment Terms*), all single
line of text; `SupplierNotes` (*Notes*, multiple lines) and `SupplierActive`
(*Active*, Yes/No, default Yes).

Permissions on both: **Stop inheriting**, then Owners = Full Control, Purchase
Request Managers = Edit, Members = **Read**.

### Purchase Requests list

1. **Site contents → New → List → Blank list**, name it `Purchase Requests`.
   (Create it as `PurchaseRequests` first so the URL has no spaces or `%20`,
   then rename it.)
2. Rename the **Title** column to **Item / Service Requested**.
3. Add the columns below. **The internal name comes from the name you type
   when you first create the column**, so create each one with the
   *Internal name*, then rename it to the *Display name*. The flows use the
   internal names.

| Internal name | Display name | Type | Settings |
|---|---|---|---|
| `ItemDescription` | Description | Multiple lines of text | Required, plain text |
| `Quantity` | Quantity | Number | Required, min 1, 0 decimals, default 1 |
| `EstimatedCost` | Estimated Total Cost | Currency | Required, min 0 |
| `Vendor` | Suggested Vendor / Link | Single line of text | Requester's suggestion |
| `Project` | Project | **Lookup** → *Projects*, column *Project* | Not required (see [09](09-projects.md)) |
| `Justification` | Business Justification | Multiple lines of text | Required |
| `Department` | Department | Choice | Required; your departments; allow fill-in |
| `NeededBy` | Needed By | Date | Date only |
| `Urgency` | Urgency | Choice | Low, Normal, High, Critical; default Normal |
| `RequestStatus` | Status | Choice | Submitted, Pending CEO Approval, Approved - Pending Purchase, Purchased, In Transit, Delayed, Partially Received, Received, Rejected, Approval Expired, Cancelled, Merged; **default Submitted**; no fill-in |
| `CEOComments` | CEO Comments | Multiple lines of text | |
| `DecisionDate` | CEO Decision Date | Date and time | Include time |
| `PurchasedOn` | Purchased On | Date | Date only |
| `PONumber` | PO / Invoice Number | Single line of text | |
| `ActualCost` | Actual Cost | Currency | |
| `FinanceNotes` | Finance Notes | Multiple lines of text | |
| `ExpectedDelivery` | Expected Delivery Date | Date | Date only |
| `RevisedDelivery` | Revised Delivery Date | Date | Date only |
| `Carrier` | Carrier / Courier | Single line of text | |
| `TrackingNumber` | Tracking Number / Link | Single line of text | |
| `DelayReason` | Delay Reason | Multiple lines of text | |
| `DeliveryUpdates` | Delivery Updates | Multiple lines of text | Plain text, **Append changes to existing text = Yes** (a tracking log) |
| `QuantityReceived` | Quantity Received | Number | Min 0 |
| `ReceivedOn` | Received On | Date | Date only |
| `ReceivedBy` | Received By | Person | People only |
| `ReceiptNotes` | Receipt Notes / Condition | Multiple lines of text | |
| `Supplier` | Supplier | **Lookup** → *Suppliers*, column *Supplier* | Set by Finance |
| `MergeInto` | Merge Into Request # | Number | 0 decimals, min 1 |
| `MergeMode` | Merge Mode | Choice | `Combine quantities and cost` (default), `Exact duplicate - keep target unchanged` |
| `MergeState` | Merge State | Choice | Awaiting Requester Approval, Merged, Declined, Invalid; **no default** |
| `MergedRequests` | Merged Requests | Multiple lines of text | |
| `AdditionalRecipients` | Additional Recipients | Multiple lines of text | Plain text; flows only |
| `DeliveryDue` | Delivery Due | Calculated | Formula `=IF(ISBLANK([Revised Delivery Date]),[Expected Delivery Date],[Revised Delivery Date])`, returns **Date and Time** (date only). Create after the two date columns. |
| `ReminderCount` | Reminders Sent | Number | Default 0 |
| `LastReminder` | Last Reminder | Date and time | |
| `CompletionNotified` | Completion Notified | Yes/No | Default **No** |
| `ReceivedNotified` | Received Notified | Yes/No | Default **No** |
| `LastDelayNotice` | Last Delay Notice | Single line of text | |

   The Status choice text must match exactly (including the spaces around
   the hyphen in `Approved - Pending Purchase`): the flows filter on it.

4. **Index the Status, Project and Supplier columns:** List settings →
   Indexed columns → Create a new index (one per column).
5. **(Optional) Tidy the new form.** The script hides the workflow and
   finance columns on the *new* form only. The modern UI can't do that by
   hand (the *Edit columns* option hides a column from both the new and edit
   forms). It's safe to leave them visible: PR-01 resets *Status*, *Reminders
   Sent* and *Completion Notified* as soon as a request is created, and
   requesters can't edit afterwards. Alternatively, you can hide *Reminders
   Sent*, *Last Reminder*, *Completion Notified*, *Received Notified* and
   *Last Delay Notice* and *Additional Recipients* from both forms, since only
   the flows set them.
6. **Create views** (filter on *Status*):
   * **My Requests**: *Created By* is equal to `[Me]`. Make this the default.
   * **Awaiting CEO Approval**: Status = Pending CEO Approval
   * **Pending Purchase**: Status = Approved - Pending Purchase, sorted by *CEO Decision Date* ascending
   * **Awaiting Delivery**: Status = Purchased **or** In Transit **or** Delayed **or** Partially Received, sorted by *Delivery Due* ascending
   * **Overdue Deliveries**: the same four statuses (group them in brackets
     in the filter panel) **and** *Delivery Due* is less than `[Today]`
   * **Received**: Status = Received, sorted by *Received On* descending
   * **Pending Purchase by Supplier**: Status = Approved - Pending Purchase;
     **Group by** *Supplier* (expanded); **Totals**: Count on *Item /
     Service Requested*, Sum on *Estimated Total Cost*
   * **By Project**: all statuses except Rejected, Approval Expired,
     Cancelled and Merged; **Group by** *Project* (collapsed); **Totals**: Sum
     on *Estimated Total Cost* and *Actual Cost*
   * **All Requests**
7. **Permissions** (see below).

## Permissions model

| Who | Permission on the list | Can do |
|---|---|---|
| Site Owners | Full Control | Everything |
| **Purchase Request Managers** (CEO + Finance + Inventory + flow owner account) | Edit | See and edit all requests. Finance marks Purchased/Cancelled; Inventory updates tracking and marks Received. |
| Requesters (site Members or a chosen group) | **Submit Purchase Request** (Read + Add Items) | Submit new requests; see **only their own**; cannot change them after submitting |
| Everyone (Projects & Suppliers lists) | Read, with managers having Edit | Pick a project on the form; only managers maintain projects and suppliers |

Manual steps:

1. Site settings → **Site permissions → Advanced permissions settings →
   Permission Levels → Add a Permission Level** named `Submit Purchase Request`
   with: *Add Items, View Items, Open Items, View Versions, Create Alerts,
   View Application Pages, View Pages, Browse User Information, Use Remote
   Interfaces, Use Client Integration Features, Open*.
2. Create a SharePoint group **Purchase Request Managers** and add the CEO,
   the Finance staff, the inventory manager(s) and the account that will own
   the flows.
3. List settings → **Permissions for this list → Stop Inheriting
   Permissions**. Then set: Owners = Full Control, Purchase Request Managers
   = Edit, Members = Submit Purchase Request. Remove any other entries.
4. List settings → **Advanced settings → Item-level Permissions**:
   *Read access = Read items that were created by the user*,
   *Create and Edit access = Create items and edit items that were created by the user*.
   (Users with Edit rights, i.e. the managers, still see everything.)

> SharePoint has no column-level permissions, so everyone in the managers
> group can technically edit any column. The flows and views assume each role
> only touches its own stage. Version history (*…→ Version history* on an
> item) shows who changed what.

> **Why requesters can't edit:** if they could, a requester could change the
> Status to *Approved - Pending Purchase* and skip the CEO. To change a
> request, they ask Finance to cancel it and then submit a new one.

## Optional: Teams

* In the **Finance** channel: **+ (Add a tab) → Lists → Purchase Requests**,
  with the *Pending Purchase* view. Finance can then work the queue without
  leaving Teams.
* In the **Inventory / Admin** channel: a tab with the *Awaiting Delivery*
  view (and optionally a second with *Overdue Deliveries*).
* Add a **Purchase Requests** tab in a company-wide channel so staff can
  submit requests from Teams.
