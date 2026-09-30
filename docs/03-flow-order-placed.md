# 03 – Flow PR-02: Order Placed (Purchased)

**Trigger:** Finance sets a request's **Status** to **Purchased**, meaning
the order has been placed with the vendor.
**Result:**

* *Purchased On* is filled in (if Finance left it blank) and the request is
  flagged as notified.
* The **requester** is told the item has been ordered and when to expect it.
* The **inventory manager** is told what's coming, from which vendor, the PO
  number, the expected delivery date and any tracking details. From here the
  inventory manager tracks the delivery and marks it received (see
  [05 – Delivery updates](05-flow-delivery-updates.md) and
  [06 – Delivery tracking digest](06-flow-delivery-tracking.md)).
* The request drops out of the Finance reminder digest because its status
  changed.

```
When an item is created or modified   (trigger condition: Status = Purchased AND not yet notified)
├─ Initialize variable  InventoryEmail
├─ Update item          Stamp Completion
├─ Send an email        Email Requester Ordered
└─ Send an email        Email Inventory Incoming
```

When marking a request *Purchased*, Finance should also set the **Supplier**
and fill in **Expected Delivery Date** and, if known, **Carrier / Courier** and **Tracking Number /
Link**. The inventory manager can add or correct these later.

## Build it

**Create → Automated cloud flow**, name it `PR-02 Order Placed`, and pick
the SharePoint trigger **When an item is created or modified**.

### 1. Trigger – *When an item is created or modified*

Site Address and List Name: same as PR-01.

**Trigger condition** (important: it keeps the flow from running on every
edit and from looping on its own update). Open the trigger → `…` →
**Settings** → **Trigger conditions → + Add**, and paste:

```
@and(equals(triggerOutputs()?['body/RequestStatus/Value'], 'Purchased'), not(equals(triggerOutputs()?['body/CompletionNotified'], true)))
```

### 2. Initialize variable – `InventoryEmail`

Type **String**, value `stores@yourorg.com` (the inventory manager, or a
distribution list).

### 3. Update item – rename to **Stamp Completion**

| Field | Value |
|---|---|
| Id | trigger `ID` |
| Title | trigger `Title` |
| Status Value | `Purchased` (the connector may otherwise reset the choice) |
| Purchased On | `@{if(empty(triggerOutputs()?['body/PurchasedOn']), utcNow(), triggerOutputs()?['body/PurchasedOn'])}` |
| Completion Notified | `Yes` |

This update triggers the flow again, but the trigger condition is now false
(*Completion Notified = Yes*), so it doesn't run a second time.

### 4. Send an email (V2) – rename to **Email Requester Ordered**

| Field | Value |
|---|---|
| To | `@{triggerOutputs()?['body/Author/Email']}` |
| CC | `@{triggerOutputs()?['body/AdditionalRecipients']}` (requesters whose duplicate requests were merged into this one, see [10](10-flow-merge-duplicates.md); empty is fine) |
| Subject | `Ordered: your request #@{triggerOutputs()?['body/ID']} – @{triggerOutputs()?['body/Title']}` |
| Body | *(code view)* |

```html
<p>Hi @{triggerOutputs()?['body/Author/DisplayName']},</p>
<p>Finance has placed the order for your request <b>#@{triggerOutputs()?['body/ID']} – @{triggerOutputs()?['body/Title']}</b>.
You'll get another email when it arrives at the office.</p>
<table cellpadding="6" style="border-collapse:collapse;border:1px solid #ccc">
  <tr><td><b>Supplier</b></td><td>@{coalesce(triggerOutputs()?['body/Supplier/Value'], triggerOutputs()?['body/Vendor'])}</td></tr>
  <tr><td><b>PO / invoice number</b></td><td>@{triggerOutputs()?['body/PONumber']}</td></tr>
  <tr><td><b>Expected delivery</b></td><td>@{if(empty(triggerOutputs()?['body/ExpectedDelivery']), 'To be confirmed', formatDateTime(coalesce(triggerOutputs()?['body/ExpectedDelivery'], utcNow()), 'dd MMM yyyy'))}</td></tr>
  <tr><td><b>Ordered by</b></td><td>@{triggerOutputs()?['body/Editor/DisplayName']}</td></tr>
</table>
<p><a href="@{triggerOutputs()?['body/{Link}']}">View request</a></p>
```

### 5. Send an email (V2) – rename to **Email Inventory Incoming**

| Field | Value |
|---|---|
| To | `InventoryEmail` variable |
| Subject | `Incoming order: #@{triggerOutputs()?['body/ID']} – @{triggerOutputs()?['body/Title']} (expected @{if(empty(triggerOutputs()?['body/ExpectedDelivery']), 'TBC', formatDateTime(coalesce(triggerOutputs()?['body/ExpectedDelivery'], utcNow()), 'dd MMM'))})` |
| Body | *(code view)* |

```html
<p>Hello,</p>
<p>Finance has placed the following order. Please track the delivery and mark it as received when it arrives.</p>
<table cellpadding="6" style="border-collapse:collapse;border:1px solid #ccc">
  <tr><td><b>Request</b></td><td>#@{triggerOutputs()?['body/ID']} – @{triggerOutputs()?['body/Title']}</td></tr>
  <tr><td><b>Quantity</b></td><td>@{triggerOutputs()?['body/Quantity']}</td></tr>
  <tr><td><b>Requested by</b></td><td>@{triggerOutputs()?['body/Author/DisplayName']} (@{triggerOutputs()?['body/Department/Value']})</td></tr>
  <tr><td><b>Project</b></td><td>@{coalesce(triggerOutputs()?['body/Project/Value'], '–')}</td></tr>
  <tr><td><b>Supplier</b></td><td>@{coalesce(triggerOutputs()?['body/Supplier/Value'], triggerOutputs()?['body/Vendor'])}</td></tr>
  <tr><td><b>PO / invoice number</b></td><td>@{triggerOutputs()?['body/PONumber']}</td></tr>
  <tr><td><b>Expected delivery</b></td><td>@{if(empty(triggerOutputs()?['body/ExpectedDelivery']), 'Not provided – please confirm with Finance / vendor', formatDateTime(coalesce(triggerOutputs()?['body/ExpectedDelivery'], utcNow()), 'dd MMM yyyy'))}</td></tr>
  <tr><td><b>Carrier</b></td><td>@{triggerOutputs()?['body/Carrier']}</td></tr>
  <tr><td><b>Tracking</b></td><td>@{triggerOutputs()?['body/TrackingNumber']}</td></tr>
</table>
<p>To update tracking: open the request → <b>Edit</b> → set <b>Status</b> to <i>In Transit</i> or <i>Delayed</i>
(with a revised date and reason). When it arrives, set <b>Status = Received</b> and fill in the quantity received.</p>
<p><a href="@{triggerOutputs()?['body/{Link}']}">Open the request</a></p>
```

For several requests from the same supplier, Finance can mark them all
*Purchased* in one go with PR-07 ([11](11-flow-supplier-batch-order.md)).
This flow then runs once per request.

## Optional additions

* **Require a PO number or expected date:** add a condition before step 3.
  If `PONumber` or `ExpectedDelivery` is empty, email the editor
  (`body/Editor/Email`) asking them to add it, and end the flow (*Terminate*,
  status Succeeded). When they add it and save, the flow triggers again.
* **Cancelled requests:** create a copy of this flow with the trigger
  condition set to `'Cancelled'`, and email the requester that the request
  was withdrawn.
