# 05 – Flow PR-04: Delivery Updates (Received / Delayed)

**Trigger:** the inventory manager sets a request's **Status** to
**Received** or **Delayed**.
**Result:**

| Status set | What happens |
|---|---|
| **Received** | *Received On* (today if blank), *Received By* (the person who saved it if blank) and *Quantity Received* (the ordered quantity if blank) are filled in. The requester is told the item is at the office, and Finance is copied so they can match the invoice. Short deliveries are flagged in the email. |
| **Delayed** | The requester is told about the delay, the reason and the revised date, and Finance is copied so they can chase the vendor. If the revised date is after the requester's *Needed By* date, the email says so. **Changing the revised date again sends a new notice**; saving other fields doesn't. |

```
When an item is created or modified   (trigger condition: Received & not notified, OR Delayed & revised date not yet notified)
├─ Initialize variable  FinanceEmail
└─ Switch on Status
    ├─ Case "Received": Update item (Stamp Receipt) → Email Requester Received
    └─ Case "Delayed":  Update item (Stamp Delay Notice) → Email Requester Delayed
```

## How the inventory manager uses it

| Stage | Set on the request |
|---|---|
| Vendor has shipped | **Status = In Transit**, *Carrier / Courier*, *Tracking Number / Link*, and *Revised Delivery Date* if the ETA changed. Add a line to **Delivery Updates**. |
| Vendor/courier reports a delay | **Status = Delayed**, *Revised Delivery Date*, *Delay Reason*, a line in **Delivery Updates**. The requester is notified. |
| Part of the order arrived | **Status = Partially Received**, *Quantity Received*, notes. It stays on the delivery tracker. |
| Everything arrived | **Status = Received**, *Quantity Received*, *Receipt Notes / Condition* (damage etc.), attach a photo of the delivery note. The requester is notified. |

*Delivery Updates* is an append-only field: every save adds a dated entry to
the history, so you get a full tracking log for each order.

## Build it

**Create → Automated cloud flow**, name it `PR-04 Delivery Updates`, and
pick the SharePoint trigger **When an item is created or modified** (same
site and list as the other flows).

### 1. Trigger condition

Trigger → `…` → **Settings → Trigger conditions → + Add**. Paste this as
**one line**:

```
@or(and(equals(triggerOutputs()?['body/RequestStatus/Value'], 'Received'), not(equals(triggerOutputs()?['body/ReceivedNotified'], true))), and(equals(triggerOutputs()?['body/RequestStatus/Value'], 'Delayed'), not(equals(coalesce(triggerOutputs()?['body/LastDelayNotice'], ''), concat('notified:', coalesce(triggerOutputs()?['body/RevisedDelivery'], 'none'))))))
```

How it avoids loops and duplicate emails:

* *Received*: the flow sets **Received Notified = Yes**, so it runs only once.
* *Delayed*: the flow writes `notified:<revised date>` to **Last Delay
  Notice**. It runs again only when the revised date changes.

### 2. Initialize variable – `FinanceEmail`

String, `finance@yourorg.com`.

### 3. Switch – rename to **Status**

On: `@{triggerOutputs()?['body/RequestStatus/Value']}`

#### Case `Received`

**3a. Update item – "Stamp Receipt"**

| Field | Value |
|---|---|
| Id / Title | trigger `ID` / `Title` |
| Status Value | `Received` |
| Received On | `@{if(empty(triggerOutputs()?['body/ReceivedOn']), utcNow(), triggerOutputs()?['body/ReceivedOn'])}` |
| Received By Claims | `@{if(empty(triggerOutputs()?['body/ReceivedBy']), concat('i:0#.f|membership|', triggerOutputs()?['body/Editor/Email']), triggerOutputs()?['body/ReceivedBy/Claims'])}` |
| Quantity Received | `@{if(empty(triggerOutputs()?['body/QuantityReceived']), triggerOutputs()?['body/Quantity'], triggerOutputs()?['body/QuantityReceived'])}` |
| Received Notified | `Yes` |

**3b. Send an email (V2) – "Email Requester Received"**

| Field | Value |
|---|---|
| To | `@{triggerOutputs()?['body/Author/Email']}` |
| CC | `@{variables('FinanceEmail')};@{triggerOutputs()?['body/AdditionalRecipients']}` (adds requesters of merged duplicates) |
| Subject | `Arrived: your request #@{triggerOutputs()?['body/ID']} – @{triggerOutputs()?['body/Title']}` |
| Body | *(code view)* |

```html
<p>Hi @{triggerOutputs()?['body/Author/DisplayName']},</p>
<p>Your order <b>#@{triggerOutputs()?['body/ID']} – @{triggerOutputs()?['body/Title']}</b> has been received at the office
and checked in by @{if(empty(triggerOutputs()?['body/ReceivedBy']), triggerOutputs()?['body/Editor/DisplayName'], triggerOutputs()?['body/ReceivedBy/DisplayName'])}.
Please contact the inventory team to collect it.</p>
<table cellpadding="6" style="border-collapse:collapse;border:1px solid #ccc">
  <tr><td><b>Quantity ordered</b></td><td>@{triggerOutputs()?['body/Quantity']}</td></tr>
  <tr><td><b>Quantity received</b></td><td>@{outputs('Stamp_Receipt')?['body/QuantityReceived']}@{if(less(float(coalesce(outputs('Stamp_Receipt')?['body/QuantityReceived'], 0)), float(coalesce(triggerOutputs()?['body/Quantity'], 0))), ' <b style="color:#a4262c">(short delivery)</b>', '')}</td></tr>
  <tr><td><b>Received on</b></td><td>@{formatDateTime(coalesce(outputs('Stamp_Receipt')?['body/ReceivedOn'], utcNow()), 'dd MMM yyyy')}</td></tr>
  <tr><td><b>Condition / notes</b></td><td>@{triggerOutputs()?['body/ReceiptNotes']}</td></tr>
  <tr><td><b>PO / invoice number</b></td><td>@{triggerOutputs()?['body/PONumber']}</td></tr>
</table>
<p><a href="@{triggerOutputs()?['body/{Link}']}">View request</a></p>
```

#### Case `Delayed`

**3c. Update item – "Stamp Delay Notice"**

| Field | Value |
|---|---|
| Id / Title | trigger `ID` / `Title` |
| Status Value | `Delayed` |
| Last Delay Notice | `@{concat('notified:', coalesce(triggerOutputs()?['body/RevisedDelivery'], 'none'))}` |

**3d. Send an email (V2) – "Email Requester Delayed"**

| Field | Value |
|---|---|
| To | `@{triggerOutputs()?['body/Author/Email']}` |
| CC | `@{variables('FinanceEmail')};@{triggerOutputs()?['body/AdditionalRecipients']}` |
| Subject | `Delayed: your order #@{triggerOutputs()?['body/ID']} – @{triggerOutputs()?['body/Title']}` |
| Body | *(code view)* |

```html
<p>Hi @{triggerOutputs()?['body/Author/DisplayName']},</p>
<p>The delivery of your order <b>#@{triggerOutputs()?['body/ID']} – @{triggerOutputs()?['body/Title']}</b> has been delayed.</p>
<table cellpadding="6" style="border-collapse:collapse;border:1px solid #ccc">
  <tr><td><b>Original expected date</b></td><td>@{if(empty(triggerOutputs()?['body/ExpectedDelivery']), '–', formatDateTime(coalesce(triggerOutputs()?['body/ExpectedDelivery'], utcNow()), 'dd MMM yyyy'))}</td></tr>
  <tr><td><b>Revised date</b></td><td>@{if(empty(triggerOutputs()?['body/RevisedDelivery']), 'Not yet known', formatDateTime(coalesce(triggerOutputs()?['body/RevisedDelivery'], utcNow()), 'dd MMM yyyy'))}</td></tr>
  <tr><td><b>Reason</b></td><td>@{triggerOutputs()?['body/DelayReason']}</td></tr>
  <tr><td><b>Carrier / tracking</b></td><td>@{triggerOutputs()?['body/Carrier']} @{triggerOutputs()?['body/TrackingNumber']}</td></tr>
</table>
@{if(and(not(empty(triggerOutputs()?['body/NeededBy'])), not(empty(triggerOutputs()?['body/RevisedDelivery'])), greater(ticks(coalesce(triggerOutputs()?['body/RevisedDelivery'], '1900-01-01')), ticks(coalesce(triggerOutputs()?['body/NeededBy'], '2999-12-31')))), '<p style="color:#a4262c"><b>Note:</b> the revised date is after the date you needed this by. Please reply to Finance if you need an alternative.</p>', '')}
<p><a href="@{triggerOutputs()?['body/{Link}']}">View request</a></p>
```

Save the flow.

## Optional additions

* **In Transit notice:** add a third case, `In Transit`, that emails the
  requester the carrier and tracking number. Add a *Transit Notified* Yes/No
  column and extend the trigger condition the same way as for *Received*.
* **Partially Received:** add a case that emails Finance, since a short
  delivery may need a vendor follow-up or a partial invoice.
* **Teams thread:** at the end of each case, reply 📦 / ⏰ in the request's
  thread in the *Purchase Requests* channel. See
  [12 – Teams channel](12-teams-channel.md#pr-04-delivery-updates-05).
